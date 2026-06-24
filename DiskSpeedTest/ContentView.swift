import AppKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: DITViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SmartHistoryRecord.capturedAt, order: .reverse) private var smartHistory: [SmartHistoryRecord]
    @Query(sort: \BenchmarkHistoryRecord.measuredAt, order: .reverse) private var benchmarkHistory: [BenchmarkHistoryRecord]
    @Query(sort: \DiskActivityHistoryRecord.endedAt, order: .reverse) private var activityHistory: [DiskActivityHistoryRecord]
    @AppStorage("appLanguage") private var languageRawValue = AppLanguage.english.rawValue

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: DITViewModel())
    }

    @MainActor
    init(viewModel: DITViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .english
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
                    saveBenchmarkResults: { saveBenchmarkResults(drive: drive) }
                )
            } else {
                ContentUnavailableView(
                    language.t("No Drives"),
                    systemImage: "internaldrive",
                    description: Text(language.statusMessage(viewModel.refreshMessage) ?? language.t("Refresh to scan attached storage."))
                )
            }
        }
        .navigationTitle("DIT")
        .environment(\.appLanguage, language)
        .environment(\.locale, Locale(identifier: language.localeIdentifier))
        .task {
            await viewModel.refreshIfNeeded()
        }
        .onChange(of: viewModel.showVirtualDisks) {
            Task { await viewModel.refresh() }
        }
    }

    private var sidebar: some View {
        List(selection: $viewModel.selectedDriveID) {
            Section(language.t("Drives")) {
                ForEach(viewModel.drives) { drive in
                    DriveSidebarRow(drive: drive, snapshot: viewModel.snapshots[drive.id])
                        .tag(drive.id as String?)
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
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isRefreshing)
                    .help(language.t("Refresh disks and SMART data"))
                }

                HStack(spacing: 8) {
                    Label(language.t("Language"), systemImage: "globe")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Picker("", selection: $languageRawValue) {
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.bar)
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 300)
    }

    private var sidebarStatusText: String {
        if let refreshMessage = viewModel.refreshMessage {
            return language.statusMessage(refreshMessage)
        }
        let warningCount = viewModel.snapshots.values.filter { $0.health.severity >= HealthStatus.warning.severity }.count
        return language.healthSummary(driveCount: viewModel.drives.count, warningCount: warningCount)
    }

    private func saveSnapshot(drive: DriveDevice, exportFolderPath: String?) -> String {
        guard let snapshot = viewModel.snapshots[drive.id] else {
            return "No SMART snapshot is available to save."
        }
        modelContext.insert(SmartHistoryRecord(drive: drive, snapshot: snapshot))
        do {
            try modelContext.save()
        } catch {
            return "Could not save SMART snapshot to history: \(error.localizedDescription)"
        }

        guard let exportFolderPath, !exportFolderPath.isEmpty else {
            return "SMART snapshot saved to history."
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: exportFolderPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "SMART snapshot saved to history, but the selected folder is unavailable."
        }

        let fileURL = URL(fileURLWithPath: exportFolderPath, isDirectory: true)
            .appendingPathComponent(snapshotFileName(drive: drive, date: snapshot.capturedAt))
        let report = ReportExporter.jsonReport(drive: drive, snapshot: snapshot, benchmarkResults: [], includeSerial: false)

        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            return "SMART snapshot saved to history and \(fileURL.path)."
        } catch {
            return "SMART snapshot saved to history, but export failed: \(error.localizedDescription)"
        }
    }

    private func snapshotFileName(drive: DriveDevice, date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        let safeName = drive.displayName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "DiskSmart-\(safeName.isEmpty ? drive.bsdName : safeName)-\(stamp).json"
    }

    private func saveBenchmarkResults(drive: DriveDevice) {
        for result in viewModel.benchmarkResults where result.driveID == drive.id {
            modelContext.insert(BenchmarkHistoryRecord(drive: drive, result: result))
        }
        try? modelContext.save()
    }
}

private struct DriveSidebarRow: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: drive.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                .font(.title3)
                .foregroundStyle(snapshot?.health.tint ?? .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(drive.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(drive.bsdName) · \(drive.protocolName) · \(formatByteCount(drive.sizeBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HealthBadge(status: snapshot?.health ?? .unavailable, compact: true)
        }
        .padding(.vertical, 4)
    }
}

private struct DriveDetailView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    @ObservedObject var viewModel: DITViewModel
    let smartHistory: [SmartHistoryRecord]
    let benchmarkHistory: [BenchmarkHistoryRecord]
    let activityHistory: [DiskActivityHistoryRecord]
    let saveSnapshot: (String?) -> String
    let saveBenchmarkResults: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        TabView {
            OverviewView(drive: drive, snapshot: snapshot)
                .tabItem { Label(language.t("Overview"), systemImage: "gauge.with.dots.needle.bottom.50percent") }
            SmartAttributesView(
                drive: drive,
                snapshot: snapshot,
                externalSupport: viewModel.externalSupport,
                verifyExternalSupport: viewModel.refreshExternalSupport,
                saveSnapshot: saveSnapshot
            )
                .tabItem { Label("SMART", systemImage: "list.bullet.rectangle") }
            BenchmarkView(drive: drive, viewModel: viewModel, saveResults: saveBenchmarkResults)
                .tabItem { Label(language.t("Benchmark"), systemImage: "speedometer") }
            DiskActivityView(initialDrive: drive, viewModel: viewModel, activityHistory: activityHistory)
                .tabItem { Label(language.t("Live Activity"), systemImage: "waveform.path.ecg.rectangle") }
            HistoryReportView(
                drive: drive,
                snapshot: snapshot,
                benchmarkResults: viewModel.benchmarkResults.filter { $0.driveID == drive.id },
                smartHistory: smartHistory,
                benchmarkHistory: benchmarkHistory,
                activityHistory: activityHistory.filter { $0.driveID == drive.id }
            )
            .tabItem { Label(language.t("History"), systemImage: "clock.arrow.circlepath") }
        }
        .padding(18)
    }
}

