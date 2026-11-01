// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AppKit
import SwiftUI
import XCTest
@testable import Capricorn

final class DeviceHelperTests: XCTestCase {
    static let disk = DeviceHelperDisk(bsdName: "disk99", mediaRegistryID: 1234,
                                       sizeBytes: 4_000_000_000_000, usbRegistryID: 5678, isInternal: false)

    func testEveryOperationProducesOnlyItsFixedCommand() throws {
        let commands: [(DeviceHelperOperation, [String])] = [
            (.readSMART, ["-a", "--json"]),
            (.selfTestCapability, ["-c", "--json"]),
            (.selfTestLog, ["-l", "selftest", "--json"]),
            (.errorLog, ["-l", "error", "--json"]),
            (.startShortSelfTest, ["-t", "short", "--json"]),
            (.startLongSelfTest, ["-t", "long", "--json"]),
            (.abortSelfTest, ["-X"])
        ]
        for (operation, command) in commands {
            let request = DeviceHelperRequest(operation: operation, disk: Self.disk, deviceType: "sat")
            XCTAssertEqual(try request.arguments(target: "/dev/disk99", driveDatabase: "/trusted/drivedb.h"),
                           ["--drivedb=/trusted/drivedb.h"] + command + ["-d", "sat", "/dev/disk99"])
        }
        var raw = DeviceHelperRequest(operation: .readSNT, disk: Self.disk, deviceType: "sntasmedia")
        raw.confirmedUnmount = true
        XCTAssertEqual(try raw.arguments(target: "usbraw:5678", driveDatabase: "/unused"),
                       ["-i", "-H", "-A", "--json=c", "-d", "sntasmedia", "usbraw:5678"])
        XCTAssertEqual(commands.count + 1, DeviceHelperOperation.allCases.count)
    }

    func testInvalidIdentityProtocolAndTransportAreRejected() {
        var wrongVersion = DeviceHelperRequest(operation: .readSMART, disk: Self.disk, deviceType: nil)
        wrongVersion.version += 1
        XCTAssertThrowsError(try wrongVersion.validate())
        for name in ["disk99s1", "/dev/disk99", "disk99;id", "disk-1", "disk99\n"] {
            let disk = DeviceHelperDisk(bsdName: name, mediaRegistryID: 1234, sizeBytes: 500,
                                        usbRegistryID: nil, isInternal: false)
            XCTAssertThrowsError(try DeviceHelperRequest(operation: .readSMART, disk: disk, deviceType: nil).validate())
        }
        for type in ["auto", "sat -s on", "sntasmedia,1", "--scan-open", "/tmp/tool"] {
            XCTAssertThrowsError(try DeviceHelperRequest(operation: .readSMART, disk: Self.disk, deviceType: type).validate())
        }
        let identities: [(UInt64, Int64)] = [(0, 500), (1234, 0), (1234, -1)]
        for (id, size) in identities {
            let disk = DeviceHelperDisk(bsdName: "disk99", mediaRegistryID: id, sizeBytes: size,
                                        usbRegistryID: nil, isInternal: false)
            XCTAssertThrowsError(try DeviceHelperRequest(operation: .readSMART, disk: disk, deviceType: nil).validate())
        }
    }

    func testRawCaptureAlwaysRequiresConfirmationAndExternalUSB() throws {
        for type in ["sntasmedia", "sntjmicron", "sntrealtek"] {
            var request = DeviceHelperRequest(operation: .readSNT, disk: Self.disk, deviceType: type)
            XCTAssertThrowsError(try request.validate())
            request.confirmedUnmount = true
            XCTAssertNoThrow(try request.validate())
            request.transportRegistryID = 1234
            XCTAssertThrowsError(try request.validate())
            request.transportRegistryID = nil
            request.avoidWaking = true
            XCTAssertThrowsError(try request.validate())
        }
        for disk in [
            DeviceHelperDisk(bsdName: "disk99", mediaRegistryID: 1234, sizeBytes: 500, usbRegistryID: 5678, isInternal: true),
            DeviceHelperDisk(bsdName: "disk99", mediaRegistryID: 1234, sizeBytes: 500, usbRegistryID: nil, isInternal: false)
        ] {
            var request = DeviceHelperRequest(operation: .readSNT, disk: disk, deviceType: "sntasmedia")
            request.confirmedUnmount = true
            XCTAssertThrowsError(try request.validate())
        }
        var ordinary = DeviceHelperRequest(operation: .readSMART, disk: Self.disk, deviceType: "sat")
        ordinary.confirmedUnmount = true
        XCTAssertThrowsError(try ordinary.validate())
    }

