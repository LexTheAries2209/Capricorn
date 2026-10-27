// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct DiskConnectionTopologyView: View {
    let drive: DriveDevice

    @Environment(\.appLanguage) private var language
    @State private var topology: DriveConnectionTopology?
    @State private var isLoading = false
    private let reader = IOKitDriveConnectionTopologyReader()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader

                if drive.isNetwork || drive.isVirtual {
                    ContentUnavailableView(
                        language.t("Connection Topology"),
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text(language.t("Physical storage topology is unavailable for this source."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else if isLoading && topology == nil {
                    ProgressView(language.t("Reading hardware path"))
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let topology, topology.hasResolvedController {
                    hardwarePathPanel(topology)
                    connectionDetails(topology)
                } else {
                    ContentUnavailableView(
                        language.t("Hardware path unavailable"),
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text(language.t("Could not inspect the hardware path."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
        }
        .task(id: drive.bsdName) {
            await loadTopology()
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(language.t("Connection Topology"))
                    .font(.title2.bold())
                Text("\(drive.displayName) · \(drive.bsdName) · \(drive.protocolName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Button {
                Task { await loadTopology() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help(language.t("Refresh Topology"))
            .accessibilityLabel(language.t("Refresh Topology"))
            .disabled(isLoading || drive.isNetwork || drive.isVirtual)
        }
    }

    private func hardwarePathPanel(_ topology: DriveConnectionTopology) -> some View {
        InfoPanel(title: language.t("Hardware Path"), symbol: "point.3.connected.trianglepath.dotted") {
            VStack(spacing: 0) {
                ForEach(Array(topology.nodes.enumerated()), id: \.offset) { index, node in
                    topologyNode(node)
                    if index < topology.nodes.count - 1 {
                        Rectangle()
                            .fill(.separator)
                            .frame(width: 1, height: 18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 17)
                    }
                }
            }
        }
    }

    private func topologyNode(_ node: DriveConnectionTopologyNode) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: node.kind.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(node.kind == .disk ? Color.accentColor : Color.secondary)
                .frame(width: 34, height: 34)
                .background(.quaternary, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(language.t(node.kind.titleKey))
                    .font(.body.weight(node.kind == .disk ? .semibold : .medium))
                if let hardwareName = node.hardwareName {
                    Text(hardwareName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 10)
            if let link = node.pcieLink {
                Text("PCIe Gen \(link.generation) · \(link.detailLabel)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
    }

    private func connectionDetails(_ topology: DriveConnectionTopology) -> some View {
        InfoPanel(title: language.t("Link Characteristics"), symbol: "speedometer") {
            LabeledContent(language.t("Host Transport")) {
                Text(drive.connectionInfo?.detailLabel(effectiveLabel: language.t("Effective")) ?? drive.protocolName)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            let pcieLinks = topology.nodes.compactMap(\.pcieLink)
            if pcieLinks.isEmpty {
                LabeledContent(language.t("Negotiated PCIe Link"), value: language.t("Not reported by the controller."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(pcieLinks.enumerated()), id: \.offset) { index, link in
                    LabeledContent(
                        "\(language.t("Negotiated PCIe Link")) \(index + 1)",
                        value: "PCIe Gen \(link.generation) · \(link.detailLabel)"
                    )
                }
            }

            Text(language.t("Connection link rate is not the disk's measured transfer speed."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func loadTopology() async {
        guard !drive.isNetwork, !drive.isVirtual else {
            topology = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        let drive = drive
        let reader = reader
        let result = await Task.detached(priority: .utility) {
            reader.read(for: drive)
        }.value
        guard !Task.isCancelled else { return }
        topology = result
    }
}

private extension DriveConnectionTopologyNode.Kind {
    var titleKey: String {
        switch self {
        case .computer: "This Mac"
        case .thunderboltTransport: "Thunderbolt Transport"
        case .pcieTunnel: "PCIe Tunnel"
        case .usbHostController: "USB Host Controller"
        case .usbHub: "USB Hub"
        case .usbDevice: "USB Device"
        case .pcieBridge: "PCIe Bridge"
        case .pcieDevice: "PCIe Device"
        case .nvmeController: "NVMe Controller"
        case .sataController: "SATA Controller"
        case .storageController: "Storage Controller"
        case .storageBridge: "Storage Bridge"
        case .disk: "Physical Disk"
        }
    }

    var symbolName: String {
        switch self {
        case .computer: "laptopcomputer"
        case .thunderboltTransport: "bolt.horizontal"
        case .pcieTunnel: "point.3.connected.trianglepath.dotted"
        case .usbHostController, .usbDevice, .storageBridge: "cable.connector.horizontal"
        case .usbHub, .pcieBridge: "point.3.connected.trianglepath.dotted"
        case .pcieDevice, .nvmeController, .sataController, .storageController: "memorychip"
        case .disk: "externaldrive"
        }
    }
}