private struct OverviewView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    @Environment(\.appLanguage) private var language
    @State private var showsSelfTestLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(drive.displayName)
                            .font(.largeTitle.bold())
                            .lineLimit(2)
                        Text("\(drive.bsdName) · \(drive.protocolName) · \(drive.isSolidState ? language.t("SSD") : language.t("HDD/Media"))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HealthBadge(status: snapshot?.health ?? .unavailable)
                }

                if let snapshot {
                    Text(language.statusMessage(snapshot.summary))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    StatTile(title: language.t("Capacity"), value: formatByteCount(drive.sizeBytes), symbol: "square.stack.3d.down.right")
                    StatTile(title: language.t("Temperature"), value: snapshot?.temperatureCelsius.map { String(format: "%.1f C", $0) } ?? language.t("Unavailable"), symbol: "thermometer.medium")
                    StatTile(title: language.t("Life Remaining"), value: snapshot?.lifeRemainingPercent.map { "\($0)%" } ?? language.t("Unavailable"), symbol: "battery.75percent")
                    StatTile(title: language.t("Power-On Hours"), value: snapshot?.powerOnHours.map(String.init) ?? language.t("Unavailable"), symbol: "timer")
                    StatTile(title: language.t("Media Errors"), value: snapshot?.mediaErrors.map(String.init) ?? language.t("Unavailable"), symbol: "exclamationmark.triangle")
                    StatTile(title: "SMART", value: language.statusMessage(snapshot?.smartStatusRaw ?? drive.smartStatusRaw) ?? language.t("Unavailable"), symbol: "checklist.checked")
                }

                InfoPanel(title: language.t("Volumes"), symbol: "opticaldiscdrive") {
                    if drive.volumes.isEmpty {
                        Text(language.t("No mounted volumes are mapped to this physical disk."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(drive.volumes) { volume in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(volume.name)
                                    Text(volume.mountPoint ?? volume.deviceIdentifier)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(formatByteCount(volume.sizeBytes))
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                    }
                }

                InfoPanel(title: language.t("Providers"), symbol: "antenna.radiowaves.left.and.right") {
                    ForEach(snapshot?.providerStatuses ?? []) { status in
                        HStack(alignment: .top) {
                            Image(systemName: status.state.symbolName)
                                .foregroundStyle(status.state.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.name)
                                    .font(.headline)
                                Text(language.statusMessage(status.message))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                SelfTestSummaryView(snapshot: snapshot, isExpanded: $showsSelfTestLog)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SmartAttributesView: View {
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
        guard let snapshot else { return false }
        let hasAvailableProvider = snapshot.providerStatuses.contains { $0.state == .available }
        let hasLimitedProvider = snapshot.providerStatuses.contains { $0.state == .limited }
        let externalDrive = !drive.isInternal || drive.isRemovable
        let lacksUsableSmart = attributes.isEmpty || snapshot.health == .unavailable || !hasAvailableProvider
        return lacksUsableSmart || (externalDrive && hasLimitedProvider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            }

            if showsExternalSupportHelp {
                ExternalSupportView(status: externalSupport, refresh: verifyExternalSupport)
                    .frame(maxWidth: 760, alignment: .leading)
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

private struct DiskActivityView: View {
    let initialDrive: DriveDevice
    @ObservedObject var viewModel: DITViewModel
    let activityHistory: [DiskActivityHistoryRecord]
    @AppStorage("diskActivitySampleInterval") private var selectedIntervalSeconds = DiskActivitySampleInterval.default.seconds
    @AppStorage("diskActivityWorkloadTargetFolder") private var workloadTargetFolderPath = ""
    @AppStorage("diskActivityWorkloadOperation") private var workloadOperationRaw = DiskActivityWorkloadOperation.write.rawValue
    @AppStorage("diskActivityWorkloadFileSize") private var workloadFileSizeRaw = DiskActivityWorkloadFileSize.gib32.rawValue
    @AppStorage("diskActivityWorkloadLoopEnabled") private var workloadLoopEnabled = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var saveMessage: String?
    @State private var showHiddenActivityHistory = false
    private let activityHistoryScrollThreshold = 10
    private let activityHistoryRowHeight: CGFloat = 58

    private var selectedDriveID: String {
        viewModel.liveActivitySelectedDriveID ?? initialDrive.id
    }

    private var selectedDrive: DriveDevice {
        viewModel.drives.first(where: { $0.id == selectedDriveID }) ?? initialDrive
    }

    private var selectedInterval: DiskActivitySampleInterval {
        DiskActivitySampleInterval(rawValue: selectedIntervalSeconds) ?? .default
    }

    private var workloadOperation: DiskActivityWorkloadOperation {
        DiskActivityWorkloadOperation(rawValue: workloadOperationRaw) ?? .write
    }

    private var workloadFileSizeOption: DiskActivityWorkloadFileSize {
        DiskActivityWorkloadFileSize(rawValue: workloadFileSizeRaw) ?? .gib32
    }

    private var workloadTargetFolderURL: URL? {
        guard !workloadTargetFolderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: workloadTargetFolderPath, isDirectory: true)
    }

    private var workloadTargetFolderIsUsable: Bool {
        guard !workloadTargetFolderPath.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: workloadTargetFolderPath, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isWritableFile(atPath: workloadTargetFolderPath)
    }

    private var workloadTargetAvailableCapacity: Int64 {
        guard workloadTargetFolderIsUsable, let workloadTargetFolderURL else { return 0 }
        return DiskActivityWorkloadStorageValidator.availableCapacity(for: workloadTargetFolderURL)
    }

    private var workloadResolvedFileSize: Int64? {
        guard workloadTargetFolderIsUsable else { return nil }
        return DiskActivityWorkloadStorageValidator.resolvedFileSize(
            for: workloadFileSizeOption,
            operation: workloadOperation,
            availableCapacity: workloadTargetAvailableCapacity
        )
    }

    private var workloadTargetDriveMismatch: Bool {
        guard workloadTargetFolderIsUsable else { return false }
        return !BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(workloadTargetFolderPath, drive: selectedDrive)
    }

    private var canStartWorkload: Bool {
        guard !viewModel.isLiveActivityWorkloadRunning,
              workloadTargetFolderIsUsable,
              !workloadTargetDriveMismatch,
              let fileSize = workloadResolvedFileSize else {
            return false
        }
        let required = DiskActivityWorkloadStorageValidator.requiredSpace(fileSizeBytes: fileSize, operation: workloadOperation)
        return workloadTargetAvailableCapacity >= required
    }

    private var selectedDriveHistory: [DiskActivityHistoryRecord] {
        HistoryVisibility.visible(activityHistory.filter { $0.driveID == selectedDrive.id })
    }

    private var selectedDriveHiddenHistory: [DiskActivityHistoryRecord] {
        HistoryVisibility.hidden(activityHistory.filter { $0.driveID == selectedDrive.id })
    }

    private var summary: DiskActivitySummary {
        let fallbackEnd = viewModel.isLiveActivityMonitoring ? Date() : viewModel.liveActivityEndedAt
        return DiskActivityStatistics.summarize(
            samples: viewModel.liveActivitySamples,
            startedAt: viewModel.liveActivityStartedAt,
            endedAt: fallbackEnd
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                controls
                workloadPanel
                DiskActivityChartView(
                    title: language.t("Live Disk Activity"),
                    samples: viewModel.liveActivitySamples,
                    current: viewModel.currentLiveActivity,
                    style: .expanded
                )
                metricGrid
                historyList
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if viewModel.liveActivitySelectedDriveID == nil {
                viewModel.liveActivitySelectedDriveID = initialDrive.id
            }
            adjustWorkloadFileSizeForTarget()
        }
        .onChange(of: workloadTargetFolderPath) { _, _ in
            viewModel.liveActivityWorkloadError = nil
            adjustWorkloadFileSizeForTarget()
        }
        .onChange(of: workloadOperationRaw) { _, _ in
            viewModel.liveActivityWorkloadError = nil
            adjustWorkloadFileSizeForTarget()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.t("Live Activity"))
                .font(.largeTitle.bold())
            Text(language.t("Monitors total I/O reported by macOS for the selected physical disk."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.t("Drive"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("", selection: selectedDriveBinding) {
                    ForEach(viewModel.drives) { drive in
                        Text("\(drive.displayName) (\(drive.bsdName))").tag(drive.id)
                    }
                }
                .labelsHidden()
                .frame(width: 280, alignment: .leading)
                .disabled(viewModel.isLiveActivityMonitoring || viewModel.isLiveActivityWorkloadRunning)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(language.t("Sample Interval"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedIntervalSeconds) {
                    ForEach(DiskActivitySampleInterval.allCases) { interval in
                        Text(interval.title).tag(interval.seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220, alignment: .leading)
                .disabled(viewModel.isLiveActivityMonitoring || viewModel.isLiveActivityWorkloadRunning)
            }

            Spacer(minLength: 10)

            Button {
                saveMessage = nil
                viewModel.startLiveActivityMonitoring(drive: selectedDrive, interval: selectedInterval)
            } label: {
                Label(language.t("Start Monitoring"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLiveActivityMonitoring || viewModel.isLiveActivityWorkloadRunning || viewModel.drives.isEmpty)

            Button {
                viewModel.stopLiveActivityMonitoring()
            } label: {
                Label(language.t("Stop Monitoring"), systemImage: "stop.fill")
            }
            .disabled(!viewModel.isLiveActivityMonitoring)

            Button {
                saveActivityHistory()
            } label: {
                Label(language.t("Save to History"), systemImage: "tray.and.arrow.down")
            }
            .disabled(viewModel.isLiveActivityMonitoring || viewModel.isLiveActivityWorkloadRunning || viewModel.liveActivitySamples.isEmpty)

            Button {
                saveMessage = nil
                viewModel.clearLiveActivity()
            } label: {
                Label(language.t("Clear Chart"), systemImage: "xmark.circle")
            }
            .disabled(viewModel.isLiveActivityMonitoring || viewModel.isLiveActivityWorkloadRunning || viewModel.liveActivitySamples.isEmpty)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }

    private var selectedDriveBinding: Binding<String> {
        Binding {
            selectedDriveID
        } set: { nextValue in
            viewModel.liveActivitySelectedDriveID = nextValue
            saveMessage = nil
        }
    }

    private var workloadPanel: some View {
        InfoPanel(title: language.t("Large File Workload"), symbol: "bolt.horizontal.circle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.t("Target Folder"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button {
                            chooseWorkloadTargetFolder()
                        } label: {
                            Label(workloadTargetFolderPath.isEmpty ? language.t("Choose Target Folder") : language.t("Change Folder"), systemImage: "folder.badge.gearshape")
                        }
                        .disabled(viewModel.isLiveActivityWorkloadRunning)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.t("Workload"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $workloadOperationRaw) {
                            ForEach(DiskActivityWorkloadOperation.allCases) { operation in
                                Text(language.activityWorkloadOperationTitle(operation)).tag(operation.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 230)
                        .disabled(viewModel.isLiveActivityWorkloadRunning)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.t("Large File Size"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $workloadFileSizeRaw) {
                            ForEach(DiskActivityWorkloadFileSize.allCases) { option in
                                Text(workloadFileSizeTitle(option))
                                    .tag(option.rawValue)
                                    .disabled(!isWorkloadFileSizeSelectable(option))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                        .disabled(viewModel.isLiveActivityWorkloadRunning)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.t("Loop"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $workloadLoopEnabled) {
                            Text(language.t("Off")).tag(false)
                            Text(language.t("On")).tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 110)
                        .disabled(viewModel.isLiveActivityWorkloadRunning)
                    }

                    Spacer(minLength: 10)

                    Button {
                        startWorkload()
                    } label: {
                        Label(language.t("Start Workload"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStartWorkload)

                    Button {
                        viewModel.stopLiveActivityWorkload()
                    } label: {
                        Label(language.t("Stop Workload"), systemImage: "stop.fill")
                    }
                    .disabled(!viewModel.isLiveActivityWorkloadRunning)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Label(workloadTargetStatusText, systemImage: workloadTargetStatusSymbol)
                        .font(.caption)
                        .foregroundStyle(workloadTargetStatusColor)
                    Text(workloadTargetFolderPath.isEmpty ? language.t("No target folder selected") : workloadTargetFolderPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(language.t("Large file workload creates temporary files and may stress or wear storage."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let progress = viewModel.liveActivityWorkloadProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress.fraction)
                        Text(workloadProgressText(progress))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = viewModel.liveActivityWorkloadError {
                    Label(language.statusMessage(error), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var workloadTargetStatusText: String {
        if workloadTargetFolderPath.isEmpty {
            return language.t("Choose a writable target folder")
        }
        guard workloadTargetFolderIsUsable else {
            return language.t("Target folder is not writable")
        }
        if workloadTargetDriveMismatch {
            return language.t("Workload target folder must be on the selected drive")
        }
        guard let fileSize = workloadResolvedFileSize else {
            return language.t("Not enough free space for the selected workload")
        }
        let required = DiskActivityWorkloadStorageValidator.requiredSpace(fileSizeBytes: fileSize, operation: workloadOperation)
        if workloadTargetAvailableCapacity < required {
            return language.t("Selected workload size exceeds available free space")
        }
        return language.t("Target folder is writable")
    }

    private var workloadTargetStatusSymbol: String {
        canStartWorkload ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var workloadTargetStatusColor: Color {
        canStartWorkload ? .green : .orange
    }

    private func workloadFileSizeTitle(_ option: DiskActivityWorkloadFileSize) -> String {
        if option == .fullDisk95 {
            guard workloadTargetFolderIsUsable,
                  let size = DiskActivityWorkloadStorageValidator.resolvedFileSize(
                    for: option,
                    operation: workloadOperation,
                    availableCapacity: workloadTargetAvailableCapacity
                  ) else {
                return language.t("Full Disk (95%)")
            }
            let suffix = workloadOperation == .mixed ? " x2" : ""
            return "\(language.t("Full Disk (95%)")) · \(formatBenchmarkFileSize(size))\(suffix)"
        }
        guard let fixedBytes = option.fixedBytes else {
            return language.t("Full Disk (95%)")
        }
        return formatBenchmarkFileSize(fixedBytes)
    }

    private func isWorkloadFileSizeSelectable(_ option: DiskActivityWorkloadFileSize) -> Bool {
        guard workloadTargetFolderIsUsable else { return true }
        return DiskActivityWorkloadStorageValidator.isFileSizeAvailable(
            option,
            operation: workloadOperation,
            availableCapacity: workloadTargetAvailableCapacity
        )
    }

    private func workloadProgressText(_ progress: DiskActivityWorkloadProgress) -> String {
        var parts = [
            "\(language.t("Loop")) \(progress.loopIndex)",
            language.statusMessage(progress.message)
        ]
        if progress.totalBytes > 0 {
            parts.append("\(formatBenchmarkFileSize(progress.completedBytes)) / \(formatBenchmarkFileSize(progress.totalBytes))")
        }
        return parts.joined(separator: " · ")
    }

    private func chooseWorkloadTargetFolder() {
        let panel = NSOpenPanel()
        panel.title = language.t("Choose Target Folder")
        panel.message = language.t("Choose a writable folder where large temporary workload files can be created.")
        panel.prompt = language.t("Use Folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let workloadTargetFolderURL {
            panel.directoryURL = workloadTargetFolderURL
        } else if let fallback = selectedDrive.benchmarkMountPoint {
            panel.directoryURL = URL(fileURLWithPath: fallback, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        workloadTargetFolderPath = url.path
        viewModel.liveActivityWorkloadError = nil
        adjustWorkloadFileSizeForTarget()
    }

    private func startWorkload() {
        guard let targetURL = workloadTargetFolderURL,
              let fileSize = workloadResolvedFileSize else {
            viewModel.liveActivityWorkloadError = "Choose a writable target folder before starting."
            return
        }
        guard canStartWorkload else {
            viewModel.liveActivityWorkloadError = workloadTargetStatusText
            return
        }

        saveMessage = nil
        viewModel.startLiveActivityWorkload(
            configuration: DiskActivityWorkloadConfiguration(
                targetFolderURL: targetURL,
                operation: workloadOperation,
                fileSizeOption: workloadFileSizeOption,
                fileSizeBytes: fileSize,
                loopEnabled: workloadLoopEnabled
            ),
            drive: selectedDrive,
            interval: selectedInterval
        )
    }

    private func adjustWorkloadFileSizeForTarget() {
        guard workloadTargetFolderIsUsable else { return }
        guard !isWorkloadFileSizeSelectable(workloadFileSizeOption) else { return }
        if let fallback = DiskActivityWorkloadStorageValidator.largestAvailableFileSizeOption(
            operation: workloadOperation,
            availableCapacity: workloadTargetAvailableCapacity
        ) {
            workloadFileSizeRaw = fallback.rawValue
        }
    }

    private var metricGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let saveMessage {
                Label(language.t(saveMessage), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack(spacing: 10) {
                ActivityMetricTile(title: language.t("Elapsed"), value: DiskActivityChartScale.formatDuration(summary.durationSeconds), symbol: "timer")
                ActivityMetricTile(title: language.t("Samples"), value: "\(summary.sampleCount)", symbol: "point.3.connected.trianglepath.dotted")
                ActivityMetricTile(title: "\(language.operationTitle(.read)) \(language.t("Peak"))", value: DiskActivityFormatter.speed(summary.peakReadMegabytesPerSecond), symbol: "arrow.down.circle")
                ActivityMetricTile(title: "\(language.operationTitle(.write)) \(language.t("Peak"))", value: DiskActivityFormatter.speed(summary.peakWriteMegabytesPerSecond), symbol: "arrow.up.circle")
                ActivityMetricTile(title: "\(language.operationTitle(.read)) \(language.t("Average"))", value: DiskActivityFormatter.speed(summary.averageReadMegabytesPerSecond), symbol: "chart.line.downtrend.xyaxis")
                ActivityMetricTile(title: "\(language.operationTitle(.write)) \(language.t("Average"))", value: DiskActivityFormatter.speed(summary.averageWriteMegabytesPerSecond), symbol: "chart.line.uptrend.xyaxis")
            }
        }
    }

    private var historyList: some View {
        InfoPanel(title: language.t("Live Activity History"), symbol: "clock.arrow.circlepath") {
            if !selectedDriveHistory.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        hideAllVisibleActivityHistory()
                    } label: {
                        Label(language.t("Hide All"), systemImage: "eye.slash")
                    }
                    .controlSize(.small)
                    .help(language.t("Hide All"))
                }
            }

            if selectedDriveHistory.isEmpty {
                Text(selectedDriveHiddenHistory.isEmpty ? language.t("No saved activity records yet.") : language.t("No visible activity records. Hidden activity records can be restored below."))
                    .foregroundStyle(.secondary)
            } else {
                activityHistoryRows(selectedDriveHistory, isHidden: false)
            }

            if !selectedDriveHiddenHistory.isEmpty {
                hiddenActivityHistoryDisclosure
            }
        }
    }

    @ViewBuilder
    private func activityHistoryRows(_ items: [DiskActivityHistoryRecord], isHidden: Bool) -> some View {
        if items.count > activityHistoryScrollThreshold {
            ScrollView(.vertical) {
                activityHistoryRowsContent(items, isHidden: isHidden)
            }
            .frame(height: CGFloat(activityHistoryScrollThreshold) * activityHistoryRowHeight)
            .scrollIndicators(.visible)
        } else {
            activityHistoryRowsContent(items, isHidden: isHidden)
        }
    }

    private func activityHistoryRowsContent(_ items: [DiskActivityHistoryRecord], isHidden: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                activityHistoryRow(item, isHidden: isHidden)
                    .padding(.vertical, 8)
                if index < items.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var hiddenActivityHistoryDisclosure: some View {
        DisclosureGroup(isExpanded: $showHiddenActivityHistory) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(language.t("Hidden records remain in the local database and can be restored here."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        restoreAllHiddenActivityHistory()
                    } label: {
                        Label(language.t("Restore All"), systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.small)
                }

                activityHistoryRows(selectedDriveHiddenHistory, isHidden: true)
            }
            .padding(.top, 8)
        } label: {
            Label(language.t("Manage Hidden Records"), systemImage: "eye.slash")
                .font(.headline)
        }
        .padding(.top, 8)
    }

    private func activityHistoryRow(_ item: DiskActivityHistoryRecord, isHidden: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.endedAt.formatted(date: .abbreviated, time: .standard))
                Text("\(language.t("Elapsed")) \(DiskActivityChartScale.formatDuration(item.durationSeconds)) · \(item.sampleCount) \(language.t("samples")) · \(item.sampleInterval.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(language.operationTitle(.read)) \(DiskActivityFormatter.speed(item.peakReadMegabytesPerSecond))")
                Text("\(language.operationTitle(.write)) \(DiskActivityFormatter.speed(item.peakWriteMegabytesPerSecond))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Button {
                selectedIntervalSeconds = item.sampleInterval.seconds
                saveMessage = nil
                viewModel.loadLiveActivityRecord(item)
            } label: {
                Image(systemName: "chart.xyaxis.line")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help(language.t("Load Chart"))
            .disabled(viewModel.isLiveActivityMonitoring)

            activityHistoryVisibilityButton(isHidden: isHidden) {
                if isHidden {
                    restoreActivityHistory(item)
                } else {
                    hideActivityHistory(item)
                }
            }
        }
    }

    private func activityHistoryVisibilityButton(isHidden: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isHidden ? "arrow.uturn.backward" : "eye.slash")
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .help(language.t(isHidden ? "Restore" : "Hide from history"))
        .accessibilityLabel(language.t(isHidden ? "Restore" : "Hide from history"))
    }

    private func hideActivityHistory(_ item: DiskActivityHistoryRecord) {
        HistoryVisibility.hide(item)
        saveHistoryVisibilityChange()
    }

    private func restoreActivityHistory(_ item: DiskActivityHistoryRecord) {
        HistoryVisibility.restore(item)
        saveHistoryVisibilityChange()
    }

    private func restoreAllHiddenActivityHistory() {
        HistoryVisibility.restoreAll(selectedDriveHiddenHistory)
        saveHistoryVisibilityChange()
    }

    private func hideAllVisibleActivityHistory() {
        HistoryVisibility.hideAll(selectedDriveHistory, driveID: selectedDrive.id)
        saveHistoryVisibilityChange()
    }

    private func saveHistoryVisibilityChange() {
        try? modelContext.save()
    }

    private func saveActivityHistory() {
        let start = viewModel.liveActivityStartedAt ?? viewModel.liveActivitySamples.first?.timestamp ?? Date()
        let end = viewModel.liveActivityEndedAt ?? viewModel.liveActivitySamples.last?.timestamp ?? Date()
        let record = DiskActivityHistoryRecord(
            drive: selectedDrive,
            samples: viewModel.liveActivitySamples,
            sampleInterval: selectedInterval,
            startedAt: start,
            endedAt: end
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
            saveMessage = "Activity record saved to history."
        } catch {
            saveMessage = "Could not save activity record."
        }
    }
}

private struct ActivityMetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct BenchmarkView: View {
    let drive: DriveDevice
    @ObservedObject var viewModel: DITViewModel
    let saveResults: () -> Void
    @Environment(\.appLanguage) private var language

    @AppStorage("benchmarkTargetFolder") private var targetFolderPath = ""
    @AppStorage("benchmarkRunCount") private var selectedRunCount = BenchmarkProfile.defaultRuns
    @AppStorage("benchmarkFileSizeBytes") private var selectedFileSizeBytes = Int(BenchmarkProfile.defaultTestSize)
    @AppStorage("benchmarkDataPattern") private var selectedDataPatternRaw = BenchmarkProfile.defaultDataPattern.rawValue
    @AppStorage("benchmarkUsesTrimmedAverage") private var usesTrimmedAverage = BenchmarkProfile.defaultUsesTrimmedAverage
    @AppStorage("benchmarkCustomRowsJSON") private var customRowsJSON = ""
    @AppStorage("benchmarkCustomEngine") private var customEngineRaw = BenchmarkEngine.synchronous.rawValue
    @AppStorage("benchmarkCustomExecutionMode") private var customExecutionModeRaw = BenchmarkExecutionMode.finite.rawValue
    @State private var selectedProfileID = BenchmarkProfile.default.id
    @State private var confirmWrite = false
    private let progressContentLeadingInset: CGFloat = 6

    private var baseProfile: BenchmarkProfile {
        let preset = BenchmarkProfile.presets.first(where: { $0.id == selectedProfileID }) ?? .default
        if preset.baseProfileID == "custom" {
            return BenchmarkProfile.custom(
                rows: customRows,
                engine: selectedCustomEngine,
                executionMode: selectedCustomExecutionMode
            )
        }
        return preset
    }

    private var profile: BenchmarkProfile {
        baseProfile.configured(
            runs: selectedRunCount,
            fileSizeBytes: selectedBenchmarkFileSizeBytes,
            dataPattern: selectedDataPattern,
            usesTrimmedAverage: usesTrimmedAverage
        )
    }

    private var selectedProfileIsLooping: Bool {
        baseProfile.executionMode == .loopUntilCancelled
    }

    private var selectedProfileIsCustom: Bool {
        selectedProfileID == BenchmarkProfile.custom.id
    }

    private var selectedBenchmarkFileSizeBytes: Int64 {
        Int64(selectedFileSizeBytes)
    }

    private var selectedDataPattern: BenchmarkDataPattern {
        BenchmarkDataPattern(rawValue: selectedDataPatternRaw) ?? BenchmarkProfile.defaultDataPattern
    }

    private var selectedCustomEngine: BenchmarkEngine {
        get {
            BenchmarkEngine(rawValue: customEngineRaw) ?? .synchronous
        }
        nonmutating set {
            customEngineRaw = newValue.rawValue
        }
    }

    private var selectedCustomExecutionMode: BenchmarkExecutionMode {
        get {
            BenchmarkExecutionMode(rawValue: customExecutionModeRaw) ?? .finite
        }
        nonmutating set {
            customExecutionModeRaw = newValue.rawValue
        }
    }

    private var customRows: [BenchmarkCustomRow] {
        get {
            BenchmarkCustomRow.decodeList(from: customRowsJSON)
        }
        nonmutating set {
            customRowsJSON = BenchmarkCustomRow.encodeList(newValue)
        }
    }

    private var customRowsBinding: Binding<[BenchmarkCustomRow]> {
        Binding {
            customRows
        } set: { nextRows in
            customRows = nextRows
        }
    }

    private var customEngineBinding: Binding<BenchmarkEngine> {
        Binding {
            selectedCustomEngine
        } set: { nextEngine in
            selectedCustomEngine = nextEngine
        }
    }

    private var customExecutionModeBinding: Binding<BenchmarkExecutionMode> {
        Binding {
            selectedCustomExecutionMode
        } set: { nextMode in
            selectedCustomExecutionMode = nextMode
        }
    }

    private var configurationDescription: BenchmarkConfigurationDescription {
        language.benchmarkConfigurationDescription(
            profile: baseProfile,
            runs: profile.runs,
            fileSizeBytes: profile.testFileSizeBytes,
            dataPattern: selectedDataPattern,
            usesTrimmedAverage: profile.usesTrimmedAverage
        )
    }

    private var driveResults: [BenchmarkResult] {
        viewModel.benchmarkResults.filter { $0.driveID == drive.id }
    }

    private var profileResults: [BenchmarkResult] {
        driveResults.filter { $0.profileID == profile.id }
    }

    private var targetFolderURL: URL? {
        guard !targetFolderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: targetFolderPath, isDirectory: true)
    }

    private var targetFolderIsUsable: Bool {
        guard !targetFolderPath.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: targetFolderPath, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isWritableFile(atPath: targetFolderPath)
    }

    private var targetFolderAvailableCapacity: Int64 {
        guard targetFolderIsUsable, let targetFolderURL else { return 0 }
        return BenchmarkStorageValidator.availableCapacity(for: targetFolderURL)
    }

    private var selectedFileSizeHasSpace: Bool {
        guard targetFolderIsUsable else { return false }
        return BenchmarkStorageValidator.isRequiredSpaceAvailable(for: profile, availableCapacity: targetFolderAvailableCapacity)
    }

    private var hasAnyAvailableFileSize: Bool {
        guard targetFolderIsUsable else { return false }
        return BenchmarkProfile.fileSizeOptions.contains { isFileSizeSelectable($0) }
    }

    private var canRunBenchmark: Bool {
        targetFolderIsUsable && selectedFileSizeHasSpace && !viewModel.isBenchmarking
    }

    private var targetFolderStatusIsReady: Bool {
        targetFolderIsUsable && selectedFileSizeHasSpace
    }

    private var targetFolderDriveMismatch: Bool {
        guard targetFolderIsUsable else { return false }
        return !BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(targetFolderPath, drive: drive)
    }

    private var targetFolderStatusSymbol: String {
        targetFolderStatusIsReady && !targetFolderDriveMismatch ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var targetFolderStatusColor: Color {
        targetFolderStatusIsReady && !targetFolderDriveMismatch ? .green : .orange
    }

    private var benchmarkConfirmationMessage: String {
        var message = "\(language.t("Write tests can temporarily use free space and stress storage."))\n\(language.benchmarkConfirmationConfiguration(profile: profile, runs: profile.runs, fileSizeBytes: profile.testFileSizeBytes, dataPattern: selectedDataPattern, usesTrimmedAverage: profile.usesTrimmedAverage))\n\(language.t("Write target folder:"))\n\(targetFolderPath)"
        if targetFolderDriveMismatch {
            message += "\n\(language.t("Benchmark will measure the target folder volume, not the selected drive."))"
        }
        return message
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                benchmarkHeader
                benchmarkControls
                targetFolderControl
                if shouldShowProgressAndErrors {
                    progressAndErrors
                }
                BenchmarkResultMatrixView(profile: profile, results: profileResults)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            adjustSelectedFileSizeForTarget()
        }
        .onChange(of: targetFolderPath) { _, _ in
            adjustSelectedFileSizeForTarget()
        }
        .onChange(of: customExecutionModeRaw) { _, _ in
            adjustSelectedFileSizeForTarget()
        }
        .onChange(of: customRowsJSON) { _, _ in
            adjustSelectedFileSizeForTarget()
        }
        .confirmationDialog(language.t("Benchmark writes a complete temporary test file to the selected target folder."), isPresented: $confirmWrite) {
            Button(language.t("Run Benchmark"), role: .destructive) {
                Task { await viewModel.runBenchmark(profile: profile, volumePath: targetFolderPath) }
            }
            Button(language.t("Cancel"), role: .cancel) {}
        } message: {
            Text(benchmarkConfirmationMessage)
        }
    }

    private var benchmarkHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.t("Benchmark"))
                    .font(.largeTitle.bold())
                Text(drive.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(language.benchmarkFooter(
                testCount: profile.tests.count,
                fileSize: profile.testFileSizeBytes,
                runs: profile.runs,
                dataPattern: selectedDataPattern,
                usesTrimmedAverage: profile.usesTrimmedAverage,
                executionMode: profile.executionMode,
                engine: profile.engine
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var benchmarkControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.t("Profile"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 154, alignment: .leading)
                    Picker("", selection: $selectedProfileID) {
                        ForEach(BenchmarkProfile.presets) { profile in
                            Text(language.profileName(profile)).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 154, alignment: .leading)
                    .disabled(viewModel.isBenchmarking)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(language.t("Runs"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    Picker("", selection: $selectedRunCount) {
                        ForEach(BenchmarkProfile.runCountOptions, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 72, alignment: .leading)
                    .disabled(viewModel.isBenchmarking || selectedProfileIsLooping)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(language.t("Test Size"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 112, alignment: .leading)
                    Picker("", selection: $selectedFileSizeBytes) {
                        ForEach(BenchmarkProfile.fileSizeOptions, id: \.self) { size in
                            Text(formatBenchmarkFileSize(size))
                                .tag(Int(size))
                                .disabled(!isFileSizeSelectable(size))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 112, alignment: .leading)
                    .disabled(viewModel.isBenchmarking)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(language.t("Data Pattern"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 142, alignment: .leading)
                    Picker("", selection: $selectedDataPatternRaw) {
                        ForEach(BenchmarkDataPattern.allCases) { pattern in
                            Text(language.benchmarkDataPatternTitle(pattern)).tag(pattern.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 142, alignment: .leading)
                    .disabled(viewModel.isBenchmarking)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(language.t("Trim Outliers"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 116, alignment: .leading)
                    Picker("", selection: $usesTrimmedAverage) {
                        Text(language.t("Off")).tag(false)
                        Text(language.t("On")).tag(true)
                    }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 116, height: 28, alignment: .leading)
                        .help(language.t("Run two extra measured passes, discard fastest and slowest, then average the rest."))
                        .disabled(viewModel.isBenchmarking || selectedProfileIsLooping)
                }

                Spacer(minLength: 12)

                Button {
                    requestBenchmarkStart()
                } label: {
                    Label(language.t("Run"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRunBenchmark)

                Button {
                    viewModel.cancelBenchmark()
                } label: {
                    Label(language.t("Cancel"), systemImage: "stop.fill")
                }
                .disabled(!viewModel.isBenchmarking)

                Button {
                    saveResults()
                } label: {
                    Label(language.t("Save Results"), systemImage: "tray.and.arrow.down")
                }
                .disabled(driveResults.isEmpty)
            }

            BenchmarkConfigurationDescriptionView(description: configurationDescription)
            if selectedProfileIsCustom {
                CustomBenchmarkRowsEditor(
                    rows: customRowsBinding,
                    engine: customEngineBinding,
                    executionMode: customExecutionModeBinding,
                    isDisabled: viewModel.isBenchmarking
                )
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }

    private var targetFolderControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(language.t("Target Folder"), systemImage: "folder")
                    .font(.headline)

                Button {
                    chooseTargetFolder()
                } label: {
                    Label(targetFolderPath.isEmpty ? language.t("Choose Target Folder") : language.t("Change Folder"), systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(.bordered)

                Label(targetFolderStatusText, systemImage: targetFolderStatusSymbol)
                    .font(.caption)
                    .foregroundStyle(targetFolderStatusColor)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }

            Text(targetFolderPath.isEmpty ? language.t("No target folder selected") : targetFolderPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if targetFolderDriveMismatch {
                Label(language.t("Benchmark will measure the target folder volume, not the selected drive."), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }

    private var targetFolderStatusText: String {
        if targetFolderPath.isEmpty {
            return language.t("Choose a writable target folder")
        }
        if targetFolderIsUsable, !hasAnyAvailableFileSize {
            return language.t("Not enough free space for the smallest test size")
        }
        if targetFolderIsUsable, !selectedFileSizeHasSpace {
            return language.t("Selected test size exceeds available free space")
        }
        if targetFolderDriveMismatch {
            return language.t("Target folder is writable but not on selected drive")
        }
        return targetFolderIsUsable ? language.t("Target folder is writable") : language.t("Target folder is not writable")
    }

    private var shouldShowProgressAndErrors: Bool {
        viewModel.isBenchmarking || viewModel.benchmarkError != nil || !canRunBenchmark
    }

    private var progressAndErrors: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = viewModel.benchmarkProgress, viewModel.isBenchmarking {
                VStack(alignment: .leading, spacing: 8) {
                    DiskActivityChartView(
                        title: language.t("Live Disk Activity"),
                        samples: viewModel.diskActivitySamples,
                        current: viewModel.currentDiskActivity,
                        style: .compact
                    )
                    ProgressView(value: progress.fraction)
                    Text("\(language.progressLabel(progress.currentTestLabel)): \(progressStatusText(progress))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, progressContentLeadingInset)
            }

            if let error = viewModel.benchmarkError {
                Label(language.statusMessage(error), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if !targetFolderIsUsable {
                Label(language.t("Select a target folder before starting the speed test."), systemImage: "folder.badge.plus")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else if !hasAnyAvailableFileSize {
                Label(language.t("Not enough free space for the smallest test size"), systemImage: "internaldrive")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else if !selectedFileSizeHasSpace {
                Label(language.t("Selected test size exceeds available free space"), systemImage: "internaldrive")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private func progressStatusText(_ progress: BenchmarkProgress) -> String {
        var text = language.statusMessage(progress.message)
        if progress.phaseTotalBytes > 0 {
            text += " · \(formatBenchmarkFileSize(progress.phaseCompletedBytes)) / \(formatBenchmarkFileSize(progress.phaseTotalBytes))"
        }
        return text
    }

    private func chooseTargetFolder() {
        let panel = NSOpenPanel()
        panel.title = language.t("Choose Target Folder")
        panel.message = language.t("Choose a writable folder where a temporary benchmark file can be created.")
        panel.prompt = language.t("Use Folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let targetFolderURL {
            panel.directoryURL = targetFolderURL
        } else if let fallback = drive.benchmarkMountPoint {
            panel.directoryURL = URL(fileURLWithPath: fallback, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        targetFolderPath = url.path
        viewModel.benchmarkError = nil
        adjustSelectedFileSizeForTarget()
    }

    private func requestBenchmarkStart() {
        guard validateTargetFolderForRun() else { return }
        confirmWrite = true
    }

    private func validateTargetFolderForRun() -> Bool {
        guard let targetFolderURL else {
            viewModel.benchmarkError = "Choose a writable target folder before starting."
            return false
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetFolderPath, isDirectory: &isDirectory) else {
            viewModel.benchmarkError = "Selected target folder no longer exists."
            return false
        }
        guard isDirectory.boolValue else {
            viewModel.benchmarkError = "The benchmark target must be a folder."
            return false
        }

        let probeURL = targetFolderURL.appendingPathComponent("Disk-Speed-Test-write-check-\(UUID().uuidString)")
        do {
            try Data().write(to: probeURL, options: .atomic)
            try? FileManager.default.removeItem(at: probeURL)
        } catch {
            try? FileManager.default.removeItem(at: probeURL)
            viewModel.benchmarkError = "Selected target folder is not writable."
            return false
        }

        let available = BenchmarkStorageValidator.availableCapacity(for: targetFolderURL)
        let required = BenchmarkStorageValidator.requiredSpace(for: profile)
        guard BenchmarkStorageValidator.isRequiredSpaceAvailable(for: profile, availableCapacity: available) else {
            viewModel.benchmarkError = BenchmarkError.insufficientSpace(required: required, available: available).localizedDescription
            return false
        }

        viewModel.benchmarkError = nil
        return true
    }

    private func isFileSizeSelectable(_ fileSizeBytes: Int64) -> Bool {
        guard targetFolderIsUsable else { return true }
        let candidateProfile = baseProfile.configured(
            runs: selectedRunCount,
            fileSizeBytes: fileSizeBytes,
            dataPattern: selectedDataPattern,
            usesTrimmedAverage: usesTrimmedAverage
        )
        return BenchmarkStorageValidator.isRequiredSpaceAvailable(for: candidateProfile, availableCapacity: targetFolderAvailableCapacity)
    }

    private func adjustSelectedFileSizeForTarget() {
        if let minimumSize = BenchmarkProfile.fileSizeOptions.first, Int64(selectedFileSizeBytes) < minimumSize {
            selectedFileSizeBytes = Int(minimumSize)
        }
        guard targetFolderIsUsable else { return }
        let selectedSize = Int64(selectedFileSizeBytes)
        guard !isFileSizeSelectable(selectedSize) else { return }
        if let fallback = BenchmarkProfile.fileSizeOptions.last(where: { isFileSizeSelectable($0) }) {
            selectedFileSizeBytes = Int(fallback)
        }
    }
}

private struct CustomBenchmarkRowsEditor: View {
    @Binding var rows: [BenchmarkCustomRow]
    @Binding var engine: BenchmarkEngine
    @Binding var executionMode: BenchmarkExecutionMode
    let isDisabled: Bool
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.top, 2)

            HStack(alignment: .firstTextBaseline) {
                Label(language.t("Custom Test Groups"), systemImage: "slider.horizontal.3")
                    .font(.headline)
                Text(language.t("Each group creates read/write tests; mixed adds a 30% write / 70% read item."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    addRow()
                } label: {
                    Label(language.t("Add Group"), systemImage: "plus")
                }
                .controlSize(.small)
                .disabled(isDisabled || rows.count >= BenchmarkCustomRow.maxRows)
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.t("Engine"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 132, alignment: .leading)
                    Picker("", selection: $engine) {
                        Text(language.t("Sync")).tag(BenchmarkEngine.synchronous)
                        Text(language.t("Async")).tag(BenchmarkEngine.asyncQueue)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 132)
                    .help(language.t("Async uses POSIX AIO queue depth; Sync uses worker threads with blocking file I/O."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(language.t("Loop"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 112, alignment: .leading)
                    Picker("", selection: $executionMode) {
                        Text(language.t("Off")).tag(BenchmarkExecutionMode.finite)
                        Text(language.t("On")).tag(BenchmarkExecutionMode.loopUntilCancelled)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 112)
                    .help(language.t("Loop repeats the custom groups until you stop it manually."))
                }

                Text(language.t("Loop mode ignores test count and extra trimmed testing."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(isDisabled)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(language.t("Type"))
                        .frame(width: 88, alignment: .leading)
                    Text(language.t("Block Size"))
                        .frame(width: 116, alignment: .leading)
                    Text("Q")
                        .frame(width: 62, alignment: .leading)
                    Text("T")
                        .frame(width: 62, alignment: .leading)
                    Text(language.t("Mixed"))
                        .frame(width: 112, alignment: .leading)
                    Spacer(minLength: 0)
                    Text(language.t("Delete"))
                        .frame(width: 42, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Picker("", selection: $rows[index].accessPattern) {
                            Text("SEQ").tag(BenchmarkAccessPattern.sequential)
                            Text("RND").tag(BenchmarkAccessPattern.random)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 88)

                        Picker("", selection: $rows[index].blockSizeBytes) {
                            ForEach(BenchmarkCustomRow.blockSizeOptions, id: \.self) { size in
                                Text(formatBytes(size)).tag(size)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 116)

                        Picker("", selection: $rows[index].queueDepth) {
                            ForEach(BenchmarkCustomRow.queueDepthOptions, id: \.self) { depth in
                                Text("\(depth)").tag(depth)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 62)

                        Picker("", selection: $rows[index].threads) {
                            ForEach(BenchmarkCustomRow.threadOptions, id: \.self) { threadCount in
                                Text("\(threadCount)").tag(threadCount)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 62)

                        Picker("", selection: $rows[index].includeMixed) {
                            Text(language.t("Off")).tag(false)
                            Text(language.t("On")).tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 112)

                        Text(rows[index].label.replacingOccurrences(of: "MiB", with: "M").replacingOccurrences(of: "KiB", with: "K"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            removeRow(at: index)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                        .help(language.t("Delete"))
                        .disabled(isDisabled || rows.count <= 1)
                    }
                    .disabled(isDisabled)
                }
            }

            Text(language.t("Maximum 4 groups."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addRow() {
        guard rows.count < BenchmarkCustomRow.maxRows else { return }
        rows.append(BenchmarkCustomRow.newRow(index: rows.count))
    }

    private func removeRow(at index: Int) {
        guard rows.count > 1, rows.indices.contains(index) else { return }
        rows.remove(at: index)
    }
}

private struct BenchmarkConfigurationDescriptionView: View {
    let description: BenchmarkConfigurationDescription

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(description.profileUse)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            BenchmarkConfigurationLine(text: description.runs)
            BenchmarkConfigurationLine(text: description.fileSize)
            BenchmarkConfigurationLine(text: description.dataPattern)
            BenchmarkConfigurationLine(text: description.testTerms)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BenchmarkConfigurationLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DiskActivityChartView: View {
    enum Style {
        case compact
        case expanded

        var chartHeight: CGFloat {
            switch self {
            case .compact: 92
            case .expanded: 220
            }
        }

        var yAxisWidth: CGFloat {
            switch self {
            case .compact: 54
            case .expanded: 68
            }
        }

        var font: Font {
            switch self {
            case .compact: .caption2
            case .expanded: .caption
            }
        }
    }

    let title: String
    let samples: [DiskActivitySample]
    let current: DiskActivitySample?
    let style: Style
    @Environment(\.appLanguage) private var language

    private var readSpeed: Double {
        current?.readMegabytesPerSecond ?? 0
    }

    private var writeSpeed: Double {
        current?.writeMegabytesPerSecond ?? 0
    }

    private var graphMaximumSpeed: Double {
        max(samples.flatMap { [$0.readMegabytesPerSecond, $0.writeMegabytesPerSecond] }.max() ?? 0, 1)
    }

    private var yTicks: [Double] {
        DiskActivityChartScale.yTicks(maxSpeed: graphMaximumSpeed)
    }

    private var xTicks: [DiskActivityChartTick] {
        DiskActivityChartScale.xTicks(for: samples)
    }

    private var durationSeconds: TimeInterval {
        DiskActivityChartScale.durationSeconds(for: samples)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.caption.bold())

                Spacer(minLength: 8)

                speedLegend(title: language.operationTitle(.read), value: readSpeed, color: .blue)
                speedLegend(title: language.operationTitle(.write), value: writeSpeed, color: .green)
            }

            HStack(alignment: .top, spacing: 6) {
                yAxisLabels
                    .frame(width: style.yAxisWidth, height: style.chartHeight)

                VStack(spacing: 4) {
                    Canvas { context, size in
                        let rect = CGRect(origin: .zero, size: size)
                        let background = Path(roundedRect: rect, cornerRadius: 6)
                        context.fill(background, with: .color(Color(nsColor: .controlBackgroundColor)))
                        context.stroke(background, with: .color(Color(nsColor: .separatorColor).opacity(0.45)), lineWidth: 1)

                        let plotRect = rect.insetBy(dx: 8, dy: 7)
                        drawGrid(in: plotRect, context: context)
                        drawSeries(\.readMegabytesPerSecond, color: .blue, in: plotRect, context: context, canvasWidth: size.width)
                        drawSeries(\.writeMegabytesPerSecond, color: .green, in: plotRect, context: context, canvasWidth: size.width)
                    }
                    .frame(height: style.chartHeight)

                    xAxisLabels
                }
            }
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text("\(language.operationTitle(.read)) \(DiskActivityFormatter.speed(readSpeed)), \(language.operationTitle(.write)) \(DiskActivityFormatter.speed(writeSpeed))"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var yAxisLabels: some View {
        VStack(spacing: 0) {
            ForEach(Array(yTicks.reversed()), id: \.self) { tick in
                Text(DiskActivityFormatter.speed(tick))
                    .font(style.font.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private var xAxisLabels: some View {
        HStack(spacing: 0) {
            ForEach(Array(xTicks.enumerated()), id: \.offset) { index, tick in
                Text(tick.label)
                    .font(style.font.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == xTicks.count - 1 ? .trailing : .center))
            }
        }
        .frame(height: 14)
    }

    private func speedLegend(title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(title) \(DiskActivityFormatter.speed(value))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func drawGrid(in rect: CGRect, context: GraphicsContext) {
        var path = Path()
        let maxSpeed = yTicks.last ?? 1
        for tick in yTicks {
            let fraction = maxSpeed > 0 ? tick / maxSpeed : 0
            let y = rect.maxY - rect.height * CGFloat(fraction)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        if durationSeconds > 0 {
            for tick in xTicks {
                let fraction = tick.value / durationSeconds
                let x = rect.minX + rect.width * CGFloat(fraction)
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        }
        context.stroke(path, with: .color(Color(nsColor: .separatorColor).opacity(0.78)), lineWidth: 0.8)
    }

    private func drawSeries(
        _ keyPath: KeyPath<DiskActivitySample, Double>,
        color: Color,
        in rect: CGRect,
        context: GraphicsContext,
        canvasWidth: CGFloat
    ) {
        guard samples.count >= 2 else {
            drawBaseline(color: color, in: rect, context: context)
            return
        }

        let maxSpeed = max(yTicks.last ?? graphMaximumSpeed, 1)
        let visibleSamples = downsampledSamples(maxCount: max(2, Int(canvasWidth)))
        let firstTimestamp = samples.first?.timestamp ?? visibleSamples.first?.timestamp ?? Date()
        let duration = max(durationSeconds, 0.0001)
        var path = Path()

        for (index, sample) in visibleSamples.enumerated() {
            let value = max(0, sample[keyPath: keyPath])
            let fraction = min(1, value / maxSpeed)
            let elapsed = max(0, sample.timestamp.timeIntervalSince(firstTimestamp))
            let point = CGPoint(
                x: rect.minX + rect.width * CGFloat(min(1, elapsed / duration)),
                y: rect.maxY - rect.height * CGFloat(fraction)
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    private func drawBaseline(color: Color, in rect: CGRect, context: GraphicsContext) {
        var path = Path()
        let y = rect.maxY
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        context.stroke(path, with: .color(color.opacity(0.35)), lineWidth: 1)
    }

    private func downsampledSamples(maxCount: Int) -> [DiskActivitySample] {
        guard samples.count > maxCount, maxCount > 2 else { return samples }
        let step = Double(samples.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { index in
            samples[min(samples.count - 1, Int((Double(index) * step).rounded()))]
        }
    }
}

private struct BenchmarkResultMatrixView: View {
    let profile: BenchmarkProfile
    let results: [BenchmarkResult]
    @Environment(\.appLanguage) private var language

    private var hasMixedColumn: Bool {
        profile.tests.contains { $0.operation == .mixed } || results.contains { $0.operation == .mixed }
    }

    private var rowLabels: [String] {
        var labels: [String] = []
        for test in profile.tests {
            let label = Self.normalizedLabel(test.label)
            if !labels.contains(label) {
                labels.append(label)
            }
        }
        return labels
    }

    private var maximumSpeed: Double {
        max(results.map(\.bestMegabytesPerSecond).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CrystalHeaderCell(title: language.t("Test"))
                    .frame(width: 146)
                CrystalHeaderCell(title: "\(language.operationTitle(.read)) MB/s")
                CrystalHeaderCell(title: "\(language.operationTitle(.write)) MB/s")
                if hasMixedColumn {
                    CrystalHeaderCell(title: "\(language.operationTitle(.mixed)) MB/s")
                }
            }

            ForEach(rowLabels, id: \.self) { label in
                HStack(spacing: 8) {
                    CrystalTestLabelCell(title: Self.displayLabel(label))
                        .frame(width: 146)
                    CrystalSpeedCell(result: result(for: label, operation: .read), maximumSpeed: maximumSpeed)
                    CrystalSpeedCell(result: result(for: label, operation: .write), maximumSpeed: maximumSpeed)
                    if hasMixedColumn {
                        CrystalSpeedCell(result: result(for: label, operation: .mixed), maximumSpeed: maximumSpeed)
                    }
                }
            }

            if results.isEmpty {
                Label(language.t("Run a benchmark profile to populate the read/write matrix."), systemImage: "speedometer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }

    private func result(for label: String, operation: BenchmarkOperation) -> BenchmarkResult? {
        results
            .filter { Self.normalizedLabel($0.testLabel) == label && $0.operation == operation }
            .max { $0.measuredAt < $1.measuredAt }
    }

    private static func normalizedLabel(_ label: String) -> String {
        label.hasSuffix(" Mix") ? String(label.dropLast(4)) : label
    }

    private static func displayLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "MiB", with: "M")
            .replacingOccurrences(of: "KiB", with: "K")
    }
}

private struct CrystalHeaderCell: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct CrystalTestLabelCell: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .monospaced()
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(.horizontal, 8)
            .background(
                LinearGradient(
                    colors: [
                        Color.green.opacity(0.92),
                        Color.green.opacity(0.58)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .foregroundStyle(.black.opacity(0.82))
    }
}

private struct CrystalSpeedCell: View {
    let result: BenchmarkResult?
    let maximumSpeed: Double
    @Environment(\.appLanguage) private var language

    private var fillFraction: Double {
        guard let result else { return 0 }
        return min(1, max(0, result.bestMegabytesPerSecond / maximumSpeed))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.green.opacity(result == nil ? 0.05 : 0.2))
                    .frame(width: proxy.size.width * fillFraction)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .trailing, spacing: 4) {
                Text(speedText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                VStack(alignment: .trailing, spacing: 1) {
                    ForEach(Array(detailLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minWidth: 150, maxWidth: .infinity, minHeight: 76)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.separator.opacity(0.4), lineWidth: 1)
        }
    }

    private var speedText: String {
        guard let result else { return "--" }
        return String(format: "%.2f", result.bestMegabytesPerSecond)
    }

    private var detailLines: [String] {
        guard let result else { return ["MB/s"] }
        if result.transferMegabytesPerSecond != nil || result.flushMilliseconds != nil {
            var lines: [String] = []
            if let transfer = result.transferMegabytesPerSecond {
                lines.append(String(format: "%@ %.0f MB/s", transferLabel, transfer))
            }
            if let flush = result.flushMilliseconds {
                lines.append(String(format: "%@ %.0f ms", flushLabel, flush))
            }
            if !lines.isEmpty {
                return lines
            }
        }
        return [String(format: "MB/s   %.0f IOPS   %.0f us", result.iops, result.latencyMicroseconds)]
    }

    private var transferLabel: String {
        language == .simplifiedChinese ? "传输" : "transfer"
    }

    private var flushLabel: String {
        language == .simplifiedChinese ? "刷盘" : "fsync"
    }
}

private struct SelfTestSummaryView: View {
    let snapshot: SmartSnapshot?
    @Binding var isExpanded: Bool
    @Environment(\.appLanguage) private var language

    private var selfTestStatus: String? {
        snapshot?.selfTestStatus?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSelfTestLog: Bool {
        guard let selfTestStatus else { return false }
        return !selfTestStatus.isEmpty
    }

    var body: some View {
        InfoPanel(title: language.t("Self-Tests"), symbol: "stethoscope") {
            if hasSelfTestLog, let selfTestStatus {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(language.statusMessage(selfTestStatus))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Label(language.t("Short and long self-test execution requires smartctl support for this drive. This version displays available logs and avoids starting destructive or vendor-specific tests automatically."), systemImage: "terminal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                } label: {
                    Label(language.t("Self-test log available"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Label(language.t("No self-test log is available from current providers."), systemImage: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExternalSupportView: View {
    let status: ExternalSupportStatus
    let refresh: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(language.t("External Drive SMART"))
                    .font(.title2.bold())
                Spacer()
                Button {
                    refresh()
                } label: {
                    Label(language.t("Verify"), systemImage: "arrow.clockwise")
                }
            }
            InfoPanel(title: language.t("Status"), symbol: "externaldrive.connected.to.line.below") {
                Label(language.t("Use this when SMART data is unavailable or limited for an external drive."), systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StatusLine(title: "smartctl", isOn: status.smartctlInstalled)
                StatusLine(title: "SAT SMART Driver", isOn: status.satDriverInstalled)
                Text(language.statusMessage(status.message))
                    .foregroundStyle(.secondary)
            }
            InfoPanel(title: language.t("Driver Paths"), symbol: "shippingbox") {
                if status.driverPaths.isEmpty {
                    Text(language.t("No SAT SMART Driver bundle was detected in standard extension locations."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(status.driverPaths, id: \.self) { path in
                        Text(path).monospaced()
                    }
                }
            }
            Link(destination: URL(string: "https://github.com/kasbert/OS-X-SAT-SMART-Driver")!) {
                Label(language.t("Open SAT SMART Driver project"), systemImage: "safari")
            }
        }
    }
}

private struct HistoryReportView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    let benchmarkResults: [BenchmarkResult]
    let smartHistory: [SmartHistoryRecord]
    let benchmarkHistory: [BenchmarkHistoryRecord]
    let activityHistory: [DiskActivityHistoryRecord]
    @AppStorage("includeSerialsInReports") private var includeSerialsInReports = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var showHiddenHistory = false
    private let historyScrollThreshold = 10
    private let historyRowHeight: CGFloat = 58

    private var visibleSmartHistory: [SmartHistoryRecord] {
        HistoryVisibility.visible(smartHistory)
    }

    private var hiddenSmartHistory: [SmartHistoryRecord] {
        HistoryVisibility.hidden(smartHistory)
    }

    private var visibleBenchmarkHistory: [BenchmarkHistoryRecord] {
        HistoryVisibility.visible(benchmarkHistory)
    }

    private var hiddenBenchmarkHistory: [BenchmarkHistoryRecord] {
        HistoryVisibility.hidden(benchmarkHistory)
    }

    private var visibleActivityHistory: [DiskActivityHistoryRecord] {
        HistoryVisibility.visible(activityHistory)
    }

    private var hiddenActivityHistory: [DiskActivityHistoryRecord] {
        HistoryVisibility.hidden(activityHistory)
    }

    private var hasHiddenHistory: Bool {
        !hiddenSmartHistory.isEmpty || !hiddenBenchmarkHistory.isEmpty || !hiddenActivityHistory.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(language.t("History & Reports"))
                        .font(.title2.bold())
                    Spacer()
                    Toggle(language.t("Include serials"), isOn: $includeSerialsInReports)
                        .toggleStyle(.checkbox)
                }

                HStack {
                    Button {
                        copy(ReportExporter.jsonReport(drive: drive, snapshot: snapshot, benchmarkResults: benchmarkResults, includeSerial: includeSerialsInReports))
                    } label: {
                        Label(language.t("Copy JSON"), systemImage: "doc.on.doc")
                    }
                    Button {
                        copy(ReportExporter.csvReport(results: benchmarkResults))
                    } label: {
                        Label(language.t("Copy CSV"), systemImage: "tablecells")
                    }
                    Button {
                        copy(ReportExporter.textReport(drive: drive, snapshot: snapshot, results: benchmarkResults, includeSerial: includeSerialsInReports))
                    } label: {
                        Label(language.t("Copy Text"), systemImage: "text.page")
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    historyPanel(
                        title: language.t("SMART Snapshots"),
                        symbol: "clock",
                        count: visibleSmartHistory.count,
                        emptyText: hiddenSmartHistory.isEmpty ? language.t("No saved snapshots yet.") : language.t("No visible snapshots. Hidden snapshots can be restored below."),
                        hideAll: { hideAllHistory(visibleSmartHistory) }
                    ) {
                        historyRows(visibleSmartHistory) { item in
                            smartHistoryRow(item, isHidden: false)
                        }
                    }

                    historyPanel(
                        title: language.t("Benchmark Runs"),
                        symbol: "chart.xyaxis.line",
                        count: visibleBenchmarkHistory.count,
                        emptyText: hiddenBenchmarkHistory.isEmpty ? language.t("No saved benchmark results yet.") : language.t("No visible benchmark results. Hidden benchmark results can be restored below."),
                        hideAll: { hideAllHistory(visibleBenchmarkHistory) }
                    ) {
                        historyRows(visibleBenchmarkHistory) { item in
                            benchmarkHistoryRow(item, isHidden: false)
                        }
                    }

                    historyPanel(
                        title: language.t("Live Activity History"),
                        symbol: "waveform.path.ecg.rectangle",
                        count: visibleActivityHistory.count,
                        emptyText: hiddenActivityHistory.isEmpty ? language.t("No saved activity records yet.") : language.t("No visible activity records. Hidden activity records can be restored below."),
                        hideAll: { hideAllHistory(visibleActivityHistory) }
                    ) {
                        historyRows(visibleActivityHistory) { item in
                            activityHistoryRow(item, isHidden: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                if hasHiddenHistory {
                    hiddenHistoryDisclosure
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var historyScrollHeight: CGFloat {
        CGFloat(historyScrollThreshold) * historyRowHeight
    }

    @ViewBuilder
    private func historyPanel<Rows: View>(
        title: String,
        symbol: String,
        count: Int,
        emptyText: String,
        hideAll: @escaping () -> Void,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                Spacer(minLength: 8)
                Button(action: hideAll) {
                    Label(language.t("Hide All"), systemImage: "eye.slash")
                }
                .controlSize(.small)
                .disabled(count == 0)
                .help(language.t("Hide All"))
            }

            if count == 0 {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else if count > historyScrollThreshold {
                ScrollView(.vertical) {
                    rows()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: historyScrollHeight)
                .scrollIndicators(.visible)
            } else {
                rows()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .frame(minWidth: 260, maxWidth: .infinity, alignment: .topLeading)
    }

    private func historyRows<Record: Identifiable, Row: View>(
        _ items: [Record],
        @ViewBuilder row: @escaping (Record) -> Row
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                    .padding(.vertical, 8)
                if index < items.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var hiddenHistoryDisclosure: some View {
        DisclosureGroup(isExpanded: $showHiddenHistory) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(language.t("Hidden records remain in the local database and can be restored here."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        restoreAllHiddenHistory()
                    } label: {
                        Label(language.t("Restore All"), systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.small)
                }

                if !hiddenSmartHistory.isEmpty {
                    Text(language.t("SMART Snapshots"))
                        .font(.subheadline.bold())
                    ForEach(hiddenSmartHistory) { item in
                        smartHistoryRow(item, isHidden: true)
                        Divider()
                    }
                }

                if !hiddenBenchmarkHistory.isEmpty {
                    Text(language.t("Benchmark Runs"))
                        .font(.subheadline.bold())
                    ForEach(hiddenBenchmarkHistory) { item in
                        benchmarkHistoryRow(item, isHidden: true)
                        Divider()
                    }
                }

                if !hiddenActivityHistory.isEmpty {
                    Text(language.t("Live Activity History"))
                        .font(.subheadline.bold())
                    ForEach(hiddenActivityHistory) { item in
                        activityHistoryRow(item, isHidden: true)
                        Divider()
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Label(language.t("Manage Hidden Records"), systemImage: "eye.slash")
                .font(.headline)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }

    private func smartHistoryRow(_ item: SmartHistoryRecord, isHidden: Bool) -> some View {
        HStack {
            HealthBadge(status: item.health, compact: true)
            VStack(alignment: .leading) {
                Text(item.capturedAt.formatted(date: .abbreviated, time: .standard))
                Text(language.statusMessage(item.summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            historyVisibilityButton(isHidden: isHidden) {
                if isHidden {
                    restoreHistory(item)
                } else {
                    hideHistory(item)
                }
            }
        }
    }

    private func benchmarkHistoryRow(_ item: BenchmarkHistoryRecord, isHidden: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(item.testLabel) \(language.operationTitle(item.operation))")
                Text(item.measuredAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%.2f MB/s", item.bestMegabytesPerSecond))
                .monospacedDigit()
            historyVisibilityButton(isHidden: isHidden) {
                if isHidden {
                    restoreHistory(item)
                } else {
                    hideHistory(item)
                }
            }
        }
    }

    private func activityHistoryRow(_ item: DiskActivityHistoryRecord, isHidden: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.endedAt.formatted(date: .abbreviated, time: .standard))
                Text("\(DiskActivityChartScale.formatDuration(item.durationSeconds)) · \(item.sampleCount) \(language.t("samples")) · \(item.sampleInterval.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(language.operationTitle(.read)) \(DiskActivityFormatter.speed(item.peakReadMegabytesPerSecond))")
                Text("\(language.operationTitle(.write)) \(DiskActivityFormatter.speed(item.peakWriteMegabytesPerSecond))")
            }
            .font(.caption.monospacedDigit())
            historyVisibilityButton(isHidden: isHidden) {
                if isHidden {
                    restoreHistory(item)
                } else {
                    hideHistory(item)
                }
            }
        }
    }

    private func historyVisibilityButton(isHidden: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isHidden ? "arrow.uturn.backward" : "eye.slash")
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .help(language.t(isHidden ? "Restore" : "Hide from history"))
        .accessibilityLabel(language.t(isHidden ? "Restore" : "Hide from history"))
    }

    private func hideHistory<T: HistoryDisplayRecord>(_ item: T) {
        HistoryVisibility.hide(item)
        saveHistoryVisibilityChange()
    }

    private func restoreHistory<T: HistoryDisplayRecord>(_ item: T) {
        HistoryVisibility.restore(item)
        saveHistoryVisibilityChange()
    }

    private func hideAllHistory<T: HistoryDisplayRecord>(_ records: [T]) {
        HistoryVisibility.hideAll(records)
        saveHistoryVisibilityChange()
    }

    private func restoreAllHiddenHistory() {
        HistoryVisibility.restoreAll(hiddenSmartHistory)
        HistoryVisibility.restoreAll(hiddenBenchmarkHistory)
        HistoryVisibility.restoreAll(hiddenActivityHistory)
        saveHistoryVisibilityChange()
    }

    private func saveHistoryVisibilityChange() {
        try? modelContext.save()
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private struct InfoPanel<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct HealthBadge: View {
    let status: HealthStatus
    var compact = false
    @Environment(\.appLanguage) private var language

    var body: some View {
        Label(language.healthBadgeTitle(status, compact: compact), systemImage: status.symbolName)
            .font(compact ? .caption.bold() : .headline)
            .foregroundStyle(status.tint)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 4 : 8)
            .background(status.tint.opacity(0.12), in: Capsule())
    }
}

private struct StatusLine: View {
    let title: String
    let isOn: Bool
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack {
            Image(systemName: isOn ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isOn ? .green : .secondary)
            Text(title)
            Spacer()
            Text(isOn ? language.t("Detected") : language.t("Not detected"))
                .foregroundStyle(.secondary)
        }
    }
}

private extension HealthStatus {
    var tint: Color {
        switch self {
        case .good: .green
        case .warning: .yellow
        case .preFail: .orange
        case .failed: .red
        case .unavailable: .secondary
        }
    }
}

private extension ProviderState {
    var tint: Color {
        switch self {
        case .available: .green
        case .limited: .yellow
        case .unavailable: .secondary
        case .failed: .red
        }
    }

    var symbolName: String {
        switch self {
        case .available: "checkmark.circle.fill"
        case .limited: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }
}

#Preview {
    ContentView(viewModel: .preview)
        .modelContainer(for: [SmartHistoryRecord.self, BenchmarkHistoryRecord.self, DiskActivityHistoryRecord.self, AppSettingsRecord.self], inMemory: true)
}
