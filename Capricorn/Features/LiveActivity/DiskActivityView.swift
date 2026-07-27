// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI

struct DiskActivityView: View {
    let drive: DriveDevice
    var viewModel: AppModel
    let activityHistory: [DiskActivityHistoryRecord]
    @AppStorage("diskActivitySampleInterval") private var selectedIntervalSeconds = DiskActivitySampleInterval.default.seconds
    @AppStorage("diskActivityWorkloadTargetsByDrive") private var workloadTargetPreferencesJSON = ""
    @AppStorage("diskActivityWorkloadTargetFolder") private var legacyWorkloadTargetFolderPath = ""
    @AppStorage("diskActivityWorkloadOperation") private var workloadOperationRaw = DiskActivityWorkloadOperation.write.rawValue
    @AppStorage("diskActivityWorkloadFileSize") private var workloadFileSizeRaw = DiskActivityWorkloadFileSize.gib32.rawValue
    @AppStorage("diskActivityWorkloadLoopEnabled") private var workloadLoopEnabled = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var saveMessage: String?
    @State private var showHiddenActivityHistory = false
    @State private var workloadTargetSelectionError: String?
    private let activityHistoryScrollThreshold = 10
    private let activityHistoryRowHeight: CGFloat = 58

    private var isShowingCurrentSession: Bool {
        viewModel.liveActivityDriveID == drive.id
    }

    private var displayedSamples: [DiskActivitySample] {
        isShowingCurrentSession ? viewModel.liveActivitySamples : []
    }

    private var displayedCurrentActivity: DiskActivitySample? {
        isShowingCurrentSession ? viewModel.currentLiveActivity : nil
    }

    private var isMonitoringThisDrive: Bool {
        isShowingCurrentSession && viewModel.isLiveActivityMonitoring
    }

    private var targetPreferences: DiskActivityWorkloadTargetPreferences {
        DiskActivityWorkloadTargetPreferences.decode(workloadTargetPreferencesJSON)
    }

    private var workloadTargetSelection: DiskActivityWorkloadTargetSelection {
        targetPreferences.selection(for: drive)
    }

    private var resolvedWorkloadTarget: DiskActivityWorkloadResolvedTarget {
        DiskActivityWorkloadTargetResolver.resolve(workloadTargetSelection, for: drive)
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
        resolvedWorkloadTarget.folderURL
    }

    private var workloadTargetFolderPath: String {
        workloadTargetFolderURL?.path ?? ""
    }

    private var workloadTargetFolderIsUsable: Bool {
        DiskActivityWorkloadTargetResolver.isUsableFolder(workloadTargetFolderPath)
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
        return !BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(workloadTargetFolderPath, drive: drive)
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
        HistoryVisibility.visible(activityHistory.filter { $0.driveID == drive.id })
    }

    private var selectedDriveHiddenHistory: [DiskActivityHistoryRecord] {
        HistoryVisibility.hidden(activityHistory.filter { $0.driveID == drive.id })
    }

