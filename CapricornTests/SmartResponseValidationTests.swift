// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import Capricorn

final class SmartResponseValidationTests: XCTestCase {
    private static var drive: DriveDevice { USBRawSmartTests.drive() }

    private static var response: [String: Any] {
        [
            "smartctl": ["version": [7, 5], "exit_status": 0],
            "model_name": "Test SATA SSD",
            "serial_number": "SSD-123",
            "firmware_version": "1.0",
            "smart_status": ["passed": true],
            "power_on_time": ["hours": 59482],
            "ata_smart_attributes": [
                "table": [
                    ["id": 66, "name": "Unknown_Attribute", "value": 100, "worst": 100,
                     "thresh": 0, "raw": ["value": 140737488486400 as Int64]]
                ]
            ]
        ]
    }

    private func result(_ root: [String: Any], stderr: String = "", status: Int32 = 0) throws -> CommandResult {
        CommandResult(stdout: try JSONSerialization.data(withJSONObject: root),
                      stderr: Data(stderr.utf8), terminationStatus: status)
    }

    private func snapshot(_ root: [String: Any], stderr: String = "", status: Int32 = 0) throws -> SmartSnapshot {
        let value = try result(root, stderr: stderr, status: status)
        return SmartctlParser.parseSnapshot(
            value.stdout, drive: Self.drive, providerName: "smartctl",
            exitStatus: value.terminationStatus, stderr: value.stderr)
    }

