import XCTest
@testable import Capricorn

final class DriveConnectionInfoTests: XCTestCase {
    func testUSBConnectionShowsCompactAndDetailedLabels() {
        let info = DriveConnectionInfo(
            transport: .usb,
            generation: "USB3.0",
            negotiatedBitsPerSecond: 5_000_000_000,
            pathDescription: nil
        )

        XCTAssertEqual(info.compactLabel, "USB3.0")
        XCTAssertEqual(info.detailLabel, "USB3.0 · 5 Gb/s")
    }

    func testThunderboltThroughUSBPathShowsEffectiveSpeed() {
        let info = DriveConnectionInfo(
            transport: .thunderbolt,
            generation: "TBT4",
            negotiatedBitsPerSecond: 480_000_000,
            pathDescription: "TBT4 → USB2.0"
        )

        XCTAssertEqual(info.compactLabel, "TBT4")
        XCTAssertEqual(info.detailLabel(effectiveLabel: "有效"), "TBT4 → USB2.0 · 有效 480 Mb/s")
    }

    func testThunderboltConnectionShowsFortyGigabitSpeed() {
        let info = DriveConnectionInfo(
            transport: .thunderbolt,
            generation: "TBT4",
            negotiatedBitsPerSecond: 40_000_000_000,
            pathDescription: nil
        )

        XCTAssertEqual(info.compactLabel, "TBT4")
        XCTAssertEqual(info.detailLabel(effectiveLabel: "有效"), "TBT4 · 40 Gb/s")
    }

    func testUSB4ThunderboltCompatibleBridgeUsesUSB4CompactLabel() {
        let info = DriveConnectionInfo(
            transport: .thunderbolt,
            generation: "TBT4",
            negotiatedBitsPerSecond: 40_000_000_000,
            pathDescription: nil,
            bridgeKind: .usb4ThunderboltCompatible
        )

        XCTAssertEqual(info.compactLabel, "USB4")
        XCTAssertEqual(info.detailLabel(effectiveLabel: "有效"), "USB4/TBT · 40 Gb/s")
    }

    func testConnectionInfoRemainsCodable() throws {
        let original = DriveConnectionInfo(
            transport: .usb4,
            generation: "USB4",
            negotiatedBitsPerSecond: 40_000_000_000,
            pathDescription: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DriveConnectionInfo.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
