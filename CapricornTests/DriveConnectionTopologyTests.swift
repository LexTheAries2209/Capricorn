// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class DriveConnectionTopologyTests: XCTestCase {
    func testTopologyDeviceNodesUseCompactVerticalDimensions() {
        let disk = DriveConnectionTopologyNode(
            id: "disk:disk8",
            kind: .disk,
            hardwareName: "External SSD",
            portDescription: nil,
            linkRateDescription: nil,
            bsdName: "disk8",
            pcieLink: nil,
            isPCIeTunnelled: false
        )
        let hub = DriveConnectionTopologyNode(
            id: "hub",
            kind: .usbHub,
            hardwareName: "TS4 USB3.2 Gen2 HUB",
            portDescription: nil,
            linkRateDescription: nil,
            bsdName: nil,
            pcieLink: nil,
            isPCIeTunnelled: false
        )

        XCTAssertEqual(StorageTopologyRadialLayout.nodeSize(disk), CGSize(width: 214, height: 124))
        XCTAssertEqual(StorageTopologyRadialLayout.nodeSize(hub), CGSize(width: 184, height: 96))
    }

    func testOpaqueUSBLocationAddressIsHiddenFromPresentationOnly() {
        let opaquePort = DriveConnectionTopologyNode(
            id: "usb-location",
            kind: .usbPort,
            hardwareName: nil,
            portDescription: "USB 0x02200000",
            linkRateDescription: nil,
            bsdName: nil,
            pcieLink: nil,
            isPCIeTunnelled: false
        )
        let readablePort = DriveConnectionTopologyNode(
            id: "usb-port",
            kind: .usbPort,
            hardwareName: nil,
            portDescription: "USB Port 1",
            linkRateDescription: nil,
            bsdName: nil,
            pcieLink: nil,
            isPCIeTunnelled: false
        )

        XCTAssertEqual(opaquePort.portDescription, "USB 0x02200000")
        XCTAssertNil(opaquePort.displayPortDescription)
        XCTAssertEqual(readablePort.displayPortDescription, "USB Port 1")
    }

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
            .computer, .pcieBridge, .pcieDevice, .nvmeController, .disk
        ])
        XCTAssertEqual(topology.nodes[2].hardwareName, "pci1e4b,1602")
        XCTAssertEqual(topology.nodes[2].pcieLink?.detailLabel, "16.0 GT/s · x4")
        XCTAssertNil(topology.nodes[1].hardwareName)
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

    func testSharedHardwareMergesByRegistryIdentityAndKeepsEveryDisk() throws {
        let host = node("computer", .computer)
        let port = node("registry:port1", .usbPort)
        let hub = node("registry:hub1", .usbHub)
        let first = node("disk:disk8", .disk, bsdName: "disk8")
        let second = node("disk:disk9", .disk, bsdName: "disk9")
        let graph = DriveConnectionTopologyGraph.assemble(paths: [
            "disk8": .init(nodes: [host, port, hub, first], hasResolvedController: true),
            "disk9": .init(nodes: [host, port, hub, second], hasResolvedController: true)
        ])
        XCTAssertEqual(graph.nodes.count, 5)
        XCTAssertEqual(graph.edges.count, 4)
        XCTAssertEqual(graph.edges.first { $0.fromID == host.id }?.driveBSDNames, ["disk8", "disk9"])
        XCTAssertEqual(graph.path(for: "disk9").map(\.id), [host.id, port.id, hub.id, second.id])
        XCTAssertFalse(graph.pathNodeIDs(to: "disk8").contains(second.id))
        XCTAssertTrue(graph.path(for: "disk99").isEmpty)
        let diagram = StorageTopologyDiagram(graph: graph)
        XCTAssertEqual(diagram.graph.nodes.map(\.id), graph.nodes.filter { $0.kind != .usbPort }.map(\.id))
    }

    func testSystemDiskIsHiddenAndSelectingItHighlightsOnlyTheComputer() {
        let host = node("computer", .computer)
        let source = DriveConnectionTopologyGraph.assemble(paths: [
            "disk0": .init(nodes: [host, node("internal-controller", .nvmeController),
                                  node("disk:disk0", .disk, bsdName: "disk0")], hasResolvedController: true),
            "disk8": .init(nodes: [host, node("usb-port", .usbPort),
                                  node("disk:disk8", .disk, bsdName: "disk8")], hasResolvedController: true)
        ])
        let diagram = StorageTopologyDiagram(graph: source, systemDriveIDs: ["disk0"])
        XCTAssertFalse(diagram.graph.nodes.contains { $0.id == "disk:disk0" || $0.id == "internal-controller" })
        XCTAssertEqual(diagram.selectedNodeIDs(for: "disk0"), ["computer"])
        XCTAssertEqual(diagram.selectedNodeIDs(for: "disk8"), ["computer", "disk:disk8"])
        XCTAssertEqual(source.path(for: "disk0").count, 3, "Inspector retains the system disk's actual data.")
    }

    func testOnlySystemDiskLeavesASelectableComputerInTheDiagram() {
        let source = DriveConnectionTopologyGraph.assemble(paths: [
            "disk0": .init(nodes: [node("computer", .computer), node("disk:disk0", .disk, bsdName: "disk0")],
                           hasResolvedController: false)
        ])
        let diagram = StorageTopologyDiagram(graph: source, systemDriveIDs: ["disk0"])
        XCTAssertEqual(diagram.graph.nodes.map(\.id), ["computer"])
        XCTAssertTrue(diagram.graph.edges.isEmpty)
        XCTAssertEqual(StorageTopologyRadialLayout(graph: diagram.graph).positions.count, 1)
    }

    func testIdenticalHardwareNamesAtDifferentPortsStaySeparate() {
        let host = node("computer", .computer)
        let firstHub = node("registry:1", .usbHub)
        let secondHub = node("registry:2", .usbHub)
        let graph = DriveConnectionTopologyGraph.assemble(paths: [
            "disk8": .init(nodes: [host, firstHub, node("disk:disk8", .disk, bsdName: "disk8")], hasResolvedController: true),
            "disk9": .init(nodes: [host, secondHub, node("disk:disk9", .disk, bsdName: "disk9")], hasResolvedController: true)
        ])
        XCTAssertEqual(graph.nodes.filter { $0.kind == .usbHub }.count, 2)
        XCTAssertEqual(graph.path(for: "disk9")[1].id, secondHub.id)
    }

    func testGenericUSBHubNamesArePortsRatherThanTopologyHubs() {
        for name in ["USB3.0 Hub", "USB Hub", "USB 集线器"] {
            let path = try! XCTUnwrap(DriveConnectionTopologyResolver.resolve(
                drive: Self.drive(),
                registryEntriesFromDiskToHost: [
                    .init(className: "IOMedia", entryName: "Media", bsdName: "disk8",
                          pcieLinkStatus: nil, isPCIeTunnelled: false),
                    .init(className: "IOUSBHostDevice", entryName: name,
                          bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false),
                    .init(className: "IOUSBHostDevice", entryName: "TS4 USB3.2 Gen2 HUB",
                          bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false)
                ]
            ))
            XCTAssertEqual(path.nodes.map(\.kind), [.computer, .usbHub, .usbPort, .disk], name)
        }
    }

    func testUSBTunnelHubIsARealIntermediateHub() throws {
        let path = try XCTUnwrap(DriveConnectionTopologyResolver.resolve(
            drive: Self.drive(),
            registryEntriesFromDiskToHost: [
                .init(className: "IOMedia", entryName: "Media", bsdName: "disk8",
                      pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(className: "IOUSBHostDevice", entryName: "USB3.0 Hub",
                      bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false,
                      hardwareDescription: "USB3.0 Hub", linkRateDescription: "10 Gb/s",
                      chipDescription: "USB 8087:0B40", isUSBTunnelled: true)
            ]
        ))

        XCTAssertEqual(path.nodes.map(\.kind), [.computer, .usbHub, .disk])
        XCTAssertEqual(path.nodes[1].hardwareName, "USB3.0 Hub")
        XCTAssertTrue(path.nodes[1].isUSBTunnelled)
        XCTAssertEqual(path.nodes[1].linkRateDescription, "10 Gb/s")
        XCTAssertEqual(path.nodes[1].chipDescription, "USB 8087:0B40")
    }

    func testPCIeBridgeGenericNameIsPresentedAsPCIHyphenBridge() {
        let bridge = DriveConnectionTopologyNode(
            id: "bridge",
            kind: .pcieBridge,
            hardwareName: "pci-bridge",
            portDescription: nil,
            linkRateDescription: nil,
            bsdName: nil,
            pcieLink: nil,
            isPCIeTunnelled: false
        )
        let namedBridge = DriveConnectionTopologyNode(
            id: "named-bridge",
            kind: .pcieBridge,
            hardwareName: "ASM2464PD PCIe Bridge",
            portDescription: nil,
            linkRateDescription: nil,
            bsdName: nil,
            pcieLink: nil,
            isPCIeTunnelled: false
        )

        XCTAssertEqual(bridge.presentationName, "PCI-Bridge")
        XCTAssertEqual(namedBridge.presentationName, "ASM2464PD PCIe Bridge")
    }

    func testSupplementalThunderboltPathPreservesRealPortAndBridgeChip() throws {
        let topology = try XCTUnwrap(DriveConnectionTopologyResolver.resolve(
            drive: Self.drive(),
            registryEntriesFromDiskToHost: [
                .init(className: "IOMedia", entryName: "Media", bsdName: "disk8", pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(registryID: "endpoint", className: "IOPCIDevice", entryName: "NVMe", bsdName: nil,
                      pcieLinkStatus: 4 | (4 << 4), isPCIeTunnelled: true, chipDescription: "PCI 1234:5678"),
                .init(registryID: "bridge", className: "IOPCIDevice", entryName: "pci-bridge", bsdName: nil,
                      pcieLinkStatus: 1 | (16 << 4), isPCIeTunnelled: true,
                      thunderboltPath: "IOService:/test", chipDescription: "PCI ABCD:1234",
                      ignoresPCIeLinkStatus: true)
            ],
            thunderboltEntriesFromPortToHost: [
                .init(registryID: "port", className: "IOThunderboltPort", entryName: "IOThunderboltPort@1",
                      bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false,
                      portNumber: 1, portDescription: "Thunderbolt Port", linkRateDescription: "40 Gb/s"),
                .init(registryID: "controller", className: "IOThunderboltControllerType5", entryName: "Controller",
                      bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false)
            ]
        ))
        XCTAssertEqual(topology.nodes.map(\.kind), [.computer, .thunderboltController, .thunderboltPort, .pcieBridge, .pcieDevice, .disk])
        XCTAssertEqual(topology.nodes[2].linkRateDescription, "40 Gb/s")
        XCTAssertEqual(topology.nodes[3].chipDescription, "PCI ABCD:1234")
        XCTAssertNil(topology.nodes[3].pcieLink)
        XCTAssertEqual(topology.nodes[4].pcieLink?.laneCount, 4)
    }

    func testRateParserRejectsUnknownCodesAndKeepsUSBLinkRate() {
        XCTAssertEqual(IOKitDriveConnectionTopologyReader.linkRateDescription(
            currentLinkSpeed: 4, usbSpeedCode: nil, usbLinkSpeed: nil), "40 Gb/s")
        XCTAssertNil(IOKitDriveConnectionTopologyReader.linkRateDescription(
            currentLinkSpeed: 7, usbSpeedCode: 7, usbLinkSpeed: nil))
        XCTAssertEqual(IOKitDriveConnectionTopologyReader.linkRateDescription(
            currentLinkSpeed: nil, usbSpeedCode: 4, usbLinkSpeed: nil), "USB · 10 Gb/s")
        XCTAssertNil(IOKitDriveConnectionTopologyReader.linkRateDescription(
            currentLinkSpeed: nil, usbSpeedCode: nil, usbLinkSpeed: 10))
    }

    func testAppleDriverWrappersAreNotReportedAsAdditionalChips() throws {
        var drive = Self.drive()
        drive.protocolName = "Apple Fabric"
        let topology = try XCTUnwrap(DriveConnectionTopologyResolver.resolve(
            drive: drive,
            registryEntriesFromDiskToHost: [
                .init(className: "IOMedia", entryName: "Media", bsdName: "disk8", pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(className: "AppleANS3NVMeController", entryName: "AppleANS3NVMeController",
                      bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(className: "RTBuddy", entryName: "RTBuddy(ANS2)", bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false),
                .init(className: "IOService", entryName: "iop-ans-nub", bsdName: nil, pcieLinkStatus: nil, isPCIeTunnelled: false)
            ]
        ))
        XCTAssertEqual(topology.nodes.map(\.kind), [.computer, .nvmeController, .disk])
        XCTAssertNil(topology.nodes[1].chipDescription)
    }

    func testDiagramKeepsHostPortAndChipWhileInspectorKeepsBothThunderboltEnds() {
        let host = node("computer", .computer)
        let hostPort = node("registry:host-port", .thunderboltPort)
        let devicePort = node("registry:device-port", .thunderboltPort)
        var bridge = node("registry:bridge", .pcieBridge)
        bridge.chipDescription = "PCI 1234:5678"
        let disk = node("disk:disk8", .disk, bsdName: "disk8")
        let graph = DriveConnectionTopologyGraph.assemble(paths: [
            "disk8": .init(nodes: [host, hostPort, devicePort, bridge, disk], hasResolvedController: true)
        ])
        let diagram = StorageTopologyDiagram(graph: graph)
        XCTAssertEqual(diagram.graph.nodes.map(\.id), [host.id, hostPort.id, bridge.id, disk.id])
        XCTAssertEqual(graph.path(for: "disk8").map(\.id), [host.id, hostPort.id, devicePort.id, bridge.id, disk.id])
        XCTAssertEqual(diagram.hardwareSegments[bridge.id]?.map(\.id), [devicePort.id, bridge.id])
    }

    func testRadialDiagramHasStablePositionsAcrossDiskSelectionAndNoNodeOverlap() {
        let host = node("computer", .computer)
        var paths: [String: DriveConnectionTopologyPath] = [:]
        for index in 0..<12 {
            let name = "disk\(index)"
            let port = node("port:\(index)", .usbPort)
            paths[name] = .init(nodes: [host, port, node("disk:\(name)", .disk, bsdName: name)],
                                hasResolvedController: true)
        }
        let graph = DriveConnectionTopologyGraph.assemble(paths: paths)
        let layout = StorageTopologyRadialLayout(graph: graph)
        XCTAssertEqual(layout.positions.count, graph.nodes.count)
        for (index, first) in graph.nodes.enumerated() {
            let firstRect = rect(first, layout: layout)
            XCTAssertTrue(CGRect(origin: .zero, size: layout.size).contains(firstRect))
            for second in graph.nodes.dropFirst(index + 1) {
                XCTAssertFalse(firstRect.intersects(rect(second, layout: layout)), "\(first.id) overlaps \(second.id)")
            }
        }
        let before = layout.positions
        _ = graph.pathNodeIDs(to: "disk1")
        _ = graph.pathNodeIDs(to: "disk11")
        XCTAssertEqual(before, StorageTopologyRadialLayout(graph: graph).positions)
    }

    func testThreeBranchesOfDifferentDepthsDoNotOverlap() {
        let host = node("computer", .computer)
        let graph = DriveConnectionTopologyGraph.assemble(paths: [
            "disk0": .init(nodes: [host, node("disk:disk0", .disk, bsdName: "disk0")], hasResolvedController: false),
            "disk6": .init(nodes: [
                host, node("registry:port1", .thunderboltPort), node("registry:bridge", .pcieBridge),
                node("disk:disk6", .disk, bsdName: "disk6")
            ], hasResolvedController: true),
            "disk13": .init(nodes: [
                host, node("registry:usb1", .usbHostController), node("registry:usb2", .usbHostController),
                node("disk:disk13", .disk, bsdName: "disk13")
            ], hasResolvedController: true)
        ])
        let layout = StorageTopologyRadialLayout(graph: graph)
        for (index, first) in graph.nodes.enumerated() {
            for second in graph.nodes.dropFirst(index + 1) {
                XCTAssertFalse(rect(first, layout: layout).intersects(rect(second, layout: layout)),
                               "\(first.id) overlaps \(second.id)")
            }
        }
    }

    private func rect(_ node: DriveConnectionTopologyNode, layout: StorageTopologyRadialLayout) -> CGRect {
        let center = layout.positions[node.id] ?? .zero
        let size = StorageTopologyRadialLayout.nodeSize(node)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    private func node(_ id: String, _ kind: DriveConnectionTopologyNode.Kind, bsdName: String? = nil) -> DriveConnectionTopologyNode {
        .init(id: id, kind: kind, hardwareName: "Hardware", portDescription: nil,
              linkRateDescription: nil, bsdName: bsdName, pcieLink: nil, isPCIeTunnelled: false)
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