    func testBinaryIdentityCannotBecomeSMARTAttributesOrHealth() throws {
        // The U330 returned these escaped bytes through the SAT driver.
        for (field, value) in [
            ("serial_number", #"\x01"#),
            ("model_name", #"\xcf\x0b\xf4\x0b"#),
            ("firmware_version", #";\x0b`\x0b"#),
            ("serial_number", "SERIAL\u{0001}"),
            ("model_name", "MODEL\u{0000}")
        ] {
            var root = Self.response
            root[field] = value
            root["smart_status"] = ["passed": false]
            let parsed = try snapshot(root, status: 4)
            XCTAssertEqual(parsed.health, .unavailable, field)
            XCTAssertFalse(parsed.hasSMARTPayload, field)
            XCTAssertTrue(parsed.attributes.isEmpty, field)
            XCTAssertNil(parsed.powerOnHours, field)
            XCTAssertNil(parsed.smartStatusRaw, field)
            XCTAssertNil(parsed.deviceSerialNumber, field)
            XCTAssertNil(parsed.selfTestReport, field)
            XCTAssertEqual(parsed.providerStatuses.first?.state, .failed, field)
            XCTAssertNotNil(parsed.smartctlDiagnostics?.openError, field)
        }
    }

    func testEmptyIdentityAndContradictorySupportDoNotValidatePayload() throws {
        for field in ["model_name", "smart_support"] {
            var root = Self.response
            if field == "model_name" { root[field] = "" }
            else { root[field] = ["available": false] }
            let parsed = try snapshot(root)
            XCTAssertFalse(parsed.hasSMARTPayload, field)
            XCTAssertEqual(parsed.health, .unavailable, field)
        }
    }

    func testSMARTChecksumErrorsRejectDataInJSONAndStderr() throws {
        let warning = "Warning! SMART Attribute Data Structure error: invalid SMART checksum."
        var root = Self.response
        root["smartctl"] = [
            "exit_status": 4,
            "messages": [["string": warning, "severity": "warning"]]
        ]
        for parsed in [try snapshot(root, status: 4),
                       try snapshot(Self.response, stderr: warning, status: 4)] {
            XCTAssertFalse(parsed.hasSMARTPayload)
            XCTAssertTrue(parsed.attributes.isEmpty)
            XCTAssertEqual(parsed.health, .unavailable)
        }
    }

    func testValidPartialResponsesVendorValuesAndActualFailureRemainVisible() throws {
        for status in [0, 4, 8, 16, 64] {
            var root = Self.response
            root["smartctl"] = ["exit_status": status]
            root["smart_status"] = ["passed": status != 8]
            let parsed = try snapshot(root, status: Int32(status))
            XCTAssertTrue(parsed.hasSMARTPayload, "\(status)")
            XCTAssertEqual(parsed.attributes.first?.rawValue, "140737488486400")
            XCTAssertEqual(parsed.powerOnHours, 59482)
            XCTAssertEqual(parsed.deviceSerialNumber, "SSD-123")
            XCTAssertEqual(parsed.health, status == 8 ? .failed : .good)
        }
    }

    func testFatalExitWithoutMessageCannotValidatePayload() throws {
        var root = Self.response
        root["smartctl"] = ["exit_status": 2]
        let parsed = try snapshot(root, status: 2)
        XCTAssertFalse(parsed.hasSMARTPayload)
        XCTAssertEqual(parsed.health, .unavailable)
    }

    func testInvalidIdentityCannotBecomeSelfTestOrErrorLogResults() throws {
        var root = Self.response
        root["serial_number"] = #"\x01"#
        root["ata_smart_data"] = [
            "self_test": ["short_supported": true, "extended_supported": true]
        ]
        root["ata_smart_error_log"] = ["summary": ["count": 1]]
        let value = try result(root)
        XCTAssertNil(SmartctlParser.parseSelfTestCapability(value))
        XCTAssertNil(SmartctlParser.parseErrorLog(value))
        XCTAssertEqual(SmartctlParser.commandFailureMessage(value),
                       "The device returned invalid SMART data. No health information is available.")
    }

    func testSerialFilteringAndStableMatchingRejectBinaryPlaceholders() {
        for serial in [#"\x01"#, "SERIAL\u{0000}", "BAD\u{0007}SERIAL"] {
            XCTAssertNil(DriveSerialNumberNormalizer.normalize(serial))
            var drive = Self.drive
            drive.serialNumber = serial
            XCTAssertEqual(DrivePageHeaderText.serialNumber(for: drive, language: .simplifiedChinese), "无")
        }
        XCTAssertEqual(DriveSerialNumberNormalizer.normalize("  X01TV11K520591  "), "X01TV11K520591")
        var first = Self.drive
        first.serialNumber = #"\x01"#
        first.volumes = []
        var other = first
        other.bsdName = "disk100"
        XCTAssertFalse(DriveStableIdentityMatcher.matches(first, other))
    }

    func testFailedDedicatedDiagnosticsCannotUsePartialPayload() throws {
        var root = Self.response
        root["smartctl"] = ["exit_status": 4]
        root["ata_smart_data"] = ["self_test": ["short_supported": true]]
        root["ata_smart_error_log"] = ["summary": ["count": 1]]
        let value = try result(root, status: 4)
        XCTAssertNil(SmartctlParser.parseSelfTestCapability(value))
        XCTAssertNil(SmartctlParser.parseErrorLog(value))
    }

    func testLegacyInvalidSnapshotCannotSupplyRetainedHealthOrSerial() throws {
        let drive = Self.drive
        var previous = try snapshot(Self.response)
        previous.deviceSerialNumber = #"\x01"#
        previous.selectedProvider = USBRawSmartService.providerName
        previous.providerStatuses = [ProviderStatus(
            name: USBRawSmartService.providerName, state: .available, message: "Old reading")]
        XCTAssertFalse(previous.hasSMARTPayload)
        XCTAssertNil(previous.reportedSerialNumber(for: drive))
        XCTAssertNil(previous.verifiedSource)
        XCTAssertEqual(DriveHealthEvaluator().evaluate(drive: drive, snapshot: previous), .unavailable)
        var skipped = SmartSnapshot.unavailable(for: drive, reason: "Standby")
        skipped.smartctlDiagnostics = SmartctlDiagnostics(readSkippedToAvoidWake: true)
        XCTAssertNil(skipped.retainingSMARTData(from: previous, for: drive).powerOnHours)
        XCTAssertNil(USBRawSmartService.retainingManualRead(
            in: skipped, from: previous, for: drive).powerOnHours)
        previous.providerStatuses = [ProviderStatus(name: "Native macOS", state: .available, message: "Read")]
        var failed = SmartSnapshot.unavailable(for: drive, reason: "Native read failed")
        failed.providerStatuses = [ProviderStatus(name: "Native macOS", state: .failed, message: "Read failed")]
        XCTAssertNil(failed.retainingNativeSMARTDataIfNeeded(from: previous, for: drive).powerOnHours)
    }

    func testValidManualReadingSurvivesAnInvalidOrdinaryTransport() throws {
        let previous = try XCTUnwrap(USBRawSmartService.parse(
            CommandResult(stdout: Data(USBRawSmartTests.json.utf8), stderr: Data(), terminationStatus: 0),
            drive: Self.drive, target: USBRawSmartTests.target, type: "sntrealtek").snapshot)
        var root = Self.response
        root["serial_number"] = #"\x01"#
        let rejected = try snapshot(root)
        let retained = USBRawSmartService.retainingManualRead(in: rejected, from: previous, for: Self.drive)
        XCTAssertEqual(retained.id, previous.id)
        XCTAssertEqual(retained.temperatureCelsius, 37)
    }

    func testInvalidSNTResponseDoesNotBecomeAManualReading() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(USBRawSmartTests.json.utf8)) as? [String: Any])
        root["serial_number"] = #"\x01"#
        let parsed = USBRawSmartService.parse(
            try result(root), drive: Self.drive, target: USBRawSmartTests.target, type: "sntrealtek")
        XCTAssertFalse(try XCTUnwrap(parsed.snapshot).hasSMARTPayload)
        XCTAssertNil(parsed.snapshot?.selectedProvider)
        XCTAssertNil(parsed.snapshot?.verifiedSource)
    }

