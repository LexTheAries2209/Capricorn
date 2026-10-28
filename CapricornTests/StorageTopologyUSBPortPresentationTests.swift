// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class StorageTopologyUSBPortPresentationTests: XCTestCase {
    func testDirectUSBConnectionSkipsPortNodeButKeepsInspectorEvidence() {
        let port = node("usb-port", .usbPort)
        let source = DriveConnectionTopologyGraph.assemble(paths: [
            "disk8": .init(nodes: [node("computer", .computer), port, node("disk:disk8", .disk, bsd: "disk8")],
                           hasResolvedController: true)
        ])
        let diagram = StorageTopologyDiagram(graph: source)
        XCTAssertEqual(Set(diagram.graph.nodes.map(\.id)), ["computer", "disk:disk8"])
        XCTAssertEqual(diagram.graph.edges.map(\.id), ["computer->disk:disk8"])
        XCTAssertTrue(diagram.hardwareSegments["disk:disk8"]?.contains(port) == true)
        XCTAssertTrue(source.path(for: "disk8").contains(port))
    }

    func testPortsInsideHubChainDoNotBecomeDiagramNodes() {
        let firstPort = node("usb-port-1", .usbPort)
        let secondPort = node("usb-port-2", .usbPort)
        let thirdPort = node("usb-port-3", .usbPort)
        let hub = node("dock", .usbHub)
        let nestedHub = node("dock-hub", .usbHub)
        let source = DriveConnectionTopologyGraph.assemble(paths: [
            "disk8": .init(nodes: [node("computer", .computer), firstPort, hub, secondPort,
                                   nestedHub, thirdPort, node("disk:disk8", .disk, bsd: "disk8")],
                           hasResolvedController: true)
        ])
        let diagram = StorageTopologyDiagram(graph: source)
        XCTAssertEqual(diagram.graph.path(for: "disk8").map(\.id), ["computer", "dock", "dock-hub", "disk:disk8"])
        XCTAssertFalse(diagram.graph.nodes.contains { $0.kind == .usbPort })
        XCTAssertTrue(diagram.hardwareSegments[hub.id]?.contains(firstPort) == true)
        XCTAssertTrue(diagram.hardwareSegments[nestedHub.id]?.contains(secondPort) == true)
        XCTAssertTrue(diagram.hardwareSegments["disk:disk8"]?.contains(thirdPort) == true)
        XCTAssertEqual(source.path(for: "disk8").filter { $0.kind == .usbPort }.count, 3)
    }

    func testTwoDisksStillShareOneHubAfterRemovingPortWrappers() {
        let host = node("computer", .computer)
        let hub = node("shared-hub", .usbHub)
        let source = DriveConnectionTopologyGraph.assemble(paths: [
            "disk8": .init(nodes: [host, node("host-port", .usbPort), hub, node("port-a", .usbPort),
                                   node("disk:disk8", .disk, bsd: "disk8")], hasResolvedController: true),
            "disk9": .init(nodes: [host, node("host-port", .usbPort), hub, node("port-b", .usbPort),
                                   node("disk:disk9", .disk, bsd: "disk9")], hasResolvedController: true)
        ])
        let diagram = StorageTopologyDiagram(graph: source)
        XCTAssertEqual(diagram.graph.nodes.filter { $0.kind == .usbHub }.count, 1)
        XCTAssertEqual(diagram.graph.edges.count, 3)
        XCTAssertEqual(diagram.selectedNodeIDs(for: "disk9"), ["computer", "shared-hub", "disk:disk9"])
    }

    func testGenericUSBHubWrappersFoldIntoDirectBranchWithoutLosingDetails() {
        let port = node("port", .usbPort)
        let genericHub = node("generic-usb-hub", .usbHub, name: "USB3.0 Hub")
        let dock = node("dock", .usbHub, name: "TS4 USB3.2 Gen2 HUB")
        let disk = node("disk:disk8", .disk, bsd: "disk8")
        let source = DriveConnectionTopologyGraph.assemble(paths: [
            "disk8": .init(nodes: [node("computer", .computer), port, genericHub, dock,
                                   node("dock-port", .usbPort), disk], hasResolvedController: true)
        ])
        let diagram = StorageTopologyDiagram(graph: source)
        XCTAssertEqual(diagram.graph.path(for: "disk8").map(\.id), ["computer", dock.id, disk.id])
        XCTAssertTrue(diagram.hardwareSegments[dock.id]?.contains(genericHub) == true)
        XCTAssertTrue(diagram.hardwareSegments[dock.id]?.contains(port) == true)
        XCTAssertTrue(diagram.hardwareSegments[disk.id]?.contains(node("dock-port", .usbPort)) == true)
        XCTAssertTrue(source.path(for: "disk8").contains(genericHub))
        XCTAssertTrue(source.path(for: "disk8").contains { $0.id == "dock-port" })
        for name in ["USB3.0 Hub", "USB Hub", "USB 集线器", "xhci hub", "Hub Device"] {
            XCTAssertTrue(USBHubPresentation.isGeneric(name), name)
        }
        XCTAssertFalse(USBHubPresentation.isGeneric("TS4 USB3.2 Gen2 HUB"))
        XCTAssertTrue(StorageTopologyDiagram.isGenericUSBHub(genericHub.hardwareName))
    }

    func testTunnelledGenericUSBHubIsKeptBeforeDockHubChain() {
        let host = node("computer", .computer)
        let tunnelHub = node("intel-usb3-tunnel", .usbHub, name: "USB3.0 Hub",
                             chip: "USB 8087:0B40", rate: "10 Gb/s", usbTunnelled: true)
        let dockHub = node("ts4-hub", .usbHub, name: "TS4 USB3.2 Gen2 HUB")
        let nestedHub = node("ts4-downstream-hub", .usbHub, name: "TS4 USB3.2 Gen2 HUB")
        let source = DriveConnectionTopologyGraph.assemble(paths: [
            "disk8": .init(nodes: [host, node("host-port", .usbPort), tunnelHub,
                                   node("disk:disk8", .disk, bsd: "disk8")], hasResolvedController: true),
            "disk9": .init(nodes: [host, node("host-port", .usbPort), tunnelHub, dockHub,
                                   node("dock-port", .usbPort), nestedHub,
                                   node("downstream-port", .usbPort), node("disk:disk9", .disk, bsd: "disk9")],
                           hasResolvedController: true)
        ])

        let diagram = StorageTopologyDiagram(graph: source)

        XCTAssertEqual(diagram.graph.path(for: "disk8").map(\.id),
                       ["computer", tunnelHub.id, "disk:disk8"])
        XCTAssertEqual(diagram.graph.path(for: "disk9").map(\.id),
                       ["computer", tunnelHub.id, dockHub.id, nestedHub.id, "disk:disk9"])
        XCTAssertEqual(diagram.graph.nodes.filter { $0.id == tunnelHub.id }.count, 1)
        XCTAssertEqual(diagram.graph.edges.first { $0.id == "computer->\(tunnelHub.id)" }?.driveBSDNames,
                       ["disk8", "disk9"])
        XCTAssertEqual(diagram.graph.edges.first { $0.id == "\(tunnelHub.id)->disk:disk8" }?.driveBSDNames,
                       ["disk8"])
        XCTAssertFalse(diagram.graph.nodes.contains { $0.kind == .usbPort })
        XCTAssertEqual(diagram.graph.nodes.first { $0.id == tunnelHub.id }?.chipDescription, "USB 8087:0B40")
        XCTAssertEqual(diagram.graph.nodes.first { $0.id == tunnelHub.id }?.linkRateDescription, "10 Gb/s")
    }

    func testRepeatedPCIeBridgeChipIsShownOnceButRawRegistryPathIsRetained() {
        let host = node("computer", .computer)
        let jhl8440 = node("jhl8440", .pcieBridge, name: "PCI-Bridge", chip: "PCI 8086:0B26")
        let asmUpstream = node("asm-upstream", .pcieBridge, name: "PCI-Bridge", chip: "PCI 1B21:2463")
        let upstreamWrapper = node("upstream-wrapper", .pcieBridge, name: "IOPP")
        let asmDownstream = node("asm-downstream", .pcieBridge, name: "PCI-Bridge", chip: "PCI 1B21:2463")
        let downstreamWrapper = node("downstream-wrapper", .pcieBridge, name: "IOPP")
        let maxio = node("maxio", .pcieDevice, name: "MAP1602", chip: "PCI 1E4B:1602")
        let disk = node("disk:disk8", .disk, bsd: "disk8")
        let source = DriveConnectionTopologyGraph.assemble(paths: [
            "disk8": .init(nodes: [host, jhl8440, asmUpstream, upstreamWrapper, asmDownstream,
                                   downstreamWrapper, maxio, disk],
                           hasResolvedController: true)
        ])

        let diagram = StorageTopologyDiagram(graph: source)
        let detailsHardware = StorageTopologyDiagram.uniquePCIeBridgeChips(in: source.path(for: "disk8"))
            .filter { $0.kind == .pcieBridge }

        XCTAssertEqual(diagram.graph.path(for: "disk8").map(\.id),
                       ["computer", jhl8440.id, asmUpstream.id, disk.id])
        XCTAssertEqual(detailsHardware.map(\.id), [jhl8440.id, asmUpstream.id])
        XCTAssertEqual(source.path(for: "disk8").filter { $0.kind == .pcieBridge }.count, 5)
        XCTAssertEqual(diagram.hardwareSegments[disk.id]?.map(\.id), [maxio.id, disk.id])
    }

    private func node(_ id: String, _ kind: DriveConnectionTopologyNode.Kind, bsd: String? = nil) -> DriveConnectionTopologyNode {
        node(id, kind, name: id, bsd: bsd)
    }

    private func node(_ id: String, _ kind: DriveConnectionTopologyNode.Kind,
                      name: String?, bsd: String? = nil, chip: String? = nil, rate: String? = nil,
                      usbTunnelled: Bool = false) -> DriveConnectionTopologyNode {
        .init(id: id, kind: kind, hardwareName: name, portDescription: nil, linkRateDescription: rate,
              bsdName: bsd, pcieLink: nil, isPCIeTunnelled: false, chipDescription: chip,
              isUSBTunnelled: usbTunnelled)
    }
}
