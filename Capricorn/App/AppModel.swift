// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppModel {
    var drives: [DriveDevice] = []
    var snapshots: [String: SmartSnapshot] = [:]
    var selectedDriveID: String?
    var isRefreshing = false
    var refreshMessage: String?
    let benchmarkSession = BenchmarkSessionModel()
    let liveActivitySession = LiveActivitySessionModel()
    let diskOperations = DiskOperationsModel()
    var externalSupport: ExternalSupportStatus
    var showVirtualDisks = false
    var selectedFeatureTab: DriveFeatureTab = .overview

    var benchmarkProgress: BenchmarkProgress? {
        get { benchmarkSession.progress }
        set { benchmarkSession.progress = newValue }
    }

    var benchmarkResults: [BenchmarkResult] {
        get { benchmarkSession.results }
        set { benchmarkSession.results = newValue }
    }

    var benchmarkError: String? {
        get { benchmarkSession.error }
        set { benchmarkSession.error = newValue }
    }

    var isBenchmarking: Bool {
        get { benchmarkSession.isActive }
        set { benchmarkSession.state = newValue ? .running : .idle }
    }

    var diskActivitySamples: [DiskActivitySample] {
        get { benchmarkSession.activitySamples }
        set { benchmarkSession.activitySamples = newValue }
    }

    var currentDiskActivity: DiskActivitySample? {
        get { benchmarkSession.currentActivity }
        set { benchmarkSession.currentActivity = newValue }
    }

    var liveActivitySamples: [DiskActivitySample] {
        get { liveActivitySession.samples }
        set { liveActivitySession.samples = newValue }
    }

    var currentLiveActivity: DiskActivitySample? {
        get { liveActivitySession.currentActivity }
        set { liveActivitySession.currentActivity = newValue }
    }

    var isLiveActivityMonitoring: Bool {
        get { liveActivitySession.isMonitoring }
        set { liveActivitySession.isMonitoring = newValue }
    }

    var liveActivitySelectedDriveID: String? {
        get { liveActivitySession.selectedDriveID }
        set { liveActivitySession.selectedDriveID = newValue }
    }

    var liveActivityStartedAt: Date? {
        get { liveActivitySession.startedAt }
        set { liveActivitySession.startedAt = newValue }
    }

    var liveActivityEndedAt: Date? {
        get { liveActivitySession.endedAt }
        set { liveActivitySession.endedAt = newValue }
    }

    var liveActivityError: String? {
        get { liveActivitySession.error }
        set { liveActivitySession.error = newValue }
    }

    var liveActivityWorkloadProgress: DiskActivityWorkloadProgress? {
        get { liveActivitySession.workloadProgress }
        set { liveActivitySession.workloadProgress = newValue }
    }

    var liveActivityWorkloadError: String? {
        get { liveActivitySession.workloadError }
        set { liveActivitySession.workloadError = newValue }
    }

    var isLiveActivityWorkloadRunning: Bool {
        get { liveActivitySession.isWorkloadActive }
        set { liveActivitySession.workloadState = newValue ? .running : .idle }
    }

    var diskOpenFileInspection: DiskOpenFileInspection? {
        get { diskOperations.openFileInspection }
        set { diskOperations.openFileInspection = newValue }
    }

    var diskActionFailure: DiskActionFailure? {
        get { diskOperations.actionFailure }
        set { diskOperations.actionFailure = newValue }
    }

    var diskCheckReport: DiskCheckReport? {
        get { diskOperations.checkReport }
        set { diskOperations.checkReport = newValue }
    }

    var isDiskChecking: Bool {
        get { diskOperations.isChecking }
        set { diskOperations.isChecking = newValue }
    }

    nonisolated static let benchmarkActivityInterval = DiskActivitySampleInterval.fifth

    private let refreshService: DriveRefreshing
    private let benchmarkRunner: BenchmarkRunning
    private let diskActivityProvider: DiskActivityProviding
    private let liveActivityWorkloadRunner: DiskActivityWorkloadRunning
    private let diskActionService: DiskActionService
    private let openFileService: DiskOpenFileService
    private let diskCheckService: DiskCheckService
    private let externalDetector: ExternalDriveSupportDetector
    private let notificationCoordinator: NotificationCoordinator
    private var diskActivityTask: Task<Void, Never>?
    private var liveActivityTask: Task<Void, Never>?
    private var liveActivityWorkloadTask: Task<Void, Never>?
    private var liveActivityWorkloadEventTask: Task<Void, Never>?
    private var activeLiveActivityWorkloadRunID: UUID?
    private var benchmarkTask: Task<Void, Never>?
    private var activeBenchmarkRunID: UUID?
    private var refreshTask: Task<DriveRefreshSnapshot, Error>?
    private var activeRefreshID: UUID?
    private var hasRequestedNotificationAuthorization = false
    private var lastBenchmarkProgressPublishedAt: Date?

    init(
        inventoryProvider: DiskInventoryProviding = DiskutilInventoryProvider(),
        smartService: SmartSnapshotService = SmartSnapshotService(),
        refreshService: DriveRefreshing? = nil,
        benchmarkRunner: BenchmarkRunning = BenchmarkRunnerRouter(),
        diskActivityProvider: DiskActivityProviding = IOKitDiskActivityProvider(),
        liveActivityWorkloadRunner: DiskActivityWorkloadRunning = NativeDiskActivityWorkloadRunner(),
        diskActionService: DiskActionService = DiskActionService(),
        openFileService: DiskOpenFileService = DiskOpenFileService(),
        diskCheckService: DiskCheckService = DiskCheckService(),
        externalDetector: ExternalDriveSupportDetector = ExternalDriveSupportDetector(),
        notificationCoordinator: NotificationCoordinator = NotificationCoordinator()
    ) {
        self.refreshService = refreshService ?? DriveRefreshService(
            inventoryProvider: inventoryProvider,
            smartService: smartService,
            externalDetector: externalDetector
        )
        self.benchmarkRunner = benchmarkRunner
        self.diskActivityProvider = diskActivityProvider
        self.liveActivityWorkloadRunner = liveActivityWorkloadRunner
        self.diskActionService = diskActionService
        self.openFileService = openFileService
        self.diskCheckService = diskCheckService
        self.externalDetector = externalDetector
        self.notificationCoordinator = notificationCoordinator
        self.externalSupport = externalDetector.detect()
    }

    var selectedDrive: DriveDevice? {
        guard let selectedDriveID else { return drives.first }
        return drives.first(where: { $0.id == selectedDriveID }) ?? drives.first
    }

    var selectedSnapshot: SmartSnapshot? {
        guard let selectedDrive else { return nil }
        return snapshots[selectedDrive.id]
    }

    var worstHealth: HealthStatus {
        let values = snapshots.values.map(\.health).filter { $0 != .unavailable }
        return values.max() ?? .unavailable
    }

    var healthSummary: String {
        guard !drives.isEmpty else { return "No drives" }
        let warningCount = snapshots.values.filter { $0.health.severity >= HealthStatus.warning.severity }.count
        if warningCount == 0 {
            return "\(drives.count) drive\(drives.count == 1 ? "" : "s") monitored"
        }
        return "\(warningCount) drive\(warningCount == 1 ? "" : "s") need attention"
    }

    func selectNextFeatureTab() {
        selectedFeatureTab = DriveFeatureTab.next(after: selectedFeatureTab)
    }

    func selectPreviousFeatureTab() {
        selectedFeatureTab = DriveFeatureTab.previous(before: selectedFeatureTab)
    }

    func refreshIfNeeded() async {
        if !hasRequestedNotificationAuthorization {
            hasRequestedNotificationAuthorization = true
            notificationCoordinator.requestAuthorizationIfNeeded()
        }
        guard drives.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        refreshTask?.cancel()
        let refreshID = UUID()
        activeRefreshID = refreshID
        let refreshService = refreshService
        let showVirtualDisks = showVirtualDisks
        let worker = Task {
            try await refreshService.refresh(showVirtual: showVirtualDisks)
        }
        refreshTask = worker
        isRefreshing = true
        refreshMessage = "Scanning disks..."
        benchmarkError = nil
        defer {
            if activeRefreshID == refreshID {
                refreshTask = nil
                activeRefreshID = nil
                isRefreshing = false
            }
        }

        do {
            let refreshSnapshot = try await worker.value
            guard activeRefreshID == refreshID else { return }
            let loadedDrives = refreshSnapshot.drives
            drives = loadedDrives
            snapshots = refreshSnapshot.snapshots
            externalSupport = refreshSnapshot.externalSupport
            if selectedDriveID == nil || !loadedDrives.contains(where: { $0.id == selectedDriveID }) {
                selectedDriveID = loadedDrives.first?.id
            }
            if liveActivitySelectedDriveID == nil || !loadedDrives.contains(where: { $0.id == liveActivitySelectedDriveID }) {
                liveActivitySelectedDriveID = selectedDriveID ?? loadedDrives.first?.id
            }

            for drive in loadedDrives {
                if let snapshot = refreshSnapshot.snapshots[drive.id] {
                    notificationCoordinator.notifyIfNeeded(drive: drive, snapshot: snapshot)
                }
            }
            guard activeRefreshID == refreshID else { return }
            refreshMessage = loadedDrives.isEmpty ? "No physical or network drives found." : "Last refreshed \(Date().formatted(date: .omitted, time: .standard))"
        } catch {
            guard activeRefreshID == refreshID else { return }
            let error = error as NSError
            CapricornLog.inventory.error("Drive refresh failed: \(error.domain, privacy: .public) \(error.code)")
            refreshMessage = error.localizedDescription
        }
    }

    func startBenchmark(profile: BenchmarkProfile, volumePath: String? = nil) {
        guard benchmarkTask == nil, benchmarkSession.state == .idle else { return }
        benchmarkTask = Task { [weak self] in
            await self?.runBenchmark(profile: profile, volumePath: volumePath)
            await MainActor.run {
                self?.benchmarkTask = nil
            }
        }
    }

    func runBenchmark(profile: BenchmarkProfile, volumePath: String? = nil) async {
        guard benchmarkSession.state == .idle else { return }
        guard let drive = selectedDrive else {
            benchmarkError = "Select a drive before running a benchmark."
            return
        }
        let targetVolume = volumePath ?? drive.benchmarkMountPoint
        guard let targetVolume else {
            benchmarkError = "This drive has no mounted writable volume available for safe file-based benchmarking."
            return
        }

        benchmarkError = nil
        CapricornLog.benchmark.info("Benchmark session started")
        let benchmarkInterval = CapricornLog.benchmarkSignposter.beginInterval("Benchmark session")
        benchmarkSession.state = .running
        let runID = UUID()
        activeBenchmarkRunID = runID
        let measuredRuns = BenchmarkMeasurementReducer.measuredRunCount(for: profile.runs, usesTrimmedAverage: profile.usesTrimmedAverage)
        let isLooping = profile.executionMode == .loopUntilCancelled
        publishBenchmarkProgress(BenchmarkProgress(
            currentTestLabel: "Starting",
            completed: 0,
            total: isLooping ? max(1, profile.tests.count) : profile.tests.count * (measuredRuns + 1),
            message: isLooping ? "Loop running" : "Preparing complete test file"
        ), force: true)
        startDiskActivityMonitoring(for: drive, runID: runID)
        replaceBenchmarkResults(driveID: drive.id, profileID: profile.id, with: [])
        defer {
            if activeBenchmarkRunID == runID {
                stopDiskActivityMonitoring()
                benchmarkSession.state = .idle
                activeBenchmarkRunID = nil
                CapricornLog.benchmarkSignposter.endInterval("Benchmark session", benchmarkInterval)
                CapricornLog.benchmark.info("Benchmark session cleanup completed")
            }
        }

        let (events, eventContinuation) = AsyncStream<BenchmarkEvent>.makeStream()
        let eventTask = Task { @MainActor [weak self] in
            for await event in events {
                guard let self,
                      self.activeBenchmarkRunID == runID,
                      self.benchmarkSession.state == .running else { continue }
                switch event {
                case let .progress(progress):
                    self.publishBenchmarkProgress(progress)
                case let .result(result):
                    self.upsertBenchmarkResult(result)
                }
            }
        }
        defer {
            eventContinuation.finish()
            eventTask.cancel()
        }

        do {
            let results = try await benchmarkRunner.run(
                profile: profile,
                drive: drive,
                volumePath: targetVolume,
                progress: { progress in
                    eventContinuation.yield(.progress(progress))
                },
                result: { result in
                    eventContinuation.yield(.result(result))
                }
            )
            eventContinuation.finish()
            await eventTask.value
            guard activeBenchmarkRunID == runID, benchmarkSession.state == .running else { return }
            replaceBenchmarkResults(driveID: drive.id, profileID: profile.id, with: results)
        } catch {
            eventContinuation.finish()
            await eventTask.value
            guard activeBenchmarkRunID == runID, benchmarkSession.state == .running else { return }
            let error = error as NSError
            benchmarkError = error.localizedDescription
            CapricornLog.benchmark.error("Benchmark session failed: \(error.domain, privacy: .public) \(error.code)")
        }
    }

    func cancelBenchmark() {
        guard benchmarkSession.state == .running || benchmarkTask != nil else { return }
        benchmarkSession.state = .stopping
        CapricornLog.benchmark.info("Benchmark cancellation requested")
        benchmarkTask?.cancel()
        benchmarkRunner.cancel()
        benchmarkError = BenchmarkError.cancelled.localizedDescription
    }

    func performDiskAction(_ action: DiskSidebarAction, on drive: DriveDevice, newName: String? = nil) async {
        CapricornLog.diskOperations.info("Disk operation started: \(action.rawValue, privacy: .public)")
        selectedDriveID = drive.id
        refreshMessage = "Running disk action..."
        diskActionFailure = nil

        do {
            try await diskActionService.perform(action, on: drive, newName: newName)
            await refresh()
            refreshMessage = "Disk action completed."
            CapricornLog.diskOperations.info("Disk operation completed: \(action.rawValue, privacy: .public)")
        } catch {
            let error = error as NSError
            CapricornLog.diskOperations.error("Disk operation failed: \(action.rawValue, privacy: .public), \(error.domain, privacy: .public) \(error.code)")
            await recordDiskActionFailure(action: action, drive: drive, message: error.localizedDescription)
        }
    }

    func inspectOpenFiles(on drive: DriveDevice) async {
        selectedDriveID = drive.id
        refreshMessage = "Inspecting open files..."
        do {
            diskOpenFileInspection = try await openFileService.inspectOpenFiles(on: drive)
            refreshMessage = "Open file inspection completed."
        } catch {
            refreshMessage = "Open file inspection failed: \(error.localizedDescription)"
        }
    }

    func runDiskCheck(_ mode: DiskCheckMode, on drive: DriveDevice) async {
        guard !isDiskChecking else { return }
        selectedDriveID = drive.id
        refreshMessage = "Checking disk..."
        diskCheckReport = DiskCheckReport(
            mode: mode,
            driveID: drive.id,
            driveName: drive.displayName,
            entries: []
        )
        isDiskChecking = true
        let finalReport = await diskCheckService.check(mode, drive: drive) { [weak self] report in
            await MainActor.run {
                self?.diskCheckReport = report
            }
        }
        diskCheckReport = finalReport
        isDiskChecking = false
        refreshMessage = "Disk check completed."
    }

    func cancelDiskCheck() {
        guard isDiskChecking else { return }
        refreshMessage = "Stopping disk check..."
        diskCheckService.cancel()
    }

    func forceUnmountAfterFailure(_ failure: DiskActionFailure) async {
        guard failure.canForceUnmount else { return }
        diskActionFailure = nil
        await performDiskAction(.forceUnmount, on: failure.drive)
    }

    private func recordDiskActionFailure(action: DiskSidebarAction, drive: DriveDevice, message: String) async {
        refreshMessage = "Disk action failed: \(message)"
        guard shouldPresentDiskActionFailure(for: action) else { return }

        let inspection: DiskOpenFileInspection
        do {
            inspection = try await openFileService.inspectOpenFiles(on: drive)
        } catch {
            inspection = DiskOpenFileInspection(
                driveID: drive.id,
                driveName: drive.displayName,
                mountPoint: drive.primaryMountPoint ?? drive.deviceNode,
                processes: []
            )
        }

        diskActionFailure = DiskActionFailure(
            action: action,
            drive: drive,
            message: message,
            openFiles: inspection
        )
    }

    private func shouldPresentDiskActionFailure(for action: DiskSidebarAction) -> Bool {
        switch action {
        case .unmount, .forceUnmount, .eject, .disconnect:
            return true
        case .mount, .inspectOpenFiles, .checkLog, .detailedCheck, .rename, .revealInFinder, .refresh:
            return false
        }
    }

    func startLiveActivityMonitoring(drive: DriveDevice, interval: DiskActivitySampleInterval) {
        guard liveActivitySession.workloadState == .idle else { return }
        stopLiveActivityMonitoring()
        liveActivitySelectedDriveID = drive.id
        liveActivityStartedAt = Date()
        liveActivityEndedAt = nil
        liveActivitySamples = []
        currentLiveActivity = nil
        liveActivityError = nil

        guard !drive.isNetwork else {
            liveActivityStartedAt = nil
            liveActivityError = "Network drives do not provide per-disk IOKit activity counters."
            isLiveActivityMonitoring = false
            return
        }

        isLiveActivityMonitoring = true

        liveActivityTask = makeDiskActivityTask(for: drive, interval: interval) { [weak self] sample in
            guard let self else { return }
            self.currentLiveActivity = sample
            self.liveActivitySamples = DiskActivitySeries.appending(sample, to: self.liveActivitySamples)
        }
    }

    func stopLiveActivityMonitoring() {
        liveActivityTask?.cancel()
        liveActivityTask = nil
        if isLiveActivityMonitoring {
            liveActivityEndedAt = Date()
        }
        isLiveActivityMonitoring = false
    }

    func clearLiveActivity() {
        guard !isLiveActivityMonitoring, !isLiveActivityWorkloadRunning else { return }
        liveActivitySamples = []
        currentLiveActivity = nil
        liveActivityStartedAt = nil
        liveActivityEndedAt = nil
        liveActivityError = nil
        liveActivityWorkloadError = nil
        liveActivityWorkloadProgress = nil
    }

    func loadLiveActivityRecord(_ record: DiskActivityHistoryRecord) {
        guard !isLiveActivityMonitoring, !isLiveActivityWorkloadRunning else { return }
        liveActivitySelectedDriveID = record.driveID
        liveActivityStartedAt = record.startedAt
        liveActivityEndedAt = record.endedAt
        liveActivitySamples = record.samples
        currentLiveActivity = record.samples.last
        liveActivityError = nil
    }

    func startLiveActivityWorkload(
        configuration: DiskActivityWorkloadConfiguration,
        drive: DriveDevice,
        interval: DiskActivitySampleInterval
    ) {
        guard !isLiveActivityWorkloadRunning else { return }
        guard BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(configuration.targetFolderURL.path, drive: drive) else {
            liveActivityWorkloadError = "Workload target folder must be on the selected drive."
            return
        }

        liveActivitySelectedDriveID = drive.id
        liveActivityWorkloadError = nil
        liveActivityWorkloadProgress = DiskActivityWorkloadProgress(
            operation: configuration.operation,
            phase: .starting,
            loopIndex: 1,
            completedBytes: 0,
            totalBytes: configuration.fileSizeBytes,
            message: "Starting workload"
        )
        liveActivitySession.workloadState = .running
        CapricornLog.workload.info("Live workload started")
        let runID = UUID()
        activeLiveActivityWorkloadRunID = runID

        if !isLiveActivityMonitoring, !drive.isNetwork {
            startLiveActivityMonitoringForWorkload(drive: drive, interval: interval)
        } else if drive.isNetwork {
            liveActivityError = "Network drives do not provide per-disk IOKit activity counters."
        }

        let runner = liveActivityWorkloadRunner
        let (events, eventContinuation) = AsyncStream<DiskActivityWorkloadEvent>.makeStream()
        let eventTask = Task { @MainActor [weak self] in
            for await event in events {
                guard let self,
                      self.activeLiveActivityWorkloadRunID == runID,
                      self.liveActivitySession.workloadState == .running else { continue }
                switch event {
                case let .progress(progress):
                    self.liveActivityWorkloadProgress = progress
                }
            }
        }
        liveActivityWorkloadEventTask = eventTask
        liveActivityWorkloadTask = Task { [weak self] in
            do {
                try await runner.run(configuration: configuration, drive: drive) { progress in
                    eventContinuation.yield(.progress(progress))
                }
                eventContinuation.finish()
                await eventTask.value
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.activeLiveActivityWorkloadRunID == runID else { return }
                    self.liveActivityWorkloadProgress = DiskActivityWorkloadProgress(
                        operation: configuration.operation,
                        phase: .complete,
                        loopIndex: self.liveActivityWorkloadProgress?.loopIndex ?? 1,
                        completedBytes: configuration.fileSizeBytes,
                        totalBytes: configuration.fileSizeBytes,
                        message: "Workload complete"
                    )
                    self.isLiveActivityWorkloadRunning = false
                    self.liveActivityWorkloadTask = nil
                    self.liveActivityWorkloadEventTask = nil
                    self.activeLiveActivityWorkloadRunID = nil
                    CapricornLog.workload.info("Live workload cleanup completed")
                }
            } catch BenchmarkError.cancelled {
                eventContinuation.finish()
                await eventTask.value
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.activeLiveActivityWorkloadRunID == runID else { return }
                    self.liveActivityWorkloadProgress = DiskActivityWorkloadProgress(
                        operation: configuration.operation,
                        phase: .stopped,
                        loopIndex: self.liveActivityWorkloadProgress?.loopIndex ?? 1,
                        completedBytes: self.liveActivityWorkloadProgress?.completedBytes ?? 0,
                        totalBytes: self.liveActivityWorkloadProgress?.totalBytes ?? configuration.fileSizeBytes,
                        message: "Workload stopped"
                    )
                    self.isLiveActivityWorkloadRunning = false
                    self.liveActivityWorkloadTask = nil
                    self.liveActivityWorkloadEventTask = nil
                    self.activeLiveActivityWorkloadRunID = nil
                    CapricornLog.workload.info("Cancelled live workload cleanup completed")
                }
            } catch {
                eventContinuation.finish()
                await eventTask.value
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.activeLiveActivityWorkloadRunID == runID else { return }
                    let error = error as NSError
                    self.liveActivityWorkloadError = error.localizedDescription
                    self.isLiveActivityWorkloadRunning = false
                    self.liveActivityWorkloadTask = nil
                    self.liveActivityWorkloadEventTask = nil
                    self.activeLiveActivityWorkloadRunID = nil
                    CapricornLog.workload.error("Live workload failed: \(error.domain, privacy: .public) \(error.code)")
                }
            }
        }
    }

    func stopLiveActivityWorkload() {
        guard liveActivitySession.workloadState == .running else { return }
        liveActivitySession.workloadState = .stopping
        CapricornLog.workload.info("Live workload cancellation requested")
        liveActivityWorkloadProgress = liveActivityWorkloadProgress.map {
            DiskActivityWorkloadProgress(
                operation: $0.operation,
                phase: .stopped,
                loopIndex: $0.loopIndex,
                completedBytes: $0.completedBytes,
                totalBytes: $0.totalBytes,
                message: "Stopping workload"
            )
        }
        liveActivityWorkloadRunner.cancel()
        liveActivityWorkloadTask?.cancel()
    }

    func refreshExternalSupport() {
        externalSupport = externalDetector.detect()
    }

    private func upsertBenchmarkResult(_ result: BenchmarkResult) {
        if let index = benchmarkResults.firstIndex(where: { $0.driveID == result.driveID && $0.profileID == result.profileID && $0.testID == result.testID }) {
            benchmarkResults[index] = result
        } else {
            benchmarkResults.append(result)
        }
    }

    private func replaceBenchmarkResults(driveID: String, profileID: String, with results: [BenchmarkResult]) {
        benchmarkResults.removeAll { $0.driveID == driveID && $0.profileID == profileID }
        benchmarkResults.append(contentsOf: results)
    }

    private func publishBenchmarkProgress(_ progress: BenchmarkProgress, force: Bool = false) {
        let now = Date()
        guard force || BenchmarkProgressUpdateGate.shouldPublish(
            previous: benchmarkProgress,
            candidate: progress,
            now: now,
            lastPublishedAt: lastBenchmarkProgressPublishedAt
        ) else {
            return
        }
        benchmarkProgress = progress
        lastBenchmarkProgressPublishedAt = now
    }

    private func startDiskActivityMonitoring(for drive: DriveDevice, runID: UUID) {
        stopDiskActivityMonitoring()
        lastBenchmarkProgressPublishedAt = nil
        diskActivitySamples = []
        currentDiskActivity = nil
        guard !drive.isNetwork else { return }
        diskActivityTask = makeDiskActivityTask(for: drive, interval: Self.benchmarkActivityInterval) { [weak self] sample in
            guard let self else { return }
            guard self.activeBenchmarkRunID == runID else { return }
            self.currentDiskActivity = sample
            self.diskActivitySamples = DiskActivitySeries.appending(sample, to: self.diskActivitySamples)
        }
    }

    private func startLiveActivityMonitoringForWorkload(drive: DriveDevice, interval: DiskActivitySampleInterval) {
        stopLiveActivityMonitoring()
        liveActivitySelectedDriveID = drive.id
        liveActivityStartedAt = Date()
        liveActivityEndedAt = nil
        liveActivitySamples = []
        currentLiveActivity = nil
        liveActivityError = nil
        guard !drive.isNetwork else {
            liveActivityStartedAt = nil
            liveActivityError = "Network drives do not provide per-disk IOKit activity counters."
            isLiveActivityMonitoring = false
            return
        }
        isLiveActivityMonitoring = true

        liveActivityTask = makeDiskActivityTask(for: drive, interval: interval) { [weak self] sample in
            guard let self else { return }
            self.currentLiveActivity = sample
            self.liveActivitySamples = DiskActivitySeries.appending(sample, to: self.liveActivitySamples)
        }
    }

    private func stopDiskActivityMonitoring() {
        diskActivityTask?.cancel()
        diskActivityTask = nil
    }

    private func makeDiskActivityTask(
        for drive: DriveDevice,
        interval: DiskActivitySampleInterval,
        onSample: @MainActor @escaping (DiskActivitySample) -> Void
    ) -> Task<Void, Never> {
        guard !drive.isNetwork else {
            return Task {}
        }

        let provider = diskActivityProvider
        let bsdName = drive.bsdName
        return Task.detached(priority: .utility) {
            let monitor = DiskActivityMonitor(provider: provider)
            await monitor.run(bsdName: bsdName, interval: interval) { sample in
                await MainActor.run {
                    onSample(sample)
                }
            }
        }
    }

    static var preview: DITViewModel {
        let model = DITViewModel(
            inventoryProvider: PreviewInventoryProvider(),
            smartService: SmartSnapshotService(nativeProvider: PreviewSmartProvider(), smartctlProvider: PreviewSmartProvider()),
            benchmarkRunner: PreviewBenchmarkRunner(),
            externalDetector: ExternalDriveSupportDetector()
        )
        model.drives = PreviewInventoryProvider.previewDrives
        model.selectedDriveID = model.drives.first?.id
        model.snapshots = Dictionary(uniqueKeysWithValues: model.drives.map { drive in
            (drive.id, PreviewSmartProvider.snapshot(for: drive))
        })
        return model
    }
}

