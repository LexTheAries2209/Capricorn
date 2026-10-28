// SPDX-License-Identifier: GPL-3.0-only
#if DEBUG
import AppKit
import SwiftUI

/// Opt-in review windows exercise the production topology view with explicit
/// synthetic socket associations. They never write the user's real associations.
@MainActor
final class StorageDesktopReviewController {
    static let shared = StorageDesktopReviewController()
    private var windows: [NSWindow] = []

    func open() {
        guard windows.isEmpty else { return }
        let models: [(String, String)] = [
            ("Mac14,3", "Mac mini M2 · 俯视"),
            ("Mac16,10", "Mac mini M4 · 俯视"),
            ("Mac14,13", "Mac Studio M2 Max · 俯视"),
            ("Mac16,2", "iMac M4 双口 · 背视"),
            ("Mac16,3", "iMac M4 四口 · 背视"),
            ("Mac18,5", "Mac mini M6 · 俯视"),
            ("review-imac-m6", "iMac M6 四口 · 背视")
        ]
        for (index, entry) in models.enumerated() {
            let model = StorageHostModel(identifier: entry.0, board: "", productName: entry.1)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "\(entry.1) · 端点数据链校对"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: StorageDesktopReviewView(model: model))
            let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            window.setFrameTopLeftPoint(CGPoint(x: screen.minX + 20 + CGFloat(index % 4) * 35,
                                                y: screen.maxY - 20 - CGFloat(index % 3) * 25))
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.exportSnapshots()
        }
    }

    private func exportSnapshots() {
        guard let index = CommandLine.arguments.firstIndex(of: "--desktop-review-export"),
              CommandLine.arguments.indices.contains(index + 1) else { return }
        let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (index, window) in windows.enumerated() {
                guard let view = window.contentView,
                      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
                try data.write(to: folder.appendingPathComponent("desktop-chain-\(index).png"), options: .atomic)
            }
            try Data("Opened \(windows.count) production topology review windows.\n".utf8)
                .write(to: folder.appendingPathComponent("status.txt"), options: .atomic)
        } catch {
            NSLog("Desktop topology review export failed: %@", String(describing: error))
        }
    }
}

private struct StorageDesktopReviewView: View {
    let model: StorageHostModel
    @State private var selectedDrive = "review-disk0"

    var body: some View {
        let fixture = Self.fixture(model)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.productName ?? model.identifier).font(.title2.weight(.semibold))
                Spacer()
                Picker("选中设备", selection: $selectedDrive) {
                    Text("示例外置盘").tag("review-disk0")
                    Text("另一示例外置盘").tag("review-disk1")
                    Text("系统盘").tag("system")
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
            }
            StorageTopologyGraphView(graph: fixture.graph, selectedDriveID: selectedDrive,
                systemDriveIDs: ["system"], selectDrive: { selectedDrive = $0 },
                previewHostPortOverrides: fixture.ports)
            Text("校对用示例链路 · 使用应用实际拓扑视图；端点已明确指定，非本机硬盘实况。")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 800, minHeight: 590)
        .background(.background)
    }

    private static func fixture(_ model: StorageHostModel)
        -> (graph: DriveConnectionTopologyGraph, ports: [String: StorageHostPort]) {
        let profile = model.desktopPortLayout!
        let first = profile.sockets.first { $0.side == .back }!
        let second = profile.sockets.first { $0.side == .front } ?? profile.sockets.last!
        let host = node("computer", .computer, "This Mac")
        var paths: [String: DriveConnectionTopologyPath] = [:]
        var overrides: [String: StorageHostPort] = [:]
        for (index, socket) in [first, second].enumerated() {
            let bsd = "review-disk\(index)"
            let rootID = "review-bridge\(index)"
            var bridge = node(rootID, .pcieBridge, "PCI-Bridge")
            bridge.chipDescription = index == 0 ? "JHL8440" : "ASM2464PD"
            let disk = node("disk:\(bsd)", .disk, index == 0 ? "External SSD" : "Portable SSD", bsd: bsd)
            paths[bsd] = .init(nodes: [host, bridge, disk], hasResolvedController: true)
            overrides[rootID] = socket.port
        }
        var graph = DriveConnectionTopologyGraph.assemble(paths: paths)
        graph.hostModel = model
        return (graph, overrides)
    }

    private static func node(_ id: String, _ kind: DriveConnectionTopologyNode.Kind,
                             _ name: String, bsd: String? = nil) -> DriveConnectionTopologyNode {
        .init(id: id, kind: kind, hardwareName: name, portDescription: nil,
              linkRateDescription: kind == .computer ? nil : "40 Gb/s",
              bsdName: bsd, pcieLink: nil, isPCIeTunnelled: false)
    }
}
#endif
