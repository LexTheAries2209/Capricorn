// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class StorageHostPortTests: XCTestCase {
    func testKnownMacBookBoardMapsSocketsToVerifiedSides() {
        for board in ["J314s", "J314c", "J316s", "J316c", "J414s", "J414c", "J416s", "J416c"] {
            let model = StorageHostModel(identifier: "Mac", board: board)
            XCTAssertTrue(model.hasVerifiedPortLayout)
            XCTAssertEqual(model.position(for: .init(number: 1)), .leftRear)
            XCTAssertEqual(model.position(for: .init(number: 2)), .leftFront)
            XCTAssertEqual(model.position(for: .init(number: 3)), .right)
            XCTAssertNil(model.position(for: .init(number: 4)))
        }
    }

    func testUnknownBoardNeverInfersPhysicalPositionFromMacName() {
        let model = StorageHostModel(identifier: "Mac14,6", board: "Unknown")
        XCTAssertFalse(model.hasVerifiedPortLayout)
        XCTAssertNil(model.position(for: .init(number: 1)))
        XCTAssertNil(StorageHostArtworkGeometry.anchor(.init(number: 1), model: model))
    }

    func testUnverifiedOrNewModelsNeverInheritMacBookSocketCoordinates() {
        for identifier in ["Mac17,16", "Mac18,5", "Mac16,3", "CapricornUnknownMac999,1"] {
            let model = StorageHostModel(identifier: identifier, board: "")
            XCTAssertFalse(model.hasVerifiedPortLayout)
            for number in 1...3 {
                XCTAssertNil(StorageHostArtworkGeometry.anchor(.init(number: number), model: model), identifier)
            }
        }
        let unknownArtwork = StorageHostModel(identifier: "CapricornUnknownMac999,1", board: "J414c")
        XCTAssertNil(StorageHostArtworkGeometry.anchor(.init(number: 1), model: unknownArtwork))
    }

    func testPortParserRequiresAnExplicitBuiltInUSBCSocket() {
        XCTAssertEqual(StorageHostPort.parse(type: "USB-C", number: 3, builtIn: true)?.number, 3)
        XCTAssertNil(StorageHostPort.parse(type: "USB-C", number: 3, builtIn: false))
        XCTAssertNil(StorageHostPort.parse(type: "USB", number: 3, builtIn: true))
        XCTAssertNil(StorageHostPort.parse(type: "USB-C", number: 0, builtIn: true))
        XCTAssertNil(StorageHostPort.parse(type: "USB-C", number: nil, builtIn: true))
    }

    func testPhysicalDiagramStartsAtSocketAndKeepsRawTransportInInspector() {
        let host = node("computer", .computer)
        let usb = node("usb-port", .usbPort, port: 1)
        let thunderbolt = node("thunderbolt-port", .thunderboltPort, port: 3)
        var bridge = node("bridge", .pcieBridge)
        bridge.chipDescription = "PCI 1234:5678"
        var source = DriveConnectionTopologyGraph.assemble(paths: [
            "disk8": .init(nodes: [host, usb, node("disk:disk8", .disk, bsd: "disk8")], hasResolvedController: true),
            "disk9": .init(nodes: [host, thunderbolt, bridge, node("disk:disk9", .disk, bsd: "disk9")], hasResolvedController: true)
        ])
        source.hostModel = .init(identifier: "Mac14,6", board: "J416c")
        let diagram = StorageTopologyDiagram(graph: source)
        XCTAssertEqual(diagram.hostPortsByEdgeID["computer->disk:disk8"]?.number, 1)
        XCTAssertEqual(diagram.hostPortsByEdgeID["computer->bridge"]?.number, 3)
        XCTAssertFalse(diagram.graph.nodes.contains { $0.id == usb.id || $0.id == thunderbolt.id })
        XCTAssertTrue(diagram.hardwareSegments["disk:disk8"]?.contains { $0.id == usb.id } == true)
        XCTAssertEqual(source.path(for: "disk9").map(\.id), [host.id, thunderbolt.id, bridge.id, "disk:disk9"])
        XCTAssertEqual(diagram.graph.hostModel, source.hostModel)

        let layout = StorageTopologyRadialLayout(graph: diagram.graph, hostPortsByEdgeID: diagram.hostPortsByEdgeID)
        let center = layout.positions["computer"]!
        XCTAssertLessThan(layout.positions["disk:disk8"]!.x, center.x)
        XCTAssertGreaterThan(layout.positions["bridge"]!.x, center.x)
        let model = source.hostModel!
        XCTAssertLessThan(StorageHostArtworkGeometry.anchor(.init(number: 1), model: model)!.x, 170)
        XCTAssertGreaterThan(StorageHostArtworkGeometry.anchor(.init(number: 3), model: model)!.x, 170)
        XCTAssertLessThan(StorageHostArtworkGeometry.anchor(.init(number: 1), model: model)!.y,
                          StorageHostArtworkGeometry.anchor(.init(number: 2), model: model)!.y)
    }

    func testPhysicalDiagramKeepsUnmappedConnectionsAwayFromSocketWires() {
        let host = node("computer", .computer)
        var paths: [String: DriveConnectionTopologyPath] = [:]
        for index in 0..<10 {
            let bsd = "disk\(index)"
            let port = index < 6 ? node("port:\(index)", .usbPort, port: index.isMultiple(of: 2) ? 1 : 3) : nil
            paths[bsd] = .init(nodes: [host] + [port].compactMap { $0 } + [node("disk:\(bsd)", .disk, bsd: bsd)],
                               hasResolvedController: port != nil)
        }
        var source = DriveConnectionTopologyGraph.assemble(paths: paths)
        source.hostModel = .init(identifier: "Mac14,6", board: "J416c")
        let diagram = StorageTopologyDiagram(graph: source)
        let layout = StorageTopologyRadialLayout(graph: diagram.graph, hostPortsByEdgeID: diagram.hostPortsByEdgeID)
        XCTAssertEqual(layout.positions.count, diagram.graph.nodes.count)
        for (index, node) in diagram.graph.nodes.enumerated() {
            let first = rect(node, layout: layout, host: source.hostModel)
            for other in diagram.graph.nodes.dropFirst(index + 1) {
                XCTAssertFalse(first.intersects(rect(other, layout: layout, host: source.hostModel)),
                               "\(node.id) overlaps \(other.id)")
            }
        }
        XCTAssertNil(diagram.hostPortsByEdgeID["computer->disk:disk9"])
        XCTAssertGreaterThan(layout.positions["disk:disk9"]!.y, layout.positions["computer"]!.y)
    }

    func testPhysicalLayoutShortensHubToDeviceConnectorByThirtyPercent() throws {
        let host = node("computer", .computer)
        let hub = node("hub", .usbHub)
        let disk = node("disk:disk8", .disk, bsd: "disk8")
        var graph = DriveConnectionTopologyGraph.assemble(paths: [
            "disk8": .init(nodes: [host, hub, disk], hasResolvedController: true)
        ])
        graph.hostModel = .init(identifier: "Mac14,6", board: "J416c")
        let layout = StorageTopologyRadialLayout(graph: graph,
            hostPortsByEdgeID: ["computer->hub": .init(number: 3)])
        let hubPosition = try XCTUnwrap(layout.positions[hub.id])
        let diskPosition = try XCTUnwrap(layout.positions[disk.id])
        let occupiedWidth = (StorageTopologyRadialLayout.nodeSize(hub).width
            + StorageTopologyRadialLayout.nodeSize(disk).width) / 2

        XCTAssertEqual(diskPosition.x - hubPosition.x - occupiedWidth,
                       (250 - occupiedWidth) * 0.7, accuracy: 0.001)
        XCTAssertEqual(diskPosition.y, hubPosition.y, accuracy: 0.001)
    }

    private func rect(_ node: DriveConnectionTopologyNode, layout: StorageTopologyRadialLayout, host: StorageHostModel?) -> CGRect {
        let center = layout.positions[node.id]!
        let size = StorageTopologyRadialLayout.nodeSize(node, host: host)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    private func node(_ id: String, _ kind: DriveConnectionTopologyNode.Kind,
                      port: Int? = nil, bsd: String? = nil) -> DriveConnectionTopologyNode {
        .init(id: id, kind: kind, hardwareName: nil, portDescription: nil, linkRateDescription: nil,
              bsdName: bsd, pcieLink: nil, isPCIeTunnelled: false, hostPort: port.map(StorageHostPort.init))
    }
}
