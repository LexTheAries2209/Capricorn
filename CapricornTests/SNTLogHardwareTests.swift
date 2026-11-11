// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import Capricorn

/// Manual experiment only: one capture, fixed read commands, no protocol fallback.
final class SNTLogHardwareTests: XCTestCase {
    func testManuallyAuthorizedErrorAndSelfTestLogRead() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CAPRICORN_SNT_LOG_TEST_READ_LOGS"] == "1",
              let diskName = environment["CAPRICORN_SNT_LOG_TEST_DISK"],
              let volumeName = environment["CAPRICORN_SNT_LOG_TEST_VOLUME"],
              let bridgeName = environment["CAPRICORN_SNT_LOG_TEST_BRIDGE"],
              let bridge = SNTBridge(rawValue: bridgeName),
              let outputPath = environment["CAPRICORN_SNT_LOG_TEST_OUTPUT"],
              outputPath.hasPrefix("/") else {
            throw XCTSkip("Explicit disk, volume, bridge, local output directory and READ_LOGS=1 are required.")
        }

        let inventory = DiskutilInventoryProvider(networkProvider: nil)
        let matches = try await inventory.loadDrives().filter { $0.bsdName == diskName }
        guard matches.count == 1, let drive = matches.first,
              USBRawSmartPolicy.supportsRead(drive),
              drive.volumes.contains(where: { $0.name == volumeName && $0.mountPoint != nil }) else {
            throw USBRawSmartError.unavailable("The explicitly selected external USB disk and mounted volume were not found.")
        }
        let output = URL(fileURLWithPath: outputPath).standardizedFileURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard !drive.volumes.compactMap(\.mountPoint).contains(where: {
            output.path == $0 || output.path.hasPrefix($0 + "/")
        }) else {
            throw USBRawSmartError.unavailable("Experiment evidence must be saved away from the selected disk.")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        print("SNT_LOG_EVIDENCE \(output.path)")
        try JSONEncoder().encode(drive).write(to: output.appendingPathComponent("before-drive.json"),
                                             options: .withoutOverwriting)

        let lease = try DiskOperationLockCoordinator().acquire(for: drive, operation: .usbRawSmart)
        defer { lease.release() }
        let executable = try XCTUnwrap(Bundle.main.executableURL)
        let tool = executable.deletingLastPathComponent().appendingPathComponent("smartctl-usbraw")
        try DeviceHelperSigning.verify(
            url: tool, identifier: "lex.Capricorn.smartctl-usbraw", team: DeviceHelperSigning.ownTeam())
        let target = try USBRawSmartTargetResolver().target(for: drive)
        let runner = ShellCommandRunner()
        let preflight = try await runner.run(
            tool.path, arguments: ["--capricorn-usb-mount-preflight", target.selector], timeout: 15)
        try write(preflight.stdoutString + preflight.stderrString, named: "mount-preflight.txt", in: output)
        guard preflight.terminationStatus == 0 else {
            throw USBRawSmartError.unavailable("Mount identity preflight failed before capture.")
        }

        try USBRawSmartService.authorizeMountedVolumes(for: drive)
        for mount in Set(drive.volumes.compactMap(\.mountPoint)).sorted() {
            let inspection = try await DiskOpenFileService().inspectOpenFiles(
                at: mount, driveID: drive.id, driveName: drive.displayName,
                timeout: 5, requiresCompleteResult: true)
            guard inspection.processes.isEmpty else {
                throw USBRawSmartError.unavailable("The selected volume is in use. No USB capture was attempted.")
            }
        }
        guard try USBRawSmartTargetResolver().target(for: drive) == target else {
            throw USBRawSmartError.unavailable("The USB target changed before capture.")
        }

        // The existing app helper only admits health reads. This experimental
        // path uses native administrator consent and retains the tool's read-only allowlist.
        let arguments = [
            "CAPRICORN_USBRAW_MANUAL=1", tool.path,
            "-i", "-c", "-l", "error", "-l", "selftest", "--json=c",
            "-d", bridge.rawValue, target.selector
        ]
        try JSONEncoder().encode(arguments).write(to: output.appendingPathComponent("arguments.json"),
                                                  options: .withoutOverwriting)
        let command: CommandResult
        do {
            command = try await AdministratorUSBRawCommandRunner().run("/usr/bin/env", arguments: arguments)
        } catch {
            try write(error.localizedDescription, named: "execution-error.txt", in: output)
            throw error
        }
        try write(command.stdoutString + command.stderrString, named: "transcript.txt", in: output)
        let result = USBRawSmartService.parse(command, drive: drive, target: target, type: bridge.rawValue)
        print("SNT_LOG_RESULT exit=\(command.terminationStatus) phases=\(result.phases.map(\.rawValue))")

        // Check real mount state independently of the tool's restored marker.
        var restored: DriveDevice?
        for attempt in 0..<6 {
            let candidates = try await inventory.loadDrives().filter {
                DriveStableIdentityMatcher.matches(drive, $0)
            }
            if candidates.count == 1, let candidate = candidates.first {
                let mountsMatch = drive.volumes.filter { $0.mountPoint != nil }.allSatisfy { previous in
                    candidate.volumes.contains {
                        $0.mountPoint == previous.mountPoint && $0.isWritable == previous.isWritable
                    }
                }
                if mountsMatch { restored = candidate; break }
            }
            if attempt < 5 { try await Task.sleep(for: .milliseconds(500)) }
        }
        if let restored {
            try JSONEncoder().encode(restored).write(to: output.appendingPathComponent("after-drive.json"),
                                                    options: .withoutOverwriting)
        }
        guard result.restorationConfirmed, let restored else {
            throw USBRawSmartError.unavailable("Volume restoration could not be confirmed. Stop further experiments.")
        }
        print("SNT_LOG_RESTORED disk=\(restored.bsdName) mounts=\(restored.volumes.compactMap(\.mountPoint))")

        let root = try XCTUnwrap(command.stdoutString.components(separatedBy: .newlines).reversed()
            .compactMap { line -> [String: Any]? in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["smartctl"] != nil else { return nil }
                return json
            }.first)
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("smartctl.json"), options: .withoutOverwriting)

