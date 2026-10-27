// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UniformTypeIdentifiers

struct StorageHostArtworkView: View {
    let model: StorageHostModel
    let selected: Bool
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(spacing: 7) {
            Group {
                if let image = StorageHostArtwork.shared.image(for: model.identifier) {
                    Image(nsImage: image)
                        .resizable().interpolation(.high).scaledToFit()
                        .shadow(color: selected ? Color.accentColor.opacity(0.5) : .clear, radius: 10)
                } else {
                    Image(systemName: "desktopcomputer").font(.system(size: 90))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                }
            }
            .frame(width: StorageHostArtworkGeometry.imageFrame.width,
                   height: StorageHostArtworkGeometry.imageFrame.height)
            Text(model.productName ?? StorageHostArtwork.contentType(for: model.identifier)?.localizedDescription ?? model.identifier)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(width: StorageHostArtworkGeometry.size.width,
               height: StorageHostArtworkGeometry.size.height, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.productName ?? model.identifier) · \(language.t("This Mac"))")
    }
}
