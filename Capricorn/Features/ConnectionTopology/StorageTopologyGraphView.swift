// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Driver wrappers, USB ports, and generic USB hubs stay in the inspector; the diagram retains named docks,
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
            let presentationPath = Self.uniquePCIeBridgeChips(in: path)
            let hasPort = path.contains { [.usbPort, .thunderboltPort].contains($0.kind) }
            let hostPort = path.compactMap(\.hostPort).first
                .flatMap { source.hostModel?.position(for: $0) == nil ? nil : $0 }
            var visible: [DriveConnectionTopologyNode] = []
            var segment: [DriveConnectionTopologyNode] = []
            var hasHostThunderboltPort = false
            for node in presentationPath {
                segment.append(node)
                let isHostThunderboltPort = node.kind == .thunderboltPort && !hasHostThunderboltPort
                if node.kind == .thunderboltPort { hasHostThunderboltPort = true }
                let keepUSBHub = node.kind == .usbHub
                    && (node.isUSBTunnelled || node.hardwareName.map { !Self.isGenericUSBHub($0) } == true)
                let keep = [.computer, .disk].contains(node.kind) || keepUSBHub
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

    // IOKit can expose one tunneled chip as repeated nested PCI bridge nodes.
    static func uniquePCIeBridgeChips(
        in nodes: [DriveConnectionTopologyNode]
    ) -> [DriveConnectionTopologyNode] {
        var seenChipIDs: Set<String> = []
        return nodes.filter { node in
            guard node.kind == .pcieBridge else { return true }
            guard let chipDescription = node.chipDescription else { return false }
            return seenChipIDs.insert(chipDescription.uppercased()).inserted
        }
    }

    static func isGenericUSBHub(_ hardwareName: String?) -> Bool {
        USBHubPresentation.isGeneric(hardwareName)
    }
}

struct StorageTopologyGraphView: View {
    let graph: DriveConnectionTopologyGraph
    let selectedDriveID: String
    var resolvedChipRecords: [String: DeviceHuntChipCatalog.Record] = [:]
    var systemDriveIDs: Set<String> = []
    let selectDrive: (String) -> Void

    @Environment(\.appLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.topologyResetRevision) private var resetRevision
    @Environment(\.topologyZoomInRevision) private var zoomInRevision
    @Environment(\.topologyZoomOutRevision) private var zoomOutRevision
    @State private var zoom: CGFloat = 1
    @State private var viewportCommand = TopologyViewportCommand()
    @State private var nodePlacement = TopologyNodePlacement()

