// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics

/// Stable document coordinates keep drag deltas independent of magnification.
/// Extra canvas space allows free placement without shifting the canvas origin.
struct TopologyNodePlacement {
    static let margin: CGFloat = 800
    private(set) var offsets: [String: CGSize] = [:]
    private var dragID: String?
    private var dragOrigin: CGSize = .zero

    func layout(from base: StorageTopologyRadialLayout) -> StorageTopologyRadialLayout {
        let positions = base.positions.mapValues {
            CGPoint(x: $0.x + Self.margin, y: $0.y + Self.margin)
        }
        let adjusted = positions.map { id, position in
            let offset = offsets[id] ?? .zero
            return (id, CGPoint(x: position.x + offset.width, y: position.y + offset.height))
        }
        return StorageTopologyRadialLayout(
            positions: Dictionary(uniqueKeysWithValues: adjusted),
            size: CGSize(width: base.size.width + Self.margin * 2,
                         height: base.size.height + Self.margin * 2)
        )
    }

    mutating func drag(
        _ id: String, translation: CGSize,
        basePosition: CGPoint, nodeSize: CGSize, documentSize: CGSize
    ) {
        guard translation.width.isFinite, translation.height.isFinite else { return }
        if dragID != id {
            dragID = id
            dragOrigin = offsets[id] ?? .zero
        }
        let base = CGPoint(x: basePosition.x + Self.margin, y: basePosition.y + Self.margin)
        let proposed = CGPoint(x: base.x + dragOrigin.width + translation.width,
                               y: base.y + dragOrigin.height + translation.height)
        // Keep the whole node reachable, including its hit target at the edge.
        let half = CGSize(width: nodeSize.width / 2 + 24, height: nodeSize.height / 2 + 24)
        let center = CGPoint(
            x: min(documentSize.width - half.width, max(half.width, proposed.x)),
            y: min(documentSize.height - half.height, max(half.height, proposed.y))
        )
        offsets[id] = CGSize(width: center.x - base.x, height: center.y - base.y)
    }

    mutating func endDrag() {
        dragID = nil
        dragOrigin = .zero
    }

    mutating func reset() {
        offsets.removeAll()
        endDrag()
    }
}
