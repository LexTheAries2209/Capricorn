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

    private func node(_ id: String, _ kind: DriveConnectionTopologyNode.Kind, bsd: String? = nil) -> DriveConnectionTopologyNode {
        node(id, kind, name: id, bsd: bsd)
    }

    private func node(_ id: String, _ kind: DriveConnectionTopologyNode.Kind,
                      name: String?, bsd: String? = nil) -> DriveConnectionTopologyNode {
        .init(id: id, kind: kind, hardwareName: name, portDescription: nil, linkRateDescription: nil,
              bsdName: bsd, pcieLink: nil, isPCIeTunnelled: false)
    }
}
