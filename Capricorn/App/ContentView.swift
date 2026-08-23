// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI

private let capricornGitHubURL = URL(string: "https://github.com/LexTheAries2209/Capricorn")!

struct ContentView: View {
    @State private var viewModel: AppModel
    @State private var preferences: AppPreferences
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SmartHistoryRecord.capturedAt, order: .reverse) private var smartHistory: [SmartHistoryRecord]
    @Query(sort: \BenchmarkHistoryRecord.measuredAt, order: .reverse) private var benchmarkHistory: [BenchmarkHistoryRecord]
    @Query(sort: \DiskActivityHistoryRecord.endedAt, order: .reverse) private var activityHistory: [DiskActivityHistoryRecord]
    @MainActor
    init() {
        _viewModel = State(initialValue: AppModel())
        _preferences = State(initialValue: AppPreferences())
    }

    @MainActor
    init(viewModel: AppModel) {
        _viewModel = State(initialValue: viewModel)
        _preferences = State(initialValue: AppPreferences())
    }

    @MainActor
    init(viewModel: AppModel, preferences: AppPreferences) {
        _viewModel = State(initialValue: viewModel)
        _preferences = State(initialValue: preferences)
    }

    private var language: AppLanguage {
        preferences.language
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let drive = viewModel.selectedDrive {
                DriveDetailView(
                    drive: drive,
                    snapshot: viewModel.snapshots[drive.id],
                    viewModel: viewModel,
                    smartHistory: smartHistory.filter { $0.driveID == drive.id },
                    benchmarkHistory: benchmarkHistory.filter { $0.driveID == drive.id },
                    activityHistory: activityHistory,
                    saveSnapshot: { exportFolderPath in saveSnapshot(drive: drive, exportFolderPath: exportFolderPath) },
                    saveBenchmarkResults: { results, activitySamples in saveBenchmarkResults(drive: drive, results: results, activitySamples: activitySamples) }
                )
            } else {
                ContentUnavailableView(
                    language.t("No Drives"),
                    systemImage: "internaldrive",
                    description: Text(language.statusMessage(viewModel.refreshMessage) ?? language.t("Refresh to scan attached storage."))
                )
            }
        }
        .navigationTitle("Capricorn")
        .environment(\.appLanguage, language)
        .environment(\.locale, Locale(identifier: language.localeIdentifier))
        .background {
            FeatureTabKeyMonitor(
                isEnabled: preferences.usesPlainTabForFeatureSwitching,
                onNext: {
                    viewModel.selectNextFeatureTab()
                },
                onPrevious: {
                    viewModel.selectPreviousFeatureTab()
                }
            )
            .frame(width: 0, height: 0)
        }
        .task {
            viewModel.showVirtualDisks = preferences.showVirtualDisks
            await viewModel.refreshIfNeeded()
        }
        .onChange(of: viewModel.showVirtualDisks) {
            preferences.showVirtualDisks = viewModel.showVirtualDisks
            Task { await viewModel.refresh() }
        }
        .onChange(of: preferences.showVirtualDisks) {
            guard viewModel.showVirtualDisks != preferences.showVirtualDisks else { return }
            viewModel.showVirtualDisks = preferences.showVirtualDisks
        }
        .sheet(item: $viewModel.diskOpenFileInspection) { inspection in
            DiskOpenFileInspectionSheet(
                title: language.t("Open Files Using Disk"),
                message: language.t("These processes currently have files open on the selected disk."),
                inspection: inspection,
                language: language,
                close: {
                    viewModel.diskOpenFileInspection = nil
                }
            )
        }
        .sheet(item: $viewModel.diskActionFailure) { failure in
            DiskActionFailureSheet(
                failure: failure,
                language: language,
                close: {
                    viewModel.diskActionFailure = nil
                },
                forceUnmount: {
                    Task { await viewModel.forceUnmountAfterFailure(failure) }
                }
            )
        }
        .sheet(isPresented: Binding(
            get: { viewModel.diskCheckReport != nil },
            set: { isPresented in
                if !isPresented, !viewModel.isDiskChecking {
                    viewModel.diskCheckReport = nil
                }
            }
        )) {
            if let report = viewModel.diskCheckReport {
                DiskCheckReportSheet(
                    report: report,
                    language: language,
                    isRunning: viewModel.isDiskChecking,
                    cancel: {
                        viewModel.cancelDiskCheck()
                    },
                    close: {
                        viewModel.diskCheckReport = nil
                    }
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.diskOperations.isFirstAidPresented },
            set: { isPresented in
                if !isPresented {
                    viewModel.closeFirstAid()
                }
            }
        )) {
            DiskFirstAidSheet(viewModel: viewModel, language: language)
        }
    }

    private var sidebar: some View {
        List(selection: sidebarDriveSelection) {
            Section(language.t("Drives")) {
                ForEach(viewModel.drives) { drive in
                    DriveSidebarRow(drive: drive, snapshot: viewModel.snapshots[drive.id])
                        .contextMenu {
                            driveContextMenu(for: drive)
                        }
                        .tag(drive.id as String?)
                        .disabled(viewModel.isLiveActivityDriveSelectionLocked && drive.id != viewModel.selectedDriveID)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Toggle(isOn: $viewModel.showVirtualDisks) {
                        Label(language.t("Show virtual disks"), systemImage: "square.stack.3d.up")
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .lineLimit(1)

                    Spacer(minLength: 8)

                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .keyboardShortcut(AppCommandShortcut.refreshDisksKeyEquivalent, modifiers: AppCommandShortcut.refreshDisks.modifiers)
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isRefreshing || viewModel.isFirstAidBlocking)
                    .help(language.t("Refresh disks and SMART data"))
                }

                HStack(spacing: 8) {
                    Label(language.t("Language"), systemImage: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Picker("", selection: $preferences.languageRawValue) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.shortTitle).tag(language.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 116)
                }

                Divider()

                Link(destination: capricornGitHubURL) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(language.t("Open Capricorn GitHub repository"), systemImage: "safari")
                            .font(.caption.weight(.semibold))
                        Text("GitHub: github.com/LexTheAries2209/Capricorn")
                            .font(.caption2.monospaced())
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(language.t("Capricorn GitHub repository introduction"))
                .accessibilityLabel(language.t("Capricorn GitHub repository introduction"))

                Divider()

                HStack(spacing: 8) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(sidebarStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Divider()

                SettingsLink {
                    HStack(spacing: 8) {
                        Label(language.t("Settings"), systemImage: "gearshape")
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 8)
                        Text("⌘P")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(language.t("Open Settings"))
                .accessibilityLabel(language.t("Open Settings"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.bar)
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 300)
    }

    private var sidebarDriveSelection: Binding<String?> {
        Binding {
            viewModel.selectedDriveID
        } set: { driveID in
            viewModel.selectDriveFromSidebar(driveID)
        }
    }

    private var sidebarStatusText: String {
        if let refreshMessage = viewModel.refreshMessage {
            return language.statusMessage(refreshMessage)
        }
        let warningCount = viewModel.snapshots.values.filter { $0.health.severity >= HealthStatus.warning.severity }.count
        return language.healthSummary(driveCount: viewModel.drives.count, warningCount: warningCount)
    }

    @ViewBuilder
    private func driveContextMenu(for drive: DriveDevice) -> some View {
        Menu {
            ForEach(DiskSidebarActionPolicy.actions(for: drive)) { action in
                Button {
                    handleSidebarAction(action, for: drive)
                } label: {
                    Label(language.t(action.titleKey), systemImage: action.systemImage)
                }
                .disabled(sidebarActionIsDisabled(action, for: drive))
            }
        } label: {
            Label(language.t("Disk Actions"), systemImage: "externaldrive.badge.gearshape")
        }
    }

    private func handleSidebarAction(_ action: DiskSidebarAction, for drive: DriveDevice) {
        viewModel.selectedDriveID = drive.id

        switch action {
        case .rename:
            guard let newName = promptForVolumeName(drive: drive) else { return }
            Task { await viewModel.performDiskAction(action, on: drive, newName: newName) }
        case .inspectOpenFiles:
            Task { await viewModel.inspectOpenFiles(on: drive) }
        case .checkLog:
            Task { await viewModel.runDiskCheck(.ordinary, on: drive) }
        case .detailedCheck:
            Task { await viewModel.runDiskCheck(.detailed, on: drive) }
        case .firstAid:
            Task { await viewModel.prepareFirstAid(on: drive) }
        case .revealInFinder:
            revealDriveInFinder(drive)
        case .refresh:
            Task { await viewModel.refresh() }
        default:
            Task { await viewModel.performDiskAction(action, on: drive) }
        }
    }

    private func sidebarActionIsDisabled(_ action: DiskSidebarAction, for drive: DriveDevice) -> Bool {
        guard DiskSidebarActionPolicy.isEnabled(action, for: drive) else { return true }
        if viewModel.isFirstAidBlocking { return true }
        if action == .firstAid {
            return viewModel.isRefreshing || viewModel.isDiskChecking || viewModel.isBenchmarking || viewModel.isLiveActivityWorkloadRunning
        }
        if action == .checkLog || action == .detailedCheck {
            return viewModel.isDiskChecking || viewModel.isBenchmarking || viewModel.isLiveActivityWorkloadRunning
        }
        return false
    }

    private func promptForVolumeName(drive: DriveDevice) -> String? {
        let alert = NSAlert()
        alert.messageText = language.t("Rename Volume")
        alert.informativeText = language.t("Enter a new name for the selected volume.")
        alert.addButton(withTitle: language.t("Rename"))
        alert.addButton(withTitle: language.t("Cancel"))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.stringValue = drive.actionTargetVolume?.name ?? drive.displayName
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func revealDriveInFinder(_ drive: DriveDevice) {
        guard let mountPoint = drive.primaryMountPoint else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: mountPoint, isDirectory: true))
    }

    private func saveSnapshot(drive: DriveDevice, exportFolderPath: String?) -> String {
        guard let snapshot = viewModel.snapshots[drive.id] else {
            return "No SMART snapshot is available to save."
        }
        do {
            try HistoryRepository(modelContext: modelContext).saveSmart(drive: drive, snapshot: snapshot)
        } catch {
            return UserFacingError.message("Could not save SMART snapshot to history.", error: error)
        }

        guard let exportFolderPath, !exportFolderPath.isEmpty else {
            return "SMART snapshot saved to history."
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: exportFolderPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "SMART snapshot saved to history, but the selected folder is unavailable."
        }

        let fileURL = URL(fileURLWithPath: exportFolderPath, isDirectory: true)
            .appendingPathComponent(ReportExporter.smartSnapshotFileName(
                drive: drive,
                date: snapshot.capturedAt,
                language: language
            ))
        do {
            let report = ReportExporter.smartSnapshotCSVReport(
                drive: drive,
                snapshot: snapshot,
                language: language
            )
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            return "SMART snapshot saved to history and \(fileURL.lastPathComponent)."
        } catch {
            return UserFacingError.message("SMART snapshot saved to history, but export failed.", error: error)
        }
    }

    private func saveBenchmarkResults(drive: DriveDevice, results: [BenchmarkResult], activitySamples: [DiskActivitySample]) {
        do {
            try HistoryRepository(modelContext: modelContext).saveBenchmarks(
                drive: drive,
                results: results,
                activitySamples: activitySamples
            )
        } catch {
            viewModel.benchmarkError = UserFacingError.message("Could not save benchmark history.", error: error)
        }
    }
}

private struct DiskActionFailureSheet: View {
    var failure: DiskActionFailure
    var language: AppLanguage
    var close: () -> Void
    var forceUnmount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(language.t("Disk Action Failed"))
                        .font(.title3.weight(.semibold))
                    Text(language.statusMessage(failure.message))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            DiskOpenFileList(inspection: failure.openFiles, language: language)

            HStack {
                Spacer()
                Button(language.t("Close")) {
                    close()
                }
                .keyboardShortcut(.cancelAction)

                if failure.canForceUnmount {
                    Button(role: .destructive) {
                        forceUnmount()
                    } label: {
                        Label(language.t("Force Unmount"), systemImage: "externaldrive.badge.xmark")
                    }
                }
            }
        }
        .padding(22)
        .frame(minWidth: 680, minHeight: 420)
    }
}