    var body: some View {
        let diagram = StorageTopologyDiagram(graph: graph, systemDriveIDs: systemDriveIDs)
        let baseLayout = StorageTopologyRadialLayout(graph: diagram.graph, hostPortsByEdgeID: diagram.hostPortsByEdgeID)
        let layout = nodePlacement.layout(from: baseLayout)
        let selectedNodes = diagram.selectedNodeIDs(for: selectedDriveID)
        let selectedEdges = diagram.graph.pathEdges(for: selectedDriveID)
        VStack(spacing: 0) {
            HStack {
                Label(language.t("Hardware Path"), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { viewportCommand.request(.zoomOut) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("\(language.t("Zoom Out")) (-)")
                .disabled(zoom <= TopologyZoomLimits.minimum + 0.001)
                Button { resetViewport() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("\(language.t("Rearrange and fit topology")) (Z)")
                Button { viewportCommand.request(.zoomIn) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("\(language.t("Zoom In")) (+)")
                .disabled(zoom >= TopologyZoomLimits.maximum - 0.001)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            TopologyMagnifyingScrollView(
                documentSize: layout.size,
                fittingRect: CGRect(x: TopologyNodePlacement.margin, y: TopologyNodePlacement.margin,
                                    width: baseLayout.size.width, height: baseLayout.size.height),
                command: viewportCommand,
                onZoomChanged: { zoom = $0 },
                nodeRegions: diagram.graph.nodes.compactMap { node in
                    guard let position = layout.positions[node.id] else { return nil }
                    let size = StorageTopologyRadialLayout.nodeSize(node, host: diagram.graph.hostModel)
                    return TopologyNodeHitRegion(id: node.id,
                        frame: CGRect(x: position.x - size.width / 2, y: position.y - size.height / 2,
                                      width: size.width, height: size.height))
                },
                onNodeDrag: { id, translation in
                    guard let base = baseLayout.positions[id],
                          let node = diagram.graph.nodes.first(where: { $0.id == id }) else { return }
                    nodePlacement.drag(id, translation: translation, basePosition: base,
                                       nodeSize: StorageTopologyRadialLayout.nodeSize(node, host: diagram.graph.hostModel),
                                       documentSize: layout.size)
                },
                onNodeDragEnded: { nodePlacement.endDrag() }
            ) {
                drawing(diagram, layout: layout, selectedNodes: selectedNodes, selectedEdges: selectedEdges)
                    .environment(\.appLanguage, language)
                    .environment(\.colorScheme, colorScheme)
                    .environment(\.locale, Locale(identifier: language.localeIdentifier))
            }
            .frame(height: diagram.graph.hostModel?.hasVerifiedPortLayout == true ? 460 : 560)
        }
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5)))
        .accessibilityIdentifier("storageTopologyGraph")
        .onChange(of: resetRevision) { resetViewport() }
        .onChange(of: zoomInRevision) { viewportCommand.request(.zoomIn) }
        .onChange(of: zoomOutRevision) { viewportCommand.request(.zoomOut) }
        .onChange(of: diagram.graph.nodes.map(\.id)) { resetViewport() }
    }

    private func resetViewport() {
        nodePlacement.reset()
        viewportCommand.request(.fit)
    }

    private func drawing(
        _ diagram: StorageTopologyDiagram,
        layout: StorageTopologyRadialLayout,
        selectedNodes: Set<String>,
        selectedEdges: Set<String>
    ) -> some View {
        ZStack(alignment: .topLeading) {
            // Small independent paths avoid allocating one GPU canvas as wide
            // as every hub in a long USB chain plus the dragging workspace.
            ForEach(diagram.graph.edges) { edge in
                if let origin = layout.positions[edge.fromID], let end = layout.positions[edge.toID] {
                    let start = connectionOrigin(origin, edge: edge, diagram: diagram)
                    let selected = selectedEdges.contains(edge.id)
                    let unresolved = edge.fromID == "computer"
                        && (diagram.graph.hostModel?.hasVerifiedPortLayout == true
                            ? diagram.hostPortsByEdgeID[edge.id] == nil
                            : diagram.graph.nodes.first { $0.id == edge.toID }?.kind == .disk)
                    TopologyConnectionLine(start: start, end: end, selected: selected, unresolved: unresolved)
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
                .contentShape(Rectangle())
                .help(segment.map { $0.presentationName ?? language.t($0.kind.titleKey) }.joined(separator: " → "))
                .position(layout.positions[node.id] ?? .zero)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    private func connectionOrigin(
        _ origin: CGPoint, edge: DriveConnectionTopologyEdge, diagram: StorageTopologyDiagram
    ) -> CGPoint {
        guard edge.fromID == "computer", let model = diagram.graph.hostModel, model.hasVerifiedPortLayout else {
            return origin
        }
        let anchor = diagram.hostPortsByEdgeID[edge.id]
            .flatMap { StorageHostArtworkGeometry.anchor($0, model: model) }
            ?? StorageHostArtworkGeometry.unresolvedAnchor
        return CGPoint(x: origin.x + anchor.x - StorageHostArtworkGeometry.size.width / 2,
                       y: origin.y + anchor.y - StorageHostArtworkGeometry.size.height / 2)
    }

    private func nodeContent(
        _ node: DriveConnectionTopologyNode,
        segment: [DriveConnectionTopologyNode],
        selected: Bool
    ) -> some View {
        let isHost = node.kind == .computer
        let rate = node.linkRateDescription ?? segment.reversed().compactMap(\.linkRateDescription).first
        let chips = Array(Set(segment.compactMap { node -> String? in
            guard let chipDescription = node.chipDescription else { return nil }
            let identifier = DeviceChipIdentifier(description: chipDescription)
            return identifier.flatMap { resolvedChipRecords[$0.displayValue]?.name } ?? chipDescription
        })).sorted()
        return VStack(spacing: 4) {
            Image(systemName: node.kind.symbolName)
                .font(.system(size: isHost ? 25 : 20))
                .foregroundStyle(selected || isHost ? Color.accentColor : .secondary)
            Text(isHost ? language.t("This Mac") : node.presentationName ?? language.t(node.kind.titleKey))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let bsdName = node.bsdName {
                Text(bsdName).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            if let rate {
                Text(rate).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            if !chips.isEmpty {
                Text(chips.joined(separator: " · ")).font(.system(size: 10))
                    .foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
            } else if node.kind == .disk && segment.count == 1 {
                Text(language.t("Chip model not reported")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
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
