// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class StorageDesktopTopologyTests: XCTestCase {
    func testDesktopSocketGeometryStaysOnFrontBackAndRearPanel() throws {
        for id in ["Macmini9,1", "Mac16,10", "Mac14,13", "Mac16,3"] {
            let model = StorageHostModel(identifier: id, board: "")
            let profile = try XCTUnwrap(model.desktopPortLayout)
            for socket in profile.sockets {
                let point = try XCTUnwrap(StorageHostArtworkGeometry.anchor(socket.port, model: model))
                XCTAssertTrue(profile.artworkFrame.insetBy(dx: -1, dy: -1).contains(point))
                if profile.family == .iMac {
                    XCTAssertLessThan(point.x, profile.artworkFrame.midX)
                    XCTAssertGreaterThan(point.y, profile.artworkFrame.midY)
                } else if socket.side == .front {
                    XCTAssertEqual(point.y, profile.artworkFrame.maxY)
                } else {
                    XCTAssertEqual(point.y, profile.artworkFrame.minY)
                }
            }
            XCTAssertNil(model.position(for: .init(number: 1)), "An unverified OS number is not a physical socket.")
        }
    }

    func testSocketAssignmentPersistsForSharedRootAndDoesNotLeakAcrossModels() throws {
        let model = StorageHostModel(identifier: "Mac16,10", board: "")
        var saved = StorageDesktopSocketAssignments(data: Data())
        saved.assign("front-c-0", to: "dock", model: model)
        let restored = StorageDesktopSocketAssignments(data: saved.data)
        let override = try XCTUnwrap(restored.ports(for: model)["dock"])
        XCTAssertEqual(model.position(for: override), .front)
        XCTAssertTrue(restored.ports(for: .init(identifier: "Mac14,13", board: "")).isEmpty)
        XCTAssertTrue(StorageDesktopSocketAssignments(data: saved.data, bootSession: "another-boot")
            .ports(for: model).isEmpty)

        let host = node("computer", .computer)
        let dock = node("dock", .usbHub)
        var source = DriveConnectionTopologyGraph.assemble(paths: [
            "disk8": .init(nodes: [host, dock, node("disk8", .disk, bsd: "disk8")], hasResolvedController: true),
            "disk9": .init(nodes: [host, dock, node("disk9", .disk, bsd: "disk9")], hasResolvedController: true)
        ])
        source.hostModel = model
        let diagram = StorageTopologyDiagram(graph: source, hostPortOverrides: restored.ports(for: model))
        XCTAssertEqual(diagram.hostPortsByEdgeID["computer->dock"], override)
        XCTAssertEqual(diagram.graph.edges.first { $0.fromID == "computer" }?.driveBSDNames, ["disk8", "disk9"])
        saved.assign(nil, to: "dock", model: model)
        XCTAssertTrue(saved.ports(for: model).isEmpty)
    }

    func testFrontBackAndUnassignedBranchesStaySeparatedWithoutOverlap() throws {
        for id in ["Mac16,10", "Mac14,13", "Mac16,3"] {
            let host = node("computer", .computer)
            let model = StorageHostModel(identifier: id, board: "")
            let profile = try XCTUnwrap(model.desktopPortLayout)
            var paths: [String: DriveConnectionTopologyPath] = [:]
            var overrides: [String: StorageHostPort] = [:]
            for (index, socket) in profile.sockets.enumerated() {
                let bsd = "disk\(index)"
                paths[bsd] = .init(nodes: [host, node(bsd, .disk, bsd: bsd)], hasResolvedController: true)
                overrides[bsd] = socket.port
            }
            paths["unassigned"] = .init(nodes: [host, node("unassigned", .disk, bsd: "unassigned")],
                                        hasResolvedController: false)
            var source = DriveConnectionTopologyGraph.assemble(paths: paths)
            source.hostModel = model
            let diagram = StorageTopologyDiagram(graph: source, hostPortOverrides: overrides)
            let layout = StorageTopologyRadialLayout(graph: diagram.graph,
                hostPortsByEdgeID: diagram.hostPortsByEdgeID)
            let center = try XCTUnwrap(layout.positions["computer"])
            for (index, socket) in profile.sockets.enumerated() {
                let point = try XCTUnwrap(layout.positions["disk\(index)"])
                if profile.family == .iMac {
                    XCTAssertLessThan(point.x, center.x)
                } else if socket.side == .front {
                    XCTAssertGreaterThan(point.y, center.y)
                } else {
                    XCTAssertLessThan(point.y, center.y)
                }
            }
            let rects = diagram.graph.nodes.map { node -> CGRect in
                let center = layout.positions[node.id]!
                let size = StorageTopologyRadialLayout.nodeSize(node, host: model)
                return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                              width: size.width, height: size.height)
            }
            for (index, frame) in rects.enumerated() {
                for other in rects.dropFirst(index + 1) {
                    XCTAssertFalse(frame.intersects(other), id)
                }
            }
        }
    }

    private func node(_ id: String, _ kind: DriveConnectionTopologyNode.Kind,
                      bsd: String? = nil) -> DriveConnectionTopologyNode {
        .init(id: id, kind: kind, hardwareName: "External device", portDescription: nil,
              linkRateDescription: nil, bsdName: bsd, pcieLink: nil, isPCIeTunnelled: false)
    }
}
