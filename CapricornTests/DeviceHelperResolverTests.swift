// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit
import IOKit.storage
import XCTest
@testable import Capricorn

final class DeviceHelperResolverTests: XCTestCase {
    func testAPFSWholeContainerDoesNotDuplicateItsPhysicalUSBDisk() throws {
        let fixture = HelperRegistryFixture()
        let disk = try DeviceHelperDeviceResolver.disk(forTarget: "usbraw:1004", registry: fixture.registry)
        XCTAssertEqual(disk.bsdName, "disk6")
        XCTAssertEqual(disk.sizeBytes, 4_096_805_658_624)
        XCTAssertEqual(disk.mediaRegistryID, 1001)
        XCTAssertEqual(disk.usbRegistryID, 1004, "Use the storage device, not its upstream USB hub.")
        XCTAssertFalse(disk.isInternal)
        XCTAssertTrue(fixture.references.isEmpty)
    }

    func testMultipleAPFSContainersAndVolumesRemainOnePhysicalDisk() throws {
        let fixture = HelperRegistryFixture()
        fixture.nodes[10] = .init(parent: 7, classes: ["IOMedia"], name: "disk12", whole: true)
        fixture.nodes[11] = .init(parent: 6, classes: ["IOMedia"], name: "disk7s1", whole: false)
        let disk = try DeviceHelperDeviceResolver.disk(forTarget: "usbraw:1004", registry: fixture.registry)
        XCTAssertEqual(disk.bsdName, "disk6")
        XCTAssertTrue(fixture.references.isEmpty)
    }

    func testDirectBSDTargetsRejectAPFSContainersAndPartitions() throws {
        let fixture = HelperRegistryFixture()
        for target in ["disk7", "/dev/disk7", "disk6s2", "/dev/disk6s2"] {
            XCTAssertThrowsError(try DeviceHelperDeviceResolver.disk(forTarget: target, registry: fixture.registry))
        }
        for target in ["disk6", "/dev/disk6"] {
            XCTAssertEqual(try DeviceHelperDeviceResolver.disk(forTarget: target, registry: fixture.registry).bsdName, "disk6")
        }
        XCTAssertTrue(fixture.references.isEmpty)
    }

    func testTwoPhysicalDisksBehindOneUSBTargetStillFailClosed() {
        let fixture = HelperRegistryFixture()
        fixture.nodes[10] = .init(parent: 11, classes: ["IOMedia"], name: "disk8", whole: true)
        fixture.nodes[11] = .init(parent: 12, classes: ["IOBlockStorageDriver"])
        fixture.nodes[12] = .init(parent: 4, classes: ["IOBlockStorageDevice"])
        XCTAssertThrowsError(try DeviceHelperDeviceResolver.disk(forTarget: "usbraw:1004", registry: fixture.registry)) {
            XCTAssertEqual(AppLanguage.simplifiedChinese.t($0.localizedDescription),
                           "此 SMART 目标对应多块物理硬盘，已停止操作。")
        }
        XCTAssertTrue(fixture.references.isEmpty)
    }

    func testUnrelatedDiskDoesNotMakeUSBTargetAmbiguous() throws {
        let fixture = HelperRegistryFixture()
        fixture.nodes[10] = .init(parent: 11, classes: ["IOMedia"], name: "disk8", whole: true)
        fixture.nodes[11] = .init(parent: 12, classes: ["IOBlockStorageDriver"])
        fixture.nodes[12] = .init(parent: 13, classes: ["IOBlockStorageDevice"])
        fixture.nodes[13] = .init(parent: 5, classes: ["IOUSBHostDevice"])
        let disk = try DeviceHelperDeviceResolver.disk(forTarget: "usbraw:1004", registry: fixture.registry)
        XCTAssertEqual(disk.bsdName, "disk6")
        XCTAssertTrue(fixture.references.isEmpty)
    }

    func testMissingAndUpstreamHubTargetsAreNotReportedAsMultipleDisks() {
        let fixture = HelperRegistryFixture()
        for target in ["usbraw:1005", "usbraw:9999", "usbraw:invalid", "/tmp/device"] {
            XCTAssertThrowsError(try DeviceHelperDeviceResolver.disk(forTarget: target, registry: fixture.registry)) {
                XCTAssertEqual(AppLanguage.simplifiedChinese.t($0.localizedDescription),
                               "未找到此 SMART 目标对应的已连接物理硬盘，请刷新硬盘列表后重试。")
            }
        }
        XCTAssertTrue(fixture.references.isEmpty)
    }

