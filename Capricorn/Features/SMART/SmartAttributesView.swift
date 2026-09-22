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
    let satDriverGuidance: SATSMARTDriverGuidance?
    let openSATDriverSettings: () -> Void
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
                snapshotHeaderDetails
                Spacer()
                snapshotActions
            }

            primarySmartContent
                .layoutPriority(1)

            if showsSmartSelfTestInterface,
               SmartDiagnosticsVisibilityPolicy.showsPanel(for: drive, attributes: attributes) {
                SmartDiagnosticsPanel(
                    drive: drive,
                    snapshot: snapshot,
                    viewModel: viewModel,
                    selfTestHistory: selfTestHistory,
                    exportFolderPath: snapshotExportFolderPath.isEmpty ? nil : snapshotExportFolderPath,
                    chooseExportFolder: { _ = chooseSnapshotExportFolder() },
                    exportSelfTestHistory: exportSelfTestHistory,
                    exportErrorLog: exportErrorLog,
                    saveMessage: $saveMessage
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var snapshotHeaderDetails: some View {
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
    }

    private var snapshotActions: some View {
        HStack(spacing: 8) {
            HealthBadge(status: snapshot?.health ?? .unavailable, compact: true)
            Button {
                _ = chooseSnapshotExportFolder()
            } label: {
                Label(language.t("Choose Folder"), systemImage: "folder.badge.gearshape")
            }
            .help(language.t(snapshotExportFolderPath.isEmpty ? "Choose Storage Folder" : "Change Storage Folder"))
            if !snapshotExportFolderPath.isEmpty {
                Button {
                    snapshotExportFolderPath = ""
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help(language.t("Clear Storage Folder"))
            }
            Button {
                saveMessage = saveSnapshot(nil)
            } label: {
                Label(language.t("Save to History"), systemImage: "clock.arrow.circlepath")
            }
            .disabled(snapshot == nil)
            .help(language.t("Save SMART Snapshot to History"))
            Button {
                saveSnapshotCSV()
            } label: {
                Label(language.t("Save CSV"), systemImage: "tray.and.arrow.down")
            }
            .keyboardShortcut(
                AppCommandShortcut.saveSmartSnapshotKeyEquivalent,
                modifiers: AppCommandShortcut.saveSmartSnapshot.modifiers
            )
            .disabled(snapshot == nil)
            .help(language.t("Save SMART Snapshot CSV (Command-S)"))
        }
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
            Group {
                if let satDriverGuidance {
                    SATSMARTDriverGuidanceUnavailableView(
                        guidance: satDriverGuidance,
                        openSettings: openSATDriverSettings
                    )
                } else {
                    ContentUnavailableView(
                        language.t("No SMART Attributes"),
                        systemImage: "questionmark.folder",
                        description: Text(language.statusMessage(snapshot?.summary) ?? language.t("SMART data is unavailable for this drive."))
                    )
                }
            }
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

    private func saveSnapshotCSV() {
        let exportFolderPath: String
        if snapshotExportFolderPath.isEmpty {
            guard let selectedFolderPath = chooseSnapshotExportFolder() else { return }
            exportFolderPath = selectedFolderPath
        } else {
            exportFolderPath = snapshotExportFolderPath
        }
        saveMessage = saveSnapshot(exportFolderPath)
    }

    @discardableResult
    private func chooseSnapshotExportFolder() -> String? {
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

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        snapshotExportFolderPath = url.path
        return url.path
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
                TableColumn(language.t("Status")) { smartAttributeStatusBadge($0).fixedSize() }
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
                TableColumn(language.t("Status")) { smartAttributeStatusBadge($0).fixedSize() }
                    .width(82)
                TableColumn(language.t("Source")) { Text($0.source) }
                    .width(92)
            }
        }
    }

    private var normalizedValueHelp: String {
        "Current, worst, and threshold are ATA normalized health values. NVMe and native macOS SMART usually do not provide them."
    }

    @ViewBuilder
    private func smartAttributeStatusBadge(_ attribute: SmartAttribute) -> some View {
        if isErrorLogAttribute(attribute), errorLogEntryCount(attribute) >= 1 {
            Label(language.t("Check"), systemImage: "magnifyingglass")
                .font(.caption.bold())
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.12), in: Capsule())
                .help(language.t("Historical controller error entries require inspection; they do not change overall disk health."))
        } else {
            HealthBadge(status: attribute.status, compact: true)
        }
    }

    private func isErrorLogAttribute(_ attribute: SmartAttribute) -> Bool {
        let key = "\(attribute.id) \(attribute.name)"
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
        return key.contains("error log") || key.contains("错误日志")
    }

    private func errorLogEntryCount(_ attribute: SmartAttribute) -> Int {
        let digits = attribute.rawValue.split(whereSeparator: { !$0.isNumber && $0 != "-" }).first
        return Int(digits.map(String.init) ?? "0") ?? 0
    }
}

