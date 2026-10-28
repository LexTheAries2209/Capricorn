// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics

struct StorageTopologyRadialLayout {
    let positions: [String: CGPoint]
    let size: CGSize

    private static let connectionLengthScale = 0.7

    init(positions: [String: CGPoint], size: CGSize) {
        self.positions = positions
        self.size = size
    }

    static func nodeSize(_ node: DriveConnectionTopologyNode, host: StorageHostModel? = nil) -> CGSize {
        switch node.kind {
        case .computer: host != nil
            ? StorageHostArtworkGeometry.size : CGSize(width: 130, height: 98)
        case .disk: CGSize(width: 214, height: 112)
        default: CGSize(width: 184, height: 96)
        }
    }

    private static func shortenedCenterDistance(
        defaultDistance: Double,
        occupiedHalfExtent: Double,
        scale: Double
    ) -> Double {
        defaultDistance - max(0, defaultDistance - occupiedHalfExtent) * (1 - scale)
    }

    init(graph: DriveConnectionTopologyGraph, hostPortsByEdgeID: [String: StorageHostPort] = [:]) {
        let defaultPositions = graph.hostModel?.hasVerifiedPortLayout == true
            ? Self.physicalPositions(graph: graph, ports: hostPortsByEdgeID)
            : Self.radialPositions(graph: graph)
        let positions = Self.compactedPositions(
            graph: graph, positions: defaultPositions, ports: hostPortsByEdgeID
        )
        let bounds = graph.nodes.reduce(CGRect.null) { rect, node in
            let center = positions[node.id] ?? .zero
            let size = Self.nodeSize(node, host: graph.hostModel)
            return rect.union(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                     width: size.width, height: size.height))
        }
        let inset: CGFloat = 32
        self.positions = positions.mapValues {
            CGPoint(x: $0.x - bounds.minX + inset, y: $0.y - bounds.minY + inset)
        }
        self.size = bounds.isNull ? CGSize(width: 300, height: 200)
            : CGSize(width: bounds.width + inset * 2, height: bounds.height + inset * 2)
    }

    private static func radialPositions(graph: DriveConnectionTopologyGraph) -> [String: CGPoint] {
        let count = max(graph.nodes.filter { $0.kind == .disk }.count, 1)
        let spacing = max(graph.hostModel == nil ? 250.0 : 360.0, Double(count) * 270 / (2 * .pi))
        let children = Dictionary(grouping: graph.edges, by: \.fromID)
        var positions: [String: CGPoint] = ["computer": .zero]
        var leafIndex = 0
        var visited: Set<String> = []
        @discardableResult
        func place(_ id: String, depth: Int) -> [Int] {
            guard visited.insert(id).inserted else { return [] }
            let next = (children[id] ?? []).sorted { $0.toID < $1.toID }
            var indices = next.flatMap { place($0.toID, depth: depth + 1) }
            if next.isEmpty {
                indices = [leafIndex]
                leafIndex += 1
            }
            if id != "computer", let first = indices.min(), let last = indices.max() {
                let startAngle = count >= 3 ? -Double.pi / 2 : 0
                let angle = startAngle + Double(first + last) / 2 * 2 * .pi / Double(count)
                let radius = spacing * Double(depth)
                positions[id] = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius * 0.62)
            }
            return indices
        }
        place("computer", depth: 0)
        return positions
    }

    private static func physicalPositions(
        graph: DriveConnectionTopologyGraph,
        ports: [String: StorageHostPort]
    ) -> [String: CGPoint] {
        let children = Dictionary(grouping: graph.edges, by: \.fromID)
        let roots = (children["computer"] ?? []).sorted {
            let lhs = ports[$0.id]?.number ?? Int.max
            let rhs = ports[$1.id]?.number ?? Int.max
            return lhs == rhs ? $0.toID < $1.toID : lhs < rhs
        }
        var positions: [String: CGPoint] = ["computer": .zero]
        var visited: Set<String> = []
        // All branches sharing one physical socket leave the same socket.
        // Unmapped paths use a separate bottom exit, never an invented port.
        for side in [-1, 1, 0] {
            let sideRoots = roots.filter { edge in
                let position = ports[edge.id].flatMap { graph.hostModel?.position(for: $0) }
                let edgeSide = position == .right ? 1 : position == nil ? 0 : -1
                return edgeSide == side
            }
            var rows: [String: (depth: Int, row: Double)] = [:]
            var leaf = 0
            @discardableResult
            func place(_ id: String, depth: Int) -> [Int] {
                guard visited.insert(id).inserted else { return [] }
                let next = (children[id] ?? []).sorted { $0.toID < $1.toID }
                var leaves = next.flatMap { place($0.toID, depth: depth + 1) }
                if leaves.isEmpty { leaves = [leaf]; leaf += 1 }
                if let first = leaves.min(), let last = leaves.max() {
                    rows[id] = (depth, Double(first + last) / 2)
                }
                return leaves
            }
            for edge in sideRoots { place(edge.toID, depth: 1) }
            let unknownExitY = max(350, (positions.values.map(\.y).max() ?? 0) + 225)
            for (id, row) in rows {
                let offset = (row.row - Double(max(0, leaf - 1)) / 2) * (side == 0 ? 245 : 185)
                positions[id] = side == 0
                    ? CGPoint(x: offset, y: unknownExitY + Double(row.depth - 1) * 240)
                    : CGPoint(x: Double(side) * (405 + Double(row.depth - 1) * 250), y: offset)
            }
        }
        return positions
    }

    private static func compactedPositions(
        graph: DriveConnectionTopologyGraph,
        positions: [String: CGPoint],
        ports: [String: StorageHostPort]
    ) -> [String: CGPoint] {
        func overlaps(_ candidate: [String: CGPoint]) -> Bool {
            let frames = graph.nodes.compactMap { node -> CGRect? in
                guard let center = candidate[node.id] else { return nil }
                let size = nodeSize(node, host: graph.hostModel)
                return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                              width: size.width, height: size.height)
            }
            return frames.enumerated().contains { index, frame in
                frames.dropFirst(index + 1).contains { frame.intersects($0) }
            }
        }
        let compacted = shortenedPositions(graph: graph, positions: positions, ports: ports,
                                          scale: connectionLengthScale)
        guard overlaps(compacted) else { return compacted }
        // Dense branches may need some of their original clearance to stay disjoint.
        var lower = connectionLengthScale
        var upper = 1.0
        var safePositions = positions
        for _ in 0..<10 {
            let scale = (lower + upper) / 2
            let candidate = shortenedPositions(graph: graph, positions: positions, ports: ports, scale: scale)
            if overlaps(candidate) {
                lower = scale
            } else {
                upper = scale
                safePositions = candidate
            }
        }
        return safePositions
    }

    private static func shortenedPositions(
        graph: DriveConnectionTopologyGraph,
        positions: [String: CGPoint],
        ports: [String: StorageHostPort],
        scale: Double
    ) -> [String: CGPoint] {
        let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        let children = Dictionary(grouping: graph.edges, by: \.fromID)
        var result = positions
        var visited: Set<String> = ["computer"]
        func placeChildren(of id: String) {
            guard let source = nodes[id], let originalCenter = positions[id],
                  let center = result[id] else { return }
            let sourceSize = nodeSize(source, host: graph.hostModel)
            for edge in (children[id] ?? []).sorted(by: { $0.toID < $1.toID }) {
                guard visited.insert(edge.toID).inserted,
                      let target = nodes[edge.toID], let end = positions[edge.toID] else { continue }
                var anchorOffset = CGPoint.zero
                let usesSocket = id == "computer" && graph.hostModel?.hasVerifiedPortLayout == true
                if usesSocket, let host = graph.hostModel {
                    let anchor = ports[edge.id].flatMap { StorageHostArtworkGeometry.anchor($0, model: host) }
                        ?? StorageHostArtworkGeometry.unresolvedAnchor
                    anchorOffset = CGPoint(x: anchor.x - sourceSize.width / 2,
                                           y: anchor.y - sourceSize.height / 2)
                }
                let dx = end.x - originalCenter.x - anchorOffset.x
                let dy = end.y - originalCenter.y - anchorOffset.y
                let distance = hypot(dx, dy)
                guard distance > 0 else { continue }
                let direction = CGPoint(x: dx / distance, y: dy / distance)
                let targetSize = nodeSize(target, host: graph.hostModel)
                let occupied = rayExtent(size: targetSize, direction: direction)
                    + (usesSocket ? 0 : rayExtent(size: sourceSize, direction: direction))
                // Compress only exposed wire, preserving card sizes and physical socket anchors.
                let shortened = shortenedCenterDistance(defaultDistance: distance,
                    occupiedHalfExtent: occupied, scale: scale)
                result[edge.toID] = CGPoint(x: center.x + anchorOffset.x + direction.x * shortened,
                                           y: center.y + anchorOffset.y + direction.y * shortened)
                placeChildren(of: edge.toID)
            }
        }
        placeChildren(of: "computer")
        return result
    }

    private static func rayExtent(size: CGSize, direction: CGPoint) -> Double {
        min(direction.x == 0 ? .infinity : size.width / (2 * abs(direction.x)),
            direction.y == 0 ? .infinity : size.height / (2 * abs(direction.y)))
    }
}
