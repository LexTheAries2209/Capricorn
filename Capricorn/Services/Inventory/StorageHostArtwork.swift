// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import UniformTypeIdentifiers

/// Prefer a bundled official keyboard view for verified MacBook chassis, then
/// resolve other Mac families through the system's device-model type database.
@MainActor
final class StorageHostArtwork {
    static let shared = StorageHostArtwork()
    private var images: [String: NSImage] = [:]
    private var missing: Set<String> = []

    static func contentType(for identifier: String) -> UTType? {
        guard let mac = UTType("com.apple.mac") else { return nil }
        // Unknown tags create a dynamic document type; that is not Mac artwork.
        return UTType.types(tag: identifier,
                            tagClass: UTTagClass(rawValue: "com.apple.device-model-code"),
                            conformingTo: nil).first {
            $0.isDeclared && $0.identifier.hasPrefix("com.apple.") && $0.conforms(to: mac)
        }
    }

    func image(for identifier: String) -> NSImage? {
        if let image = images[identifier] { return image }
        if let view = StorageHostTopView(identifier: identifier),
           let image = NSImage(named: view.assetName) {
            images[identifier] = image
            return image
        }
        guard !missing.contains(identifier), let type = Self.contentType(for: identifier) else {
            missing.insert(identifier)
            return nil
        }
        let image = NSWorkspace.shared.icon(for: type)
        let result = Self.trimmingTransparentPadding(image)
        images[identifier] = result
        return result
    }

    private static func trimmingTransparentPadding(_ image: NSImage) -> NSImage {
        var proposed = NSRect(x: 0, y: 0, width: 1024, height: 1024)
        guard let original = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return image }
        let width = original.width, height = original.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                        | CGBitmapInfo.byteOrder32Big.rawValue) else { return image }
        context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return image }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > 2 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY, let rendered = context.makeImage(),
              let cropped = rendered.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
        else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }
}
