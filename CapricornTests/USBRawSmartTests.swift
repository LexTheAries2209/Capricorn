// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import XCTest
@testable import Capricorn

final class USBRawSmartTests: XCTestCase {
    static func drive() -> DriveDevice {
        var drive = CapricornTests.fixtureDrive()
        drive.isInternal = false
        drive.isSystemDisk = false
        drive.isVirtual = false
        drive.protocolName = "USB"
        drive.smartStatusRaw = nil
        drive.bsdName = "disk99"
        drive.deviceNode = "/dev/disk99"
        drive.displayName = "USB NVMe Test Disk"
        drive.serialNumber = "SNT-TEST-DRIVE"
        return drive
    }

    static let target = USBRawSmartTarget(registryID: 987654321)
    static let json = #"{"smartctl":{"exit_status":0,"version":[8,0]},"device":{"name":"usbraw:987654321","type":"sntrealtek","protocol":"NVMe"},"model_name":"Test NVMe","smart_status":{"passed":true},"nvme_smart_health_information_log":{"temperature":37,"percentage_used":3,"available_spare":100,"power_on_hours":20}}"#

    func testMenuRequiresExternalUSBWithoutSMARTPayload() {
        let drive = Self.drive()
        let missing = SmartSnapshot.unavailable(for: drive, reason: "Not supported")
        XCTAssertTrue(USBRawSmartPolicy.isEligible(drive: drive, snapshot: missing))
        XCTAssertFalse(USBRawSmartPolicy.isEligible(drive: drive, snapshot: nil))
        XCTAssertFalse(USBRawSmartPolicy.isEligible(drive: drive, snapshot: CapricornTests.fixtureSnapshot(for: drive)))
        for kind in ["internal", "system", "virtual", "network", "card", "thunderbolt"] {
            var protected = drive
            switch kind {
            case "internal": protected.isInternal = true
            case "system": protected.isSystemDisk = true
            case "virtual": protected.isVirtual = true
            case "network": protected.isNetwork = true
            case "card": protected.isMemoryCard = true
            default: protected.protocolName = "Thunderbolt"
            }
            XCTAssertFalse(USBRawSmartPolicy.isEligible(drive: protected, snapshot: missing), kind)
        }
    }

    func testExitEnvelopePreservesHealthWarningAndCleanupOutput() throws {
        let output = Self.json + "\nCAPRICORN_USBRAW\trestore_failed\nCAPRICORN_USBRAW_EXIT=8\n"
        let decoded = try AdministratorUSBRawCommandRunner.decode(output)
        XCTAssertEqual(decoded.terminationStatus, 8)
        XCTAssertTrue(decoded.stdoutString.contains(Self.json))
        XCTAssertTrue(decoded.stdoutString.contains("restore_failed"))
        XCTAssertFalse(decoded.stdoutString.contains("CAPRICORN_USBRAW_EXIT="))
        for invalid in ["", Self.json, "CAPRICORN_USBRAW_EXIT=bad", "CAPRICORN_USBRAW_EXIT=-1",
                        "CAPRICORN_USBRAW_EXIT=0\ntrailing output"] {
            XCTAssertThrowsError(try AdministratorUSBRawCommandRunner.decode(invalid))
        }
    }

