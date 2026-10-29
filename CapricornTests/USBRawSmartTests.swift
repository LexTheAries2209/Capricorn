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

    static func codexDrive() -> DriveDevice {
        var drive = drive()
        drive.serialNumber = nil
        drive.mediaName = "COMPACT DRIVE"
        drive.sizeBytes = 960_197_124_096
        drive.blockSize = 512
        drive.usbDevice = DriveUSBDeviceIdentity(
            vendorName: "CODEX", productName: "CX.0001005", vendorID: 0x2818, productID: 0x0012)
        drive.volumes = [.init(
            deviceIdentifier: drive.bsdName, name: "B_0022_1DOZ", mountPoint: "/Volumes/B_0022_1DOZ",
            sizeBytes: 960_191_528_960, isWritable: false, isSystem: false, fileSystemType: "udf",
            topologyKind: .physicalPartition)]
        return drive
    }

    func testCodexNameExceptionIsNarrowAndSurvivesBSDRenumbering() {
        let drive = Self.codexDrive()
        var renamed = drive
        renamed.bsdName = "disk101"
        renamed.volumes[0].deviceIdentifier = renamed.bsdName
        XCTAssertTrue(DriveStableIdentityMatcher.matches(drive, renamed))
        for invalid in 0..<10 {
            var candidate = renamed
            switch invalid {
            case 0: candidate.usbDevice?.vendorID = 0x174c
            case 1: candidate.usbDevice?.productID = 0x0001
            case 2: candidate.mediaName = "OTHER DRIVE"
            case 3: candidate.volumes[0].name = "OTHER_CARD"
            case 4: candidate.volumes[0].fileSystemType = "exfat"
            case 5: candidate.sizeBytes += 512
            case 6: candidate.blockSize = 4096
            case 7: candidate.volumes[0].name = ""
            case 8: candidate.volumes[0].volumeUUID = "OTHER-UUID"
            default: candidate.volumes.append(candidate.volumes[0])
            }
            XCTAssertFalse(DriveStableIdentityMatcher.matches(drive, candidate), "\(invalid)")
        }
    }

    @MainActor
    func testCodexManualReadPublishesAndSurvivesRefreshByVolumeName() async {
        let drive = Self.codexDrive()
        let service = USBRawSuspendedService()
        let model = AppModel(refreshService: USBRawCodexRefresh(drives: [drive]), usbRawSmartService: service)
        model.drives = [drive]
        model.snapshots = [drive.id: .unavailable(for: drive, reason: "Not supported")]
        model.smartSelfTestCapabilities[drive.id] = .unavailable("Fixture")
        model.requestUSBRawSmart(for: drive)
        let task = Task { await model.beginUSBRawSmart() }
        await service.waitUntilStarted()
        await service.finish()
        await task.value
        XCTAssertNil(model.usbRawSmartSession?.error)
        XCTAssertEqual(model.selectedSnapshot?.temperatureCelsius, 37)
        model.closeUSBRawSmart()
        model.finishUSBRawSmartDismissal()
        await model.refresh()
        XCTAssertEqual(model.selectedSnapshot?.temperatureCelsius, 37)
    }

    @MainActor
    func testDuplicateCodexNamesNeverPublishAnAmbiguousManualRead() async {
        let drive = Self.codexDrive()
        var duplicate = drive
        duplicate.bsdName = "disk101"
        duplicate.volumes[0].deviceIdentifier = duplicate.bsdName
        let service = USBRawSuspendedService()
        let model = AppModel(refreshService: USBRawCodexRefresh(drives: [drive, duplicate]), usbRawSmartService: service)
        model.drives = [drive, duplicate]
        for item in model.drives {
            model.snapshots[item.id] = .unavailable(for: item, reason: "Not supported")
            model.smartSelfTestCapabilities[item.id] = .unavailable("Fixture")
        }
        model.requestUSBRawSmart(for: drive)
        let task = Task { await model.beginUSBRawSmart() }
        await service.waitUntilStarted()
        await service.finish()
        await task.value
        XCTAssertTrue(model.usbRawSmartSession?.error?.contains("uniquely identified") == true)
        XCTAssertTrue(model.snapshots.values.allSatisfy { $0.selectedProvider != USBRawSmartService.providerName })
    }

    @MainActor
    func testCodexReadWaitsForCompleteReconnectedInventory() async {
        let drive = Self.codexDrive()
        var incomplete = drive
        incomplete.volumes = []
        incomplete.usbDevice = nil
        var restored = drive
        restored.bsdName = "disk101"
        restored.volumes[0].deviceIdentifier = restored.bsdName
        let inventory = USBRawSequencedRefresh(inventories: [[incomplete], [restored]])
        let service = USBRawSuspendedService()
        let model = AppModel(refreshService: inventory, usbRawSmartService: service)
        model.drives = [drive]
        model.snapshots = [drive.id: .unavailable(for: drive, reason: "Not supported")]
        model.smartSelfTestCapabilities[restored.id] = .unavailable("Fixture")
        model.requestUSBRawSmart(for: drive)
        let task = Task { await model.beginUSBRawSmart() }
        await service.waitUntilStarted()
        await service.finish()
        await task.value
        XCTAssertNil(model.usbRawSmartSession?.error)
        XCTAssertEqual(model.selectedDriveID, restored.id)
        XCTAssertEqual(model.selectedSnapshot?.temperatureCelsius, 37)
        let count = await inventory.discoverCount
        XCTAssertEqual(count, 2)
        let transcript = model.usbRawSmartSession?.result?.transcript ?? ""
        XCTAssertTrue(transcript.contains("CAPRICORN_USBRAW_IDENTITY"))
        XCTAssertTrue(transcript.contains(#""attempt":2"#))
        model.closeUSBRawSmart()
        model.finishUSBRawSmartDismissal()
        await model.refresh()
        XCTAssertEqual(model.selectedSnapshot?.temperatureCelsius, 37)
    }

    @MainActor
    func testAmbiguousCodexReadDoesNotRetryUntilOneDeviceDisappears() async {
        let drive = Self.codexDrive()
        var duplicate = drive
        duplicate.bsdName = "disk101"
        duplicate.volumes[0].deviceIdentifier = duplicate.bsdName
        let inventory = USBRawSequencedRefresh(inventories: [[drive, duplicate], [drive]])
        let service = USBRawSuspendedService()
        let model = AppModel(refreshService: inventory, usbRawSmartService: service)
        model.drives = [drive]
        model.snapshots = [drive.id: .unavailable(for: drive, reason: "Not supported")]
        for item in [drive, duplicate] {
            model.smartSelfTestCapabilities[item.id] = .unavailable("Fixture")
        }
        model.requestUSBRawSmart(for: drive)
        let task = Task { await model.beginUSBRawSmart() }
        await service.waitUntilStarted()
        await service.finish()
        await task.value
        XCTAssertNotNil(model.usbRawSmartSession?.error)
        let count = await inventory.discoverCount
        XCTAssertEqual(count, 1)
        XCTAssertTrue(model.snapshots.values.allSatisfy { $0.selectedProvider != USBRawSmartService.providerName })
    }

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
        XCTAssertFalse(model.isUSBRawSmartPresented)
        XCTAssertNotNil(model.usbRawSmartSession)
        model.finishUSBRawSmartDismissal()
        XCTAssertNil(model.usbRawSmartSession)
    }

    @MainActor
    func testClosingResultKeepsSheetContentUntilDismissalCompletes() async throws {
        let model = Self.model(service: USBRawSuspendedService())
        model.requestUSBRawSmart(for: Self.drive())
        model.usbRawSmartSession?.state = .completed
        model.usbRawSmartSession?.result = Self.result(restored: true)
        let view = NSHostingView(rootView: USBRawSmartSheet(viewModel: model, language: .simplifiedChinese))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 628, height: 450),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(50))
        let originalHeight = view.fittingSize.height
        XCTAssertGreaterThan(originalHeight, 250)
        model.closeUSBRawSmart()
        try await Task.sleep(for: .milliseconds(50))
        view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(model.usbRawSmartSession)
        XCTAssertEqual(view.fittingSize.height, originalHeight, accuracy: 1)
        XCTAssertFalse(model.isUSBRawSmartPresented)
        model.finishUSBRawSmartDismissal()
        XCTAssertNil(model.usbRawSmartSession)
        model.requestUSBRawSmart(for: Self.drive())
        XCTAssertTrue(model.isUSBRawSmartPresented)
        model.finishUSBRawSmartDismissal()
        XCTAssertNotNil(model.usbRawSmartSession, "A stale dismiss callback must not clear a new presentation.")
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
    func testManualReadSurvivesOrdinaryRefreshAfterClosingResult() async throws {
        let service = USBRawSuspendedService()
        let inventory = USBRawUpdatingRefresh()
        let model = Self.model(service: service, refresh: inventory)
        model.requestUSBRawSmart(for: Self.drive())
        let task = Task { await model.beginUSBRawSmart() }
        await service.waitUntilStarted()
        await service.finish()
        await task.value
        let capturedAt = try XCTUnwrap(model.selectedSnapshot?.capturedAt)
        model.closeUSBRawSmart()
        model.finishUSBRawSmartDismissal()
        await model.refresh()
        XCTAssertEqual(model.selectedSnapshot?.temperatureCelsius, 37)
        XCTAssertEqual(model.selectedSnapshot?.selectedProvider, USBRawSmartService.providerName)
        XCTAssertEqual(model.selectedSnapshot?.capturedAt, capturedAt)
        XCTAssertFalse(model.selectedSnapshot?.providerStatuses.contains {
            $0.message == "Refreshing Native SMART data..."
        } ?? true)
        XCTAssertFalse(model.offersUSBRawSmart(for: try XCTUnwrap(model.selectedDrive)))
    }

    @MainActor
    func testSharedEFIUUIDDoesNotPreventPublishingOrRetainingManualRead() async throws {
        let service = USBRawSuspendedService()
        let inventory = USBRawUpdatingRefresh()
        var target = Self.drive()
        target.serialNumber = nil
        target.volumes = [
            .init(deviceIdentifier: "disk100s1", name: "Data F", mountPoint: "/Volumes/Data F",
                  sizeBytes: target.sizeBytes, isWritable: true, isSystem: false,
                  fileSystemType: "APFS", volumeUUID: "7D9E2270-0778-4D7D-9212-697D6AB4022D",
                  topologyKind: .logicalVolume),
            .init(deviceIdentifier: "disk99s1", name: "EFI", mountPoint: nil,
                  sizeBytes: 209_715_200, isWritable: true, isSystem: false,
                  fileSystemType: "EFI", volumeUUID: "0E239BC6-F960-3107-89CF-1C97F78BB46B",
                  topologyKind: .physicalPartition)
        ]
        var other = target
        other.bsdName = "disk101"
        other.deviceNode = "/dev/disk101"
        other.serialNumber = "OTHER-DRIVE"
        other.volumes[0].volumeUUID = "CF64F70E-C347-4668-85A2-9B2691AF499A"
        other.volumes[0].deviceIdentifier = "disk102s1"
        other.volumes[0].name = "Data D"
        other.volumes[0].mountPoint = "/Volumes/Data D"
        XCTAssertFalse(DriveStableIdentityMatcher.matches(target, other))

        await inventory.setDrives([target, other])
        let model = Self.model(service: service, refresh: inventory)
        model.drives = [target, other]
        model.requestUSBRawSmart(for: target)
        let task = Task { await model.beginUSBRawSmart() }
        await service.waitUntilStarted()
        await service.finish()
        await task.value
        XCTAssertEqual(model.selectedSnapshot?.temperatureCelsius, 37)
        XCTAssertEqual(model.selectedDriveID, target.id)
        XCTAssertNil(model.usbRawSmartSession?.error)
        await model.refresh()
        XCTAssertEqual(model.snapshots[target.id]?.temperatureCelsius, 37)
        XCTAssertNotEqual(model.snapshots[other.id]?.selectedProvider, USBRawSmartService.providerName)
    }

    func testMountedEFIAndAuxiliaryUUIDsCannotIdentifyUnrelatedDisks() {
        var first = Self.drive()
        first.serialNumber = nil
        first.volumes = [
            .init(deviceIdentifier: "disk99s1", name: "EFI", mountPoint: "/Volumes/EFI",
                  sizeBytes: 209_715_200, isWritable: true, isSystem: false,
                  fileSystemType: "FAT32", volumeUUID: "SHARED-EFI",
                  topologyKind: .physicalPartition, partitionContent: "EFI"),
            .init(deviceIdentifier: "disk100s2", name: "Preboot", mountPoint: nil,
                  sizeBytes: 4096, isWritable: true, isSystem: false,
                  fileSystemType: "APFS", volumeUUID: "SHARED-PREBOOT", apfsRole: "Preboot",
                  topologyKind: .logicalVolume)
        ]
        var second = first
        second.bsdName = "disk101"
        XCTAssertFalse(DriveStableIdentityMatcher.matches(first, second))
    }

    @MainActor
    func testUnmatchedReadingExplainsWhyItWasNotPublished() async {
        let service = USBRawSuspendedService()
        let inventory = USBRawUpdatingRefresh()
        var duplicate = Self.drive()
        duplicate.bsdName = "disk101"
        await inventory.setDrives([Self.drive(), duplicate])
        let model = Self.model(service: service, refresh: inventory)
        model.requestUSBRawSmart(for: Self.drive())
        let task = Task { await model.beginUSBRawSmart() }
        await service.waitUntilStarted()
        await service.finish()
        await task.value
        XCTAssertTrue(model.usbRawSmartSession?.result?.snapshot?.hasSMARTPayload == true)
        XCTAssertTrue(model.usbRawSmartSession?.error?.contains("uniquely identified") == true)
        XCTAssertEqual(model.refreshMessage, model.usbRawSmartSession?.error)
        XCTAssertNotEqual(model.selectedSnapshot?.selectedProvider, USBRawSmartService.providerName)
    }

    @MainActor
    func testManualReadFollowsStableIdentityButNotReusedBSDNameOrReconnect() async throws {
        let service = USBRawSuspendedService()
        let inventory = USBRawUpdatingRefresh()
        let model = Self.model(service: service, refresh: inventory)
        model.requestUSBRawSmart(for: Self.drive())
        let task = Task { await model.beginUSBRawSmart() }
        await service.waitUntilStarted()
        await service.finish()
        await task.value
        model.closeUSBRawSmart()
        model.finishUSBRawSmartDismissal()

        var renamed = Self.drive()
        renamed.bsdName = "disk101"
        renamed.deviceNode = "/dev/disk101"
        await inventory.setDrives([renamed])
        await model.refresh()
        XCTAssertEqual(model.snapshots["disk101"]?.temperatureCelsius, 37)
        XCTAssertEqual(model.snapshots["disk101"]?.driveID, "disk101")
        XCTAssertNil(model.snapshots["disk99"])

        var replacement = renamed
        replacement.serialNumber = "DIFFERENT-DRIVE"
        await inventory.setDrives([replacement])
        await model.refresh()
        XCTAssertNil(model.snapshots["disk101"]?.temperatureCelsius)
        XCTAssertNotEqual(model.snapshots["disk101"]?.selectedProvider, USBRawSmartService.providerName)

        await inventory.setDrives([])
        await model.refresh()
        await inventory.setDrives([renamed])
        await model.refresh()
        XCTAssertNil(model.snapshots["disk101"]?.temperatureCelsius)
    }

    @MainActor
    func testAmbiguousIdentityDoesNotDuplicateManualReading() async {
        let inventory = USBRawUpdatingRefresh()
        let model = Self.model(service: USBRawSuspendedService(), refresh: inventory)
        model.snapshots[Self.drive().id] = Self.result(restored: true).snapshot
        var duplicate = Self.drive()
        duplicate.bsdName = "disk101"
        duplicate.deviceNode = "/dev/disk101"
        await inventory.setDrives([Self.drive(), duplicate])
        await model.refresh()
        XCTAssertTrue(model.snapshots.values.allSatisfy { $0.temperatureCelsius == nil })
    }

    func testVerifiedNewReadingSupersedesManualSnapshotButUnsupportedStatusDoesNot() throws {
        let previous = try XCTUnwrap(Self.result(restored: true).snapshot)
        var drive = Self.drive()
        drive.smartStatusRaw = "Not Supported"
        let unavailable = SmartSnapshot.unavailable(for: drive, reason: "USB SMART unsupported")
        XCTAssertTrue(unavailable.hasSMARTPayload) // A status string alone is not a verified reading.
        let retained = USBRawSmartService.retainingManualRead(in: unavailable, from: previous, for: drive)
        XCTAssertEqual(retained.id, previous.id)
        XCTAssertEqual(retained.capturedAt, previous.capturedAt)
        var fresh = previous
        fresh.id = UUID()
        fresh.temperatureCelsius = 30
        fresh.selectedProvider = "Native macOS"
        fresh.providerStatuses = [ProviderStatus(name: "Native macOS", state: .available, message: "Read")]
        XCTAssertEqual(USBRawSmartService.retainingManualRead(
            in: fresh, from: previous, for: drive).id, fresh.id)
    }

    @MainActor
    func testCaptureEventsCannotInterruptPostReadInventoryReconciliation() async throws {
        let service = USBRawSuspendedService()
        let inventory = USBRawReconciliationRefresh()
        let monitor = ManualDriveSystemEventMonitor()
        let model = AppModel(refreshService: inventory, driveSystemEventMonitor: monitor,
                             driveSystemEventDebounceNanoseconds: 1_000_000, usbRawSmartService: service)
        let drive = Self.drive()
        model.drives = [drive]
        model.snapshots = [drive.id: .unavailable(for: drive, reason: "Not supported")]
        model.startDriveSystemEventMonitoring()
        defer { model.stopDriveSystemEventMonitoring() }
        let subscribed = await AsyncTestWaiter.wait { monitor.hasSubscriber }
        XCTAssertTrue(subscribed)
        model.requestUSBRawSmart(for: drive)
        let task = Task { await model.beginUSBRawSmart() }
        await service.waitUntilStarted()
        monitor.send(.volumeUnmounted)
        monitor.send(.deviceTerminated)
        await service.finish()
        let reconciling = await AsyncTestWaiter.wait { model.isRefreshing }
        XCTAssertTrue(reconciling)
        XCTAssertTrue(model.isUSBRawSmartActive)
        model.closeUSBRawSmart()
        XCTAssertNotNil(model.usbRawSmartSession)
        monitor.send(.deviceAppeared)
        monitor.send(.volumeMounted)
        await model.refresh()
        try await Task.sleep(for: .milliseconds(30))
        let count = await inventory.discoverCount
        XCTAssertEqual(count, 1)
        await inventory.finish()
        await task.value
        XCTAssertEqual(model.usbRawSmartSession?.state, .completed)
        XCTAssertEqual(model.selectedSnapshot?.temperatureCelsius, 37)
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

private actor USBRawSequencedRefresh: DriveRefreshing {
    let inventories: [[DriveDevice]]
    private(set) var discoverCount = 0
    init(inventories: [[DriveDevice]]) { self.inventories = inventories }
    func discover() async throws -> DriveRefreshSnapshot {
        let index = min(discoverCount, inventories.count - 1)
        discoverCount += 1
        return .init(drives: inventories[index], snapshots: [:])
    }
    func snapshotUpdates(for drives: [DriveDevice]) async -> AsyncStream<DriveSnapshotUpdate> {
        await USBRawCodexRefresh(drives: drives).snapshotUpdates(for: drives)
    }
}

private struct USBRawCodexRefresh: DriveRefreshing {
    let drives: [DriveDevice]
    func discover() async throws -> DriveRefreshSnapshot { .init(drives: drives, snapshots: [:]) }
    func snapshotUpdates(for drives: [DriveDevice]) async -> AsyncStream<DriveSnapshotUpdate> {
        AsyncStream { continuation in
            for drive in drives {
                continuation.yield(.init(driveID: drive.id,
                    snapshot: .unavailable(for: drive, reason: "Not supported"), phase: .complete))
            }
            continuation.finish()
        }
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

private actor USBRawUpdatingRefresh: DriveRefreshing {
    var liveDrives = [USBRawSmartTests.drive()]
    func setDrives(_ drives: [DriveDevice]) { liveDrives = drives }

    func discover() async throws -> DriveRefreshSnapshot {
        let drives = liveDrives.map { original in
            var drive = original
            drive.isSystemDisk = true // Avoid unrelated capability probes in this fixture.
            return drive
        }
        return DriveRefreshSnapshot(drives: drives, snapshots: [:])
    }

    func snapshotUpdates(for drives: [DriveDevice]) async -> AsyncStream<DriveSnapshotUpdate> {
        AsyncStream { continuation in
            for drive in drives {
                for phase in [DriveSnapshotUpdatePhase.native, .complete] {
                    continuation.yield(DriveSnapshotUpdate(
                        driveID: drive.id,
                        snapshot: .unavailable(for: drive, reason: "USB SMART unsupported"),
                        phase: phase))
                }
            }
            continuation.finish()
        }
    }
}

private actor USBRawReconciliationRefresh: DriveRefreshing {
    var discoverCount = 0
    var continuation: CheckedContinuation<Void, Never>?
    func discover() async throws -> DriveRefreshSnapshot {
        discoverCount += 1
        await withCheckedContinuation { continuation = $0 }
        var drive = USBRawSmartTests.drive()
        drive.isSystemDisk = true
        return DriveRefreshSnapshot(drives: [drive], snapshots: [:])
    }
    func finish() {
        continuation?.resume()
        continuation = nil
    }
    func snapshotUpdates(for drives: [DriveDevice]) async -> AsyncStream<DriveSnapshotUpdate> {
        AsyncStream { $0.finish() }
    }
}