enum SmartDiagnosticsVisibilityPolicy {
    static func showsPanel(for drive: DriveDevice, attributes: [SmartAttribute]) -> Bool {
        !drive.isNetwork && !drive.isSystemDisk && !attributes.isEmpty
    }

    static func showsErrorLogSection(for drive: DriveDevice) -> Bool {
        !drive.isSystemDisk
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
    @State private var isExpanded = true
    @State private var showsSelfTestHistory = false
    @State private var showsErrorLog = false
    @State private var isConfirmingSelfTestAbort = false

    private var report: SmartSelfTestReport? { snapshot?.selfTestReport }
    private var capabilityState: SmartSelfTestCapabilityState { viewModel.smartSelfTestCapability(for: drive) }
    private var errorLogCapabilityState: SmartErrorLogCapabilityState { viewModel.smartErrorLogCapability(for: drive) }
    private var errorLogReport: SmartErrorLogReport? { viewModel.smartErrorLogReports[drive.id] }
    private var historicalErrorEntryCount: Int {
        SmartErrorLogPresentationState.historicalEntryCount(in: snapshot?.attributes ?? [])
    }
    private var errorLogPresentationState: SmartErrorLogPresentationState {
        guard let errorLogReport else { return .unavailable }
        return SmartErrorLogPresentationState.resolve(
            report: errorLogReport,
            historicalEntryCount: historicalErrorEntryCount
        )
    }
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
        drive.isNetwork || drive.isMemoryCard
    }

    private var cannotCompleteSelfTest: Bool {
        guard case let .unavailable(message) = capabilityState else { return false }
        return message == SmartSelfTestService.macOSNativeNVMeUnavailableMessage
    }