    func testInternalPhysicalStorageAndDriverSubclassRemainSupported() throws {
        let fixture = HelperRegistryFixture()
        fixture.nodes[3]?.properties["Protocol Characteristics"] = ["Physical Interconnect Location": "Internal"]
        fixture.nodes[3]?.parent = 0
        fixture.nodes[2]?.classes.insert("CustomBlockStorageDriverSubclass")
        let disk = try DeviceHelperDeviceResolver.resolve(bsdName: "disk6", registry: fixture.registry)
        XCTAssertTrue(disk.isInternal)
        XCTAssertNil(disk.usbRegistryID)
        XCTAssertEqual(disk.mediaRegistryID, 1001)
        XCTAssertTrue(fixture.references.isEmpty)
    }

    func testWholeDiskImagesAndMissingStorageProvidersAreRejected() {
        for kind in 0..<5 {
            let fixture = HelperRegistryFixture()
            switch kind {
            case 0: fixture.nodes[3]?.classes = ["VirtualStorageDevice"]
            case 1: fixture.nodes[1]?.parent = 0
            case 2: fixture.nodes[2]?.classes = ["PartitionScheme"]
            case 3: fixture.nodes[1]?.properties[kIOMediaSizeKey] = NSNumber(value: 0)
            default:
                fixture.nodes[3]?.properties["Protocol Characteristics"] = [
                    "Physical Interconnect": "Virtual Interface", "Physical Interconnect Location": "File"
                ]
            }
            XCTAssertThrowsError(try DeviceHelperDeviceResolver.resolve(bsdName: "disk6", registry: fixture.registry))
            XCTAssertTrue(fixture.references.isEmpty, "kind=\(kind)")
        }
    }
}

private final class HelperRegistryFixture {
    struct Node {
        var parent: io_registry_entry_t
        var classes: Set<String>
        var properties: [String: Any]

        init(parent: io_registry_entry_t, classes: Set<String>, name: String? = nil, whole: Bool? = nil) {
            self.parent = parent
            self.classes = classes
            properties = [:]
            if let name { properties[kIOBSDNameKey] = name }
            if let whole {
                properties[kIOMediaWholeKey] = whole
                properties[kIOMediaSizeKey] = NSNumber(value: name == "disk6" ? 4_096_805_658_624 : 4_096_594_542_592)
            }
        }
    }

    // Mirrors the live disk6 -> disk6s2 -> APFS disk7 stack, with a USB hub.
    var nodes: [io_registry_entry_t: Node] = [
        1: .init(parent: 2, classes: ["IOMedia"], name: "disk6", whole: true),
        2: .init(parent: 3, classes: ["IOBlockStorageDriver"]),
        3: .init(parent: 4, classes: ["IOBlockStorageDevice"]),
        4: .init(parent: 5, classes: ["IOUSBHostDevice"]),
        5: .init(parent: 0, classes: ["IOUSBHostDevice"]),
        6: .init(parent: 7, classes: ["IOMedia", "AppleAPFSMedia"], name: "disk7", whole: true),
        7: .init(parent: 8, classes: ["AppleAPFSContainerScheme"]),
        8: .init(parent: 9, classes: ["IOMedia"], name: "disk6s2", whole: false),
        9: .init(parent: 1, classes: ["IOGUIDPartitionScheme"])
    ]
    var references: [io_registry_entry_t: Int] = [:]

    private func retained(_ entry: io_registry_entry_t) -> io_registry_entry_t {
        if entry != 0 {
            XCTAssertNotNil(nodes[entry])
            references[entry, default: 0] += 1
        }
        return entry
    }

    var registry: DeviceHelperRegistry {
        .init(
            matchingBSDName: { name in
                self.retained(self.nodes.first { $0.value.properties[kIOBSDNameKey] as? String == name }?.key ?? 0)
            },
            parent: { self.retained(self.nodes[$0]?.parent ?? 0) },
            property: { self.nodes[$0]?.properties[$1] },
            conforms: { self.nodes[$0]?.classes.contains($1) == true },
            identifier: { self.nodes[$0] == nil ? nil : UInt64($0) + 1000 },
            retain: { _ = self.retained($0) },
            release: { entry in
                let count = self.references[entry, default: 0]
                XCTAssertGreaterThan(count, 0, "Unbalanced registry release: \(entry)")
                if count <= 1 { self.references.removeValue(forKey: entry) }
                else { self.references[entry] = count - 1 }
            },
            mediaNames: {
                self.nodes.sorted { $0.key < $1.key }.compactMap {
                    $0.value.classes.contains("IOMedia") ? $0.value.properties[kIOBSDNameKey] as? String : nil
                }
            })
    }
}
