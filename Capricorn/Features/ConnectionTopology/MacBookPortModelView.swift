// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// A top-oriented schematic. Socket numbers come from IOPort; positions are
/// enabled only for the board layouts verified by StorageHostModel.
struct MacBookPortModelView: View {
    let model: StorageHostModel
    let selected: Bool
    let connectedPorts: Set<StorageHostPort>
    let selectedPorts: Set<StorageHostPort>
    @Environment(\.appLanguage) private var language

    static func anchor(_ port: StorageHostPort) -> CGPoint? {
        switch port.number {
        case 1: CGPoint(x: 38, y: 167)
        case 2: CGPoint(x: 38, y: 198)
        case 3: CGPoint(x: 302, y: 181)
        default: nil
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .secondary, lineWidth: 2))
                .frame(width: 224, height: 128).position(x: 170, y: 74)
            VStack(spacing: 6) {
                Image(systemName: "apple.logo").font(.title2)
                Text("MacBook Pro").font(.subheadline.bold())
                Text(model.identifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(language.t("This Mac")).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 216, height: 120).position(x: 170, y: 74)
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.13))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor : .secondary, lineWidth: selected ? 2 : 1))
                .frame(width: 264, height: 118).position(x: 170, y: 199)
            Canvas { context, _ in
                for row in 0..<4 {
                    for column in 0..<12 {
                        let rect = CGRect(x: CGFloat(78 + column * 15), y: CGFloat(151 + row * 12), width: 12, height: 8)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.secondary.opacity(0.5)))
                    }
                }
                let trackpad = Path(roundedRect: CGRect(x: 132, y: 210, width: 76, height: 34), cornerRadius: 4)
                context.stroke(trackpad, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
            }
            ForEach(1...3, id: \.self) { number in
                let port = StorageHostPort(number: number)
                if let point = Self.anchor(port) {
                    let active = selectedPorts.contains(port)
                    Capsule()
                        .fill(active ? Color.accentColor : connectedPorts.contains(port) ? .primary : .secondary.opacity(0.4))
                        .frame(width: 6, height: 15)
                        .position(point)
                    Text("\(number)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(active ? Color.accentColor : .secondary)
                        .position(x: number == 3 ? 319 : 21, y: point.y)
                }
            }
            Text("1 \(language.t("Left rear"))  ·  2 \(language.t("Left front"))  ·  3 \(language.t("Right side"))")
                .font(.system(size: 9)).foregroundStyle(.secondary)
                .frame(width: 330).position(x: 170, y: 274)
        }
        .frame(width: 340, height: 280)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MacBook Pro · \(model.identifier) · \(language.t("This Mac"))")
    }
}
