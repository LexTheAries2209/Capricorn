import AppKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: DITViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SmartHistoryRecord.capturedAt, order: .reverse) private var smartHistory: [SmartHistoryRecord]
    @Query(sort: \BenchmarkHistoryRecord.measuredAt, order: .reverse) private var benchmarkHistory: [BenchmarkHistoryRecord]
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
    let saveSnapshot: (String?) -> String
    let saveBenchmarkResults: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        TabView {
            OverviewView(drive: drive, snapshot: snapshot)
                .tabItem { Label(language.t("Overview"), systemImage: "gauge.with.dots.needle.bottom.50percent") }
            SmartAttributesView(drive: drive, snapshot: snapshot, saveSnapshot: saveSnapshot)
                .tabItem { Label("SMART", systemImage: "list.bullet.rectangle") }
            BenchmarkView(drive: drive, viewModel: viewModel, saveResults: saveBenchmarkResults)
                .tabItem { Label(language.t("Benchmark"), systemImage: "speedometer") }
            ExternalSupportView(status: viewModel.externalSupport, refresh: viewModel.refreshExternalSupport)
                .tabItem { Label(language.t("External"), systemImage: "externaldrive.connected.to.line.below") }
            HistoryReportView(
                drive: drive,
                snapshot: snapshot,
                benchmarkResults: viewModel.benchmarkResults.filter { $0.driveID == drive.id },
                smartHistory: smartHistory,
                benchmarkHistory: benchmarkHistory
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
    @State private var selectedProfileID = BenchmarkProfile.default.id
    @State private var confirmWrite = false
    private let progressContentLeadingInset: CGFloat = 6

    private var baseProfile: BenchmarkProfile {
        BenchmarkProfile.presets.first(where: { $0.id == selectedProfileID }) ?? .default
    }

    private var profile: BenchmarkProfile {
        baseProfile.configured(
            runs: selectedRunCount,
            fileSizeBytes: selectedBenchmarkFileSizeBytes,
            dataPattern: selectedDataPattern,
            usesTrimmedAverage: usesTrimmedAverage
        )
    }

    private var selectedBenchmarkFileSizeBytes: Int64 {
        Int64(selectedFileSizeBytes)
    }

    private var selectedDataPattern: BenchmarkDataPattern {
        BenchmarkDataPattern(rawValue: selectedDataPatternRaw) ?? BenchmarkProfile.defaultDataPattern
    }

    private var configurationDescription: BenchmarkConfigurationDescription {
        language.benchmarkConfigurationDescription(
            profile: baseProfile,
            runs: profile.runs,
            fileSizeBytes: profile.testFileSizeBytes,
            dataPattern: selectedDataPattern,
            usesTrimmedAverage: usesTrimmedAverage
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
        return BenchmarkStorageValidator.isFileSizeAvailable(profile.testFileSizeBytes, availableCapacity: targetFolderAvailableCapacity)
    }

    private var hasAnyAvailableFileSize: Bool {
        guard targetFolderIsUsable else { return false }
        return BenchmarkStorageValidator.largestAvailableFileSize(from: BenchmarkProfile.fileSizeOptions, availableCapacity: targetFolderAvailableCapacity) != nil
    }

    private var canRunBenchmark: Bool {
        targetFolderIsUsable && selectedFileSizeHasSpace && !viewModel.isBenchmarking
    }

    private var targetFolderStatusIsReady: Bool {
        targetFolderIsUsable && selectedFileSizeHasSpace
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
        .confirmationDialog(language.t("Benchmark writes a complete temporary test file to the selected target folder."), isPresented: $confirmWrite) {
            Button(language.t("Run Benchmark"), role: .destructive) {
                Task { await viewModel.runBenchmark(profile: profile, volumePath: targetFolderPath) }
            }
            Button(language.t("Cancel"), role: .cancel) {}
        } message: {
            Text("\(language.t("Write tests can temporarily use free space and stress storage."))\n\(language.t("Write target folder:"))\n\(targetFolderPath)")
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
                usesTrimmedAverage: usesTrimmedAverage
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
                    .disabled(viewModel.isBenchmarking)
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
                        .disabled(viewModel.isBenchmarking)
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

                Label(targetFolderStatusText, systemImage: targetFolderStatusIsReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(targetFolderStatusIsReady ? .green : .orange)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }

            Text(targetFolderPath.isEmpty ? language.t("No target folder selected") : targetFolderPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        return targetFolderIsUsable ? language.t("Target folder is writable") : language.t("Target folder is not writable")
    }

    private var shouldShowProgressAndErrors: Bool {
        viewModel.isBenchmarking || viewModel.benchmarkError != nil || !canRunBenchmark
    }

    private var progressAndErrors: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let progress = viewModel.benchmarkProgress, viewModel.isBenchmarking {
                VStack(alignment: .leading, spacing: 8) {
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
        let required = BenchmarkStorageValidator.requiredSpace(for: profile.testFileSizeBytes)
        guard BenchmarkStorageValidator.isFileSizeAvailable(profile.testFileSizeBytes, availableCapacity: available) else {
            viewModel.benchmarkError = BenchmarkError.insufficientSpace(required: required, available: available).localizedDescription
            return false
        }

        viewModel.benchmarkError = nil
        return true
    }

    private func isFileSizeSelectable(_ fileSizeBytes: Int64) -> Bool {
        guard targetFolderIsUsable else { return true }
        return BenchmarkStorageValidator.isFileSizeAvailable(fileSizeBytes, availableCapacity: targetFolderAvailableCapacity)
    }

    private func adjustSelectedFileSizeForTarget() {
        guard targetFolderIsUsable else { return }
        let selectedSize = Int64(selectedFileSizeBytes)
        guard !BenchmarkStorageValidator.isFileSizeAvailable(selectedSize, availableCapacity: targetFolderAvailableCapacity) else { return }
        if let fallback = BenchmarkStorageValidator.largestAvailableFileSize(from: BenchmarkProfile.fileSizeOptions, availableCapacity: targetFolderAvailableCapacity) {
            selectedFileSizeBytes = Int(fallback)
        }
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
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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

    private var detailText: String {
        guard let result else { return "MB/s" }
        return String(format: "MB/s   %.0f IOPS   %.0f us", result.iops, result.latencyMicroseconds)
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
            Spacer()
        }
    }
}

private struct HistoryReportView: View {
    let drive: DriveDevice
    let snapshot: SmartSnapshot?
    let benchmarkResults: [BenchmarkResult]
    let smartHistory: [SmartHistoryRecord]
    let benchmarkHistory: [BenchmarkHistoryRecord]
    @AppStorage("includeSerialsInReports") private var includeSerialsInReports = false
    @Environment(\.appLanguage) private var language

    var body: some View {
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
                InfoPanel(title: language.t("SMART Snapshots"), symbol: "clock") {
                    if smartHistory.isEmpty {
                        Text(language.t("No saved snapshots yet."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(smartHistory.prefix(8)) { item in
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
                            }
                            Divider()
                        }
                    }
                }
                InfoPanel(title: language.t("Benchmark Runs"), symbol: "chart.xyaxis.line") {
                    if benchmarkHistory.isEmpty {
                        Text(language.t("No saved benchmark results yet."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(benchmarkHistory.prefix(8)) { item in
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
                            }
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .modelContainer(for: [SmartHistoryRecord.self, BenchmarkHistoryRecord.self, AppSettingsRecord.self], inMemory: true)
}