    func testPowerModeAndSelfTestTransportBoundaries() throws {
        for type in ["ata", "sat", "sntjmicron/sat", "sntrealtek/sat"] {
            var request = DeviceHelperRequest(operation: .readSMART, disk: Self.disk, deviceType: type)
            request.avoidWaking = true
            XCTAssertEqual(Array(try request.arguments(target: "/dev/disk99", driveDatabase: "/trusted").dropFirst().prefix(2)),
                           ["-n", "standby,0"])
        }
        let noPowerCheck: [String?] = [nil, "nvme", "sntasmedia", "sntjmicron", "sntrealtek"]
        for type in noPowerCheck {
            var request = DeviceHelperRequest(operation: .readSMART, disk: Self.disk, deviceType: type)
            request.avoidWaking = true
            XCTAssertThrowsError(try request.validate())
        }
        for operation in [DeviceHelperOperation.startShortSelfTest, .startLongSelfTest, .abortSelfTest] {
            for type in ["nvme", "sntasmedia", "sntrealtek"] {
                XCTAssertThrowsError(try DeviceHelperRequest(operation: operation, disk: Self.disk, deviceType: type).validate())
            }
            // Existing JMicron SCSI passthrough support must remain available.
            XCTAssertNoThrow(try DeviceHelperRequest(operation: operation, disk: Self.disk, deviceType: "sntjmicron").validate())
        }
    }

