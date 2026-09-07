// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI

struct SmartAttributesView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    let viewModel: AppModel
    let selfTestHistory: [SmartSelfTestHistoryRecord]
    let saveSnapshot: (String?) -> String
    let exportSelfTestHistory: ([SmartSelfTestHistoryRecord], String?, SmartDiagnosticsExportFormat) -> String
    let exportErrorLog: (SmartErrorLogReport, String?, SmartDiagnosticsExportFormat) -> String
    @Environment(\.appLanguage) private var language
    @AppStorage(AppPreferences.Key.showsSmartSelfTestInterface) private var showsSmartSelfTestInterface = false
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
        return saveMessage.localizedCaseInsensitiveContains("failed")
            || saveMessage.localizedCaseInsensitiveContains("unavailable")
            || saveMessage.hasPrefix("Could not")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DrivePageHeaderView(
                drive: drive,
                snapshot: snapshot,
                showsHealthBadge: false,
                showsSerialNumber: true
            )

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(language.t("SMART Attributes"))
                        .font(.title2.bold())
                    snapshotStorageSummary
                    if let nativeStatus = snapshot?.providerStatuses.first(where: {
                        $0.name.caseInsensitiveCompare("Native macOS") == .orderedSame
                            && $0.state == .limited
                    }) {
                        Label(language.statusMessage(nativeStatus.message), systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                    .keyboardShortcut(
                        AppCommandShortcut.saveSmartSnapshotKeyEquivalent,
                        modifiers: AppCommandShortcut.saveSmartSnapshot.modifiers
                    )
                    .disabled(snapshot == nil)
                    .help(language.t("Save SMART Snapshot CSV (Command-S)"))
                }
            }

            primarySmartContent
                .layoutPriority(1)

            if showsSmartSelfTestInterface {
                SmartDiagnosticsPanel(
                    drive: drive,
                    snapshot: snapshot,
                    viewModel: viewModel,
                    selfTestHistory: selfTestHistory,
                    exportFolderPath: snapshotExportFolderPath.isEmpty ? nil : snapshotExportFolderPath,
                    chooseExportFolder: chooseSnapshotExportFolder,
                    exportSelfTestHistory: exportSelfTestHistory,
                    exportErrorLog: exportErrorLog,
                    saveMessage: $saveMessage
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var primarySmartContent: some View {
        if !attributes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                attributesTable
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsNormalizedColumns {
                    Label(language.t(normalizedValueHelp), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView(
                language.t("No SMART Attributes"),
                systemImage: "questionmark.folder",
                description: Text(language.statusMessage(snapshot?.summary) ?? language.t("SMART data is unavailable for this drive."))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
        panel.message = language.t("Choose an optional folder for exported SMART reports.")
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

struct SmartDiagnosticsPanel: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    let viewModel: AppModel
    let selfTestHistory: [SmartSelfTestHistoryRecord]
    let exportFolderPath: String?
    let chooseExportFolder: () -> Void
    let exportSelfTestHistory: ([SmartSelfTestHistoryRecord], String?, SmartDiagnosticsExportFormat) -> String
    let exportErrorLog: (SmartErrorLogReport, String?, SmartDiagnosticsExportFormat) -> String
    @Binding var saveMessage: String?
    @Environment(\.appLanguage) private var language
    @AppStorage(AppPreferences.Key.allowSystemDiskSelfTests) private var allowSystemDiskSelfTests = false
    @State private var isExpanded = true
    @State private var showsSelfTestHistory = false
    @State private var showsErrorLog = false

    private var report: SmartSelfTestReport? { snapshot?.selfTestReport }
    private var capabilityState: SmartSelfTestCapabilityState { viewModel.smartSelfTestCapability(for: drive) }
    private var errorLogCapabilityState: SmartErrorLogCapabilityState { viewModel.smartErrorLogCapability(for: drive) }
    private var errorLogReport: SmartErrorLogReport? { viewModel.smartErrorLogReports[drive.id] }
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
        InfoPanel(title: language.t("SMART Diagnostics"), symbol: "stethoscope") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(language.t("Self-tests, saved reports, and controller error entries."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down.circle" : "chevron.right.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(language.t(isExpanded ? "Collapse SMART Diagnostics" : "Show SMART Diagnostics"))
                }

                if isExpanded {
                    selfTestSection
                    Divider()
                    errorLogSection
                }
            }
        }
        .sheet(isPresented: $showsSelfTestHistory) {
            SmartSelfTestHistorySheet(records: selfTestHistory, language: language)
        }
        .sheet(isPresented: $showsErrorLog) {
            if let errorLogReport {
                SmartErrorLogSheet(report: errorLogReport, language: language)
            }
        }
    }

    private var selfTestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                selfTestControls
            }

            if let message = viewModel.smartSelfTestMessage, isActiveForDrive || viewModel.smartSelfTestSession != .idle {
                HStack(alignment: .top, spacing: 8) {
                    Text(language.statusMessage(message))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button {
                        viewModel.clearSmartSelfTestMessage()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(language.t("Clear Self-Test Status"))
                }
            }

            if let latestEntry = report?.latestEntry {
                selfTestEntryRow(latestEntry)
            }

            HStack(spacing: 8) {
                Button {
                    showsSelfTestHistory = true
                } label: {
                    Label(language.t("View Self-Test History"), systemImage: "clock.arrow.circlepath")
                }
                .disabled(selfTestHistory.isEmpty)

                Menu {
                    Button(language.t("Export CSV")) {
                        saveMessage = exportSelfTestHistory(selfTestHistory, exportFolderPath, .csv)
                    }
                    Button(language.t("Export JSON")) {
                        saveMessage = exportSelfTestHistory(selfTestHistory, exportFolderPath, .json)
                    }
                } label: {
                    Label(language.t("Export Self-Test History"), systemImage: "square.and.arrow.up")
                }
                .disabled(selfTestHistory.isEmpty)

                if exportFolderPath == nil {
                    Button {
                        chooseExportFolder()
                    } label: {
                        Label(language.t("Choose Storage Folder"), systemImage: "folder")
                    }
                }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var selfTestControls: some View {
        if isActiveForDrive {
            Button {
                viewModel.abortSmartSelfTest()
            } label: {
                Label(language.t("Abort Self-Test"), systemImage: "stop.circle")
            }
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
                    .disabled(controlsUnavailable || !capability.shortSupported)
                    Button {
                        viewModel.startSmartSelfTest(kind: .long, drive: drive)
                    } label: {
                        Label(language.t("Full Self-Test"), systemImage: "tortoise")
                    }
                    .disabled(controlsUnavailable || !capability.longSupported)
                }
            case .checking:
                ProgressView()
                    .controlSize(.small)
                    .help(language.t("Checking Self-Test Support"))
            case let .retrying(message, attempt):
                Label("\(language.t("Retrying")) \(attempt)/3: \(language.statusMessage(message))", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .unknown, .unavailable:
                if drive.isSystemDisk && !allowSystemDiskSelfTests {
                    SettingsLink {
                        Label(language.t("Settings"), systemImage: "gearshape")
                    }
                } else {
                    Button {
                        viewModel.checkSmartSelfTestCapability(for: drive)
                    } label: {
                        Label(language.t("Retry Self-Test Check"), systemImage: "checkmark.shield")
                    }
                    .disabled(controlsUnavailable)
                }
            }
        }
    }

    private var errorLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(errorLogTitle, systemImage: errorLogSymbol)
                        .font(.headline)
                        .foregroundStyle(errorLogTint)
                    Text(errorLogDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                errorLogControls
            }

            if let errorLogReport {
                HStack(spacing: 8) {
                    Text(errorLogSummary(errorLogReport))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showsErrorLog = true
                    } label: {
                        Label(language.t("View Error Entries"), systemImage: "list.bullet.rectangle")
                    }
                    Menu {
                        Button(language.t("Export CSV")) {
                            saveMessage = exportErrorLog(errorLogReport, exportFolderPath, .csv)
                        }
                        Button(language.t("Export JSON")) {
                            saveMessage = exportErrorLog(errorLogReport, exportFolderPath, .json)
                        }
                    } label: {
                        Label(language.t("Export Error Entries"), systemImage: "square.and.arrow.up")
                    }
                    if exportFolderPath == nil {
                        Button {
                            chooseExportFolder()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help(language.t("Choose Storage Folder"))
                    }
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var errorLogControls: some View {
        switch errorLogCapabilityState {
        case .supported:
            Button {
                viewModel.readSmartErrorLog(for: drive)
            } label: {
                Label(language.t("Read Error Entries"), systemImage: "arrow.clockwise")
            }
        case .checking:
            ProgressView()
                .controlSize(.small)
                .help(language.t("Checking Error Log Support"))
        case let .retrying(message, attempt):
            Label("\(language.t("Retrying")) \(attempt)/3: \(language.statusMessage(message))", systemImage: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unknown, .unavailable:
            Button {
                viewModel.checkSmartErrorLogCapability(for: drive)
            } label: {
                Label(language.t("Retry Error Log Check"), systemImage: "checkmark.shield")
            }
            .disabled(drive.isNetwork || drive.isMemoryCard)
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
            return language.t("Checking self-test support automatically.")
        case .checking:
            return language.t("Checking Self-Test Support")
        case let .retrying(message, attempt):
            return "\(language.t("Retrying")) \(attempt)/3: \(language.statusMessage(message))"
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

    private var errorLogTitle: String {
        switch errorLogCapabilityState {
        case .supported:
            return language.t("SMART Error Entries")
        case .checking, .retrying:
            return language.t("Checking Error Log Support")
        case .unknown:
            return language.t("Error Log Support Pending")
        case .unavailable:
            return language.t("Error Log Unavailable")
        }
    }

    private var errorLogDescription: String {
        switch errorLogCapabilityState {
        case .supported:
            return errorLogReport?.message ?? language.t("Read ATA or NVMe controller error entries on demand.")
        case .checking:
            return language.t("Checking error-log support automatically.")
        case let .retrying(message, attempt):
            return "\(language.t("Retrying")) \(attempt)/3: \(language.statusMessage(message))"
        case .unknown:
            return language.t("Error-log support will be retried when this drive is available.")
        case let .unavailable(message):
            return language.statusMessage(message)
        }
    }

    private var errorLogSymbol: String {
        if let errorLogReport, !errorLogReport.entries.isEmpty {
            return "exclamationmark.triangle.fill"
        }
        switch errorLogCapabilityState {
        case .supported: return "checkmark.circle.fill"
        case .checking, .retrying: return "arrow.clockwise"
        case .unknown, .unavailable: return "questionmark.circle"
        }
    }

    private var errorLogTint: Color {
        if let errorLogReport, !errorLogReport.entries.isEmpty {
            return .orange
        }
        switch errorLogCapabilityState {
        case .supported: return .green
        default: return .secondary
        }
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

    private func errorLogSummary(_ report: SmartErrorLogReport) -> String {
        if report.entries.isEmpty {
            return language.t("No controller error entries were reported.")
        }
        let count = report.totalEntryCount ?? report.entries.count
        return "\(count) \(language.t("Error Entries"))"
    }
}

private struct SmartSelfTestHistorySheet: View {
    let records: [SmartSelfTestHistoryRecord]
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?

    private var selectedRecord: SmartSelfTestHistoryRecord? {
        records.first(where: { $0.id == selectedID }) ?? records.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(language.t("Self-Test History"), systemImage: "clock.arrow.circlepath")
                    .font(.title3.bold())
                Spacer()
                Button(language.t("Close")) { dismiss() }
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(records.sorted { $0.capturedAt > $1.capturedAt }) { record in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.capturedAt.formatted(date: .abbreviated, time: .standard))
                            Text("\(record.testKind.rawValue.capitalized) · \(record.statusDetails)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(record.id)
                    }
                }
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)

                Divider()

                ScrollView {
                    if let selectedRecord {
                        SmartSelfTestHistoryDetail(record: selectedRecord, language: language)
                            .padding()
                    } else {
                        ContentUnavailableView(
                            language.t("No Self-Test Record"),
                            systemImage: "clock.badge.questionmark"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}

private struct SmartSelfTestHistoryDetail: View {
    let record: SmartSelfTestHistoryRecord
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.driveName)
                .font(.title3.bold())
            LabeledContent(language.t("Completed"), value: record.capturedAt.formatted(date: .abbreviated, time: .standard))
            LabeledContent(language.t("Test Type"), value: record.testKind.rawValue.capitalized)
            LabeledContent(language.t("Status"), value: language.statusMessage(record.statusDetails))
            if let hours = record.powerOnHours {
                LabeledContent(language.t("Power-On Hours"), value: String(hours))
            }
            if let failingLBA = record.failingLBA {
                LabeledContent("LBA", value: failingLBA)
            }
            if let report = record.report, !report.entries.isEmpty {
                Divider()
                Text(language.t("Recorded Entries"))
                    .font(.headline)
                ForEach(report.entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.kind.rawValue.capitalized) · \(language.statusMessage(entry.status))")
                        Text(entry.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SmartErrorLogSheet: View {
    let report: SmartErrorLogReport
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?

    private var selectedEntry: SmartErrorLogEntry? {
        report.entries.first(where: { $0.id == selectedID }) ?? report.entries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(language.t("SMART Error Entries"), systemImage: "exclamationmark.triangle")
                    .font(.title3.bold())
                Spacer()
                Button(language.t("Close")) { dismiss() }
            }
            .padding()

            Divider()

            if report.entries.isEmpty {
                ContentUnavailableView(
                    language.t("No Error Entries"),
                    systemImage: "checkmark.circle",
                    description: Text(language.statusMessage(report.message))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    List(selection: $selectedID) {
                        ForEach(report.entries) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.status)
                                Text(entry.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .tag(entry.id)
                        }
                    }
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)

                    Divider()

                    ScrollView {
                        if let selectedEntry {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(selectedEntry.status)
                                    .font(.title3.bold())
                                Text(selectedEntry.message)
                                if let number = selectedEntry.errorNumber {
                                    LabeledContent(language.t("Error Number"), value: String(number))
                                }
                                if let hours = selectedEntry.lifetimeHours {
                                    LabeledContent(language.t("Power-On Hours"), value: String(hours))
                                }
                                if let lba = selectedEntry.failingLBA {
                                    LabeledContent("LBA", value: String(lba))
                                }
                                if let namespaceID = selectedEntry.namespaceID {
                                    LabeledContent(language.t("Namespace"), value: String(namespaceID))
                                }
                                if !selectedEntry.details.isEmpty {
                                    Divider()
                                    ForEach(selectedEntry.details.keys.sorted(), id: \.self) { key in
                                        LabeledContent(key, value: selectedEntry.details[key] ?? "")
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 460)
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
