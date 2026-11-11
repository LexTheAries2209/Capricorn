// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class SmartSelfTestVisibilityTests: XCTestCase {
    private func snapshot(for drive: DriveDevice, source: String) -> SmartSnapshot {
        var snapshot = CapricornTests.fixtureSnapshot(for: drive)
        snapshot.attributes = [SmartAttribute(
            id: "temperature.current", name: "Temperature", rawValue: "32 C",
            current: nil, worst: nil, threshold: nil, status: .good, source: source)]
        return snapshot
    }

    func testDisabledOverrideKeepsExistingRules() {
        var drive = CapricornTests.fixtureDrive()
        drive.isSystemDisk = false
        let smartctl = snapshot(for: drive, source: "smartctl")
        let native = snapshot(for: drive, source: "Native macOS")
        XCTAssertTrue(SmartDiagnosticsVisibilityPolicy.showsSelfTestPanel(
            for: drive, snapshot: smartctl, isEnabled: true, alwaysShow: false))
        XCTAssertFalse(SmartDiagnosticsVisibilityPolicy.showsSelfTestPanel(
            for: drive, snapshot: smartctl, isEnabled: false, alwaysShow: false))
        XCTAssertFalse(SmartDiagnosticsVisibilityPolicy.showsSelfTestPanel(
            for: drive, snapshot: native, isEnabled: true, alwaysShow: false))
        drive.isSystemDisk = true
        XCTAssertFalse(SmartDiagnosticsVisibilityPolicy.showsSelfTestPanel(
            for: drive, snapshot: smartctl, isEnabled: true, alwaysShow: false))
        drive.isSystemDisk = false
        drive.isNetwork = true
        XCTAssertFalse(SmartDiagnosticsVisibilityPolicy.showsSelfTestPanel(
            for: drive, snapshot: smartctl, isEnabled: true, alwaysShow: false))
    }

    func testOverrideShowsEveryDriveKindWithSMARTDataEvenWhenDiagnosticsIsOff() {
        for kind in ["system", "network", "memory-card", "virtual", "external"] {
            var drive = CapricornTests.fixtureDrive()
            drive.isInternal = kind == "system"
            drive.isSystemDisk = kind == "system"
            drive.isNetwork = kind == "network"
            drive.isMemoryCard = kind == "memory-card"
            drive.isVirtual = kind == "virtual"
            XCTAssertTrue(SmartDiagnosticsVisibilityPolicy.showsSelfTestPanel(
                for: drive, snapshot: snapshot(for: drive, source: "Native macOS"),
                isEnabled: false, alwaysShow: true), kind)
        }
    }

    func testOverrideRequiresSMARTDataFromTheCurrentDrive() {
        var drive = CapricornTests.fixtureDrive()
        drive.smartStatusRaw = "Not Supported"
        var unavailable = SmartSnapshot.unavailable(for: drive, reason: "Not supported")
        XCTAssertTrue(unavailable.hasSMARTPayload, "The legacy payload flag also counts inventory status text.")
        XCTAssertFalse(SmartDiagnosticsVisibilityPolicy.showsSelfTestPanel(
            for: drive, snapshot: nil, isEnabled: true, alwaysShow: true))
        XCTAssertFalse(SmartDiagnosticsVisibilityPolicy.showsSelfTestPanel(
            for: drive, snapshot: unavailable, isEnabled: true, alwaysShow: true))
        unavailable.selectedProvider = "smartctl"
        unavailable.providerStatuses = [.init(name: "smartctl", state: .available, message: "Identified")]
        XCTAssertFalse(SmartDiagnosticsVisibilityPolicy.showsSelfTestPanel(
            for: drive, snapshot: unavailable, isEnabled: true, alwaysShow: true))
        var stale = snapshot(for: drive, source: "Native macOS")
        stale.driveID = "another-disk"
        XCTAssertFalse(SmartDiagnosticsVisibilityPolicy.showsSelfTestPanel(
            for: drive, snapshot: stale, isEnabled: true, alwaysShow: true))
        unavailable.smartStatusRaw = "Passed"
        unavailable.health = .good
        XCTAssertTrue(SmartDiagnosticsVisibilityPolicy.showsSelfTestPanel(
            for: drive, snapshot: unavailable, isEnabled: false, alwaysShow: true))
    }

    func testSNTStaysHiddenIncludingMixedSourcesAndOrdinarySNTTransports() throws {
        let drive = USBRawSmartTests.drive()
        let raw = try XCTUnwrap(USBRawSmartTests.result(restored: true).snapshot)
        var mixed = raw
        mixed.attributes += snapshot(for: drive, source: "smartctl").attributes
        var ordinary = snapshot(for: drive, source: "smartctl")
        ordinary.selectedTransport = "sntjmicron"
        var diagnosticsOnly = snapshot(for: drive, source: "smartctl")
        diagnosticsOnly.smartctlDiagnostics = .init(deviceType: "sntrealtek", protocolName: "NVMe")
        for snapshot in [raw, mixed, ordinary, diagnosticsOnly] {
            for alwaysShow in [false, true] {
                XCTAssertFalse(SmartDiagnosticsVisibilityPolicy.showsSelfTestPanel(
                    for: drive, snapshot: snapshot, isEnabled: true, alwaysShow: alwaysShow))
            }
        }
    }
}