    func testAdapterMapsAllExistingCommandsWithoutForwardingClientPaths() throws {
        let tool = try XCTUnwrap(Bundle.main.url(forResource: "smartctl", withExtension: nil)).path
        let commands: [(DeviceHelperOperation, [String])] = [
            (.readSMART, ["-a", "--json"]),
            (.selfTestCapability, ["-c", "--json"]),
            (.selfTestLog, ["-l", "selftest", "--json"]),
            (.errorLog, ["-l", "error", "--json"]),
            (.startShortSelfTest, ["-t", "short", "--json"]),
            (.startLongSelfTest, ["-t", "long", "--json"]),
            (.abortSelfTest, ["-X"])
        ]
        for (operation, args) in commands {
            let request = try PrivilegedDeviceCommandRunner.request(
                executable: tool, arguments: ["--drivedb=/untrusted/client/path"] + args + ["-d", "sat", "/dev/disk99"],
                bundle: .main, resolve: { _ in Self.disk }, resolveTransport: { _, _ in nil })
            XCTAssertEqual(request.operation, operation)
            XCTAssertEqual(request.deviceType, "sat")
            let data = try JSONEncoder().encode(request)
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("/untrusted"))
            XCTAssertFalse(request.confirmedUnmount)
        }
        let request = try PrivilegedDeviceCommandRunner.request(
            executable: tool, arguments: ["-n", "standby,0", "-a", "--json", "-d", "sat", "/dev/disk99"],
            bundle: .main, resolve: { _ in Self.disk }, resolveTransport: { _, _ in 4321 })
        XCTAssertTrue(request.avoidWaking)
        XCTAssertEqual(request.transportRegistryID, 4321)
    }

    func testAdapterRejectsScansShellAndArbitraryOptions() throws {
        let tool = try XCTUnwrap(Bundle.main.url(forResource: "smartctl", withExtension: nil)).path
        for args in [
            ["--scan-open"], ["--scan", "--json"], ["-s", "on", "/dev/disk99"],
            ["-t", "conveyance", "--json", "/dev/disk99"],
            ["-a", "--json", "--drivedb=/tmp/injected", "/dev/disk99"],
            ["-a", "--json", "-d", "sat;id", "/dev/disk99"]
        ] {
            XCTAssertThrowsError(try PrivilegedDeviceCommandRunner.request(
                executable: tool, arguments: args, bundle: .main, resolve: { _ in Self.disk },
                resolveTransport: { _, _ in nil }))
        }
        for executable in ["/bin/sh", "/tmp/smartctl", "/usr/local/bin/smartctl"] {
            XCTAssertThrowsError(try PrivilegedDeviceCommandRunner.request(
                executable: executable, arguments: ["-a", "--json", "/dev/disk99"],
                bundle: .main, resolve: { _ in Self.disk }))
        }
    }

    func testRawAdapterRequiresExactBundledExecutableAndManualMarker() throws {
        let raw = try XCTUnwrap(Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("smartctl-usbraw").path)
        let args = ["-i", "-H", "-A", "--json=c", "-d", "sntasmedia", "usbraw:5678"]
        let request = try PrivilegedDeviceCommandRunner.request(
            executable: "/usr/bin/env", arguments: ["CAPRICORN_USBRAW_MANUAL=1", raw] + args,
            bundle: .main, resolve: { _ in Self.disk })
        XCTAssertEqual(request.operation, .readSNT)
        XCTAssertTrue(request.confirmedUnmount)
        for prefix in [[raw], ["CAPRICORN_USBRAW_MANUAL=0", raw],
                       ["CAPRICORN_USBRAW_MANUAL=1", "/tmp/smartctl-usbraw"],
                       ["CAPRICORN_USBRAW_MANUAL=1", "PATH=/tmp", raw]] {
            XCTAssertThrowsError(try PrivilegedDeviceCommandRunner.request(
                executable: "/usr/bin/env", arguments: prefix + args,
                bundle: .main, resolve: { _ in Self.disk }))
        }
        XCTAssertThrowsError(try PrivilegedDeviceCommandRunner.request(
            executable: raw, arguments: args, bundle: .main, resolve: { _ in Self.disk }))
    }

    func testAdapterPreservesBothOutputStreamsAndSmartctlExitBits() async throws {
        let client = HelperRecordingClient()
        let runner = PrivilegedDeviceCommandRunner(client: client, resolve: { _ in Self.disk })
        let tool = try XCTUnwrap(Bundle.main.url(forResource: "smartctl", withExtension: nil)).path
        let result = try await runner.run(tool, arguments: ["-a", "--json", "-d", "sat", "/dev/disk99"])
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "health-data")
        XCTAssertEqual(String(decoding: result.stderr, as: UTF8.self), "warning-data")
        XCTAssertEqual(result.terminationStatus, 8)
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.operation, .readSMART)
    }

    func testOperationGateBlocksAllPeersAndStopUntilWorkerCompletes() {
        let gate = DeviceHelperOperationGate()
        let id = UUID()
        guard case .accepted = gate.begin(id: id, uid: 501) else { return XCTFail() }
        guard case .busy = gate.begin(id: id, uid: 501) else { return XCTFail() }
        guard case .busy = gate.begin(id: UUID(), uid: 502) else { return XCTFail() }
        XCTAssertFalse(gate.prepareToStop(), "USB release and mount restoration must complete before stop.")
        gate.finish(id: UUID(), uid: 501, response: nil)
        XCTAssertFalse(gate.prepareToStop(), "Another request cannot release the active worker.")
        gate.finish(id: id, uid: 501, response: nil)
        XCTAssertTrue(gate.prepareToStop())
        guard case .busy = gate.begin(id: UUID(), uid: 501) else { return XCTFail() }
        gate.cancelStop()
        guard case .accepted = gate.begin(id: UUID(), uid: 501) else { return XCTFail() }
    }

    func testCompletedRequestsAreIdempotentUserBoundAndBounded() {
        let gate = DeviceHelperOperationGate()
        let first = UUID()
        guard case .accepted = gate.begin(id: first, uid: 501) else { return XCTFail() }
        let response = DeviceHelperResponse(requestID: first, stdout: Data([1]), stderr: Data(), exitStatus: 0)
        gate.finish(id: first, uid: 501, response: response)
        guard case .cached(let cached) = gate.begin(id: first, uid: 501) else { return XCTFail() }
        XCTAssertEqual(cached.stdout, Data([1]))
        XCTAssertNil(gate.result(id: first.uuidString, uid: 502))
        guard case .accepted = gate.begin(id: first, uid: 502) else { return XCTFail() }
        gate.finish(id: first, uid: 502, response: nil)
        for _ in 0..<8 {
            let id = UUID()
            guard case .accepted = gate.begin(id: id, uid: 501) else { return XCTFail() }
            gate.finish(id: id, uid: 501,
                        response: DeviceHelperResponse(requestID: id, stdout: Data(), stderr: Data(), exitStatus: 0))
        }
        XCTAssertNil(gate.result(id: first.uuidString, uid: 501))
    }

    func testConcurrentRequestsAdmitExactlyOneWorker() {
        let gate = DeviceHelperOperationGate()
        let counter = HelperTestCounter()
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if case .accepted = gate.begin(id: UUID(), uid: 501) { counter.increment() }
        }
        XCTAssertEqual(counter.value, 1)
    }

    func testResolverRejectsPartitionsAndNonDevicePathsBeforeIOKitAccess() {
        for target in ["disk0s1", "/tmp/disk0", "/dev/disk0s1", "disk0;id"] {
            XCTAssertThrowsError(try DeviceHelperDeviceResolver.disk(forTarget: target))
        }
        XCTAssertThrowsError(try DeviceHelperDeviceResolver.transportID(path: "/tmp/device", disk: Self.disk))
        XCTAssertEqual(try DeviceHelperDeviceResolver.transportID(path: "/dev/disk99", disk: Self.disk), nil)
    }

    func testNormalRefreshOnlyUsesEnabledHelperForPermissionFailures() async throws {
        for (enabled, denied, expectedCalls) in [(false, true, 0), (true, false, 0), (true, true, 1)] {
            let ordinary = HelperReadRunner(denied: denied)
            let privileged = HelperReadRunner(denied: false)
            let provider = SmartctlSmartProvider(
                runner: ordinary, commandCoordinator: SmartctlCommandCoordinator(),
                avoidsWakingSleepingDisks: { false }, privilegedRunner: privileged,
                deviceServiceEnabled: { enabled })
            let snapshot = await provider.snapshot(
                for: CapricornTests.fixtureDrive(),
                resolvedTargetDescriptor: SmartctlTargetDescriptor(path: "/dev/disk0", type: "sat"))
            let calls = await privileged.calls
            XCTAssertEqual(calls, expectedCalls)
            if enabled || !denied { XCTAssertTrue(snapshot?.hasSMARTPayload == true) }
        }
    }

    func testBundledHelperHasTheCodeIdentityRequiredByXPC() throws {
        let team = try DeviceHelperSigning.ownTeam()
        let executable = try XCTUnwrap(Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent(DeviceHelperIdentity.executable))
        XCTAssertNoThrow(try DeviceHelperSigning.verify(
            url: executable, identifier: DeviceHelperIdentity.service, team: team))
        let worker = executable.deletingLastPathComponent().appendingPathComponent("smartctl")
        XCTAssertNoThrow(try DeviceHelperSigning.verify(url: worker, identifier: "smartctl", team: team))
        XCTAssertNoThrow(try DeviceHelperSigning.verify(
            url: executable.deletingLastPathComponent().appendingPathComponent("smartctl-usbraw"),
            identifier: "lex.Capricorn.smartctl-usbraw", team: team))
        XCTAssertThrowsError(try DeviceHelperSigning.verify(
            url: executable, identifier: DeviceHelperIdentity.appIdentifier, team: team))
        XCTAssertThrowsError(try DeviceHelperSigning.verify(
            url: executable, identifier: DeviceHelperIdentity.service, team: "AAAAAAAAAA"))
    }

    func testContainingAppUsesTheLoadedImageAndRequiresStandardEmbedding() throws {
        XCTAssertEqual(try DeviceHelperSigning.containingApp(), Bundle.main.bundleURL.resolvingSymlinksInPath())
        XCTAssertEqual(try DeviceHelperSigning.containingApp(
            executableURL: URL(fileURLWithPath: "/Applications/Capricorn.app/Contents/MacOS/CapricornDeviceHelper")).path,
                       "/Applications/Capricorn.app")
        for path in ["/CapricornDeviceHelper", "/usr/local/bin/CapricornDeviceHelper",
                     "/Applications/Capricorn.app/Contents/Resources/CapricornDeviceHelper"] {
            XCTAssertThrowsError(try DeviceHelperSigning.containingApp(executableURL: URL(fileURLWithPath: path)))
        }
    }

    func testLaunchDaemonIsDemandStartedAndUsesOnlyBundledProgram() throws {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchDaemons/" + DeviceHelperIdentity.plistName)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, DeviceHelperIdentity.service)
        XCTAssertEqual(plist["BundleProgram"] as? String, "Contents/MacOS/" + DeviceHelperIdentity.executable)
        XCTAssertEqual(plist["MachServices"] as? [String: Bool], [DeviceHelperIdentity.service: true])
        XCTAssertNil(plist["RunAtLoad"])
        XCTAssertNil(plist["KeepAlive"])
        XCTAssertNil(plist["Program"])
        XCTAssertNil(plist["ProgramArguments"])
    }

    func testHelperRefusesDirectUnprivilegedLaunchBeforeDoingDeviceWork() throws {
        guard geteuid() != 0 else { throw XCTSkip("The direct-launch rejection test requires a non-root test host.") }
        let process = Process()
        process.executableURL = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent(DeviceHelperIdentity.executable)
        let error = Pipe()
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 1)
        XCTAssertTrue(String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .contains("must be started by launchd as root"))
    }

    @MainActor
    func testServiceSettingsRenderBothLanguagesWithoutEnablingTheService() async throws {
        for language in AppLanguage.allCases {
            let view = NSHostingView(rootView: Form {
                DeviceHelperSettingsSection(language: language)
            }.formStyle(.grouped).frame(width: 620, height: 340))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 340),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            window.appearance = NSAppearance(named: .aqua)
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(150))
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/private/tmp/capricorn-device-service-\(language.rawValue).png"))
            XCTAssertGreaterThan(png.count, 1_000)
        }
    }
}

private actor HelperRecordingClient: DeviceHelperRequesting {
    private(set) var requests: [DeviceHelperRequest] = []
    func perform(_ request: DeviceHelperRequest) async throws -> DeviceHelperResponse {
        requests.append(request)
        return DeviceHelperResponse(requestID: request.id, stdout: Data("health-data".utf8),
                                    stderr: Data("warning-data".utf8), exitStatus: 8)
    }
}

private actor HelperReadRunner: CommandRunning {
    let denied: Bool
    private(set) var calls = 0
    init(denied: Bool) { self.denied = denied }
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        calls += 1
        return CommandResult(
            stdout: Data((denied ? "" : USBRawSmartTests.json).utf8),
            stderr: Data((denied ? "Permission denied" : "").utf8),
            terminationStatus: denied ? 2 : 0)
    }
}

private final class HelperTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    func increment() { lock.lock(); storage += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return storage }
}
