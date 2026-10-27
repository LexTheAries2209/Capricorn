// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct TopologyConnectionLine: View {
    let start: CGPoint
    let end: CGPoint
    let selected: Bool
    let unresolved: Bool

    var body: some View {
        let origin = CGPoint(x: min(start.x, end.x) - 2, y: min(start.y, end.y) - 2)
        Path { path in
            path.move(to: CGPoint(x: start.x - origin.x, y: start.y - origin.y))
            path.addLine(to: CGPoint(x: end.x - origin.x, y: end.y - origin.y))
        }
        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.35),
                style: StrokeStyle(lineWidth: selected ? 2.5 : 1.5, dash: unresolved ? [5, 5] : []))
        .frame(width: abs(end.x - start.x) + 4, height: abs(end.y - start.y) + 4)
        .position(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