    func testAuthorizedCommandRejoinsRequestingAppSessionWithoutDroppingRoot() async throws {
        let shell = USBRawRecordingRunner(result: CommandResult(
            stdout: Data("CAPRICORN_USBRAW_EXIT=0\n".utf8), stderr: Data(), terminationStatus: 0))
        let runner = AdministratorUSBRawCommandRunner(runner: shell, userID: 501)
        _ = try await runner.run("/path with spaces/tool", arguments: ["a'b", "$HOME"])
        let calls = await shell.calls
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.executable, "/usr/bin/osascript")
        let script = try XCTUnwrap(call.arguments.last)
        for token in ["/bin/launchctl", "asuser", "501", "/usr/bin/env"] {
            XCTAssertTrue(script.contains("'\(token)'"))
        }
        XCTAssertTrue(script.contains("'CAPRICORN_USBRAW_USER_UID=501'"))
        XCTAssertTrue(script.contains("'/path with spaces/tool'"))
        XCTAssertTrue(script.contains("'$HOME'"))
        XCTAssertFalse(script.contains("sudo"))
        XCTAssertFalse(script.contains("bsexec"))
        XCTAssertTrue(script.hasSuffix("with administrator privileges"))
    }

    func testSystemOrInvalidRequesterCannotAuthorizeUSB() async {
        let shell = USBRawRecordingRunner(result: Self.commandResult())
        let invalidUsers: [UInt32] = [0, .max]
        for uid in invalidUsers {
            let runner = AdministratorUSBRawCommandRunner(runner: shell, userID: uid)
            do {
                _ = try await runner.run("/usr/bin/true", arguments: [])
                XCTFail("An invalid GUI requester must not reach authorization")
            } catch {}
        }
        let calls = await shell.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testReadAndMountRestorationHaveIndependentOutcomes() {
        let failed = Self.result(restored: false)
        XCTAssertEqual(failed.snapshot?.temperatureCelsius, 37)
        XCTAssertTrue(failed.snapshot?.hasSMARTPayload == true)
        XCTAssertFalse(failed.restorationConfirmed)
        XCTAssertTrue(failed.message.contains("could not be confirmed"))
        let succeeded = Self.result(restored: true)
        XCTAssertTrue(succeeded.restorationConfirmed)
        XCTAssertEqual(succeeded.snapshot?.selectedProvider, USBRawSmartService.providerName)
        XCTAssertEqual(succeeded.snapshot?.selectedTransport, "sntrealtek")
    }

    func testMissingRestorationEvidenceNeverMeansSuccess() {
        let parsed = USBRawSmartService.parse(
            CommandResult(stdout: Data(Self.json.utf8), stderr: Data(), terminationStatus: 0),
            drive: Self.drive(), target: Self.target, type: "sntrealtek")
        XCTAssertTrue(parsed.snapshot?.hasSMARTPayload == true)
        XCTAssertFalse(parsed.restorationConfirmed)
    }

    func testCloseFailureFatalBitDoesNotDiscardValidHealthData() {
        let original = Self.json.replacingOccurrences(
            of: #""exit_status":0"#,
            with: #""exit_status":2,"messages":[{"string":"close failed: volume did not reappear","severity":"error"}]"#)
        let parsed = USBRawSmartService.parse(CommandResult(
            stdout: Data(("CAPRICORN_USBRAW\treading\n" + original
                + "\nCAPRICORN_USBRAW\trestore_failed").utf8),
            stderr: Data(), terminationStatus: 2),
            drive: Self.drive(), target: Self.target, type: "sntrealtek")
        XCTAssertTrue(parsed.snapshot?.hasSMARTPayload == true)
        XCTAssertEqual(parsed.snapshot?.temperatureCelsius, 37)
        XCTAssertEqual(parsed.exitStatus, 2)
        XCTAssertEqual(parsed.snapshot?.verifiedSource?.state, .limited)
        XCTAssertFalse(parsed.restorationConfirmed)
    }

    func testModelInformationWithoutHealthIsNotSuccessfulRead() {
        let parsed = USBRawSmartService.parse(
            CommandResult(stdout: Data(#"{"smartctl":{"exit_status":0},"model_name":"Bridge"}"#.utf8),
                          stderr: Data("CAPRICORN_USBRAW\trestored".utf8), terminationStatus: 0),
            drive: Self.drive(), target: Self.target, type: "sntrealtek")
        XCTAssertFalse(parsed.snapshot?.hasSMARTPayload == true)
        XCTAssertTrue(parsed.restorationConfirmed)
        XCTAssertTrue(parsed.message.contains("no SMART data"))
    }

    func testReadUsesPassiveScanThenExplicitFrozenTarget() async throws {
        let drive = Self.drive()
        let scan = USBRawRecordingRunner(result: Self.scan(for: drive, type: "sntrealtek"))
        let privileged = USBRawRecordingRunner(result: Self.commandResult())
        let service = USBRawSmartService(
            runner: scan, administratorRunner: privileged, executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            targetResolver: { _ in Self.target }, authorizeVolumes: { _ in })
        let result = try await service.read(drive: drive, target: Self.target, bridge: .automatic)
        XCTAssertTrue(result.snapshot?.hasSMARTPayload == true)
        let scans = await scan.calls
        XCTAssertEqual(scans.first?.arguments, ["--scan", "-d", "usb", "--json=c"])
        let reads = await privileged.calls
        XCTAssertEqual(reads.first?.executable, "/usr/bin/env")
        XCTAssertEqual(reads.first?.arguments, [
            "CAPRICORN_USBRAW_MANUAL=1", "/usr/bin/true",
            "-i", "-H", "-A", "--json=c", "-d", "sntrealtek", Self.target.selector
        ])
    }

    func testUnknownBridgeDoesNotAuthorizeCapture() async {
        let drive = Self.drive()
        let scan = USBRawRecordingRunner(result: Self.scan(for: drive, type: "sat,auto"))
        let privileged = USBRawRecordingRunner(result: Self.commandResult())
        let service = USBRawSmartService(
            runner: scan, administratorRunner: privileged, executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            targetResolver: { _ in Self.target }, authorizeVolumes: { _ in })
        do {
            _ = try await service.read(drive: drive, target: Self.target, bridge: .automatic)
            XCTFail("Unknown bridge must stop before authorization")
        } catch {}
        let calls = await privileged.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testChangedDeviceDoesNotAuthorizeCapture() async {
        let scan = USBRawRecordingRunner(result: Self.scan(for: Self.drive(), type: "sntrealtek"))
        let privileged = USBRawRecordingRunner(result: Self.commandResult())
        let service = USBRawSmartService(
            runner: scan, administratorRunner: privileged, executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            targetResolver: { _ in USBRawSmartTarget(registryID: 222) })
        do {
            _ = try await service.read(drive: Self.drive(), target: Self.target, bridge: .realtek)
            XCTFail("A reused disk node must not capture a new device")
        } catch {}
        let scans = await scan.calls
        let reads = await privileged.calls
        XCTAssertTrue(scans.isEmpty)
        XCTAssertTrue(reads.isEmpty)
    }

    func testDeniedVolumeAccessStopsBeforeRootAndCapture() async {
        let drive = Self.drive()
        let scan = USBRawRecordingRunner(result: Self.scan(for: drive, type: "sntasmedia"))
        let privileged = USBRawRecordingRunner(result: Self.commandResult())
        let service = USBRawSmartService(
            runner: scan, administratorRunner: privileged, executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            targetResolver: { _ in Self.target },
            authorizeVolumes: { _ in throw CocoaError(.fileReadNoPermission) })
        do {
            _ = try await service.read(drive: drive, target: Self.target, bridge: .automatic)
            XCTFail("Denied removable-volume access must leave the device mounted")
        } catch {}
        let calls = await privileged.calls
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testConfirmationDoesNotStartReadAndBusyModelBlocksStart() async {
        let service = USBRawSuspendedService()
        let model = Self.model(service: service)
        let drive = Self.drive()
        model.requestUSBRawSmart(for: drive)
        XCTAssertEqual(model.usbRawSmartSession?.state, .confirmation)
        let count = await service.readCount
        XCTAssertEqual(count, 0)
        model.isRefreshing = true
        await model.beginUSBRawSmart()
        let stillZero = await service.readCount
        XCTAssertEqual(stillZero, 0)
        model.closeUSBRawSmart()
        XCTAssertNil(model.usbRawSmartSession)
    }

    @MainActor
    func testConfirmationSheetRendersBothLanguagesWithoutStartingRead() async throws {
        let service = USBRawSuspendedService()
        for language in AppLanguage.allCases {
            let model = Self.model(service: service)
            model.requestUSBRawSmart(for: Self.drive())
            _ = try XCTUnwrap(model.usbRawSmartSession)
            let view = NSHostingView(rootView: USBRawSmartSheet(viewModel: model, language: language)
                .environment(\.colorScheme, .light)
                .background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 450),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            window.appearance = NSAppearance(named: .aqua)
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(150))
            view.frame.size = view.fittingSize
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/private/tmp/capricorn-snt-confirmation-\(language.rawValue).png"))
            XCTAssertGreaterThan(view.fittingSize.height, 250)
            XCTAssertEqual(model.usbRawSmartSession?.state, .confirmation)
        }
        let count = await service.readCount
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testRunningReadBlocksRefreshCloseBenchmarkAndUpdateThenPublishesStableMatch() async throws {
        let service = USBRawSuspendedService()
        let inventory = USBRawTestRefresh()
        let model = Self.model(service: service, refresh: inventory)
        model.requestUSBRawSmart(for: Self.drive())
        _ = try XCTUnwrap(model.usbRawSmartSession)
        let task = Task { await model.beginUSBRawSmart() }
        await service.waitUntilStarted()
        XCTAssertTrue(model.isUSBRawSmartActive)
        XCTAssertTrue(model.isDriveSelectionLocked)
        XCTAssertTrue(model.appUpdateConflicts.contains(.diskCommand))
        XCTAssertFalse(model.startBenchmark(profile: .quick))
        model.closeUSBRawSmart()
        XCTAssertNotNil(model.usbRawSmartSession)
        await model.refresh()
        let before = await inventory.discoverCount
        XCTAssertEqual(before, 0)
        await service.finish()
        await task.value
        XCTAssertFalse(model.isUSBRawSmartActive)
        XCTAssertEqual(model.usbRawSmartSession?.state, .completed)
        XCTAssertEqual(model.snapshots[Self.drive().id]?.selectedProvider, USBRawSmartService.providerName)
        XCTAssertFalse(model.appUpdateConflicts.contains(.diskCommand))
    }

    @MainActor
    static func model(service: USBRawSmartRunning, refresh: DriveRefreshing = USBRawTestRefresh()) -> AppModel {
        let model = AppModel(refreshService: refresh, usbRawSmartService: service)
        let drive = drive()
        model.drives = [drive]
        model.snapshots = [drive.id: SmartSnapshot.unavailable(for: drive, reason: "Not supported")]
        return model
    }

    static func result(restored: Bool) -> USBRawSmartResult {
        USBRawSmartService.parse(commandResult(restored: restored), drive: drive(), target: target, type: "sntrealtek")
    }

    static func commandResult(restored: Bool = true) -> CommandResult {
        let output = "CAPRICORN_USBRAW\tunmounting\nCAPRICORN_USBRAW\tcapturing\nCAPRICORN_USBRAW\treading\n"
            + json + "\nCAPRICORN_USBRAW\treleasing\nCAPRICORN_USBRAW\trestoring\nCAPRICORN_USBRAW\t"
            + (restored ? "restored" : "restore_failed")
        return CommandResult(stdout: Data(output.utf8), stderr: Data(), terminationStatus: restored ? 0 : 2)
    }

    static func scan(for drive: DriveDevice, type: String) -> CommandResult {
        CommandResult(stdout: Data(#"{"devices":[{"name":"/dev/\#(drive.bsdName)","type":"\#(type)","protocol":"NVMe"}]}"#.utf8),
                      stderr: Data(), terminationStatus: 0)
    }
}

private actor USBRawRecordingRunner: CommandRunning {
    struct Call: Sendable { let executable: String; let arguments: [String] }
    private(set) var calls: [Call] = []
    let result: CommandResult
    init(result: CommandResult) { self.result = result }
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        calls.append(Call(executable: executable, arguments: arguments))
        return result
    }
}

private actor USBRawSuspendedService: USBRawSmartRunning {
    var readCount = 0
    var continuation: CheckedContinuation<USBRawSmartResult, Never>?
    var startObserver: CheckedContinuation<Void, Never>?
    nonisolated func target(for drive: DriveDevice) throws -> USBRawSmartTarget { USBRawSmartTests.target }
    func read(drive: DriveDevice, target: USBRawSmartTarget, bridge: SNTBridge) async throws -> USBRawSmartResult {
        readCount += 1
        return await withCheckedContinuation {
            continuation = $0
            startObserver?.resume()
            startObserver = nil
        }
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { startObserver = $0 }
    }
    func finish() {
        continuation?.resume(returning: USBRawSmartTests.result(restored: true))
        continuation = nil
    }
}

private actor USBRawTestRefresh: DriveRefreshing {
    var discoverCount = 0
    func discover() async throws -> DriveRefreshSnapshot {
        discoverCount += 1
        var drive = USBRawSmartTests.drive()
        drive.isSystemDisk = true // Avoid unrelated automatic capability probes.
        return DriveRefreshSnapshot(drives: [drive], snapshots: [:])
    }
    func snapshotUpdates(for drives: [DriveDevice]) async -> AsyncStream<DriveSnapshotUpdate> {
        AsyncStream { $0.finish() }
    }
}
