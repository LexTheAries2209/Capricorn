// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

// The production artwork view uses this environment only for its accessibility label.
// Keep the preview independent of the application's unrelated domain translations.
struct ReviewLanguage {
    func t(_ key: String) -> String { key == "This Mac" ? "本机" : key }
}

private struct ReviewLanguageKey: EnvironmentKey {
    static let defaultValue = ReviewLanguage()
}

extension EnvironmentValues {
    var appLanguage: ReviewLanguage {
        get { self[ReviewLanguageKey.self] }
        set { self[ReviewLanguageKey.self] = newValue }
    }
}

struct ReviewMarker: Decodable {
    let x: Double
    let y: Double
    let kind: String

    var color: Color {
        switch kind {
        case "usbC": .orange
        case "usbA": .purple
        case "thunderbolt5": .green
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
    let asset: String?
    let url: URL?
    let crop: [Double]?
    let height: Double
    let projection: ReviewProjection?
    let productionModel: String?
    let templateModel: String?
    let portNumbers: [Int]?
    let hostModels: [ReviewHost]?
    let markers: [ReviewMarker]

    func resolvedMarkers(imageSize: CGSize) -> [ReviewMarker] {
        if let identifier = productionModel ?? templateModel {
            let model = StorageHostModel(identifier: identifier, board: "J414c")
            let frame = StorageHostArtworkGeometry.imageFrame
            let scale = min(frame.width / imageSize.width, frame.height / imageSize.height)
            let imageOrigin = CGPoint(x: frame.midX - imageSize.width * scale / 2,
                                      y: frame.midY - imageSize.height * scale / 2)
            return (portNumbers ?? [1, 2, 3]).compactMap { number in
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

struct ReviewHost: Decodable {
    let identifier: String
    let title: String

    var model: StorageHostModel {
        .init(identifier: identifier, board: "", productName: title)
    }
}

enum ReviewFailure: Error {
    case invalidMarker(asset: String, x: Double, y: Double)
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
struct ReviewSystemEndpoints: View {
    let hosts: [ReviewHost]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("选中外置盘时的本机")
                Spacer()
                Text("选中系统盘时的本机")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            ForEach(hosts, id: \.identifier) { host in
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(host.title) · \(host.identifier)").font(.system(size: 12))
                    HStack(spacing: 24) {
                        endpoint(host.model, selected: false)
                        endpoint(host.model, selected: true)
                    }
                }
            }
        }
    }

    private func endpoint(_ model: StorageHostModel, selected: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            // Unverified desktop layouts use the node center in StorageTopologyGraphView.
            if !selected {
                TopologyConnectionLine(start: CGPoint(x: 153, y: 70),
                    end: CGPoint(x: 300, y: 70), selected: true, unresolved: true)
            }
            StorageHostArtworkView(model: model, selected: selected)
                .scaleEffect(0.5, anchor: .topLeading)
                .frame(width: 170, height: 140, alignment: .topLeading)
                .position(x: 153, y: 70)
        }
        .frame(width: 306, height: 152)
        .clipped()
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
                if let hosts = panel.hostModels {
                    ReviewSystemEndpoints(hosts: hosts)
                } else if let asset = panel.asset, let image = images[asset] {
                    ReviewImagePanel(panel: panel, image: image)
                }
            }
            if !model.panels.contains(where: { $0.hostModels != nil }) {
                HStack(spacing: 16) {
                    legend("雷雳 / USB 4 · 40 Gb/s", color: .blue)
                    legend("USB-C · 10 Gb/s", color: .orange)
                    legend("USB-A · 5 Gb/s", color: .purple)
                    if model.panels.flatMap(\.markers).contains(where: { $0.kind == "thunderbolt5" }) {
                        legend("雷雳 5 · 80 Gb/s", color: .green)
                    }
                }
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
            let additional = CommandLine.arguments.contains("--additional")
            let manifest = CommandLine.arguments.contains("--2026") ? "2026-models.json"
                : additional ? "additional-models.json" : "models.json"
            let models = try JSONDecoder().decode([ReviewModel].self,
                from: Data(contentsOf: resources.appendingPathComponent(manifest)))
            var images: [String: NSImage] = [:]
            // This developer-only preview downloads official artwork once, then reuses the local files.
            for panel in models.flatMap(\.panels) {
                guard let asset = panel.asset else { continue }
                let path = resources.appendingPathComponent(asset)
                if !FileManager.default.fileExists(atPath: path.path), let url = panel.url {
                    let request = URLRequest(url: url, timeoutInterval: 20)
                    let semaphore = DispatchSemaphore(value: 0)
                    let download = ReviewDownload()
                    URLSession.shared.dataTask(with: request) { data, response, error in
                        download.data = (response as? HTTPURLResponse)?.statusCode == 200 ? data : nil
                        download.error = error
                        semaphore.signal()
                    }.resume()
                    guard semaphore.wait(timeout: .now() + 25) == .success,
                          let data = download.data else {
                        throw download.error ?? CocoaError(.fileReadUnknown)
                    }
                    try data.write(to: path, options: .atomic)
                }
                guard let image = NSImage(contentsOf: path) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                for marker in panel.resolvedMarkers(imageSize: image.size) {
                    guard marker.x.isFinite, marker.y.isFinite,
                          CGRect(origin: .zero, size: image.size).contains(CGPoint(x: marker.x, y: marker.y))
                    else { throw ReviewFailure.invalidMarker(asset: asset, x: marker.x, y: marker.y) }
                }
                if !panel.markers.isEmpty {
                    let bitmap = try NSBitmapImageRep(data: Data(contentsOf: path)).unwrap()
                    for marker in panel.markers {
                        func luminance(_ x: Int, _ y: Int) -> Double {
                            guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh,
                                  let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                            else { return 1 }
                            return color.redComponent * 0.2126
                                + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                        }
                        // Silver and colored socket tongues need contrast against the nearby casing.
                        let casing = (luminance(Int(marker.x) - 12, Int(marker.y))
                            + luminance(Int(marker.x) + 12, Int(marker.y))) / 2
                        let threshold = max(0.3, min(0.55, casing - 0.15))
                        var darkPixels = 0
                        for y in (Int(marker.y) - 4)...(Int(marker.y) + 4) {
                            for x in (Int(marker.x) - 4)...(Int(marker.x) + 4) {
                                if luminance(x, y) < threshold {
                                    darkPixels += 1
                                }
                            }
                        }
                        guard darkPixels >= 20
                        else { throw ReviewFailure.invalidMarker(asset: asset, x: marker.x, y: marker.y) }
                    }
                }
                images[asset] = image
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
                        x: min(screen.maxX - 700 * scale - 10, screen.minX + 25 + CGFloat(index % 6) * 38),
                        y: screen.maxY - 20 - CGFloat(index % 3)
                            * min(18, max(0, (screen.height - 780 * scale - 40) / 3))))
                    window.makeKeyAndOrderFront(nil)
                    windows.append(window)
                }
            }
            let status = "Rendered \(models.count) models; opened \(windows.count) windows.\n"
                + models.map(\.title).joined(separator: "\n") + "\n"
            try Data(status.utf8)
                .write(to: export.appendingPathComponent("status.txt"), options: .atomic)
            if CommandLine.arguments.contains("--render-only") {
                NSApp.terminate(nil)
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        } catch {
            failed = true
            NSLog("Port review failed: %@", String(describing: error))
            exit(1)
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
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出校对窗口", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        app.mainMenu = menu
        app.windowsMenu = windowMenu
        let delegate = ReviewDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
        if delegate.failed { exit(1) }
    }
}

private final class ReviewDownload: @unchecked Sendable {
    // The semaphore publishes completion before the main thread reads these values.
    var data: Data?
    var error: Error?
}

private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let value = self else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }
}
