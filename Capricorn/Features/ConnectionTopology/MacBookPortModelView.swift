// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Use official artwork, with numbered socket hotspots overlaid
/// on its chassis. These are a connection diagram, not additional image assets.
struct MacBookPortModelView: View {
    let model: StorageHostModel
    let selected: Bool
    let connectedPorts: Set<StorageHostPort>
    let selectedPorts: Set<StorageHostPort>
    @Environment(\.appLanguage) private var language

    var body: some View {
        ZStack(alignment: .topLeading) {
            StorageHostArtworkView(model: model, selected: selected)
            ForEach(1...3, id: \.self) { number in
                let port = StorageHostPort(number: number)
                if let point = StorageHostArtworkGeometry.anchor(port, model: model) {
                    let active = selectedPorts.contains(port)
                    Circle()
                        .fill(active ? Color.accentColor : connectedPorts.contains(port) ? .primary : .secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .position(point)
                    Text("\(number)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(active ? Color.accentColor : .secondary)
                        .position(x: point.x + (number == 3 ? 12 : -12),
                                  y: point.y + (number == 1 ? -10 : number == 2 ? 8 : 0))
                }
            }
        }
        .frame(width: StorageHostArtworkGeometry.size.width, height: StorageHostArtworkGeometry.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.productName ?? "MacBook Pro") · \(model.identifier) · \(language.t("This Mac"))")
    }
}
