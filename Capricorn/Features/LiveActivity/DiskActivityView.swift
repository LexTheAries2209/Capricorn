// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI

struct DiskActivityView: View {
    let drive: DriveDevice
    var viewModel: AppModel
    @AppStorage("diskActivitySampleInterval") private var selectedIntervalSeconds = DiskActivitySampleInterval.default.seconds
    @AppStorage("diskActivityWorkloadTargetsByDrive") private var workloadTargetPreferencesJSON = ""
    @AppStorage("diskActivityWorkloadTargetFolder") private var legacyWorkloadTargetFolderPath = ""
    @AppStorage("diskActivityWorkloadOperation") private var workloadOperationRaw = DiskActivityWorkloadOperation.write.rawValue
    @AppStorage("diskActivityWorkloadFileSize") private var workloadFileSizeRaw = DiskActivityWorkloadFileSize.gib32.rawValue
    @AppStorage("diskActivityWorkloadLoopEnabled") private var workloadLoopEnabled = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var saveMessage: String?
    @State private var workloadTargetSelectionError: String?
    @State private var workloadTargetSnapshot = WorkloadTargetSnapshot.empty
    @State private var controlsViewportWidth: CGFloat = 0
    @State private var controlsContentWidth: CGFloat = 0

    private let controlGroupSpacing: CGFloat = 8

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
        workloadTargetSnapshot.resolvedTarget
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
        workloadTargetSnapshot.resolvedTarget.folderURL
    }

    private var workloadTargetFolderPath: String {
        workloadTargetFolderURL?.path ?? ""
    }

    private var workloadTargetFolderIsUsable: Bool {
        workloadTargetSnapshot.folderIsUsable
    }

    private var workloadTargetAvailableCapacity: Int64 {
        workloadTargetSnapshot.availableCapacity
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
            refreshWorkloadTargetSnapshot()
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
        // Keep the history actions on the panel's trailing edge when the row fits.
        // Switch to a single scrollable row only after the available width is
        // genuinely smaller than the controls' intrinsic width.
        Group {
            if controlsViewportWidth == 0 || controlsContentWidth <= controlsViewportWidth {
                liveActivityMonitoringGroup
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottomTrailing) {
                        historyActionButtons
                    }
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .bottom, spacing: 16) {
                        liveActivityMonitoringGroup
                        historyActionButtons
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            controlsIntrinsicMeasurement
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .preference(key: ControlsViewportWidthKey.self, value: geometry.size.width)
            }
        }
        .padding(10)
        .padding(.leading, 4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .onPreferenceChange(ControlsViewportWidthKey.self) { width in
            guard abs(width - controlsViewportWidth) > 0.5 else { return }
            controlsViewportWidth = width
        }
        .onPreferenceChange(ControlsIntrinsicWidthsKey.self) { widths in
            let contentWidth = widths.liveActivity + 16 + widths.history
            guard abs(contentWidth - controlsContentWidth) > 0.5 else { return }
            controlsContentWidth = contentWidth
        }
    }

    private var controlsIntrinsicMeasurement: some View {
        HStack(alignment: .bottom, spacing: 16) {
            liveActivityMonitoringGroup
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: ControlsIntrinsicWidthsKey.self,
                                value: ControlsIntrinsicWidths(liveActivity: geometry.size.width)
                            )
                    }
                }
            historyActionButtons
                .background {
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: ControlsIntrinsicWidthsKey.self,
                                value: ControlsIntrinsicWidths(history: geometry.size.width)
                            )
                    }
                }
        }
        .fixedSize(horizontal: true, vertical: false)
        .hidden()
    }

    private var sampleIntervalControl: some View {
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
        .fixedSize(horizontal: true, vertical: false)
    }

    private var liveActivityMonitoringGroup: some View {
        HStack(alignment: .bottom, spacing: controlGroupSpacing) {
            monitoringActionGroup
            sampleIntervalControl
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var monitoringActionGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.t("Monitoring Controls"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            monitoringActionButtons
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var monitoringActionButtons: some View {
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
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var historyActionButtons: some View {
        HStack(spacing: 8) {
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
        .fixedSize(horizontal: true, vertical: false)
    }

    private var workloadPanel: some View {
        InfoPanel(title: language.t("Large File Workload"), symbol: "bolt.horizontal.circle") {
            VStack(alignment: .leading, spacing: 10) {
                workloadControlLayout

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

    private var workloadControlLayout: some View {
        // Keep the workload controls at one height. A scrollable row avoids
        // ViewThatFits measuring several complete control trees during resize.
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .bottom, spacing: controlGroupSpacing) {
                workloadActionsControl
                workloadTargetControl(width: 360)
                workloadOperationControl
                workloadFileSizeControl
                workloadLoopControl
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workloadTargetControl(width: CGFloat?) -> some View {
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
                    .frame(width: (width ?? 360) - 40, alignment: .leading)
            }
            .fixedSize(horizontal: true, vertical: false)
            .help(workloadTargetMenuHelp)
            .disabled(viewModel.isLiveActivityWorkloadRunning)
        }
    }

    private var workloadOperationControl: some View {
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
            .fixedSize(horizontal: true, vertical: false)
            .disabled(viewModel.isLiveActivityWorkloadRunning)
        }
    }

    private var workloadFileSizeControl: some View {
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
            .fixedSize(horizontal: true, vertical: false)
            .disabled(viewModel.isLiveActivityWorkloadRunning)
        }
    }

    private var workloadLoopControl: some View {
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
            .fixedSize(horizontal: true, vertical: false)
            .disabled(viewModel.isLiveActivityWorkloadRunning)
        }
    }

    private var workloadActionsControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.t("Workload Controls"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    startWorkload()
                } label: {
                    workloadActionLabel(language.t("Start Workload"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartWorkload)

                Button {
                    viewModel.stopLiveActivityWorkload()
                } label: {
                    workloadActionLabel(language.t("Stop Workload"), systemImage: "stop.fill")
                }
                .disabled(!viewModel.isLiveActivityWorkloadRunning || !isShowingCurrentSession)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func workloadActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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
        guard let volume = DiskActivityWorkloadTargetResolver.defaultVolume(
            for: drive,
            preferredVolumeID: viewModel.representativeVolume(for: drive)?.deviceIdentifier
        ) else {
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

    private var workloadTargetMenuHelp: String {
        switch workloadTargetSelection {
        case .automatic:
            return resolvedWorkloadTarget.volume?.name ?? language.t("Automatic")
        case .volume:
            return resolvedWorkloadTarget.volume?.name ?? automaticTargetTitle
        case let .folder(path):
            return path
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
        } else if let fallback = DiskActivityWorkloadTargetResolver.defaultVolume(
            for: drive,
            preferredVolumeID: viewModel.representativeVolume(for: drive)?.deviceIdentifier
        )?.mountPoint {
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
        refreshWorkloadTargetSnapshot()
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
        let resolved = DiskActivityWorkloadTargetResolver.resolve(
            requestedSelection,
            for: drive,
            preferredVolumeID: viewModel.representativeVolume(for: drive)?.deviceIdentifier
        )
        if resolved.didFallBackToAutomatic {
            preferences.setSelection(.automatic, for: drive)
        }

        let encoded = preferences.encoded()
        if encoded != workloadTargetPreferencesJSON {
            workloadTargetPreferencesJSON = encoded
        }
        refreshWorkloadTargetSnapshot()
    }

    private func refreshWorkloadTargetSnapshot() {
        let resolvedTarget = DiskActivityWorkloadTargetResolver.resolve(
            workloadTargetSelection,
            for: drive,
            preferredVolumeID: viewModel.representativeVolume(for: drive)?.deviceIdentifier
        )
        let folderIsUsable = resolvedTarget.folderURL.map {
            DiskActivityWorkloadTargetResolver.isUsableFolder($0.path)
        } ?? false
        let availableCapacity: Int64
        if folderIsUsable, let folderURL = resolvedTarget.folderURL {
            availableCapacity = DiskActivityWorkloadStorageValidator.availableCapacity(for: folderURL)
        } else {
            availableCapacity = 0
        }

        let nextSnapshot = WorkloadTargetSnapshot(
            resolvedTarget: resolvedTarget,
            folderIsUsable: folderIsUsable,
            availableCapacity: availableCapacity
        )
        if workloadTargetSnapshot != nextSnapshot {
            workloadTargetSnapshot = nextSnapshot
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

private struct WorkloadTargetSnapshot: Equatable {
    let resolvedTarget: DiskActivityWorkloadResolvedTarget
    let folderIsUsable: Bool
    let availableCapacity: Int64

    static let empty = WorkloadTargetSnapshot(
        resolvedTarget: DiskActivityWorkloadResolvedTarget(
            selection: .automatic,
            volume: nil,
            folderURL: nil,
            didFallBackToAutomatic: false
        ),
        folderIsUsable: false,
        availableCapacity: 0
    )
}

private struct ControlsViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ControlsIntrinsicWidths: Equatable {
    var liveActivity: CGFloat = 0
    var history: CGFloat = 0
}

private struct ControlsIntrinsicWidthsKey: PreferenceKey {
    static let defaultValue = ControlsIntrinsicWidths()

    static func reduce(value: inout ControlsIntrinsicWidths, nextValue: () -> ControlsIntrinsicWidths) {
        let next = nextValue()
        value.liveActivity = max(value.liveActivity, next.liveActivity)
        value.history = max(value.history, next.history)
    }
}
