// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct DiskConnectionTopologyView: View {
    let drives: [DriveDevice]
    let selectedDrive: DriveDevice
    let graph: DriveConnectionTopologyGraph?
    let selectDrive: (String) -> Void

    @Environment(\.appLanguage) private var language

    private var resolvedChipRecords: [String: DeviceHuntChipCatalog.Record] {
        guard let graph else { return [:] }
        let externalDriveIDs = Set(drives.filter {
            !$0.isSystemDisk && !$0.isVirtual && !$0.isNetwork
        }.map(\.bsdName))
        let descriptions = externalDriveIDs.flatMap { graph.path(for: $0) }
            .compactMap(\.chipDescription)
        return DeviceHuntChipCatalog.bundled.resolve(chipDescriptions: descriptions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader

                if let graph, !graph.nodes.isEmpty {
                    StorageTopologyGraphView(
                        graph: graph,
                        selectedDriveID: selectedDrive.bsdName,
                        resolvedChipRecords: resolvedChipRecords,
                        systemDriveIDs: Set(drives.filter(\.isSystemDisk).map(\.bsdName)),
                        selectDrive: selectDrive
                    )
                    StorageTopologyDetailsView(
                        drive: selectedDrive,
                        graph: graph,
                        resolvedChipRecords: resolvedChipRecords
                    )
                    Label(language.t("Chip names use the bundled DeviceHunt catalog. Unknown IDs remain visible."),
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Text(language.t("Storage connections on this Mac"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Label("\(drives.filter { !$0.isVirtual && !$0.isNetwork && !$0.isSystemDisk }.count)", systemImage: "externaldrive")
                .font(.caption.monospacedDigit())
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