private struct DiskOpenFileInspectionSheet: View {
    var title: String
    var message: String
    var inspection: DiskOpenFileInspection
    var language: AppLanguage
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }

            DiskOpenFileList(inspection: inspection, language: language)

            HStack {
                Spacer()
                Button(language.t("Close")) {
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(minWidth: 680, minHeight: 420)
    }
}

private struct DiskCheckReportSheet: View {
    var report: DiskCheckReport
    var language: AppLanguage
    var isRunning: Bool
    var cancel: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: report.hasIssues ? "exclamationmark.magnifyingglass" : "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(report.hasIssues ? .orange : .green)
                VStack(alignment: .leading, spacing: 6) {
                    Text(language.t("Disk Check Report"))
                        .font(.title3.weight(.semibold))
                    Text("\(report.driveName) · \(language.t(report.mode.titleKey))")
                        .foregroundStyle(.secondary)
                    Text(language.t(report.mode.descriptionKey))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(statusMessage, systemImage: statusIcon)
                    .foregroundStyle(statusColor)
                if isRunning {
                    if report.totalEntryCount > 0 {
                        ProgressView(value: report.progressFraction)
                    } else {
                        ProgressView()
                    }
                }
                Text("\(language.t("Completed")) \(report.completedEntryCount) / \(report.totalEntryCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if report.entries.isEmpty {
                        ContentUnavailableView(
                            language.t("Preparing Disk Check"),
                            systemImage: "hourglass",
                            description: Text(language.t("The command list is being prepared."))
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(report.entries) { entry in
                            DiskCheckEntryView(entry: entry, language: language)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)

            HStack {
                Spacer()
                if isRunning {
                    Button(role: .destructive) {
                        cancel()
                    } label: {
                        Label(language.t("Cancel Check"), systemImage: "stop.fill")
                    }
                    .keyboardShortcut(.cancelAction)
                }
                Button(language.t("Close")) {
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRunning)
            }
        }
        .padding(22)
        .frame(minWidth: 760, minHeight: 560)
    }

    private var statusMessage: String {
        if isRunning {
            return language.t("Disk check is running. Keep this window open to monitor progress.")
        }
        return language.t(report.hasIssues ? "The check reported issues or unsupported targets." : "No issues were reported by the completed checks.")
    }

    private var statusIcon: String {
        if isRunning { return "hourglass" }
        return report.hasIssues ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
    }

    private var statusColor: Color {
        if isRunning { return .blue }
        return report.hasIssues ? .orange : .green
    }
}

private struct DiskCheckEntryView: View {
    var entry: DiskCheckEntry
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(entry.title, systemImage: entryIcon)
                    .font(.headline)
                    .foregroundStyle(entryColor)
                Spacer()
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(entryColor.opacity(0.16))
                    .clipShape(Capsule())
            }

