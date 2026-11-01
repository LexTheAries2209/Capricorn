// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import Capricorn

final class SmartctlTargetIdentityTests: XCTestCase {
    private func resolve(_ names: [String]) async throws -> SmartctlTargetDescriptor? {
        var drive = USBRawSmartTests.drive()
        drive.bsdName = "disk7"
        drive.deviceNode = "/dev/disk7"
        let scan = try JSONSerialization.data(withJSONObject: [
            "devices": names.map { ["name": $0, "type": "sat", "protocol": "ATA"] }
        ])
        let provider = SmartctlSmartProvider(
            runner: TargetScanFixtureRunner(scan: scan),
            bundledExecutableURL: URL(fileURLWithPath: "/usr/bin/true"),
            bundledDriveDatabaseURL: URL(fileURLWithPath: #filePath),
            commandCoordinator: SmartctlCommandCoordinator(),
            ioServiceTargetResolver: NoTargetFixtureResolver(),
            avoidsWakingSleepingDisks: { true })
        return await provider.resolvedTargetDescriptors(for: [drive])[drive.id]
    }

    func testExactDiskWinsOverEarlierPrefixCollisions() async throws {
        let descriptor = try await resolve(["/dev/disk70", "/dev/disk71", "/dev/disk7"])
        XCTAssertEqual(descriptor?.path, "/dev/disk7")
        XCTAssertEqual(descriptor?.type, "sat")
    }

    func testSimilarDiskNumbersAndPartitionsCannotSelectAnotherDevice() async throws {
        for name in ["/dev/disk70", "/dev/disk71", "/dev/disk7s1", "/dev/disk7s10"] {
            let descriptor = try await resolve([name])
            XCTAssertNil(descriptor, name)
        }
    }

    func testBareBSDNamesAndDeviceNodesBothMatchExactly() async throws {
        for name in ["disk7", "/dev/disk7"] {
            let descriptor = try await resolve([name])
            XCTAssertEqual(descriptor?.path, name)
        }
    }
}

private struct TargetScanFixtureRunner: CommandRunning {
    let scan: Data
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        CommandResult(stdout: scan, stderr: Data(), terminationStatus: 0)
    }
}

private struct NoTargetFixtureResolver: SmartctlIOServiceTargetResolving {
    func targetDescriptor(for drive: DriveDevice) -> SmartctlTargetDescriptor? { nil }
}