typealias DITViewModel = AppModel

private struct PreviewInventoryProvider: DiskInventoryProviding {
    static let previewDrives = [
        DriveDevice(
            bsdName: "disk0",
            deviceNode: "/dev/disk0",
            displayName: "APPLE SSD AP1024Z",
            mediaName: "APPLE SSD AP1024Z",
            protocolName: "Apple Fabric",
            sizeBytes: 1_000_555_581_440,
            blockSize: 4096,
            isInternal: true,
            isRemovable: false,
            isSolidState: true,
            isWritable: true,
            isVirtual: false,
            isSystemDisk: true,
            smartStatusRaw: "Verified",
            nativeSmartKeys: [
                "AVAILABLE_SPARE": 100,
                "AVAILABLE_SPARE_THRESHOLD": 99,
                "PERCENTAGE_USED": 2,
                "TEMPERATURE": 308,
                "MEDIA_ERRORS_0": 0,
                "POWER_ON_HOURS_0": 1295
            ],
            volumes: [
                DriveDevice.Volume(deviceIdentifier: "disk3s5", name: "Data", mountPoint: "/System/Volumes/Data", sizeBytes: 994_662_584_320, isWritable: true, isSystem: false)
            ],
            model: "APPLE SSD AP1024Z Media",
            serialNumber: "REDACTED"
        )
    ]

