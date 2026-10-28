// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class DeviceHuntChipCatalogTests: XCTestCase {
    func testParsesAndNormalizesPCIIdentifier() throws {
        let identifier = try XCTUnwrap(DeviceChipIdentifier(description: "PCI 10de:1eb8"))

        XCTAssertEqual(identifier.displayValue, "PCI 10DE:1EB8")
    }

    func testParsesAndNormalizesUSBIdentifier() throws {
        let identifier = try XCTUnwrap(DeviceChipIdentifier(description: "USB 04a5:0002"))

        XCTAssertEqual(identifier.displayValue, "USB 04A5:0002")
    }

    func testRejectsMalformedChipDescriptions() {
        XCTAssertNil(DeviceChipIdentifier(description: "PCI 1234:ABC"))
        XCTAssertNil(DeviceChipIdentifier(description: "SATA 1234:5678"))
        XCTAssertNil(DeviceChipIdentifier(description: "PCI 1234:5678 extra"))
    }

    func testBundledCatalogHasCommonUSBAndPCIControllers() {
        let catalog = DeviceHuntChipCatalog.bundled
        XCTAssertGreaterThanOrEqual(catalog.records.count, 30)
        XCTAssertEqual(catalog.source, "DeviceHunt")
        XCTAssertEqual(catalog.snapshotDate, "2026-10-28")

        let manufacturers = Set(catalog.records.map(\.manufacturer))
        XCTAssertTrue(manufacturers.contains("ASMedia"))
        XCTAssertTrue(manufacturers.contains("Intel"))
        XCTAssertTrue(manufacturers.contains("VIA Labs"))
    }

    func testCatalogCoversCommonASMediaIntelAndVIAHubControllers() {
        let matches = DeviceHuntChipCatalog.bundled.resolve(chipDescriptions: [
            "PCI 1B21:2142",
            "PCI 8086:7A60",
            "PCI 1106:3483",
            "USB 174C:3074",
            "USB 2109:0812"
        ])

        XCTAssertEqual(matches["PCI 1B21:2142"]?.manufacturer, "ASMedia")
        XCTAssertEqual(matches["PCI 1B21:2142"]?.category, "USB 3.1 Host Controller")
        XCTAssertEqual(matches["PCI 8086:7A60"]?.manufacturer, "Intel")
        XCTAssertEqual(matches["PCI 1106:3483"]?.name, "VL805/806 xHCI USB 3.0 Controller")
        XCTAssertEqual(matches["USB 174C:3074"]?.name, "ASM1074 SuperSpeed Hub")
        XCTAssertEqual(matches["USB 2109:0812"]?.name, "VL812 Hub")
    }

    func testCatalogResolvesGoshenRidgeThunderboltBridgeAsJHL8440() {
        let record = DeviceHuntChipCatalog.bundled.resolve(chipDescriptions: ["PCI 8086:0B26"])["PCI 8086:0B26"]

        XCTAssertEqual(record?.manufacturer, "Intel")
        XCTAssertEqual(record?.name, "JHL8440 (Goshen Ridge) Thunderbolt 4 Controller")
        XCTAssertEqual(record?.category, "Thunderbolt 4 Bridge")
    }

    func testResolvesPCIStorageAndUSBBridgeChipNamesLocally() {
        let catalog = DeviceHuntChipCatalog.bundled
        let matches = catalog.resolve(chipDescriptions: [
            "PCI 1b21:1166",
            "USB 152D:0583",
            "USB 0BDA:9210"
        ])

        XCTAssertEqual(matches["PCI 1B21:1166"]?.name, "ASM1166 Serial ATA Controller")
        XCTAssertEqual(matches["PCI 1B21:1166"]?.category, "SATA Controller")
        XCTAssertEqual(matches["USB 152D:0583"]?.name, "JMS583 Gen 2 to PCIe Gen3x2 Bridge")
        XCTAssertEqual(matches["USB 0BDA:9210"]?.name, "RTL9210 M.2 NVMe Adapter")
    }

    func testUnknownIDsAreOmittedAndCanRemainVisibleAsRawIdentifiers() {
        let matches = DeviceHuntChipCatalog.bundled.resolve(chipDescriptions: [
            "USB FFFF:FFFF",
            "PCI ABCD:1234",
            "SATA 1234:5678"
        ])

        XCTAssertTrue(matches.isEmpty)
        XCTAssertEqual(DeviceChipIdentifier(description: "USB FFFF:FFFF")?.displayValue, "USB FFFF:FFFF")
    }

    func testRejectsDuplicateOrInvalidCatalogRecords() {
        let duplicate = """
        {
          "schemaVersion": 1,
          "source": "DeviceHunt",
          "snapshotDate": "2026-10-28",
          "records": [
            {"id":"PCI 1B21:1166","manufacturer":"ASMedia","category":"SATA Controller","name":"ASM1166","sourceURL":"https://devicehunt.com/view/type/pci/vendor/1B21/device/1166"},
            {"id":"PCI 1b21:1166","manufacturer":"ASMedia","category":"SATA Controller","name":"Duplicate","sourceURL":"https://devicehunt.com/view/type/pci/vendor/1B21/device/1166"}
          ]
        }
        """
        let invalidSource = """
        {
          "schemaVersion": 1,
          "source": "DeviceHunt",
          "snapshotDate": "2026-10-28",
          "records": [
            {"id":"PCI 1B21:1166","manufacturer":"ASMedia","category":"SATA Controller","name":"ASM1166","sourceURL":"https://example.com/device"}
          ]
        }
        """

        XCTAssertThrowsError(try DeviceHuntChipCatalog(data: Data(duplicate.utf8)))
        XCTAssertThrowsError(try DeviceHuntChipCatalog(data: Data(invalidSource.utf8)))
    }
}
