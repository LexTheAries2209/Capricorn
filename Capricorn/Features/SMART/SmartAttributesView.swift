// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI

struct SmartAttributesView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    let viewModel: AppModel
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

    private var attributesTableHeight: CGFloat {
        let estimatedHeight = CGFloat(attributes.count) * 44 + 32
        return min(max(estimatedHeight, 260), 420)
    }

    private var saveMessageIsWarning: Bool {
        guard let saveMessage else { return false }
        return saveMessage.contains("failed") || saveMessage.contains("unavailable") || saveMessage.hasPrefix("Could not")
    }

    private var showsExternalSupportPanel: Bool {
        ExternalSmartDisclosurePolicy.showsPanel(for: drive)
    }

    private var externalSmartIsVerified: Bool {
        ExternalSmartDisclosurePolicy.isVerified(
            providerStatuses: snapshot?.providerStatuses ?? [],
            diagnostics: snapshot?.smartctlDiagnostics
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DrivePageHeaderView(drive: drive, snapshot: snapshot, showsHealthBadge: false, showsSerialNumber: true)

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
                        Label(language.t("Save SMART Snapshot CSV"), systemImage: "tray.and.arrow.down")
                    }
                    .disabled(snapshot == nil)
                }
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    if !attributes.isEmpty {
                        attributesTable
                            .frame(height: attributesTableHeight)

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
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    }

                    supplementaryPanels
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var supplementaryPanels: some View {
        SmartSelfTestPanel(drive: drive, snapshot: snapshot, viewModel: viewModel)

        if showsExternalSupportPanel {
            ExternalSupportView(
                status: externalSupport,
                diagnostics: snapshot?.smartctlDiagnostics,
                isVerified: externalSmartIsVerified,
                initiallyExpanded: ExternalSmartDisclosurePolicy.startsExpanded(
                    for: drive,
                    status: externalSupport,
                    isVerified: externalSmartIsVerified
                ),
                refresh: verifyExternalSupport
            )
                .id(drive.id)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        panel.message = language.t("Choose an optional folder for exported SMART snapshot CSV files.")
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

enum ExternalSmartDisclosurePolicy {
    static func showsPanel(for drive: DriveDevice) -> Bool {
        !drive.isNetwork && !drive.isMemoryCard
    }

    static func startsExpanded(
        for drive: DriveDevice,
        status: ExternalSupportStatus,
        isVerified: Bool
    ) -> Bool {
        guard showsPanel(for: drive) else { return false }
        if drive.isInternal || (status.smartctlInstalled && status.satDriverInstalled) {
            return false
        }
        return !isVerified
    }

    static func isVerified(
        providerStatuses: [ProviderStatus],
        diagnostics: SmartctlDiagnostics?
    ) -> Bool {
        let smartctlIsAvailable = providerStatuses.contains { status in
            status.name.caseInsensitiveCompare("smartctl") == .orderedSame
                && status.state == .available
        }
        let hasOpenError = diagnostics?.openError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return smartctlIsAvailable && !hasOpenError
    }
}

struct SmartSelfTestPanel: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    let viewModel: AppModel
    @Environment(\.appLanguage) private var language
    @AppStorage(AppPreferences.Key.allowSystemDiskSelfTests) private var allowSystemDiskSelfTests = false
    @State private var showsRecentSelfTestRecords = false
    @State private var showsRawOutput = false

    private var report: SmartSelfTestReport? { snapshot?.selfTestReport }
    private var capabilityState: SmartSelfTestCapabilityState { viewModel.smartSelfTestCapability(for: drive) }
    private var isActiveForDrive: Bool { viewModel.smartSelfTestDriveID == drive.id && viewModel.isSmartSelfTestActive }
    private var effectiveState: SmartSelfTestState? {
        if isActiveForDrive {
            switch viewModel.smartSelfTestSession {
            case .starting, .running, .stopping: return .running
            case .idle, .failed: break
            }
        }
        return report?.state
    }
    private var controlsUnavailable: Bool {
        drive.isNetwork || drive.isMemoryCard || (drive.isSystemDisk && !allowSystemDiskSelfTests)
    }

    var body: some View {
        InfoPanel(title: language.t("Self-Tests"), symbol: "stethoscope") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(stateTitle, systemImage: stateSymbol)
                            .font(.headline)
                            .foregroundStyle(stateTint)
                        Text(stateDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isActiveForDrive {
                        Button {
                            viewModel.abortSmartSelfTest()
                        } label: {
                            Label(language.t("Abort Self-Test"), systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.smartSelfTestSession == .stopping)
                    } else {
                        switch capabilityState {
                        case let .supported(capability):
                            HStack(spacing: 8) {
                                Button {
                                    viewModel.startSmartSelfTest(kind: .short, drive: drive)
                                } label: {
                                    Label(language.t("Quick Self-Test"), systemImage: "hare")
                                }
                                .disabled(controlsUnavailable || viewModel.isSmartSelfTestActive || !capability.shortSupported)
                                Button {
                                    viewModel.startSmartSelfTest(kind: .long, drive: drive)
                                } label: {
                                    Label(language.t("Full Self-Test"), systemImage: "tortoise")
                                }
                                .disabled(controlsUnavailable || viewModel.isSmartSelfTestActive || !capability.longSupported)
                            }
                        case .checking:
                            ProgressView()
                                .controlSize(.small)
                                .help(language.t("Checking Self-Test Support"))
                        case .unknown, .unavailable(_):
                            if drive.isSystemDisk && !allowSystemDiskSelfTests {
                                SettingsLink {
                                    Label(language.t("Settings"), systemImage: "gearshape")
                                }
                            } else {
                                Button {
                                    viewModel.checkSmartSelfTestCapability(for: drive)
                                } label: {
                                    Label(language.t("Check Self-Test Support"), systemImage: "checkmark.shield")
                                }
                                .disabled(controlsUnavailable || viewModel.isSmartSelfTestActive)
                            }
                        }
                    }
                }

                if let message = viewModel.smartSelfTestMessage, isActiveForDrive || viewModel.smartSelfTestSession != .idle {
                    HStack(alignment: .top, spacing: 8) {
                        Text(language.statusMessage(message))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            viewModel.clearSmartSelfTestMessage()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(language.t("Clear Self-Test Output"))
                        .accessibilityLabel(language.t("Clear Self-Test Output"))
                    }
                }

                if let entries = report?.entries, !entries.isEmpty, let latestEntry = report?.latestEntry {
                    VStack(alignment: .leading, spacing: 6) {
                        DisclosureGroup(isExpanded: $showsRecentSelfTestRecords) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(entries) { entry in
                                    selfTestEntryRow(entry)
                                }
                            }
                        } label: {
                            Label(language.t("Recent Self-Test Records"), systemImage: "clock.arrow.circlepath")
                                .font(.subheadline.bold())
                        }

                        if !showsRecentSelfTestRecords {
                            selfTestEntryRow(latestEntry)
                        }
                    }
                }

                if let rawOutput = report?.rawOutput, !rawOutput.isEmpty {
                    DisclosureGroup(isExpanded: $showsRawOutput) {
                        ScrollView([.horizontal, .vertical]) {
                            Text(rawOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 220)
                        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    } label: {
                        Label(language.t("Raw Self-Test Output"), systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.bold())
                    }
                }
            }
        }
    }

    private var stateTitle: String {
        if let state = effectiveState {
            switch state {
            case .noLog: return language.t("No Self-Test Record")
            case .running: return language.t("Self-Test In Progress")
            case .passed: return language.t("Self-Test Passed")
            case .failed: return language.t("Self-Test Failed")
            case .aborted: return language.t("Self-Test Aborted")
            case .unknown: return language.t("Self-Test Status Unknown")
            }
        }
        return language.t("No Self-Test Record")
    }

    private var stateDescription: String {
        if drive.isSystemDisk && !allowSystemDiskSelfTests {
            return language.t("Enable system-disk self-tests in Settings only after confirming that a current backup is available.")
        }
        if controlsUnavailable {
            return language.t("Self-tests require smartctl support for this drive.")
        }
        switch capabilityState {
        case .unknown:
            return language.t("Self-test support must be checked before a test can start.")
        case .checking:
            return language.t("Checking Self-Test Support")
        case let .unavailable(message):
            return language.statusMessage(message)
        case let .supported(capability):
            if !capability.shortSupported {
                return language.t("Quick self-test is not supported by this drive.")
            }
            if !capability.longSupported {
                return language.t("Full self-test is not supported by this drive.")
            }
        }
        let remaining = report?.currentRemainingPercent ?? sessionRemainingPercent
        if let remaining, effectiveState == .running {
            return "\(language.t("Remaining")): \(remaining)%"
        }
        return language.t("Self-test capability confirmed.")
    }

    private var stateSymbol: String {
        switch effectiveState {
        case .passed: "checkmark.circle.fill"
        case .failed, .aborted: "exclamationmark.triangle.fill"
        case .running: "hourglass"
        default: "questionmark.circle"
        }
    }

    private var stateTint: Color {
        switch effectiveState {
        case .passed: .green
        case .failed, .aborted: .orange
        default: .secondary
        }
    }

    private func kindTitle(_ kind: SmartSelfTestKind) -> String {
        switch kind {
        case .short: language.t("Quick")
        case .long: language.t("Full")
        case .vendor: language.t("Vendor")
        case .unknown: language.t("Unknown")
        }
    }

    private var sessionRemainingPercent: Int? {
        guard case let .running(_, remainingPercent) = viewModel.smartSelfTestSession else { return nil }
        return remainingPercent
    }

    private func selfTestEntryRow(_ entry: SmartSelfTestEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.state == .passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(entry.state == .passed ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(kindTitle(entry.kind)) · \(language.statusMessage(entry.status))")
                    .font(.subheadline)
                Text(entryDetails(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func entryDetails(_ entry: SmartSelfTestEntry) -> String {
        var parts: [String] = []
        if let hours = entry.lifetimeHours { parts.append("\(language.t("Power-On Hours")): \(hours)") }
        if let lba = entry.failingLBA { parts.append("LBA: \(lba)") }
        if let remaining = entry.remainingPercent { parts.append("\(language.t("Remaining")): \(remaining)%") }
        return parts.isEmpty ? language.t("No additional details") : parts.joined(separator: " · ")
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
