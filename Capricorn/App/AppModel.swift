// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation
import OSLog

enum BenchmarkResultUpdatePolicy: Sendable, Equatable {
    case replaceProfile
    case mergeTests
}

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
    var smartSelfTestSession: SmartSelfTestSessionState = .idle
    var smartSelfTestDriveID: String?
    var smartSelfTestMessage: String?
    var smartSelfTestCapabilities: [String: SmartSelfTestCapabilityState] = [:]

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

    var liveActivityDriveID: String? {
        get { liveActivitySession.driveID }
        set { liveActivitySession.driveID = newValue }
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

    var isLiveActivityDriveSelectionLocked: Bool {
        isLiveActivityMonitoring || isLiveActivityWorkloadRunning
    }

    func selectDriveFromSidebar(_ driveID: String?) {
        guard !isLiveActivityDriveSelectionLocked || driveID == selectedDriveID else { return }
        selectedDriveID = driveID
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

    var firstAidState: DiskFirstAidSessionState {
        get { diskOperations.firstAidState }
        set { diskOperations.firstAidState = newValue }
    }

    var firstAidPlan: DiskFirstAidPlan? {
        get { diskOperations.firstAidPlan }
        set { diskOperations.firstAidPlan = newValue }
    }

    var firstAidReport: DiskFirstAidReport? {
        get { diskOperations.firstAidReport }
        set { diskOperations.firstAidReport = newValue }
    }

    var firstAidError: String? {
        get { diskOperations.firstAidError }
        set { diskOperations.firstAidError = newValue }
    }

    var firstAidOpenFileInspections: [DiskOpenFileInspection] {
        get { diskOperations.firstAidOpenFileInspections }
        set { diskOperations.firstAidOpenFileInspections = newValue }
    }

    var firstAidSelectedTargetIDs: Set<String> {
        get { diskOperations.firstAidSelectedTargetIDs }
        set { diskOperations.firstAidSelectedTargetIDs = newValue }
    }

    var firstAidBackupConfirmed: Bool {
        get { diskOperations.firstAidBackupConfirmed }
        set { diskOperations.firstAidBackupConfirmed = newValue }
    }

    var firstAidActivityConfirmed: Bool {
        get { diskOperations.firstAidActivityConfirmed }
        set { diskOperations.firstAidActivityConfirmed = newValue }
    }

    var firstAidHealthWarningConfirmed: Bool {
        get { diskOperations.firstAidHealthWarningConfirmed }
        set { diskOperations.firstAidHealthWarningConfirmed = newValue }
    }

    var firstAidCurrentTargetID: String? {
        get { diskOperations.firstAidCurrentTargetID }
        set { diskOperations.firstAidCurrentTargetID = newValue }
    }

    var firstAidCurrentTargetIndex: Int {
        get { diskOperations.firstAidCurrentTargetIndex }
        set { diskOperations.firstAidCurrentTargetIndex = newValue }
    }

    var firstAidTotalTargetCount: Int {
        get { diskOperations.firstAidTotalTargetCount }
        set { diskOperations.firstAidTotalTargetCount = newValue }
    }

    var firstAidLiveOutput: String {
        get { diskOperations.firstAidLiveOutput }
        set { diskOperations.firstAidLiveOutput = newValue }
    }

    var isFirstAidBlocking: Bool {
        diskOperations.isFirstAidBlocking
    }

    nonisolated static let benchmarkActivityInterval = DiskActivitySampleInterval.fifth

    private let refreshService: DriveRefreshing
    private let smartSnapshotService: SmartSnapshotService
    private let smartSelfTestService: SmartSelfTestService
    private let allowsSystemDiskSelfTests: @Sendable () -> Bool
    private let benchmarkRunner: BenchmarkRunning
    private let diskActivityProvider: DiskActivityProviding
    private let liveActivityWorkloadRunner: DiskActivityWorkloadRunning
    private let diskActionService: DiskActionService
    private let openFileService: DiskOpenFileService
    private let diskCheckService: DiskCheckService
    private let diskFirstAidService: DiskFirstAidRunning
    private let externalDetector: ExternalDriveSupportDetector
    private let notificationCoordinator: NotificationCoordinator
    private var diskActivityTask: Task<Void, Never>?
    private var liveActivityTask: Task<Void, Never>?
    private var activeLiveActivityMonitoringRunID: UUID?
    private var liveActivityBaselineRunID: UUID?
    private var liveActivityWorkloadTask: Task<Void, Never>?
    private var liveActivityWorkloadEventTask: Task<Void, Never>?
    private var activeLiveActivityWorkloadRunID: UUID?
    private var benchmarkTask: Task<Void, Never>?
    private var activeBenchmarkRunID: UUID?
    private var refreshTask: Task<Void, Never>?
    private var activeRefreshID: UUID?
    private var firstAidEventTask: Task<Void, Never>?
    private var activeFirstAidRunID: UUID?
    private var activeFirstAidPreparationID: UUID?
    private var hasRequestedNotificationAuthorization = false
    private var lastBenchmarkProgressPublishedAt: Date?
    private var smartSelfTestTask: Task<Void, Never>?
    private var smartSelfTestCapabilityTask: Task<Void, Never>?
    private var smartSelfTestRunID: UUID?

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
        diskFirstAidService: DiskFirstAidRunning = DiskFirstAidService(),
        externalDetector: ExternalDriveSupportDetector = ExternalDriveSupportDetector(),
        notificationCoordinator: NotificationCoordinator = NotificationCoordinator(),
        smartSelfTestService: SmartSelfTestService = SmartSelfTestService(),
        allowsSystemDiskSelfTests: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: AppPreferences.Key.allowSystemDiskSelfTests)
        }
    ) {
        self.smartSnapshotService = smartService
        self.smartSelfTestService = smartSelfTestService
        self.allowsSystemDiskSelfTests = allowsSystemDiskSelfTests
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
        self.diskFirstAidService = diskFirstAidService
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

    func refresh(allowDuringFirstAid: Bool = false) async {
        guard allowDuringFirstAid || !diskOperations.isFirstAidBlocking else { return }
        refreshTask?.cancel()
        let refreshID = UUID()
        activeRefreshID = refreshID
        let refreshService = refreshService
        let showVirtualDisks = showVirtualDisks
        isRefreshing = true
        refreshMessage = "Scanning disks..."
        benchmarkError = nil
        let worker = Task { [weak self] in
            do {
                let discovery = try await refreshService.discover(showVirtual: showVirtualDisks)
                try Task.checkCancellation()
                guard let self, self.activeRefreshID == refreshID else { return }
                self.applyDriveDiscovery(discovery, refreshID: refreshID)

                let updates = await refreshService.snapshotUpdates(for: discovery.drives)
                for await update in updates {
                    guard !Task.isCancelled, self.activeRefreshID == refreshID else { break }
                    self.applyDriveSnapshotUpdate(update, refreshID: refreshID)
                }
                guard !Task.isCancelled, self.activeRefreshID == refreshID else { return }
                self.refreshMessage = discovery.drives.isEmpty
                    ? "No physical or network drives found."
                    : "Last refreshed \(Date().formatted(date: .omitted, time: .standard))"
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.activeRefreshID == refreshID else { return }
                let error = error as NSError
                CapricornLog.inventory.error("Drive refresh failed: \(error.domain, privacy: .public) \(error.code)")
                self.refreshMessage = error.localizedDescription
            }

            guard let self, self.activeRefreshID == refreshID else { return }
            self.refreshTask = nil
            self.activeRefreshID = nil
            self.isRefreshing = false
        }
        refreshTask = worker
        await worker.value
    }

    private func applyDriveDiscovery(_ discovery: DriveRefreshSnapshot, refreshID: UUID) {
        guard activeRefreshID == refreshID else { return }
        let previousDrives = drives
        let previousSnapshots = snapshots
        let loadedDrives = discovery.drives

        drives = loadedDrives
        snapshots = Dictionary(uniqueKeysWithValues: loadedDrives.map { drive in
            let previousDrive = previousDrives.first { DriveStableIdentityMatcher.matches($0, drive) }
            if let previousDrive, let previousSnapshot = previousSnapshots[previousDrive.id] {
                return (drive.id, previousSnapshot.markingNativeSMARTRefreshing(for: drive))
            }
            return (drive.id, discovery.snapshots[drive.id] ?? SmartSnapshot.refreshingNative(for: drive))
        })
        if !isSmartSelfTestActive {
            smartSelfTestCapabilities = [:]
        }
        externalSupport = discovery.externalSupport
        if selectedDriveID == nil || !loadedDrives.contains(where: { $0.id == selectedDriveID }) {
            selectedDriveID = loadedDrives.first?.id
        }
        if let liveActivityDriveID,
           !loadedDrives.contains(where: { $0.id == liveActivityDriveID }),
           isLiveActivityMonitoring || isLiveActivityWorkloadRunning {
            if isLiveActivityWorkloadRunning {
                stopLiveActivityWorkload()
            }
            stopLiveActivityMonitoring()
            liveActivityError = "The active drive is no longer available."
        }
        refreshMessage = loadedDrives.isEmpty ? "No physical or network drives found." : "Reading SMART data..."
    }

    private func applyDriveSnapshotUpdate(_ update: DriveSnapshotUpdate, refreshID: UUID) {
        guard activeRefreshID == refreshID,
              let drive = drives.first(where: { $0.id == update.driveID }) else { return }
        let previous = snapshots[update.driveID]
        var refreshed = update.snapshot
        if let previous {
            refreshed = refreshed.retainingNativeSMARTDataIfNeeded(from: previous, for: drive)
            refreshed = refreshed.retainingSMARTData(from: previous, for: drive)
        }
        snapshots[update.driveID] = refreshed
        if update.phase == .complete {
            notificationCoordinator.notifyIfNeeded(drive: drive, snapshot: refreshed)
        }
    }

    @discardableResult
    func startBenchmark(
        profile: BenchmarkProfile,
        volumePath: String? = nil,
        resultUpdatePolicy: BenchmarkResultUpdatePolicy = .replaceProfile
    ) -> Bool {
        guard benchmarkTask == nil, benchmarkSession.state == .idle, !diskOperations.isFirstAidBlocking else { return false }
        benchmarkTask = Task { [weak self] in
            await self?.runBenchmark(
                profile: profile,
                volumePath: volumePath,
                resultUpdatePolicy: resultUpdatePolicy
            )
            await MainActor.run {
                self?.benchmarkTask = nil
            }
        }
        return true
    }

    func runBenchmark(
        profile: BenchmarkProfile,
        volumePath: String? = nil,
        resultUpdatePolicy: BenchmarkResultUpdatePolicy = .replaceProfile
    ) async {
        guard benchmarkSession.state == .idle, !diskOperations.isFirstAidBlocking else { return }
        guard let drive = selectedDrive else {
            benchmarkError = "Select a drive before running a benchmark."
            return
        }
        let targetVolume = volumePath ?? drive.benchmarkMountPoint
        guard let targetVolume else {
            benchmarkError = "This drive has no mounted writable volume available for safe file-based benchmarking."
            return
        }
        guard BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(targetVolume, drive: drive) else {
            benchmarkError = "The selected folder must be writable and on the selected drive."
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
        if resultUpdatePolicy == .replaceProfile {
            replaceBenchmarkResults(driveID: drive.id, profileID: profile.id, with: [])
        }
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
            switch resultUpdatePolicy {
            case .replaceProfile:
                replaceBenchmarkResults(driveID: drive.id, profileID: profile.id, with: results)
            case .mergeTests:
                results.forEach(upsertBenchmarkResult)
            }
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
        guard !diskOperations.isFirstAidBlocking else { return }
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
        guard !isDiskChecking, !diskOperations.isFirstAidBlocking else { return }
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

    func prepareFirstAid(on drive: DriveDevice) async {
        guard !diskOperations.isFirstAidBlocking,
              !isDiskChecking,
              benchmarkSession.state == .idle,
              !isLiveActivityWorkloadRunning else { return }

        selectedDriveID = drive.id
        let preparationID = UUID()
        activeFirstAidPreparationID = preparationID
        firstAidState = .preflighting
        firstAidPlan = nil
        firstAidReport = nil
        firstAidError = nil
        firstAidOpenFileInspections = []
        firstAidSelectedTargetIDs = []
        firstAidBackupConfirmed = false
        firstAidActivityConfirmed = false
        firstAidHealthWarningConfirmed = false
        firstAidLiveOutput = ""
        firstAidCurrentTargetID = nil
        firstAidCurrentTargetIndex = 0
        firstAidTotalTargetCount = 0
        refreshMessage = "Preparing First Aid..."

        do {
            let health = snapshots[drive.id]?.health ?? .unavailable
            let plan = try await diskFirstAidService.prepare(drive: drive, health: health)
            guard activeFirstAidPreparationID == preparationID else { return }
            activeFirstAidPreparationID = nil
            firstAidPlan = plan
            firstAidState = .awaitingConfirmation
            refreshMessage = plan.blockedReason == nil ? "First Aid is ready for confirmation." : plan.blockedReason?.messageKey ?? "First Aid is unavailable."
            CapricornLog.diskOperations.info("First Aid preflight completed")
        } catch {
            guard activeFirstAidPreparationID == preparationID else { return }
            activeFirstAidPreparationID = nil
            firstAidError = error.localizedDescription
            firstAidState = .completed
            refreshMessage = "First Aid preflight failed."
            CapricornLog.diskOperations.error("First Aid preflight failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func beginFirstAid() async {
        guard let plan = firstAidPlan,
              firstAidState == .awaitingConfirmation,
              plan.blockedReason == nil,
              !firstAidSelectedTargetIDs.isEmpty,
              firstAidBackupConfirmed,
              firstAidActivityConfirmed,
              !plan.requiresHealthWarningConfirmation || firstAidHealthWarningConfirmed else {
            return
        }

        firstAidOpenFileInspections = []
        for target in plan.targets where firstAidSelectedTargetIDs.contains(target.id) {
            guard let mountPoint = target.mountPoint else { continue }
            do {
                let inspection = try await openFileService.inspectOpenFiles(
                    at: mountPoint,
                    driveID: plan.driveID,
                    driveName: plan.driveName
                )
                if !inspection.processes.isEmpty {
                    firstAidOpenFileInspections.append(inspection)
                }
            } catch {
                firstAidError = error.localizedDescription
                refreshMessage = "Could not inspect open files before First Aid."
                return
            }
        }

        if !firstAidOpenFileInspections.isEmpty {
            refreshMessage = "Open files were found on the selected volume."
            return
        }

        startFirstAidExecution()
    }

    func continueFirstAidAfterOpenFiles() {
        guard firstAidState == .awaitingConfirmation,
              firstAidPlan?.blockedReason == nil else { return }
        firstAidOpenFileInspections = []
        startFirstAidExecution()
    }

    func dismissFirstAidOpenFiles() {
        guard firstAidState == .awaitingConfirmation else { return }
        firstAidOpenFileInspections = []
        firstAidError = nil
    }

    func requestFirstAidStopAfterCurrent() async {
        guard firstAidState == .running else { return }
        firstAidState = .stoppingAfterCurrent
        refreshMessage = "First Aid will stop after the current volume."
        await diskFirstAidService.requestStopAfterCurrent()
    }

    func closeFirstAid() {
        guard !firstAidState.isRepairing, firstAidState != .refreshing else { return }
        firstAidEventTask = nil
        activeFirstAidRunID = nil
        activeFirstAidPreparationID = nil
        firstAidState = .idle
        firstAidPlan = nil
        firstAidReport = nil
        firstAidError = nil
        firstAidOpenFileInspections = []
        firstAidSelectedTargetIDs = []
        firstAidLiveOutput = ""
        firstAidCurrentTargetID = nil
        firstAidCurrentTargetIndex = 0
        firstAidTotalTargetCount = 0
    }

    private func startFirstAidExecution() {
        guard let plan = firstAidPlan,
              plan.blockedReason == nil,
              !firstAidSelectedTargetIDs.isEmpty else { return }

        var runPlan = plan
        runPlan.selectedTargetIDs = firstAidSelectedTargetIDs
        firstAidPlan = runPlan
        firstAidReport = DiskFirstAidReport(
            id: runPlan.id,
            driveID: runPlan.driveID,
            driveName: runPlan.driveName,
            capturedAt: Date(),
            results: []
        )
        firstAidLiveOutput = ""
        firstAidCurrentTargetID = nil
        firstAidCurrentTargetIndex = 0
        firstAidTotalTargetCount = runPlan.selectedTargets.count
        firstAidState = .running
        refreshMessage = "First Aid is running..."
        activeFirstAidRunID = runPlan.id
        CapricornLog.diskOperations.info("First Aid started")

        let stream = diskFirstAidService.run(runPlan)
        firstAidEventTask = Task { @MainActor [weak self] in
            do {
                for try await event in stream {
                    guard let self, self.activeFirstAidRunID == runPlan.id else { continue }
                    self.applyFirstAidEvent(event)
                }
            } catch {
                guard let self, self.activeFirstAidRunID == runPlan.id else { return }
                self.firstAidError = error.localizedDescription
                self.firstAidState = .completed
                self.refreshMessage = "First Aid failed."
                self.activeFirstAidRunID = nil
                self.firstAidEventTask = nil
                CapricornLog.diskOperations.error("First Aid stream failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func applyFirstAidEvent(_ event: DiskFirstAidEvent) {
        switch event {
        case let .targetStarted(runID, target, index, total):
            guard activeFirstAidRunID == runID else { return }
            firstAidCurrentTargetID = target.id
            firstAidCurrentTargetIndex = index
            firstAidTotalTargetCount = total
            firstAidLiveOutput = ""
        case let .output(runID, targetID, stream, text):
            guard activeFirstAidRunID == runID, firstAidCurrentTargetID == targetID else { return }
            let prefix = stream == .stderr ? "[stderr] " : ""
            firstAidLiveOutput += prefix + text
        case let .targetFinished(runID, result, index, total):
            guard activeFirstAidRunID == runID else { return }
            firstAidCurrentTargetIndex = index
            firstAidTotalTargetCount = total
            if var report = firstAidReport {
                report.results.removeAll { $0.id == result.id }
                report.results.append(result)
                firstAidReport = report
            }
        case let .completed(runID, report):
            guard activeFirstAidRunID == runID else { return }
            firstAidReport = report
            firstAidState = .refreshing
            refreshMessage = "Refreshing disk information after First Aid..."
            Task { @MainActor [weak self] in
                guard let self, self.activeFirstAidRunID == runID else { return }
                await self.refresh(allowDuringFirstAid: true)
                guard self.activeFirstAidRunID == runID else { return }
                self.firstAidState = .completed
                self.activeFirstAidRunID = nil
                self.firstAidEventTask = nil
                self.refreshMessage = report.hasFailures ? "First Aid completed with issues." : "First Aid completed."
                CapricornLog.diskOperations.info("First Aid cleanup completed")
            }
        }
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
        case .mount, .inspectOpenFiles, .checkLog, .detailedCheck, .firstAid, .rename, .revealInFinder, .refresh:
            return false
        }
    }

    func startLiveActivityMonitoring(drive: DriveDevice, interval: DiskActivitySampleInterval) {
        guard liveActivitySession.workloadState == .idle, !diskOperations.isFirstAidBlocking else { return }
        stopLiveActivityMonitoring()
        liveActivityDriveID = drive.id
        liveActivitySession.continuationDriveID = nil
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

        beginLiveActivityMonitoring(drive: drive, interval: interval, skipsInitialSample: false)
    }

    func canContinueLiveActivityMonitoring(for drive: DriveDevice) -> Bool {
        !isLiveActivityMonitoring
            && !isLiveActivityWorkloadRunning
            && !diskOperations.isFirstAidBlocking
            && !drive.isNetwork
            && !liveActivitySamples.isEmpty
            && liveActivitySession.continuationDriveID == drive.id
    }

    func continueLiveActivityMonitoring(drive: DriveDevice, interval: DiskActivitySampleInterval) {
        guard canContinueLiveActivityMonitoring(for: drive) else { return }
        liveActivityDriveID = drive.id
        liveActivityEndedAt = nil
        currentLiveActivity = liveActivitySamples.last
        liveActivityError = nil
        beginLiveActivityMonitoring(drive: drive, interval: interval, skipsInitialSample: true)
    }

    func stopLiveActivityMonitoring() {
        let wasMonitoring = isLiveActivityMonitoring
        liveActivityTask?.cancel()
        liveActivityTask = nil
        activeLiveActivityMonitoringRunID = nil
        liveActivityBaselineRunID = nil
        if wasMonitoring {
            liveActivityEndedAt = Date()
            liveActivitySession.continuationDriveID = liveActivitySamples.isEmpty ? nil : liveActivityDriveID
        }
        isLiveActivityMonitoring = false
    }

    func clearLiveActivity() {
        guard !isLiveActivityMonitoring, !isLiveActivityWorkloadRunning else { return }
        liveActivitySamples = []
        currentLiveActivity = nil
        liveActivityStartedAt = nil
        liveActivityEndedAt = nil
        liveActivitySession.continuationDriveID = nil
        liveActivityError = nil
        liveActivityWorkloadError = nil
        liveActivityWorkloadProgress = nil
    }

    func loadLiveActivityRecord(_ record: DiskActivityHistoryRecord, drive: DriveDevice) {
        guard !isLiveActivityMonitoring,
              !isLiveActivityWorkloadRunning,
              HistoryDriveMatcher.matches(record: record, drive: drive) else { return }
        liveActivityDriveID = drive.id
        liveActivityStartedAt = record.startedAt
        liveActivityEndedAt = record.endedAt
        liveActivitySession.continuationDriveID = nil
        liveActivitySamples = record.samples
        currentLiveActivity = record.samples.last
        liveActivityError = nil
    }

    func startLiveActivityWorkload(
        configuration: DiskActivityWorkloadConfiguration,
        drive: DriveDevice,
        interval: DiskActivitySampleInterval
    ) {
        guard !isLiveActivityWorkloadRunning, !diskOperations.isFirstAidBlocking else { return }
        guard BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(configuration.targetFolderURL.path, drive: drive) else {
            liveActivityWorkloadError = "Workload target folder must be on the selected drive."
            return
        }

        liveActivityDriveID = drive.id
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
        Task { [weak self] in
            await self?.refresh()
        }
    }

    var isSmartSelfTestActive: Bool {
        smartSelfTestSession.isActive
    }

    func clearSmartSelfTestMessage() {
        smartSelfTestMessage = nil
    }

    func smartSelfTestCapability(for drive: DriveDevice) -> SmartSelfTestCapabilityState {
        smartSelfTestCapabilities[drive.id] ?? .unknown
    }

    func checkSmartSelfTestCapability(for drive: DriveDevice) {
        guard !isSmartSelfTestActive else { return }
        guard !drive.isSystemDisk || allowsSystemDiskSelfTests() else {
            let message = "System-disk self-tests are disabled in Settings."
            smartSelfTestCapabilities[drive.id] = .unavailable(message)
            smartSelfTestMessage = message
            return
        }

        smartSelfTestCapabilityTask?.cancel()
        smartSelfTestCapabilities[drive.id] = .checking
        smartSelfTestMessage = nil
        let service = smartSelfTestService
        smartSelfTestCapabilityTask = Task { [weak self] in
            do {
                let capability = try await service.capability(for: drive)
                await MainActor.run { [weak self] in
                    self?.smartSelfTestCapabilities[drive.id] = .supported(capability)
                    self?.smartSelfTestCapabilityTask = nil
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.smartSelfTestCapabilities[drive.id] = .unknown
                    self?.smartSelfTestCapabilityTask = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.smartSelfTestCapabilities[drive.id] = .unavailable(error.localizedDescription)
                    self?.smartSelfTestMessage = error.localizedDescription
                    self?.smartSelfTestCapabilityTask = nil
                }
            }
        }
    }

    func startSmartSelfTest(kind: SmartSelfTestKind, drive: DriveDevice) {
        guard !isSmartSelfTestActive else { return }
        guard kind == .short || kind == .long else { return }
        guard !drive.isSystemDisk || allowsSystemDiskSelfTests() else {
            let message = "System-disk self-tests are disabled in Settings."
            smartSelfTestSession = .failed(message)
            smartSelfTestMessage = message
            return
        }
        guard case let .supported(capability) = smartSelfTestCapability(for: drive), capability.supports(kind) else {
            let message = "Self-test support must be checked before a test can start."
            smartSelfTestSession = .failed(message)
            smartSelfTestMessage = message
            return
        }
        smartSelfTestTask?.cancel()
        smartSelfTestDriveID = drive.id
        let runID = UUID()
        smartSelfTestRunID = runID
        smartSelfTestMessage = nil
        smartSelfTestSession = .starting(kind)
        let service = smartSelfTestService
        let snapshotService = smartSnapshotService
        let baselineReport = snapshots[drive.id]?.selfTestReport
        smartSelfTestTask = Task { [weak self] in
            do {
                let start = try await service.start(kind: kind, drive: drive)
                await MainActor.run {
                    guard let self, self.smartSelfTestRunID == runID, self.smartSelfTestDriveID == drive.id else { return }
                    self.smartSelfTestSession = .running(kind, remainingPercent: nil)
                    self.smartSelfTestMessage = start.message.isEmpty ? nil : start.message
                }

                let target = await service.targetDescriptor(for: drive)
                let timeout = Date().addingTimeInterval(TimeInterval(max(start.estimatedDurationSeconds ?? 7_200, 7_200)))
                while !Task.isCancelled && Date() < timeout {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    let snapshot = await snapshotService.snapshot(for: drive, smartctlTargetDescriptor: target)
                    await MainActor.run {
                        guard let self, self.smartSelfTestRunID == runID, self.smartSelfTestDriveID == drive.id else { return }
                        self.snapshots[drive.id] = snapshot
                        let report = snapshot.selfTestReport
                        if let report, report.state == .running {
                            self.smartSelfTestSession = .running(kind, remainingPercent: report.currentRemainingPercent)
                        } else if let report, report.state.isTerminal,
                                  self.selfTestReportChanged(report, from: baselineReport) {
                            self.smartSelfTestSession = .idle
                            self.smartSelfTestMessage = nil
                        }
                    }
                    let finished = await MainActor.run { [weak self] in
                        guard let self, self.smartSelfTestRunID == runID, self.smartSelfTestDriveID == drive.id else { return true }
                        return !self.smartSelfTestSession.isActive
                    }
                    if finished { break }
                }

                await MainActor.run {
                    guard let self, self.smartSelfTestRunID == runID, self.smartSelfTestDriveID == drive.id else { return }
                    if self.smartSelfTestSession.isActive {
                        self.smartSelfTestSession = .failed("Self-test polling timed out.")
                    }
                    self.smartSelfTestTask = nil
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self, self.smartSelfTestRunID == runID, self.smartSelfTestDriveID == drive.id else { return }
                    self.smartSelfTestSession = .idle
                    self.smartSelfTestTask = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.smartSelfTestRunID == runID, self.smartSelfTestDriveID == drive.id else { return }
                    self.smartSelfTestSession = .failed(error.localizedDescription)
                    self.smartSelfTestMessage = error.localizedDescription
                    self.smartSelfTestCapabilities[drive.id] = .unavailable(error.localizedDescription)
                    self.smartSelfTestTask = nil
                }
            }
        }
    }

    func abortSmartSelfTest() {
        guard isSmartSelfTestActive, let driveID = smartSelfTestDriveID,
              let drive = drives.first(where: { $0.id == driveID }) else { return }
        smartSelfTestSession = .stopping
        let service = smartSelfTestService
        smartSelfTestTask?.cancel()
        let runID = UUID()
        smartSelfTestRunID = runID
        let snapshotService = smartSnapshotService
        smartSelfTestTask = Task { [weak self] in
            do {
                try await service.abort(drive: drive)
                let target = await service.targetDescriptor(for: drive)
                let snapshot = await snapshotService.snapshot(for: drive, smartctlTargetDescriptor: target)
                await MainActor.run { [weak self] in
                    guard let self, self.smartSelfTestRunID == runID else { return }
                    self.snapshots[drive.id] = snapshot
                    self.smartSelfTestSession = .idle
                    self.smartSelfTestMessage = nil
                    self.smartSelfTestTask = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.smartSelfTestRunID == runID else { return }
                    self.smartSelfTestSession = .failed(error.localizedDescription)
                    self.smartSelfTestMessage = error.localizedDescription
                    self.smartSelfTestTask = nil
                }
            }
        }
    }

    private func selfTestReportChanged(_ report: SmartSelfTestReport, from baseline: SmartSelfTestReport?) -> Bool {
        guard let baseline else { return true }
        return report.state != baseline.state
            || report.currentKind != baseline.currentKind
            || report.currentRemainingPercent != baseline.currentRemainingPercent
            || report.entries != baseline.entries
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
        liveActivityDriveID = drive.id
        liveActivitySession.continuationDriveID = nil
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
        beginLiveActivityMonitoring(drive: drive, interval: interval, skipsInitialSample: false)
    }

    private func beginLiveActivityMonitoring(
        drive: DriveDevice,
        interval: DiskActivitySampleInterval,
        skipsInitialSample: Bool
    ) {
        let runID = UUID()
        activeLiveActivityMonitoringRunID = runID
        liveActivityBaselineRunID = skipsInitialSample ? runID : nil
        isLiveActivityMonitoring = true

        liveActivityTask = makeDiskActivityTask(for: drive, interval: interval) { [weak self] sample in
            guard let self,
                  self.activeLiveActivityMonitoringRunID == runID,
                  self.isLiveActivityMonitoring else { return }
            if self.liveActivityBaselineRunID == runID {
                self.liveActivityBaselineRunID = nil
                return
            }
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
                DriveDevice.Volume(
                    deviceIdentifier: "disk3s5",
                    name: "Data",
                    mountPoint: "/System/Volumes/Data",
                    sizeBytes: 994_662_584_320,
                    isWritable: true,
                    isSystem: false,
                    fileSystemType: "APFS",
                    capacityGroupIdentifier: "apfs:disk3",
                    totalCapacityBytes: 994_662_584_320,
                    availableCapacityBytes: 412_000_000_000
                )
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
