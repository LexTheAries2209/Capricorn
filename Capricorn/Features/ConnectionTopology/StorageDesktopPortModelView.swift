// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Desktop Macs use a top or rear view so every connection line begins at a
/// visible front, rear, or back-panel port marker.
struct StorageDesktopPortModelView: View {
    let model: StorageHostModel
    let selected: Bool
    let connectedPorts: Set<StorageHostPort>
    let selectedPorts: Set<StorageHostPort>

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let profile = model.desktopPortLayout,
               let assetName = StorageHostArtworkGeometry.assetName(for: model),
               let image = NSImage(named: assetName) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: profile.artworkFrame.width, height: profile.artworkFrame.height)
                    .shadow(color: selected ? Color.accentColor.opacity(0.5) : .clear, radius: 10)
                    .position(x: profile.artworkFrame.midX, y: profile.artworkFrame.midY)
            } else {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 90))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            ForEach(model.desktopPortLayout?.sockets ?? []) { socket in
                let port = socket.port
                if let point = StorageHostArtworkGeometry.anchor(port, model: model) {
                    Circle()
                        .fill(selectedPorts.contains(port)
                            ? Color.accentColor
                            : connectedPorts.contains(port) ? .primary : .secondary.opacity(0.4))
                        .overlay(Circle().stroke(.background, lineWidth: 1))
                        .frame(width: 7, height: 7)
                        .position(point)
                        .help(socket.title)
                }
            }
            Text(model.productName ?? model.identifier)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 320, height: 34)
                .position(x: 170, y: 231)
        }
        .frame(width: StorageHostArtworkGeometry.size.width,
               height: StorageHostArtworkGeometry.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.productName ?? model.identifier) · This Mac")
    }

}
