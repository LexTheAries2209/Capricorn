// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI

struct SmartAttributesView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    let externalSupport: ExternalSupportStatus
    let verifyExternalSupport: () -> Void
    let saveSnapshot: (String?) -> String
    @Environment(\.appLanguage) private var language
    @AppStorage("smartSnapshotExportFolder") private var snapshotExportFolderPath = ""
    @State private var saveMessage: String?

    private var attributes: [SmartAttribute] {
        snapshot?.attributes ?? []
    }

    private var showsNormalizedColumns: Bool {
        SmartAttributeTableColumns.showsNormalizedColumns(for: attributes)
    }

    private var saveMessageIsWarning: Bool {
        guard let saveMessage else { return false }
        return saveMessage.contains("failed") || saveMessage.contains("unavailable") || saveMessage.hasPrefix("Could not")
    }

    private var showsExternalSupportHelp: Bool {
        guard !drive.isNetwork, !drive.isMemoryCard else { return false }
        guard let snapshot else { return false }
        let hasAvailableProvider = snapshot.providerStatuses.contains { $0.state == .available }
        let hasLimitedProvider = snapshot.providerStatuses.contains { $0.state == .limited }
        let externalDrive = !drive.isInternal || drive.isRemovable
        let lacksUsableSmart = attributes.isEmpty || snapshot.health == .unavailable || !hasAvailableProvider
        return lacksUsableSmart || (externalDrive && hasLimitedProvider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DrivePageHeaderView(drive: drive, snapshot: snapshot, showsHealthBadge: false)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(language.t("SMART Attributes"))
                        .font(.title2.bold())
                    snapshotStorageSummary
                    if let saveMessage {
                        Label(language.statusMessage(saveMessage), systemImage: saveMessageIsWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(saveMessageIsWarning ? Color.orange : Color.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    HealthBadge(status: snapshot?.health ?? .unavailable, compact: true)
                    Button {
                        chooseSnapshotExportFolder()
                    } label: {
                        Label(language.t(snapshotExportFolderPath.isEmpty ? "Choose Storage Folder" : "Change Storage Folder"), systemImage: "folder.badge.gearshape")
                    }
                    if !snapshotExportFolderPath.isEmpty {
                        Button {
                            snapshotExportFolderPath = ""
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .help(language.t("Clear Storage Folder"))
                    }
                    Button {
                        saveMessage = saveSnapshot(snapshotExportFolderPath.isEmpty ? nil : snapshotExportFolderPath)
                    } label: {
                        Label(language.t("Save SMART Snapshot"), systemImage: "tray.and.arrow.down")
                    }
                    .disabled(snapshot == nil)
                }
            }

            if !attributes.isEmpty {
                attributesTable

                if showsNormalizedColumns {
                    Label(language.t(normalizedValueHelp), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    language.t("No SMART Attributes"),
                    systemImage: "questionmark.folder",
                    description: Text(language.statusMessage(snapshot?.summary) ?? language.t("SMART data is unavailable for this drive."))
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }

            if showsExternalSupportHelp {
                ExternalSupportView(status: externalSupport, refresh: verifyExternalSupport)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var snapshotStorageSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(language.t("Default storage: App history database"), systemImage: "clock.arrow.circlepath")
            Label(snapshotExportFolderPath.isEmpty ? language.t("Selected storage: Not selected") : "\(language.t("Selected storage:")) \(snapshotExportFolderPath)", systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func chooseSnapshotExportFolder() {
        let panel = NSOpenPanel()
        panel.title = language.t("Choose Storage Folder")
        panel.message = language.t("Choose an optional folder for exported SMART snapshot JSON files.")
        panel.prompt = language.t("Use Folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if !snapshotExportFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: snapshotExportFolderPath, isDirectory: true)
        } else if let fallback = drive.benchmarkMountPoint {
            panel.directoryURL = URL(fileURLWithPath: fallback, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        snapshotExportFolderPath = url.path
    }

    @ViewBuilder
    private var attributesTable: some View {
        if showsNormalizedColumns {
            Table(attributes) {
                TableColumn(language.t("ID")) { Text($0.id).monospaced() }
                    .width(min: 64, ideal: 80)
                TableColumn(language.t("Name")) { attribute in
                    SmartAttributeNameCell(attribute: attribute)
                }
                .width(min: 220, ideal: 320)
                TableColumn(language.t("Raw")) { Text($0.rawValue).monospacedDigit() }
                    .width(min: 140, ideal: 180)
                TableColumn(language.t("Current")) { Text($0.current.map(String.init) ?? "-").help(language.t(normalizedValueHelp)) }
                    .width(62)
                TableColumn(language.t("Worst")) { Text($0.worst.map(String.init) ?? "-").help(language.t(normalizedValueHelp)) }
                    .width(62)
                TableColumn(language.t("Threshold")) { Text($0.threshold.map(String.init) ?? "-").help(language.t(normalizedValueHelp)) }
                    .width(72)
                TableColumn(language.t("Status")) { HealthBadge(status: $0.status, compact: true).fixedSize() }
                    .width(82)
                TableColumn(language.t("Source")) { Text($0.source) }
                    .width(92)
            }
        } else {
            Table(attributes) {
                TableColumn(language.t("ID")) { Text($0.id).monospaced() }
                    .width(min: 64, ideal: 80)
                TableColumn(language.t("Name")) { attribute in
                    SmartAttributeNameCell(attribute: attribute)
                }
                .width(min: 220, ideal: 320)
                TableColumn(language.t("Raw")) { Text($0.rawValue).monospacedDigit() }
                    .width(min: 140, ideal: 180)
                TableColumn(language.t("Status")) { HealthBadge(status: $0.status, compact: true).fixedSize() }
                    .width(82)
                TableColumn(language.t("Source")) { Text($0.source) }
                    .width(92)
            }
        }
    }

    private var normalizedValueHelp: String {
        "Current, worst, and threshold are ATA normalized health values. NVMe and native macOS SMART usually do not provide them."
    }
}
private struct SmartAttributeNameCell: View {
    let attribute: SmartAttribute
    @Environment(\.appLanguage) private var language

    private var display: SmartAttributeDisplay {
        language.smartAttributeDisplay(attribute)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(display.title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(language == .simplifiedChinese ? "\(attribute.name) · \(display.subtitle)" : display.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(display.help)
    }
}
