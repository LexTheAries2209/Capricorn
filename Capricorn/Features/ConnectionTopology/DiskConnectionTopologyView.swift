// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct DiskConnectionTopologyView: View {
    let drives: [DriveDevice]
    let selectedDrive: DriveDevice
    let graph: DriveConnectionTopologyGraph?
    let selectDrive: (String) -> Void

    @Environment(\.appLanguage) private var language

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader

                if let graph, !graph.nodes.isEmpty {
                    StorageTopologyGraphView(
                        graph: graph,
                        selectedDriveID: selectedDrive.bsdName,
                        selectDrive: selectDrive
                    )
                    connectionDetails(graph)
                } else if graph == nil {
                    ProgressView(language.t("Reading hardware path"))
                        .frame(maxWidth: .infinity, minHeight: 420)
                } else {
                    ContentUnavailableView(
                        language.t("Connection Topology"),
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text(language.t("No physical storage paths are currently available."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 420)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(language.t("Connection Topology"))
                    .font(.title2.bold())
                Text(language.t("All storage devices on this Mac"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Label("\(drives.filter { !$0.isVirtual && !$0.isNetwork }.count)", systemImage: "externaldrive")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func connectionDetails(_ graph: DriveConnectionTopologyGraph) -> some View {
        let drive = selectedDrive
        let selectedPath = graph.path(for: drive.bsdName)
        return InfoPanel(title: language.t("Selected drive details"), symbol: "externaldrive") {
            LabeledContent(language.t("Device"), value: "\(drive.displayName) · \(drive.bsdName)")
            LabeledContent(language.t("Capacity"), value: formatByteCount(drive.sizeBytes))
            LabeledContent(language.t("Host Transport")) {
                Text(drive.connectionInfo?.detailLabel(effectiveLabel: language.t("Effective")) ?? drive.protocolName)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            let pcieLinks = selectedPath.compactMap(\.pcieLink)
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

            ForEach(selectedPath.filter { $0.kind != .computer && $0.kind != .disk }) { node in
                LabeledContent(language.t(node.kind.titleKey)) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(node.hardwareName ?? language.t("Chip model not reported"))
                        if let chip = node.chipDescription {
                            Text(chip).monospaced()
                        }
                        if let port = node.portDescription {
                            Text(port)
                        }
                        if let rate = node.linkRateDescription {
                            Text(rate)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            }
            if selectedPath.isEmpty {
                Text(language.t("Physical storage topology is unavailable for this source."))
                    .foregroundStyle(.secondary)
            }
            Text(language.t("Connection link rate is not the disk's measured transfer speed."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(language.t("Port identifiers are reported by macOS; physical position and chip model may not be available."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension DriveConnectionTopologyNode.Kind {
    var titleKey: String {
        switch self {
        case .computer: "This Mac"
        case .thunderboltController: "Thunderbolt Controller"
        case .thunderboltSwitch: "Thunderbolt Switch"
        case .thunderboltPort: "Thunderbolt Port"
        case .thunderboltAdapter: "Thunderbolt Adapter"
        case .thunderboltTransport: "Thunderbolt Transport"
        case .pcieTunnel: "PCIe Tunnel"
        case .usbPort: "USB Port"
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
        case .thunderboltController, .thunderboltSwitch, .thunderboltAdapter: "cpu"
        case .thunderboltPort: "bolt.horizontal"
        case .thunderboltTransport: "bolt.horizontal"
        case .pcieTunnel: "point.3.connected.trianglepath.dotted"
        case .usbPort: "cable.connector.horizontal"
        case .usbHostController, .usbDevice, .storageBridge: "cable.connector.horizontal"
        case .usbHub, .pcieBridge: "point.3.connected.trianglepath.dotted"
        case .pcieDevice, .nvmeController, .sataController, .storageController: "memorychip"
        case .disk: "externaldrive"
        }
    }
}
