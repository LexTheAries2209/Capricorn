// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Driver wrappers stay in the inspector; the diagram retains ports, hubs,
/// identified bridge chips and disks, preserving shared registry identities.
struct StorageTopologyDiagram {
    let graph: DriveConnectionTopologyGraph
    let hardwareSegments: [String: [DriveConnectionTopologyNode]]
    let systemDriveIDs: Set<String>
    let hostPortsByEdgeID: [String: StorageHostPort]

    init(graph source: DriveConnectionTopologyGraph, systemDriveIDs: Set<String> = []) {
        self.systemDriveIDs = systemDriveIDs
        var paths: [String: DriveConnectionTopologyPath] = [:]
        var segments: [String: [DriveConnectionTopologyNode]] = [:]
        var portsByEdgeID: [String: StorageHostPort] = [:]
        for disk in source.nodes where disk.kind == .disk {
            guard let bsdName = disk.bsdName, !systemDriveIDs.contains(bsdName) else { continue }
            let path = source.path(for: bsdName)
            let hasPort = path.contains { [.usbPort, .thunderboltPort].contains($0.kind) }
            let hostPort = path.compactMap(\.hostPort).first
                .flatMap { source.hostModel?.position(for: $0) == nil ? nil : $0 }
            var visible: [DriveConnectionTopologyNode] = []
            var segment: [DriveConnectionTopologyNode] = []
            var hasHostThunderboltPort = false
            for node in path {
                segment.append(node)
                let isHostThunderboltPort = node.kind == .thunderboltPort && !hasHostThunderboltPort
                if node.kind == .thunderboltPort { hasHostThunderboltPort = true }
                let keepPort = node.kind == .usbPort && (hostPort == nil || node.hostPort != hostPort)
                let keep = [.computer, .disk, .usbHub].contains(node.kind) || keepPort
                    || (isHostThunderboltPort && hostPort == nil)
                    || (node.kind == .pcieBridge && node.chipDescription != nil)
                    || (!hasPort && hostPort == nil
                        && [.usbHostController, .storageController, .sataController, .nvmeController].contains(node.kind))
                if keep {
                    visible.append(node)
                    segments[node.id] = segment
                    segment = []
                }
            }
            paths[bsdName] = .init(nodes: visible, hasResolvedController: visible.count > 2)
            if let hostPort, visible.count > 1 {
                portsByEdgeID["computer->\(visible[1].id)"] = hostPort
            }
        }
        let assembled = DriveConnectionTopologyGraph.assemble(paths: paths)
        // The host remains visible even when its built-in system disk is the only disk.
        if assembled.nodes.isEmpty, let host = source.nodes.first(where: { $0.kind == .computer }) {
            graph = .init(nodes: [host], edges: [], hostModel: source.hostModel)
        } else {
            graph = .init(nodes: assembled.nodes, edges: assembled.edges, hostModel: source.hostModel)
        }
        hardwareSegments = segments
        hostPortsByEdgeID = portsByEdgeID
    }

    func selectedNodeIDs(for driveID: String) -> Set<String> {
        systemDriveIDs.contains(driveID) ? ["computer"] : graph.pathNodeIDs(to: driveID)
    }
}

struct StorageTopologyGraphView: View {
    let graph: DriveConnectionTopologyGraph
    let selectedDriveID: String
    var systemDriveIDs: Set<String> = []
    let selectDrive: (String) -> Void

    @Environment(\.appLanguage) private var language
    @State private var zoom: CGFloat = 1

