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
        XCTAssertEqual(record?.name, "JHL8440 (Goshen Ridge) Thunderbolt Controller")
        XCTAssertEqual(record?.topologyName, "JHL8440")
        XCTAssertEqual(record?.category, "Thunderbolt 4 Bridge")
    }

    func testCatalogResolvesJHLThunderboltGenerationMappings() {
        let descriptions = [
            "PCI 8086:15C0", "PCI 8086:15BF", "PCI 8086:15C1",
            "PCI 8086:15DA", "PCI 8086:15D9", "PCI 8086:15DB",
            "PCI 8086:15D3", "PCI 8086:15D2", "PCI 8086:15D4",
            "PCI 8086:15EF", "PCI 8086:15F0",
            "PCI 8086:15E7", "PCI 8086:15EA", "PCI 8086:15E8", "PCI 8086:15EB",
            "PCI 8086:15E9", "PCI 8086:15EC",
            "PCI 8086:57A4", "PCI 8086:57A5",
            "PCI 8086:5786", "PCI 8086:5787",
            "PCI 8086:5783", "PCI 8086:5784", "PCI 8086:5785",
            "PCI 8086:5780", "PCI 8086:5781", "PCI 8086:5782"
        ]
        let matches = DeviceHuntChipCatalog.bundled.resolve(chipDescriptions: descriptions)

        XCTAssertEqual(matches.count, descriptions.count)
        XCTAssertEqual(matches["PCI 8086:15C0"]?.topologyName, "JHL6240")
        XCTAssertEqual(matches["PCI 8086:15DA"]?.topologyName, "JHL6340")
        XCTAssertEqual(matches["PCI 8086:15D3"]?.topologyName, "JHL6540")
        XCTAssertEqual(matches["PCI 8086:15EF"]?.topologyName, "JHL7440")
        XCTAssertEqual(matches["PCI 8086:15E7"]?.topologyName, "JHL7540")
        XCTAssertEqual(matches["PCI 8086:57A4"]?.topologyName, "JHL9440")
        XCTAssertEqual(matches["PCI 8086:5786"]?.topologyName, "JHL9480")
        XCTAssertEqual(matches["PCI 8086:5783"]?.topologyName, "JHL9540")
        XCTAssertEqual(matches["PCI 8086:5780"]?.topologyName, "JHL9580")
        XCTAssertEqual(matches["PCI 8086:15BF"]?.category, "Thunderbolt 3 NHI")
        XCTAssertEqual(matches["PCI 8086:5782"]?.category, "Thunderbolt 5 USB Controller")
    }

    func testCatalogResolvesCommonUSB4AndNVMeControllersOffline() {
        let matches = DeviceHuntChipCatalog.bundled.resolve(chipDescriptions: [
            "PCI 1B21:2463",
            "PCI 1E4B:1202",
            "PCI 1E4B:1602",
            "PCI 1987:5012",
            "PCI 1987:5016",
            "PCI 1987:5018",
            "PCI 126F:2264",
            "PCI 126F:2267"
        ])

        XCTAssertEqual(matches["PCI 1B21:2463"]?.name, "ASM2464PD")
        XCTAssertEqual(matches["PCI 1B21:2463"]?.manufacturer, "ASMedia")
        XCTAssertEqual(matches["PCI 1E4B:1202"]?.name, "MAXIO MAP1202")
        XCTAssertEqual(matches["PCI 1E4B:1602"]?.name, "MAXIO MAP1602")
        XCTAssertEqual(matches["PCI 1987:5012"]?.name, "Phison PS5012-E12")
        XCTAssertEqual(matches["PCI 1987:5016"]?.name, "Phison PS5016-E16")
        XCTAssertEqual(matches["PCI 1987:5018"]?.name, "Phison PS5018-E18")
        XCTAssertEqual(matches["PCI 126F:2264"]?.name, "Silicon Motion SM2264")
        XCTAssertEqual(matches["PCI 126F:2267"]?.name, "Silicon Motion SM2267/SM2267XT")
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
