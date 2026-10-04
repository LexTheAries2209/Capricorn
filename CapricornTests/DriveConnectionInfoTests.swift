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
            generation: "TB4",
            negotiatedBitsPerSecond: 480_000_000,
            pathDescription: "TB4 → USB2.0"
        )

        XCTAssertEqual(info.compactLabel, "TB4")
        XCTAssertEqual(info.detailLabel, "TB4 → USB2.0 · 有效 480 Mb/s")
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