            if !entry.commandLine.isEmpty {
                Text(entry.commandLine)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            ScrollView([.vertical, .horizontal]) {
                Text(outputText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .defaultScrollAnchor(.topLeading)
            .frame(minHeight: 120, maxHeight: 220)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scrollIndicators(.visible)
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusText: String {
        if entry.isRunning {
            return language.t("Running")
        }
        guard let terminationStatus = entry.terminationStatus else {
            return language.t("Unsupported")
        }
        return "\(language.t("Exit Code")) \(terminationStatus)"
    }

    private var outputText: String {
        if entry.isRunning, entry.combinedOutput == "No output." {
            return language.t("Waiting for command output...")
        }
        return entry.combinedOutput
    }

    private var entryIcon: String {
        if entry.isRunning { return "hourglass" }
        return entry.hasIssue ? "exclamationmark.triangle" : "checkmark.circle"
    }

    private var entryColor: Color {
        if entry.isRunning { return .blue }
        return entry.hasIssue ? .orange : .green
    }
}

private struct DiskOpenFileList: View {
    var inspection: DiskOpenFileInspection
    var language: AppLanguage

    private var columns: [GridItem] {
        DiskOpenFileTableLayout.columnWidths.map {
            GridItem(.fixed($0), spacing: DiskOpenFileTableLayout.spacing, alignment: .leading)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(inspection.driveName, systemImage: "externaldrive")
                    .font(.headline)
                Text(inspection.mountPoint)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            if inspection.processes.isEmpty {
                ContentUnavailableView(
                    language.t("No Occupying Processes"),
                    systemImage: "checkmark.circle",
                    description: Text(language.t("No process with open files was reported for this disk."))
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: 0) {
                        LazyVGrid(columns: columns, spacing: 0) {
                            header(language.t("Program"))
                            header("PID")
                            header(language.t("User"))
                            header(language.t("Path"))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.quaternary)

                        LazyVGrid(columns: columns, spacing: 0) {
                            ForEach(inspection.processes) { process in
                                cell(process.command, weight: .semibold)
                                cell(String(process.pid))
                                cell(process.user)
                                cell(process.path, monospaced: true)
                            }
                        }
                        .padding(12)
                    }
                    .frame(width: DiskOpenFileTableLayout.contentWidth + 24, alignment: .leading)
                }
                .defaultScrollAnchor(.topLeading)
                .scrollIndicators(.visible)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.separator.opacity(0.8), lineWidth: 1)
                }
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ text: String, weight: Font.Weight = .regular, monospaced: Bool = false) -> some View {
        Text(text)
            .font(monospaced ? .system(.caption, design: .monospaced).weight(weight) : .caption.weight(weight))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
    }
}

private struct DriveSidebarRow: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(snapshot?.health.tint ?? .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                driveName
                HStack(spacing: 8) {
                    Text(deviceSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(identifierSummary)
                    Spacer(minLength: 4)
                    HealthBadge(status: snapshot?.health ?? .unavailable, compact: true)
                }
                if let capacitySummary {
                    Text(capacitySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var driveName: some View {
        if let match = drive.catalogMatch {
            Text(match.marketingName)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .help(drive.catalogDisplayHelp(language: language))
            Text(match.canonicalModel)
                .font(.caption.bold())
                .lineLimit(1)
                .help(drive.catalogDisplayHelp(language: language))
        } else {
            Text(drive.displayName)
                .font(.headline)
                .lineLimit(1)
                .help(drive.displayName)
        }
    }

    private var iconName: String {
        if drive.isNetwork {
            return "network"
        }
        if drive.isMemoryCard {
            return "sdcard.fill"
        }
        return drive.isInternal ? "internaldrive.fill" : "externaldrive.fill"
    }

    private var deviceSummary: String {
        var components: [String] = []
        if let fileSystem = drive.fileSystemSummary {
            components.append(fileSystem)
        }
        if !drive.protocolName.isEmpty,
           !components.contains(where: { $0.caseInsensitiveCompare(drive.protocolName) == .orderedSame }) {
            components.append(drive.protocolName)
        }
        if drive.sizeBytes > 0 {
            components.append(formatByteCount(drive.sizeBytes))
        }
        return components.isEmpty ? drive.bsdName : components.joined(separator: " · ")
    }

    private var capacitySummary: String? {
        guard let capacityUsage = drive.capacityUsage else { return nil }
        return "\(language.t("Used")) \(formatByteCount(capacityUsage.usedBytes)) · \(language.t("Available")) \(formatByteCount(capacityUsage.availableBytes))"
    }

    private var identifierSummary: String {
        if drive.isNetwork {
            let mount = drive.primaryMountPoint ?? drive.deviceNode
            return "\(drive.protocolName) · \(language.t("Network Drive")) · \(mount)"
        }
        return "\(drive.bsdName) · \(drive.protocolName) · \(formatByteCount(drive.sizeBytes))"
    }
}

private struct DriveDetailView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    var viewModel: AppModel
    let smartHistory: [SmartHistoryRecord]
    let benchmarkHistory: [BenchmarkHistoryRecord]
    let activityHistory: [DiskActivityHistoryRecord]
    let saveSnapshot: (String?) -> String
    let saveBenchmarkResults: ([BenchmarkResult], [DiskActivitySample]) -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        @Bindable var viewModel = viewModel
        TabView(selection: $viewModel.selectedFeatureTab) {
            OverviewView(drive: drive, snapshot: snapshot)
                .tabItem { Label(language.t("Overview"), systemImage: "gauge.with.dots.needle.bottom.50percent") }
                .tag(DriveFeatureTab.overview)
            SmartAttributesView(
                drive: drive,
                snapshot: snapshot,
                viewModel: viewModel,
                externalSupport: viewModel.externalSupport,
                verifyExternalSupport: viewModel.refreshExternalSupport,
                saveSnapshot: saveSnapshot
            )
                .tabItem { Label("SMART", systemImage: "list.bullet.rectangle") }
                .tag(DriveFeatureTab.smart)
            BenchmarkView(drive: drive, viewModel: viewModel, saveResults: saveBenchmarkResults)
                .tabItem { Label(language.t("Benchmark"), systemImage: "speedometer") }
                .tag(DriveFeatureTab.benchmark)
            DiskActivityView(drive: drive, viewModel: viewModel, activityHistory: activityHistory)
                .tabItem { Label(language.t("Live Activity"), systemImage: "waveform.path.ecg.rectangle") }
                .tag(DriveFeatureTab.liveActivity)
            HistoryReportView(
                drive: drive,
                snapshot: snapshot,
                smartHistory: smartHistory,
                benchmarkHistory: benchmarkHistory,
                activityHistory: activityHistory.filter { $0.driveID == drive.id }
            )
            .tabItem { Label(language.t("History"), systemImage: "clock.arrow.circlepath") }
            .tag(DriveFeatureTab.history)
        }
        .padding(18)
    }
}

struct DrivePageHeaderView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    var showsHealthBadge = true
    var showsSerialNumber = false
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(drive.catalogHeaderDisplayName)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .help(drive.catalogDisplayHelp(language: language))
                if showsSerialNumber {
                    Text("\(language.t("Serial Number")): \(DrivePageHeaderText.serialNumber(for: drive))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                Text(DrivePageHeaderText.subtitle(for: drive, language: language))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsHealthBadge {
                HealthBadge(status: snapshot?.health ?? .unavailable)
            }
        }
    }
}

#Preview {
    ContentView(viewModel: .preview)
        .modelContainer(for: [SmartHistoryRecord.self, BenchmarkHistoryRecord.self, DiskActivityHistoryRecord.self, AppSettingsRecord.self], inMemory: true)
}
