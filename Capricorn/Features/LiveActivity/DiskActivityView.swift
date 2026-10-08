// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI

private struct WorkloadStartRequest: Identifiable {
    let id = UUID()
    let configuration: DiskActivityWorkloadConfiguration
    let interval: DiskActivitySampleInterval
}

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
    @State private var workloadStartRequest: WorkloadStartRequest?

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
            workloadStartRequest = nil
            prepareWorkloadTarget()
            adjustWorkloadFileSizeForTarget()
        }
        .sheet(item: $workloadStartRequest) { request in
            BenchmarkConfirmationSheet(
                language: language,
                title: language.t("Start Workload"),
                driveName: drive.catalogDisplayName,
                message: language.activityWorkloadConfirmationMessage(isNetworkDrive: drive.isNetwork),
                warning: language.activityWorkloadConfirmationWarning(request.configuration.operation),
                fields: language.activityWorkloadConfirmationFields(
                    configuration: request.configuration,
                    interval: request.interval
                ),
                targetFolder: request.configuration.targetFolderURL.path,
                targetFolderTitle: language.t("Target Location"),
                confirmTitle: language.t("Start Workload"),
                onConfirm: {
                    workloadStartRequest = nil
                    startWorkload(request)
                },
                onDismiss: { workloadStartRequest = nil }
            )
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
        // The scroll view owns overflow, while the frame inside it is at least
        // as wide as the visible panel. This keeps trailing actions at the
        // panel edge when there is room and extends the row only when needed.
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: true) {
                TrailingControlRow(minimumWidth: geometry.size.width, spacing: 16) {
                    liveActivityMonitoringGroup
                    historyActionButtons
                }
            }
            .frame(width: geometry.size.width)
        }
        .frame(height: 46)
        .padding(10)
        .padding(.leading, 4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
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

                Label(workloadTargetStatusText, systemImage: workloadTargetStatusSymbol)
                    .font(.caption)
                    .foregroundStyle(workloadTargetStatusColor)

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
                    requestWorkloadStart()
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

    private func requestWorkloadStart() {
        refreshWorkloadTargetSnapshot()
        guard let targetURL = workloadTargetFolderURL,
              let fileSize = workloadResolvedFileSize else {
            workloadTargetSelectionError = language.t("Choose a writable target folder before starting.")
            return
        }
        guard canStartWorkload else {
            workloadTargetSelectionError = workloadTargetStatusText
            return
        }

        workloadTargetSelectionError = nil
        // Freeze what the user is approving, including the resolved full-disk size.
        workloadStartRequest = WorkloadStartRequest(
            configuration: DiskActivityWorkloadConfiguration(
                targetFolderURL: targetURL,
                operation: workloadOperation,
                fileSizeOption: workloadFileSizeOption,
                fileSizeBytes: fileSize,
                loopEnabled: workloadLoopEnabled
            ),
            interval: selectedInterval
        )
    }

    private func startWorkload(_ request: WorkloadStartRequest) {
        let configuration = request.configuration
        guard !viewModel.isLiveActivityWorkloadRunning else { return }
        guard DiskActivityWorkloadTargetResolver.isUsableFolder(configuration.targetFolderURL.path),
              BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(configuration.targetFolderURL.path, drive: drive) else {
            workloadTargetSelectionError = language.t("The selected folder must be writable and on the selected drive.")
            refreshWorkloadTargetSnapshot()
            return
        }
        // Recheck the approved path rather than falling back to a different target.
        let availableCapacity = DiskActivityWorkloadStorageValidator.availableCapacity(for: configuration.targetFolderURL)
        let requiredSpace = DiskActivityWorkloadStorageValidator.requiredSpace(
            fileSizeBytes: configuration.fileSizeBytes,
            operation: configuration.operation
        )
        guard availableCapacity >= requiredSpace else {
            workloadTargetSelectionError = language.t("Selected workload size exceeds available free space")
            refreshWorkloadTargetSnapshot()
            return
        }
        saveMessage = nil
        workloadTargetSelectionError = nil
        viewModel.startLiveActivityWorkload(
            configuration: configuration,
            drive: drive,
            interval: request.interval
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

            ActivityMetricGridLayout {
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

struct ActivityMetricGridLayout: Layout {
    let minimumWidth: CGFloat = 120
    let spacing: CGFloat = 10

    func geometry(width: CGFloat, itemCount: Int) -> (columns: Int, rows: Int, columnWidth: CGFloat) {
        guard itemCount > 0 else { return (0, 0, 0) }
        let width = max(0, width.isFinite ? width : minimumWidth * CGFloat(itemCount) + spacing * CGFloat(itemCount - 1))
        // Cap tracks at the item count so wide windows never reserve empty columns.
        let columns = max(1, Int(min(CGFloat(itemCount), floor((width + spacing) / (minimumWidth + spacing)))))
        let columnWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        return (columns, (itemCount + columns - 1) / columns, columnWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let idealWidth = minimumWidth * CGFloat(subviews.count) + spacing * CGFloat(subviews.count - 1)
        let width = max(0, proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth)
        let grid = geometry(width: width, itemCount: subviews.count)
        let height = rowHeight(columnWidth: grid.columnWidth, subviews: subviews)
        return CGSize(width: width, height: height * CGFloat(grid.rows) + spacing * CGFloat(grid.rows - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let grid = geometry(width: bounds.width, itemCount: subviews.count)
        let height = rowHeight(columnWidth: grid.columnWidth, subviews: subviews)
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(index % grid.columns) * (grid.columnWidth + spacing),
                    y: bounds.minY + CGFloat(index / grid.columns) * (height + spacing)
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: grid.columnWidth, height: height)
            )
        }
    }

    private func rowHeight(columnWidth: CGFloat, subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }.max() ?? 0
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

private struct TrailingControlRow: Layout {
    let minimumWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let contentWidth = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1))
        let contentHeight = sizes.map(\.height).max() ?? 0
        return CGSize(width: max(minimumWidth, contentWidth), height: contentHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count >= 2 else { return }

        let firstSize = subviews[0].sizeThatFits(.unspecified)
        let secondSize = subviews[1].sizeThatFits(.unspecified)
        let firstY = bounds.maxY - firstSize.height
        let secondY = bounds.maxY - secondSize.height

        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: firstY),
            anchor: .topLeading,
            proposal: ProposedViewSize(firstSize)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX - secondSize.width, y: secondY),
            anchor: .topLeading,
            proposal: ProposedViewSize(secondSize)
        )
    }
}
