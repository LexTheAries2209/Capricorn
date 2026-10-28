// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct ReviewMarker: Decodable {
    let x: Double
    let y: Double
    let kind: String

    var color: Color {
        switch kind {
        case "usbC": .orange
        case "usbA": .purple
        default: .blue
        }
    }
}

struct ReviewProjection: Decodable {
    let chassis: [Double]
    let sideRange: [Double]
    let socketX: [Double]
}

struct ReviewPanel: Decodable {
    let title: String
    let asset: String
    let url: URL?
    let crop: [Double]?
    let height: Double
    let projection: ReviewProjection?
    let productionModel: String?
    let markers: [ReviewMarker]

    func resolvedMarkers(imageSize: CGSize) -> [ReviewMarker] {
        if let identifier = productionModel {
            let model = StorageHostModel(identifier: identifier, board: "J414c")
            let frame = StorageHostArtworkGeometry.imageFrame
            let scale = min(frame.width / imageSize.width, frame.height / imageSize.height)
            let imageOrigin = CGPoint(x: frame.midX - imageSize.width * scale / 2,
                                      y: frame.midY - imageSize.height * scale / 2)
            return (1...3).compactMap { number in
                guard let point = StorageHostArtworkGeometry.anchor(.init(number: number), model: model)
                else { return nil }
                return .init(x: (point.x - imageOrigin.x) / scale,
                             y: (point.y - imageOrigin.y) / scale, kind: "thunderbolt")
            }
        }
        if let projection {
            let depth = projection.sideRange[1] - projection.sideRange[0]
            return projection.socketX.map {
                .init(x: projection.chassis[0],
                      y: projection.chassis[1] + ($0 - projection.sideRange[0]) / depth * projection.chassis[3],
                      kind: "thunderbolt")
            }
        }
        return markers
    }
}

struct ReviewModel: Decodable {
    let id: String
    let title: String
    let subtitle: String
    let note: String
    let source: URL
    let panels: [ReviewPanel]
}

@MainActor
struct ReviewImagePanel: View {
    let panel: ReviewPanel
    let image: NSImage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(panel.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            GeometryReader { proxy in
                let size = image.size
                let crop = panel.crop.map { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
                    ?? CGRect(origin: .zero, size: size)
                let scale = min(proxy.size.width / crop.width, proxy.size.height / crop.height)
                let frame = CGRect(x: (proxy.size.width - crop.width * scale) / 2,
                                   y: (proxy.size.height - crop.height * scale) / 2,
                                   width: crop.width * scale, height: crop.height * scale)
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .position(x: (size.width / 2 - crop.minX) * scale,
                                  y: (size.height / 2 - crop.minY) * scale)
                    ForEach(Array(panel.resolvedMarkers(imageSize: size).enumerated()), id: \.offset) { _, marker in
                        Circle().fill(marker.color)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .frame(width: 8, height: 8)
                            .position(x: (marker.x - crop.minX) * scale,
                                      y: (marker.y - crop.minY) * scale)
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .clipped()
                .position(x: frame.midX, y: frame.midY)
            }
            .frame(height: panel.height)
        }
    }
}

@MainActor
struct ReviewView: View {
    let model: ReviewModel
    let images: [String: NSImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.title).font(.system(size: 20, weight: .semibold))
                Text(model.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(Array(model.panels.enumerated()), id: \.offset) { _, panel in
                if let image = images[panel.asset] {
                    ReviewImagePanel(panel: panel, image: image)
                }
            }
            HStack(spacing: 20) {
                legend("雷雳 / USB 4 · 40 Gb/s", color: .blue)
                legend("USB-C · 10 Gb/s", color: .orange)
                legend("USB-A · 5 Gb/s", color: .purple)
            }
            Text(model.note).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Apple 官方资料 · support.apple.com").font(.system(size: 12))
                .foregroundStyle(.blue)
                .onTapGesture { NSWorkspace.shared.open(model.source) }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 700, height: 780, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10))
        }
    }
}

@MainActor
final class ReviewDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var failed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let resources = Bundle.main.resourceURL!
            let models = try JSONDecoder().decode([ReviewModel].self,
                from: Data(contentsOf: resources.appendingPathComponent("models.json")))
            var images: [String: NSImage] = [:]
            // This developer-only preview downloads official artwork once, then reuses the local files.
            for panel in models.flatMap(\.panels) where images[panel.asset] == nil {
                let path = resources.appendingPathComponent(panel.asset)
                if !FileManager.default.fileExists(atPath: path.path), let url = panel.url {
                    try Data(contentsOf: url).write(to: path, options: .atomic)
                }
                guard let image = NSImage(contentsOf: path) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                for marker in panel.resolvedMarkers(imageSize: image.size) {
                    guard marker.x.isFinite, marker.y.isFinite,
                          CGRect(origin: .zero, size: image.size).contains(CGPoint(x: marker.x, y: marker.y))
                    else { throw CocoaError(.coderInvalidValue) }
                }
                if !panel.markers.isEmpty {
                    let bitmap = try NSBitmapImageRep(data: Data(contentsOf: path)).unwrap()
                    for marker in panel.markers {
                        let color = try bitmap.colorAt(x: Int(marker.x), y: Int(marker.y))?
                            .usingColorSpace(.deviceRGB).unwrap()
                        // Explicit side/rear anchors must land on the dark socket, not the casing.
                        guard let color, max(color.redComponent, color.greenComponent, color.blueComponent) < 0.55
                        else { throw CocoaError(.coderInvalidValue) }
                    }
                }
                images[panel.asset] = image
            }
            let export = resources.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("renders", isDirectory: true)
            try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
            for (index, model) in models.enumerated() {
                let content = ReviewView(model: model, images: images)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                guard let bitmap = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:])
                else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: export.appendingPathComponent("\(model.id).png"), options: .atomic)
                if !CommandLine.arguments.contains("--render-only") {
                    let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
                    let scale = min(1, (screen.width - 50) / 700, (screen.height - 70) / 780)
                    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700 * scale, height: 780 * scale),
                        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
                    window.title = model.title
                    window.isReleasedWhenClosed = false
                    window.contentView = NSHostingView(rootView: content.scaleEffect(scale)
                        .frame(width: 700 * scale, height: 780 * scale))
                    window.setFrameTopLeftPoint(CGPoint(
                        x: screen.minX + 25 + CGFloat(index) * 45,
                        y: screen.maxY - 25 - CGFloat(index) * 28))
                    window.makeKeyAndOrderFront(nil)
                    windows.append(window)
                }
            }
            try Data("Rendered \(models.count) models; opened \(windows.count) windows.\n".utf8)
                .write(to: export.appendingPathComponent("status.txt"), options: .atomic)
            if CommandLine.arguments.contains("--render-only") {
                NSApp.terminate(nil)
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        } catch {
            failed = true
            NSLog("Port review failed: %@", String(describing: error))
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
enum HostPortReview {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = ReviewDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
        if delegate.failed { exit(1) }
    }
}

private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let value = self else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }
}
