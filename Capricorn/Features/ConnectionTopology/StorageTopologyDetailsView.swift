// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct StorageTopologyDetailsView: View {
    let drive: DriveDevice
    let graph: DriveConnectionTopologyGraph
    var resolvedChipRecords: [String: DeviceHuntChipCatalog.Record] = [:]
    @Environment(\.appLanguage) private var language

    var body: some View {
        let path = graph.path(for: drive.bsdName)
        let hardware = StorageTopologyDiagram.uniquePCIeBridgeChips(in: path)
            .filter { $0.kind != .computer && $0.kind != .disk }
        let pcieLinks = path.compactMap(\.pcieLink)
        InfoPanel(title: language.t("Selected drive details"),
                  symbol: drive.isSystemDisk ? "laptopcomputer" : "externaldrive") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), alignment: .topLeading)],
                      alignment: .leading, spacing: 16) {
                summaryField("Device", value: "\(drive.displayName) · \(drive.bsdName)")
                summaryField("Capacity", value: formatByteCount(drive.sizeBytes))
                summaryField("Protocol", value: drive.protocolName)
                summaryField("Host Transport", value: drive.connectionInfo?.detailLabel(effectiveLabel: language.t("Effective"))
                             ?? drive.protocolName)
                summaryField("Mac Port", value: hostPortDescription(path))
                summaryField("Negotiated PCIe Link", value: pcieLinks.isEmpty
                             ? language.t("Not reported")
                             : pcieLinks.map { "PCIe Gen \($0.generation) · \($0.detailLabel)" }.joined(separator: "\n"))
            }
            .padding(.vertical, 4)

            if !hardware.isEmpty {
                Divider()
                ViewThatFits(in: .horizontal) {
                    hardwareTable(hardware).frame(minWidth: 700)
                    compactHardware(hardware)
                }
            } else if path.isEmpty {
                Text(language.t("Physical storage topology is unavailable for this source."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
        .accessibilityIdentifier("topologyDriveDetails")
    }

    private func summaryField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(language.t(title)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hostPortDescription(_ path: [DriveConnectionTopologyNode]) -> String {
        if drive.isSystemDisk { return language.t("Built into this Mac") }
        guard let port = path.compactMap(\.hostPort).first else { return language.t("Not reported") }
        let socket = "USB-C \(port.number)"
        guard let position = graph.hostModel?.position(for: port) else { return socket }
        return "\(language.t(position.titleKey)) · \(socket)"
    }

    private func hardwareTable(_ hardware: [DriveConnectionTopologyNode]) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                tableText(language.t("Component"), minimum: 115).bold()
                tableText(language.t("Hardware"), minimum: 180).bold()
                tableText(language.t("Chip / ID"), minimum: 130).bold()
                tableText(language.t("Port / Link"), minimum: 170).bold()
            }
            .foregroundStyle(.secondary)
            ForEach(hardware) { node in
                Divider().gridCellColumns(4)
                GridRow {
                    tableText(language.t(node.kind.titleKey), minimum: 115)
                    tableText(node.presentationName ?? language.t("Not reported"), minimum: 180)
                    chipCell(node)
                    tableText([node.displayPortDescription, node.linkRateDescription].compactMap { $0 }.joined(separator: "\n"),
                              minimum: 170)
                }
            }
        }
        .font(.caption)
    }

    private func tableText(_ text: String, minimum: CGFloat) -> some View {
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: minimum, maxWidth: .infinity, alignment: .leading)
    }

    private func compactHardware(_ hardware: [DriveConnectionTopologyNode]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(hardware) { node in
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.t(node.kind.titleKey)).font(.caption.bold())
                    Text([node.presentationName, node.displayPortDescription, node.linkRateDescription]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if node.chipDescription != nil {
                        chipCell(node)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chipCell(_ node: DriveConnectionTopologyNode) -> some View {
        if let description = node.chipDescription,
           let identifier = DeviceChipIdentifier(description: description) {
            if let record = resolvedChipRecords[identifier.displayValue] {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(record.manufacturer) · \(language.t(record.category))")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(description)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
            } else {
                Text(description)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
            }
        } else {
            tableText(node.chipDescription ?? language.t("Not reported"), minimum: 130)
        }
    }
}