    private var summary: DiskActivitySummary {
        let fallbackEnd = isMonitoringThisDrive ? Date() : (isShowingCurrentSession ? viewModel.liveActivityEndedAt : nil)
        return DiskActivityStatistics.summarize(
            samples: displayedSamples,
            startedAt: isShowingCurrentSession ? viewModel.liveActivityStartedAt : nil,
            endedAt: fallbackEnd
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                controls
                if isShowingCurrentSession, let error = viewModel.liveActivityError {
                    Label(language.statusMessage(error), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                workloadPanel
                DiskActivityChartView(
                    title: language.t("Live Disk Activity"),
                    samples: displayedSamples,
                    current: displayedCurrentActivity,
                    style: .expanded
                )
                metricGrid
                historyList
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            prepareWorkloadTarget()
            adjustWorkloadFileSizeForTarget()
        }
        .onChange(of: workloadTargetFolderPath) { _, _ in
            workloadTargetSelectionError = nil
            adjustWorkloadFileSizeForTarget()
        }
        .onChange(of: drive.id) { _, _ in
            saveMessage = nil
            workloadTargetSelectionError = nil
            prepareWorkloadTarget()
            adjustWorkloadFileSizeForTarget()
        }
        .onChange(of: workloadOperationRaw) { _, _ in
            if isShowingCurrentSession {
                viewModel.liveActivityWorkloadError = nil
            }
            adjustWorkloadFileSizeForTarget()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.t("Live Activity"))
                .font(.largeTitle.bold())
            Text(drive.catalogDisplayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(drive.catalogDisplayHelp(language: language))
            Text(language.t(drive.isNetwork ? "Network drives do not provide per-disk IOKit activity counters." : "Monitors total I/O reported by macOS for the selected physical disk."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
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

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    saveMessage = nil
                    viewModel.startLiveActivityMonitoring(drive: drive, interval: selectedInterval)
                } label: {
                    Label(language.t("Start Monitoring"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLiveActivityMonitoring || viewModel.isLiveActivityWorkloadRunning || drive.isNetwork)

                Button {
                    saveMessage = nil
                    viewModel.continueLiveActivityMonitoring(drive: drive, interval: selectedInterval)
                } label: {
                    Label(language.t("Continue Monitoring"), systemImage: "play.circle")
                }
                .disabled(!viewModel.canContinueLiveActivityMonitoring(for: drive))

                Button {
                    viewModel.stopLiveActivityMonitoring()
                } label: {
                    Label(language.t("Stop Monitoring"), systemImage: "stop.fill")
                }
                .disabled(!isMonitoringThisDrive)

                Spacer(minLength: 10)

                Button {
                    saveActivityHistory()
                } label: {
                    Label(language.t("Save to History"), systemImage: "tray.and.arrow.down")
                }
                .disabled(viewModel.isLiveActivityMonitoring || viewModel.isLiveActivityWorkloadRunning || displayedSamples.isEmpty)

                Button {
                    saveMessage = nil
                    viewModel.clearLiveActivity()
                } label: {
                    Label(language.t("Clear Chart"), systemImage: "xmark.circle")
                }
                .disabled(viewModel.isLiveActivityMonitoring || viewModel.isLiveActivityWorkloadRunning || displayedSamples.isEmpty)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }

    private var workloadPanel: some View {
        InfoPanel(title: language.t("Large File Workload"), symbol: "bolt.horizontal.circle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.t("Target Location"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Menu {
                            Button {
                                setWorkloadTargetSelection(.automatic)
                            } label: {
                                Label(
                                    automaticTargetTitle,
                                    systemImage: workloadTargetSelection == .automatic ? "checkmark" : "internaldrive"
                                )
                            }

                            Divider()

                            ForEach(DiskActivityWorkloadTargetResolver.orderedVolumes(for: drive)) { volume in
                                Button {
                                    setWorkloadTargetSelection(.volume(deviceIdentifier: volume.deviceIdentifier))
                                } label: {
                                    Label(
                                        workloadVolumeTitle(volume),
                                        systemImage: workloadTargetSelection == .volume(deviceIdentifier: volume.deviceIdentifier) ? "checkmark" : "externaldrive"
                                    )
                                }
                                .disabled(!DiskActivityWorkloadTargetResolver.isUsable(volume))
                            }

                            Divider()

                            Button {
                                chooseWorkloadTargetFolder()
                            } label: {
                                Label(language.t("Choose Folder…"), systemImage: "folder.badge.gearshape")
                            }
                        } label: {
                            Label(workloadTargetMenuTitle, systemImage: "folder")
                        }
                        .frame(width: 220, alignment: .leading)
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
                }

                HStack(spacing: 8) {
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
                    .disabled(!viewModel.isLiveActivityWorkloadRunning || !isShowingCurrentSession)
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
                    Text(language.t("Workload engine: SEQ1M Q4T4 async, 4 MiB chunks, 0 Fill."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if isShowingCurrentSession, let progress = viewModel.liveActivityWorkloadProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress.fraction)
                        Text(workloadProgressText(progress))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = workloadTargetSelectionError ?? (isShowingCurrentSession ? viewModel.liveActivityWorkloadError : nil) {
                    Label(language.statusMessage(error), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var workloadTargetStatusText: String {
        if workloadTargetFolderPath.isEmpty {
            return language.t("No writable mounted volume")
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

    private var automaticTargetTitle: String {
        guard let volume = DiskActivityWorkloadTargetResolver.defaultVolume(for: drive) else {
            return language.t("Automatic")
        }
        return "\(language.t("Automatic")) · \(volume.name)"
    }

    private var workloadTargetMenuTitle: String {
        if resolvedWorkloadTarget.didFallBackToAutomatic {
            return automaticTargetTitle
        }
        switch workloadTargetSelection {
        case .automatic:
            return automaticTargetTitle
        case .volume:
            return resolvedWorkloadTarget.volume?.name ?? automaticTargetTitle
        case let .folder(path):
            let name = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
            return name.isEmpty ? path : name
        }
    }

    private func workloadVolumeTitle(_ volume: DriveDevice.Volume) -> String {
        let base = "\(volume.name) (\(volume.deviceIdentifier))"
        guard volume.mountPoint != nil else {
            return "\(base) · \(language.t("Not Mounted"))"
        }
        guard volume.isWritable else {
            return "\(base) · \(language.t("Read Only"))"
        }
        guard DiskActivityWorkloadTargetResolver.isUsable(volume) else {
            return "\(base) · \(language.t("Unavailable"))"
        }
        return base
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
        } else if let fallback = DiskActivityWorkloadTargetResolver.defaultVolume(for: drive)?.mountPoint {
            panel.directoryURL = URL(fileURLWithPath: fallback, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard DiskActivityWorkloadTargetResolver.isUsableFolder(url.path),
              let volume = BenchmarkTargetFolderMatcher.matchingVolume(for: url.path, drive: drive),
              volume.isWritable else {
            workloadTargetSelectionError = language.t("The selected folder must be writable and on the selected drive.")
            return
        }
        setWorkloadTargetSelection(.folder(path: url.path))
    }

    private func setWorkloadTargetSelection(_ selection: DiskActivityWorkloadTargetSelection) {
        var preferences = targetPreferences
        preferences.setSelection(selection, for: drive)
        workloadTargetPreferencesJSON = preferences.encoded()
        workloadTargetSelectionError = nil
        if isShowingCurrentSession {
            viewModel.liveActivityWorkloadError = nil
        }
        adjustWorkloadFileSizeForTarget()
    }

    private func prepareWorkloadTarget() {
        var preferences = targetPreferences
        let currentSelection = preferences.selection(for: drive)

        if !legacyWorkloadTargetFolderPath.isEmpty {
            if currentSelection == .automatic {
                _ = preferences.migrateLegacyFolder(legacyWorkloadTargetFolderPath, to: drive)
            }
            legacyWorkloadTargetFolderPath = ""
        }

        let requestedSelection = preferences.selection(for: drive)
        let resolved = DiskActivityWorkloadTargetResolver.resolve(requestedSelection, for: drive)
        if resolved.didFallBackToAutomatic {
            preferences.setSelection(.automatic, for: drive)
        }

        let encoded = preferences.encoded()
        if encoded != workloadTargetPreferencesJSON {
            workloadTargetPreferencesJSON = encoded
        }
    }

    private func startWorkload() {
        guard let targetURL = workloadTargetFolderURL,
              let fileSize = workloadResolvedFileSize else {
            workloadTargetSelectionError = language.t("Choose a writable target folder before starting.")
            return
        }
        guard canStartWorkload else {
            workloadTargetSelectionError = workloadTargetStatusText
            return
        }

        saveMessage = nil
        workloadTargetSelectionError = nil
        viewModel.startLiveActivityWorkload(
            configuration: DiskActivityWorkloadConfiguration(
                targetFolderURL: targetURL,
                operation: workloadOperation,
                fileSizeOption: workloadFileSizeOption,
                fileSizeBytes: fileSize,
                loopEnabled: workloadLoopEnabled
            ),
            drive: drive,
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
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
        do {
            try HistoryRepository(modelContext: modelContext).hide(item)
        } catch {
            saveMessage = UserFacingError.message("Could not update activity history.", error: error)
        }
    }

    private func restoreActivityHistory(_ item: DiskActivityHistoryRecord) {
        do {
            try HistoryRepository(modelContext: modelContext).restore(item)
        } catch {
            saveMessage = UserFacingError.message("Could not update activity history.", error: error)
        }
    }

    private func restoreAllHiddenActivityHistory() {
        do {
            try HistoryRepository(modelContext: modelContext).restoreAll(selectedDriveHiddenHistory)
        } catch {
            saveMessage = UserFacingError.message("Could not update activity history.", error: error)
        }
    }

    private func hideAllVisibleActivityHistory() {
        do {
            try HistoryRepository(modelContext: modelContext).hideAll(selectedDriveHistory, driveID: drive.id)
        } catch {
            saveMessage = UserFacingError.message("Could not update activity history.", error: error)
        }
    }

    private func saveActivityHistory() {
        let start = viewModel.liveActivityStartedAt ?? displayedSamples.first?.timestamp ?? Date()
        let end = viewModel.liveActivityEndedAt ?? displayedSamples.last?.timestamp ?? Date()
        do {
            try HistoryRepository(modelContext: modelContext).saveActivity(
                drive: drive,
                samples: displayedSamples,
                sampleInterval: selectedInterval,
                startedAt: start,
                endedAt: end
            )
            saveMessage = "Activity record saved to history."
        } catch {
            saveMessage = UserFacingError.message("Could not save activity record.", error: error)
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