    func loadDrives(showVirtual: Bool) async throws -> [DriveDevice] {
        Self.previewDrives
    }
}

private struct PreviewSmartProvider: SmartProviding {
    let providerName = "Preview"

    func snapshot(for drive: DriveDevice) async -> SmartSnapshot? {
        Self.snapshot(for: drive)
    }

    static func snapshot(for drive: DriveDevice) -> SmartSnapshot {
        SmartSnapshot(
            driveID: drive.id,
            capturedAt: Date(),
            health: .good,
            summary: "SMART data does not show immediate risk for \(drive.displayName).",
            providerStatuses: [ProviderStatus(name: "Preview", state: .available, message: "Fixture data")],
            attributes: [
                SmartAttribute(id: "AVAILABLE_SPARE", name: "Available Spare", rawValue: "100%", current: nil, worst: nil, threshold: nil, status: .good, source: "Preview"),
                SmartAttribute(id: "PERCENTAGE_USED", name: "Percentage Used", rawValue: "2%", current: nil, worst: nil, threshold: nil, status: .good, source: "Preview")
            ],
            temperatureCelsius: 35,
            lifeRemainingPercent: 98,
            powerOnHours: 1295,
            powerCycleCount: 384,
            mediaErrors: 0,
            unsafeShutdowns: 35,
            smartStatusRaw: "Verified",
            selfTestStatus: nil
        )
    }
}

private final class PreviewBenchmarkRunner: BenchmarkRunning {
    func run(
        profile: BenchmarkProfile,
        drive: DriveDevice,
        volumePath: String,
        progress: @escaping @Sendable (BenchmarkProgress) -> Void,
        result: @escaping @Sendable (BenchmarkResult) -> Void
    ) async throws -> [BenchmarkResult] {
        progress(BenchmarkProgress(currentTestLabel: "Preview", completed: 1, total: 1, message: "Preview complete"))
        let previewResult = BenchmarkResult(
            driveID: drive.id,
            volumePath: volumePath,
            profileID: profile.id,
            profileName: profile.name,
            testID: "preview",
            testLabel: "SEQ1M Q1T1",
            operation: .read,
            measuredAt: Date(),
            bestMegabytesPerSecond: 4800,
            iops: 4577,
            latencyMicroseconds: 218,
            bytesTransferred: 1_073_741_824
        )
        result(previewResult)
        return [previewResult]
    }

    func cancel() {}
}