    var body: some View {
        InfoPanel(title: language.t("SMART Diagnostics"), symbol: "stethoscope") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(language.t(
                        SmartDiagnosticsVisibilityPolicy.showsErrorLogSection(for: drive)
                            ? "Self-tests, saved reports, and controller error entries."
                            : "Self-tests and saved reports."
                    ))
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
                    if SmartDiagnosticsVisibilityPolicy.showsErrorLogSection(for: drive) {
                        Divider()
                        errorLogSection
                    }
                }
            }
        }
        .sheet(isPresented: $showsSelfTestHistory) {
            SmartSelfTestHistorySheet(records: selfTestHistory, language: language)
        }
        .sheet(isPresented: $showsErrorLog) {
            if let errorLogReport {
                SmartErrorLogSheet(
                    report: errorLogReport,
                    displayState: errorLogPresentationState,
                    language: language
                )
            }
        }
        .alert(language.t("Abort SMART Self-Test?"), isPresented: $isConfirmingSelfTestAbort) {
            Button(language.t("Abort Self-Test"), role: .destructive) {
                viewModel.abortSmartSelfTest()
            }
            Button(language.t("Keep Running"), role: .cancel) {}
        } message: {
            Text(language.t("Capricorn will ask the drive to stop its current self-test. Any progress made by this test will be lost."))
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

            if isActiveForDrive, let progress = viewModel.smartSelfTestProgress {
                selfTestCompactStatus(progress)
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
            HStack(spacing: 8) {
                Button {
                    viewModel.showSmartSelfTestMonitor()
                } label: {
                    Label(language.t("View Progress"), systemImage: "waveform.path.ecg")
                }
                Button(role: .destructive) {
                    isConfirmingSelfTestAbort = true
                } label: {
                    Label(language.t("Abort Self-Test"), systemImage: "stop.circle")
                }
                .disabled(viewModel.smartSelfTestSession == .stopping)
            }
        } else {
            switch capabilityState {
            case let .supported(capability):
                HStack(spacing: 8) {
                    Button {
                        viewModel.requestSmartSelfTest(kind: .short, drive: drive)
                    } label: {
                        Label(language.t("Quick Self-Test"), systemImage: "hare")
                    }
                    .disabled(controlsUnavailable || viewModel.isSmartSelfTestActive || !capability.shortSupported)
                    Button {
                        viewModel.requestSmartSelfTest(kind: .long, drive: drive)
                    } label: {
                        Label(language.t("Full Self-Test"), systemImage: "tortoise")
                    }
                    .disabled(controlsUnavailable || viewModel.isSmartSelfTestActive || !capability.longSupported)
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
                Button {
                    viewModel.checkSmartSelfTestCapability(for: drive)
                } label: {
                    Label(language.t("Retry Self-Test Check"), systemImage: "checkmark.shield")
                }
                .disabled(controlsUnavailable)
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
                    if let summary = errorLogSummary(errorLogReport) {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                    .disabled(!errorLogPresentationState.hasExportableDetails)
                    .help(
                        errorLogPresentationState.hasExportableDetails
                            ? language.t("Export Error Entries")
                            : language.t("No parseable error details are available to export.")
                    )
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
        if cannotCompleteSelfTest {
            return language.t("Unable to Complete Self-Test")
        }
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
        if controlsUnavailable {
            return language.t("Self-tests require smartctl support for this drive.")
        }
        if isActiveForDrive, let progress = viewModel.smartSelfTestProgress {
            return activeProgressDetail(progress)
        }
        switch capabilityState {
        case .unknown:
            return language.t("Self-test support has not been checked yet.")
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
        if errorLogPresentationState.requiresInspection {
            return "\(language.t("SMART Error Entries")) · \(language.t("Check"))"
        }
        switch errorLogCapabilityState {
        case .supported:
            return language.t("SMART Error Entries")
        case .checking, .retrying:
            return language.t("Checking Error Log Support")
        case .unknown:
            return language.t("Error Log Support Not Checked")
        case .unavailable:
            return language.t("Error Log Unavailable")
        }
    }

    private var errorLogDescription: String {
        switch errorLogPresentationState {
        case let .inspectHistoricalCount(count):
            return language.smartErrorLogHistoryWithoutDetailsMessage(count: count)
        case .inspectDetails, .noEntries:
            if let errorLogReport {
                return language.statusMessage(errorLogReport.message)
            }
        case .unavailable:
            break
        }
        switch errorLogCapabilityState {
        case .supported:
            return language.t("Read ATA or NVMe controller error entries on demand.")
        case .checking:
            return language.t("Checking error-log support automatically.")
        case let .retrying(message, attempt):
            return "\(language.t("Retrying")) \(attempt)/3: \(language.statusMessage(message))"
        case .unknown:
            return language.t("Error-log support has not been checked yet.")
        case let .unavailable(message):
            return language.statusMessage(message)
        }
    }

    private var errorLogSymbol: String {
        if errorLogPresentationState.requiresInspection {
            return "magnifyingglass"
        }
        switch errorLogCapabilityState {
        case .supported: return "checkmark.circle.fill"
        case .checking, .retrying: return "arrow.clockwise"
        case .unknown, .unavailable: return "questionmark.circle"
        }
    }

    private var errorLogTint: Color {
        if errorLogPresentationState.requiresInspection {
            return .blue
        }
        switch errorLogCapabilityState {
        case .supported: return .green
        default: return .secondary
        }
    }

    private var stateSymbol: String {
        if cannotCompleteSelfTest {
            return "minus.circle"
        }
        switch effectiveState {
        case .passed: return "checkmark.circle.fill"
        case .failed, .aborted: return "exclamationmark.triangle.fill"
        case .running: return "hourglass"
        default: return "questionmark.circle"
        }
    }

    private var stateTint: Color {
        if cannotCompleteSelfTest {
            return .secondary
        }
        switch effectiveState {
        case .passed: return .green
        case .failed, .aborted: return .orange
        default: return .secondary
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

    private func selfTestCompactStatus(_ progress: SmartSelfTestProgress) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: activeProgressSymbol)
                        .foregroundStyle(.blue)
                    Text(compactProgressSummary(progress, now: timeline.date))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if let updatedAt = progress.lastStatusUpdateAt {
                        Text(formattedTime(updatedAt))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if let completed = progress.completedPercent {
                    ProgressView(value: Double(completed), total: 100)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
            .padding(10)
            .background(.blue.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var activeProgressSymbol: String {
        switch viewModel.smartSelfTestSession {
        case .starting: "paperplane"
        case .running: "waveform.path.ecg"
        case .stopping: "stop.circle"
        case .idle, .failed: "hourglass"
        }
    }

    private func compactProgressSummary(_ progress: SmartSelfTestProgress, now: Date) -> String {
        let phase: String = switch viewModel.smartSelfTestSession {
        case .starting: language.t("Starting")
        case .running: language.t("Running")
        case .stopping: language.t("Stopping")
        case .idle, .failed: language.t("Self-Test Status Unknown")
        }
        var parts = ["\(selfTestName(progress.kind)) · \(phase)"]
        if let completed = progress.completedPercent {
            parts.append("\(completed)%")
        }
        parts.append("\(language.t("Estimated Completion")): \(estimatedCompletionText(progress, now: now))")
        return parts.joined(separator: " · ")
    }

    private func activeProgressDetail(_ progress: SmartSelfTestProgress) -> String {
        switch viewModel.smartSelfTestSession {
        case .starting:
            return language.t("Sending the self-test command to the drive.")
        case .stopping:
            return language.t("Waiting for the drive to stop the self-test.")
        case .running:
            if let completed = progress.completedPercent,
               let remaining = progress.remainingPercent {
                return "\(language.t("Completed")): \(completed)% · \(language.t("Remaining")): \(remaining)%"
            }
            return language.t("The drive has not reported percentage progress. Status refreshes every 5 seconds.")
        case .idle, .failed:
            return language.t("Self-Test Status Unknown")
        }
    }

    private func selfTestName(_ kind: SmartSelfTestKind) -> String {
        switch language {
        case .english: "\(kindTitle(kind)) self-test"
        case .simplifiedChinese: "\(kindTitle(kind))自检"
        }
    }

    private func estimatedCompletionText(_ progress: SmartSelfTestProgress, now: Date) -> String {
        guard let seconds = progress.estimatedDurationSeconds else {
            return language.t("Not reported by drive")
        }
        let completion = progress.startedAt.addingTimeInterval(TimeInterval(seconds))
        if now > completion, case .running = viewModel.smartSelfTestSession {
            return "\(formattedTime(completion)) · \(language.t("Waiting for drive"))"
        }
        return formattedTime(completion)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
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

    private func errorLogSummary(_ report: SmartErrorLogReport) -> String? {
        guard errorLogPresentationState == .inspectDetails else { return nil }
        let count = max(report.entries.count, report.totalEntryCount ?? 0)
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
                            Text("\(language.smartSelfTestKindTitle(record.testKind)) · \(language.statusMessage(record.statusDetails))")
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
            LabeledContent(language.t("Test Type"), value: language.smartSelfTestKindTitle(record.testKind))
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
                        Text("\(language.smartSelfTestKindTitle(entry.kind)) · \(language.statusMessage(entry.status))")
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
    let displayState: SmartErrorLogPresentationState
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?

    private var selectedEntry: SmartErrorLogEntry? {
        report.entries.first(where: { $0.id == selectedID }) ?? report.entries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(
                    displayState.requiresInspection
                        ? "\(language.t("SMART Error Entries")) · \(language.t("Check"))"
                        : language.t("SMART Error Entries"),
                    systemImage: displayState.requiresInspection ? "magnifyingglass" : "exclamationmark.triangle"
                )
                    .font(.title3.bold())
                    .foregroundStyle(displayState.requiresInspection ? .blue : .primary)
                Spacer()
                Button(language.t("Close")) { dismiss() }
            }
            .padding()

            Divider()

            if report.entries.isEmpty {
                switch displayState {
                case let .inspectHistoricalCount(count):
                    ContentUnavailableView(
                        language.t("Historical Error Count Requires Inspection"),
                        systemImage: "magnifyingglass",
                        description: Text(language.smartErrorLogHistoryWithoutDetailsMessage(count: count))
                    )
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .noEntries:
                    ContentUnavailableView(
                        language.t("No Error Entries"),
                        systemImage: "checkmark.circle",
                        description: Text(language.statusMessage(report.message))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unavailable:
                    ContentUnavailableView(
                        language.t("Error Log Unavailable"),
                        systemImage: "questionmark.circle",
                        description: Text(language.statusMessage(report.message))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .inspectDetails:
                    EmptyView()
                }
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