        let errorLog = root["nvme_error_information_log"] ?? root["nvme_error_log"]
        let selfTestLog = root["nvme_self_test_log"]
        let outcome = try verifyLogResponse(root, exitStatus: command.terminationStatus)
        let summary: [String: Any] = [
            "exit_status": command.terminationStatus,
            "restoration_confirmed": true,
            "error_log_present": errorLog != nil,
            "self_test_log_present": selfTestLog != nil,
            "self_test_log_outcome": outcome,
            "self_test_advertised": (root["nvme_optional_admin_commands"] as? [String: Any])?["self_test"] ?? NSNull(),
            "error_log": errorLog ?? NSNull(),
            "self_test_log": selfTestLog ?? NSNull(),
            "messages": (root["smartctl"] as? [String: Any])?["messages"] ?? []
        ]
        let summaryData = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        try summaryData.write(to: output.appendingPathComponent("summary.json"), options: .withoutOverwriting)
        print("SNT_LOG_SUMMARY \(String(decoding: summaryData, as: UTF8.self))")
        XCTAssertTrue(result.phases.contains(.reading))
    }

    func testCapturedCODEXResponsePreservesUnsupportedSelfTests() throws {
        let root: [String: Any] = [
            "smartctl": ["exit_status": 0],
            "nvme_optional_admin_commands": ["value": 6, "self_test": false],
            "nvme_error_information_log": ["size": 64, "read": 16, "unread": 0]
        ]
        XCTAssertEqual(try verifyLogResponse(root, exitStatus: 0), "unsupported")
    }

    /// Re-evaluates saved evidence without invoking diskutil or touching USB.
    func testReplaySavedSNTLogsWithoutHardwareAccess() throws {
        guard let path = ProcessInfo.processInfo.environment["CAPRICORN_SNT_LOG_TEST_REPLAY"] else {
            throw XCTSkip("Set CAPRICORN_SNT_LOG_TEST_REPLAY to a saved experiment directory for offline verification.")
        }
        let directory = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: directory.appendingPathComponent("smartctl.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exitStatus = try XCTUnwrap((root["smartctl"] as? [String: Any])?["exit_status"] as? Int32)
        let before = try JSONDecoder().decode(
            DriveDevice.self, from: Data(contentsOf: directory.appendingPathComponent("before-drive.json")))
        let after = try JSONDecoder().decode(
            DriveDevice.self, from: Data(contentsOf: directory.appendingPathComponent("after-drive.json")))
        let transcript = try Data(contentsOf: directory.appendingPathComponent("transcript.txt"))
        let command = CommandResult(stdout: transcript, stderr: Data(), terminationStatus: exitStatus)
        let device = try XCTUnwrap(root["device"] as? [String: Any])
        let selector = try XCTUnwrap(device["name"] as? String)
        XCTAssertTrue(selector.hasPrefix("usbraw:"))
        let registryID = try XCTUnwrap(UInt64(selector.dropFirst("usbraw:".count)))
        let bridge = try XCTUnwrap(device["type"] as? String)
        let result = USBRawSmartService.parse(
            command, drive: before, target: .init(registryID: registryID), type: bridge)
        XCTAssertEqual(result.phases, [.unmounting, .capturing, .reading, .releasing, .restoring, .restored])
        XCTAssertTrue(DriveStableIdentityMatcher.matches(before, after))
        for volume in before.volumes where volume.mountPoint != nil {
            XCTAssertTrue(after.volumes.contains {
                $0.mountPoint == volume.mountPoint && $0.isWritable == volume.isWritable
            })
        }
        let outcome = try verifyLogResponse(root, exitStatus: exitStatus)
        let summary: [String: Any] = [
            "source": "smartctl.json",
            "exit_status": exitStatus,
            "error_log_outcome": "read",
            "self_test_log_outcome": outcome,
            "restoration_confirmed": result.restorationConfirmed
        ]
        let summaryData = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        print("SNT_LOG_REPLAY_VALIDATED \(String(decoding: summaryData, as: UTF8.self))")
    }

    private func verifyLogResponse(_ root: [String: Any], exitStatus: Int32) throws -> String {
        XCTAssertEqual(exitStatus & 0x07, 0, "smartctl reported a command or read failure.")
        let data = try JSONSerialization.data(withJSONObject: root)
        let command = CommandResult(stdout: data, stderr: Data(), terminationStatus: exitStatus)
        let errorLog = try XCTUnwrap(SmartctlParser.parseErrorLog(command))
        XCTAssertTrue(errorLog.isSupported)
        let rawLog = try XCTUnwrap(root["nvme_error_information_log"] as? [String: Any])
        XCTAssertGreaterThan(try XCTUnwrap(rawLog["read"] as? Int), 0)
        print("SNT_LOG_ERROR_ENTRIES returned=\(errorLog.entries.count)")
        let selfTestLog = root["nvme_self_test_log"]
        let capability = try XCTUnwrap(SmartctlParser.parseSelfTestCapability(command))
        let advertised = (root["nvme_optional_admin_commands"] as? [String: Any])?["self_test"] as? Bool
        if advertised == false {
            // Unsupported is distinct from successfully reading an empty history.
            XCTAssertFalse(capability.shortSupported)
            XCTAssertFalse(capability.longSupported)
            XCTAssertNil(selfTestLog)
            print("SNT_LOG_SELF_TEST unsupported (Identify OACS self_test=false)")
            return "unsupported"
        }
        XCTAssertNotNil(selfTestLog, "Self-test support was not explicitly denied, but no log was returned.")
        return selfTestLog == nil ? "unavailable" : "read"
    }

    private func write(_ text: String, named name: String, in directory: URL) throws {
        try Data(text.utf8).write(to: directory.appendingPathComponent(name), options: .withoutOverwriting)
    }
}