    @MainActor
    func testRefreshDropsLegacyInvalidManualReadingBeforeProviderUpdates() async throws {
        let drive = Self.drive
        var previous = try snapshot(Self.response)
        previous.deviceSerialNumber = #"\x01"#
        previous.selectedProvider = USBRawSmartService.providerName
        let model = AppModel(refreshService: ValidationDiscoveryOnlyRefresh(drive: drive))
        model.drives = [drive]
        model.selectedDriveID = drive.id
        model.snapshots[drive.id] = previous
        model.smartSelfTestCapabilities[drive.id] = .unavailable("Fixture")
        await model.refresh()
        XCTAssertTrue(model.selectedSnapshot?.attributes.isEmpty == true)
        XCTAssertNil(model.selectedSnapshot?.powerOnHours)
        XCTAssertNil(model.selectedSnapshot?.deviceSerialNumber)
        XCTAssertNil(model.selectedSnapshot?.selectedProvider)
    }

    func testRejectedSmartctlResponseDoesNotDiscardValidNativeHealth() async throws {
        var native = SmartSnapshot.unavailable(for: Self.drive, reason: "Native data")
        native.providerStatuses = [ProviderStatus(name: "Native macOS", state: .available, message: "Read")]
        native.smartStatusRaw = "Verified"
        native.temperatureCelsius = 31
        native.selectedProvider = "Native macOS"
        var root = Self.response
        root["serial_number"] = #"\x01"#
        let service = SmartSnapshotService(
            nativeProvider: ValidationFixtureProvider(providerName: "Native macOS", value: native),
            smartctlProvider: ValidationFixtureProvider(providerName: "smartctl", value: try snapshot(root)))
        let merged = await service.snapshot(for: Self.drive)
        XCTAssertEqual(merged.health, .good)
        XCTAssertEqual(merged.temperatureCelsius, 31)
        XCTAssertNil(merged.powerOnHours)
        XCTAssertNil(merged.deviceSerialNumber)
        XCTAssertEqual(merged.selectedProvider, "Native macOS")
    }
}

private struct ValidationFixtureProvider: SmartProviding {
    let providerName: String
    let value: SmartSnapshot
    func snapshot(for drive: DriveDevice) async -> SmartSnapshot? { value }
}

private struct ValidationDiscoveryOnlyRefresh: DriveRefreshing {
    let drive: DriveDevice
    func discover() async throws -> DriveRefreshSnapshot {
        DriveRefreshSnapshot(drives: [drive], snapshots: [:])
    }
    func snapshotUpdates(for drives: [DriveDevice]) async -> AsyncStream<DriveSnapshotUpdate> {
        AsyncStream { $0.finish() }
    }
}
