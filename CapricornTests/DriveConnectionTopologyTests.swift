// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class DriveConnectionTopologyTests: XCTestCase {
    func testPCIeLinkStatusDecodesGenerationSpeedAndWidth() throws {
        let link = try XCTUnwrap(DrivePCIeLinkParser.parse(linkStatus: 4 | (4 << 4)))

        XCTAssertEqual(link.generation, 4)
        XCTAssertEqual(link.gigatransfersPerSecond, 16.0)
        XCTAssertEqual(link.laneCount, 4)
        XCTAssertEqual(link.detailLabel, "16.0 GT/s · x4")
    }

    func testPCIeLinkStatusRejectsUnknownRateAndMissingWidth() {
        XCTAssertNil(DrivePCIeLinkParser.parse(linkStatus: 7 | (4 << 4)))
        XCTAssertNil(DrivePCIeLinkParser.parse(linkStatus: 4))
    }

    func testTopologyOrdersHostControllerAndDiskAndCarriesPCIeLink() throws {
        let drive = Self.drive()
        let topology = try XCTUnwrap(DriveConnectionTopologyResolver.resolve(
            drive: drive,
            registryEntriesFromDiskToHost: [
                .init(className: "IOMedia", entryName: "External SSD Media", bsdName: "disk8", pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(className: "IONVMeBlockStorageDevice", entryName: "IONVMeBlockStorageDevice@1", bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(className: "IONVMeController", entryName: "IONVMeController", bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(className: "IOPCIDevice", entryName: "pci1e4b,1602", bsdName: nil, pcieLinkStatus: 4 | (4 << 4), isPCIeTunnelled: true),
                .init(className: "IOPCI2PCIBridge", entryName: "IOPP", bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false)
            ]
        ))

        XCTAssertTrue(topology.hasResolvedController)
        XCTAssertEqual(topology.nodes.map(\.kind), [
            .computer, .pcieTunnel, .pcieBridge, .pcieDevice, .nvmeController, .disk
        ])
        XCTAssertEqual(topology.nodes[3].hardwareName, "pci1e4b,1602")
        XCTAssertEqual(topology.nodes[3].pcieLink?.detailLabel, "16.0 GT/s · x4")
        XCTAssertNil(topology.nodes[2].hardwareName)
    }

    func testUSBRegistryEntriesProduceHostToDevicePathWithoutPCIeRate() throws {
        let drive = Self.drive()
        let topology = try XCTUnwrap(DriveConnectionTopologyResolver.resolve(
            drive: drive,
            registryEntriesFromDiskToHost: [
                .init(className: "IOMedia", entryName: "USB SSD Media", bsdName: "disk8", pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(className: "IOUSBHostDevice", entryName: "Portable SSD", bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(className: "AppleUSBXHCI", entryName: "USB Host Controller", bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false)
            ]
        ))

        XCTAssertEqual(topology.nodes.map(\.kind), [
            .computer, .usbHostController, .usbDevice, .disk
        ])
        XCTAssertTrue(topology.nodes.allSatisfy { $0.pcieLink == nil })
    }

    func testPCIeDeviceEntryNamedAsBridgeUsesBridgeNodeKind() throws {
        let topology = try XCTUnwrap(DriveConnectionTopologyResolver.resolve(
            drive: Self.drive(),
            registryEntriesFromDiskToHost: [
                .init(className: "IOMedia", entryName: "External SSD Media", bsdName: "disk8", pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(className: "IONVMeController", entryName: "IONVMeController", bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(className: "IOPCIDevice", entryName: "pcic2-bridge", bsdName: nil, pcieLinkStatus: 1 | (16 << 4), isPCIeTunnelled: false)
            ]
        ))

        XCTAssertEqual(topology.nodes.map(\.kind), [
            .computer, .pcieBridge, .nvmeController, .disk
        ])
        XCTAssertEqual(topology.nodes[1].hardwareName, "pcic2-bridge")
    }

    func testTopologyDoesNotMapAnotherDiskFromRegistryPath() {
        let topology = DriveConnectionTopologyResolver.resolve(
            drive: Self.drive(),
            registryEntriesFromDiskToHost: [
                .init(className: "IOMedia", entryName: "Different Disk Media", bsdName: "disk9", pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(className: "IONVMeController", entryName: "IONVMeController", bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false)
            ]
        )

        XCTAssertNil(topology)
    }

    private static func drive() -> DriveDevice {
        DriveDevice(
            bsdName: "disk8",
            deviceNode: "/dev/disk8",
            displayName: "External SSD",
            mediaName: "External SSD",
            protocolName: "NVMe",
            sizeBytes: 1_000_000_000,
            blockSize: 512,
            isInternal: false,
            isRemovable: false,
            isSolidState: true,
            isWritable: true,
            isVirtual: false,
            isSystemDisk: false,
            smartStatusRaw: nil,
            nativeSmartKeys: [:],
            volumes: []
        )
    }
}