    var body: some View {
        let diagram = StorageTopologyDiagram(graph: graph, systemDriveIDs: systemDriveIDs)
        let layout = StorageTopologyRadialLayout(graph: diagram.graph, hostPortsByEdgeID: diagram.hostPortsByEdgeID)
        let selectedNodes = diagram.selectedNodeIDs(for: selectedDriveID)
        let selectedEdges = diagram.graph.pathEdges(for: selectedDriveID)
        VStack(spacing: 0) {
            HStack {
                Label(language.t("Hardware Path"), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { zoom = max(0.6, zoom - 0.2) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help(language.t("Zoom Out"))
                .disabled(zoom <= 0.6)
                Button { zoom = 1 } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help(language.t("Fit Topology"))
                Button { zoom = min(3, zoom + 0.2) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help(language.t("Zoom In"))
                .disabled(zoom >= 3)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            GeometryReader { geometry in
                let fit = min(1, (geometry.size.width - 24) / layout.size.width,
                              (geometry.size.height - 24) / layout.size.height)
                let scale = fit * zoom
                ScrollView([.horizontal, .vertical]) {
                    drawing(diagram, layout: layout, selectedNodes: selectedNodes, selectedEdges: selectedEdges)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: layout.size.width * scale, height: layout.size.height * scale,
                               alignment: .topLeading)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
            }
            .frame(height: diagram.graph.hostModel?.hasVerifiedPortLayout == true ? 460 : 560)
        }
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5)))
        .accessibilityIdentifier("storageTopologyGraph")
    }

    private func drawing(
        _ diagram: StorageTopologyDiagram,
        layout: StorageTopologyRadialLayout,
        selectedNodes: Set<String>,
        selectedEdges: Set<String>
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for edge in diagram.graph.edges {
                    guard var start = layout.positions[edge.fromID], let end = layout.positions[edge.toID] else { continue }
                    if edge.fromID == "computer", let model = diagram.graph.hostModel, model.hasVerifiedPortLayout {
                        let anchor = diagram.hostPortsByEdgeID[edge.id]
                            .flatMap { StorageHostArtworkGeometry.anchor($0, model: model) }
                            ?? StorageHostArtworkGeometry.unresolvedAnchor
                        start.x += anchor.x - StorageHostArtworkGeometry.size.width / 2
                        start.y += anchor.y - StorageHostArtworkGeometry.size.height / 2
                    }
                    let selected = selectedEdges.contains(edge.id)
                    var path = Path()
                    path.move(to: start)
                    path.addLine(to: end)
                    let unresolved = edge.fromID == "computer"
                        && (diagram.graph.hostModel?.hasVerifiedPortLayout == true
                            ? diagram.hostPortsByEdgeID[edge.id] == nil
                            : diagram.graph.nodes.first { $0.id == edge.toID }?.kind == .disk)
                    context.stroke(path, with: .color(selected ? .accentColor : .secondary.opacity(0.35)),
                                   style: StrokeStyle(lineWidth: selected ? 2.5 : 1.5,
                                                      dash: unresolved ? [5, 5] : []))
                }
            }
            ForEach(diagram.graph.nodes) { node in
                let selected = selectedNodes.contains(node.id)
                let size = StorageTopologyRadialLayout.nodeSize(node, host: diagram.graph.hostModel)
                let segment = diagram.hardwareSegments[node.id] ?? [node]
                Group {
                    if node.kind == .computer, let model = diagram.graph.hostModel {
                        Button {
                            if let id = systemDriveIDs.contains(selectedDriveID) ? selectedDriveID : systemDriveIDs.sorted().first {
                                selectDrive(id)
                            }
                        } label: {
                            if model.hasVerifiedPortLayout {
                                MacBookPortModelView(
                                    model: model, selected: selected,
                                    connectedPorts: Set(diagram.hostPortsByEdgeID.values),
                                    selectedPorts: Set(diagram.hostPortsByEdgeID.filter { selectedEdges.contains($0.key) }.map(\.value))
                                )
                            } else {
                                StorageHostArtworkView(model: model, selected: selected)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("topologyHostComputer")
                    } else if let bsdName = node.bsdName {
                        Button { selectDrive(bsdName) } label: {
                            nodeContent(node, segment: segment, selected: selected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("topologyDisk-\(bsdName)")
                    } else {
                        nodeContent(node, segment: segment, selected: selected)
                    }
                }
                .frame(width: size.width, height: size.height)
                .help(segment.map { $0.hardwareName ?? language.t($0.kind.titleKey) }.joined(separator: " → "))
                .position(layout.positions[node.id] ?? .zero)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    private func nodeContent(
        _ node: DriveConnectionTopologyNode,
        segment: [DriveConnectionTopologyNode],
        selected: Bool
    ) -> some View {
        let isHost = node.kind == .computer
        let rate = node.linkRateDescription ?? segment.reversed().compactMap(\.linkRateDescription).first
        let chips = Array(Set(segment.compactMap(\.chipDescription))).sorted()
        return VStack(spacing: 5) {
            Image(systemName: node.kind.symbolName)
                .font(.system(size: isHost ? 25 : 20))
                .foregroundStyle(selected || isHost ? Color.accentColor : .secondary)
            Text(isHost ? language.t("This Mac") : node.hardwareName ?? language.t(node.kind.titleKey))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let port = node.portDescription {
                Text(port).font(.system(size: 10)).lineLimit(1)
            }
            if let bsdName = node.bsdName {
                Text(bsdName).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            if let rate {
                Text(rate).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            if !chips.isEmpty {
                Text(chips.joined(separator: " · ")).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
            } else if node.kind == .disk && segment.count == 1 {
                Text(language.t("Chip model not reported")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                              lineWidth: selected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
