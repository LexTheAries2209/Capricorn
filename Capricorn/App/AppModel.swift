// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation
import OSLog

enum BenchmarkResultUpdatePolicy: Sendable, Equatable {
    case replaceProfile
    case mergeTests
}

struct SmartSelfTestCompletion: Identifiable, Sendable {
    let id: UUID
    let drive: DriveDevice
    let report: SmartSelfTestReport
}

struct SidebarStatusEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let message: String

    init(id: UUID = UUID(), message: String) {
        self.id = id
        self.message = message
    }
}

@MainActor
@Observable
final class AppModel {
    var drives: [DriveDevice] = []
    var snapshots: [String: SmartSnapshot] = [:]
    var selectedDriveID: String?
    var isRefreshing = false
    var refreshMessage: String? {
        didSet {
            recordSidebarStatus(refreshMessage)
        }
    }
    private(set) var sidebarRefreshStatus: String?
    private(set) var sidebarStatusHistory: [SidebarStatusEntry] = []
    private var sidebarRefreshStatusEntryID: UUID?
    let benchmarkSession = BenchmarkSessionModel()
    let liveActivitySession = LiveActivitySessionModel()
    let diskOperations = DiskOperationsModel()
    var showVirtualDisks = false
    var selectedFeatureTab: DriveFeatureTab = .overview
    var smartSelfTestSession: SmartSelfTestSessionState = .idle
    var smartSelfTestDriveID: String?
    var smartSelfTestMessage: String?
    var smartSelfTestCapabilities: [String: SmartSelfTestCapabilityState] = [:]
    var smartErrorLogCapabilities: [String: SmartErrorLogCapabilityState] = [:]
    var smartErrorLogReports: [String: SmartErrorLogReport] = [:]
    var smartErrorLogMessage: String?
    var completedSmartSelfTest: SmartSelfTestCompletion?
    private(set) var diskCheckReportsByDrive: [String: DiskCheckReport] = [:]
    private var representativeVolumePreferences = RepresentativeVolumePreferences()
    private var activeRepresentativeVolumeIDsByDrive: [String: String] = [:]
    private var manuallySelectedRepresentativeVolumeKeys: Set<String> = []
    private var representativeVolumeStartupPreference: RepresentativeVolumeStartupPreference = .largestCapacity
    private var hasConfiguredRepresentativeVolumes = false

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

    func diskCheckReport(for drive: DriveDevice) -> DiskCheckReport? {
        diskCheckReportsByDrive[drive.id]
    }

    func restoreDiskCheckReports(from reportsBySerial: [String: DiskCheckReport]) {
        let liveDriveIDs = Set(drives.map(\.id))
        diskCheckReportsByDrive = diskCheckReportsByDrive.filter { liveDriveIDs.contains($0.key) }

        for drive in drives {
            guard let serialNumber = HistoryDriveMatcher.normalize(drive.serialNumber),
                  var report = reportsBySerial[serialNumber] else {
                diskCheckReportsByDrive.removeValue(forKey: drive.id)
                continue
            }
            report.driveID = drive.id
            report.driveName = drive.displayName
            diskCheckReportsByDrive[drive.id] = report
        }

        diskCheckReport = selectedDrive.flatMap { diskCheckReportsByDrive[$0.id] }
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
    private let smartErrorLogService: SmartErrorLogService
    private let smartDiagnosticsCapabilityCache: SmartDiagnosticsCapabilityCaching
    private let allowsSystemDiskSelfTests: @Sendable () -> Bool
    private let benchmarkRunner: BenchmarkRunning
    private let diskActivityProvider: DiskActivityProviding
    private let liveActivityWorkloadRunner: DiskActivityWorkloadRunning
    private let diskActionService: DiskActionService
    private let openFileService: DiskOpenFileService
    private let diskCheckService: DiskCheckService
    private let diskFirstAidService: DiskFirstAidRunning
    private let notificationCoordinator: NotificationCoordinator
    private let driveSystemEventMonitor: DriveSystemEventMonitoring
    private let driveSystemEventDebounceNanoseconds: UInt64
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
    private var driveSystemEventTask: Task<Void, Never>?
    private var driveSystemEventDebounceTask: Task<Void, Never>?
    private var firstAidEventTask: Task<Void, Never>?
    private var activeFirstAidRunID: UUID?
    private var activeFirstAidPreparationID: UUID?
    private var hasRequestedNotificationAuthorization = false
    private var lastBenchmarkProgressPublishedAt: Date?
    private var smartSelfTestTask: Task<Void, Never>?
    private var smartSelfTestCapabilityTasks: [String: Task<Void, Never>] = [:]
    private var smartErrorLogCapabilityTasks: [String: Task<Void, Never>] = [:]
    private var smartErrorLogReadTasks: [String: Task<Void, Never>] = [:]
    private var smartSelfTestRunID: UUID?

    init(
        inventoryProvider: DiskInventoryProviding = DiskutilInventoryProvider(),
        smartService: SmartSnapshotService = SmartSnapshotService(),
        refreshService: DriveRefreshing? = nil,
        driveSystemEventMonitor: DriveSystemEventMonitoring = SystemDriveSystemEventMonitor(),
        driveSystemEventDebounceNanoseconds: UInt64 = 750_000_000,
        benchmarkRunner: BenchmarkRunning = BenchmarkRunnerRouter(),
        diskActivityProvider: DiskActivityProviding = IOKitDiskActivityProvider(),
        liveActivityWorkloadRunner: DiskActivityWorkloadRunning = NativeDiskActivityWorkloadRunner(),
        diskActionService: DiskActionService = DiskActionService(),
        openFileService: DiskOpenFileService = DiskOpenFileService(),
        diskCheckService: DiskCheckService = DiskCheckService(),
        diskFirstAidService: DiskFirstAidRunning = DiskFirstAidService(),
        notificationCoordinator: NotificationCoordinator = NotificationCoordinator(),
        smartSelfTestService: SmartSelfTestService = SmartSelfTestService(),
        smartErrorLogService: SmartErrorLogService = SmartErrorLogService(),
        smartDiagnosticsCapabilityCache: SmartDiagnosticsCapabilityCaching = SmartDiagnosticsCapabilityCache(),
        allowsSystemDiskSelfTests: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: AppPreferences.Key.allowSystemDiskSelfTests)
        }
    ) {
        self.smartSnapshotService = smartService
        self.smartSelfTestService = smartSelfTestService
        self.smartErrorLogService = smartErrorLogService
        self.smartDiagnosticsCapabilityCache = smartDiagnosticsCapabilityCache
        self.allowsSystemDiskSelfTests = allowsSystemDiskSelfTests
        self.refreshService = refreshService ?? DriveRefreshService(
            inventoryProvider: inventoryProvider,
            smartService: smartService
        )
        self.benchmarkRunner = benchmarkRunner
        self.diskActivityProvider = diskActivityProvider
        self.liveActivityWorkloadRunner = liveActivityWorkloadRunner
        self.diskActionService = diskActionService
        self.openFileService = openFileService
        self.diskCheckService = diskCheckService
        self.diskFirstAidService = diskFirstAidService
        self.notificationCoordinator = notificationCoordinator
        self.driveSystemEventMonitor = driveSystemEventMonitor
        self.driveSystemEventDebounceNanoseconds = driveSystemEventDebounceNanoseconds
    }

    var selectedDrive: DriveDevice? {
        guard let selectedDriveID else { return drives.first }
        return drives.first(where: { $0.id == selectedDriveID }) ?? drives.first
    }

    var selectedSnapshot: SmartSnapshot? {
        guard let selectedDrive else { return nil }
        return snapshots[selectedDrive.id]
    }

    private func recordSidebarStatus(_ message: String?) {
        guard let message, !message.isEmpty,
              sidebarStatusHistory.first?.message != message else {
            return
        }
        sidebarStatusHistory.insert(SidebarStatusEntry(message: message), at: 0)
        if sidebarStatusHistory.count > 4 {
            sidebarStatusHistory.removeLast(sidebarStatusHistory.count - 4)
        }
    }

    var sidebarRecentStatusHistory: [SidebarStatusEntry] {
        Array(sidebarStatusHistory.lazy.filter { $0.id != self.sidebarRefreshStatusEntryID }.prefix(3))
    }

    private func setSidebarRefreshStatus(_ message: String) {
        refreshMessage = message
        sidebarRefreshStatus = message
        sidebarRefreshStatusEntryID = sidebarStatusHistory.first?.id
    }

    /// Applies persisted choices only once at launch. Later manual changes are
    /// kept in memory for this session even when the next-launch default is
    /// configured as the largest volume.
    func configureRepresentativeVolumes(
        startupPreference: RepresentativeVolumeStartupPreference,
        encodedPreferences: String
    ) {
        guard !hasConfiguredRepresentativeVolumes else { return }
        representativeVolumeStartupPreference = startupPreference
        representativeVolumePreferences = RepresentativeVolumePreferences.decode(encodedPreferences)
        hasConfiguredRepresentativeVolumes = true
        refreshRepresentativeVolumeSelections(for: drives)
    }

    var encodedRepresentativeVolumePreferences: String {
        representativeVolumePreferences.encoded()
    }

    func representativeVolume(for drive: DriveDevice) -> DriveDevice.Volume? {
        let key = RepresentativeVolumeResolver.preferenceKey(for: drive)
        return RepresentativeVolumeResolver.resolve(
            for: drive,
            preferredVolumeID: activeRepresentativeVolumeIDsByDrive[key]
        )
    }

    func selectRepresentativeVolume(_ volume: DriveDevice.Volume, for drive: DriveDevice) {
        guard RepresentativeVolumeResolver.maySwitchVolume(for: drive),
              RepresentativeVolumeResolver.isSelectable(volume) else {
            return
        }
        let key = RepresentativeVolumeResolver.preferenceKey(for: drive)
        activeRepresentativeVolumeIDsByDrive[key] = volume.deviceIdentifier
        manuallySelectedRepresentativeVolumeKeys.insert(key)
        representativeVolumePreferences.setSelectedVolumeID(volume.deviceIdentifier, for: drive)
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

    func startDriveSystemEventMonitoring() {
        guard driveSystemEventTask == nil else { return }
        let eventMonitor = driveSystemEventMonitor
        driveSystemEventTask = Task { [weak self] in
            for await event in eventMonitor.events() {
                guard !Task.isCancelled else { break }
                self?.scheduleRefresh(for: event)
            }
        }
    }

    func stopDriveSystemEventMonitoring() {
        driveSystemEventTask?.cancel()
        driveSystemEventTask = nil
        driveSystemEventDebounceTask?.cancel()
        driveSystemEventDebounceTask = nil
    }

    /// Runs while the main content view is active. Changing the preference
    /// replaces the SwiftUI task, so each new interval starts a fresh countdown.
    /// Periodic work never cancels a refresh or First Aid operation already in progress.
    func runAutomaticRefresh(
        every interval: DiskAutomaticRefreshInterval,
        intervalNanoseconds: UInt64? = nil
    ) async {
        guard let delay = intervalNanoseconds ?? interval.nanoseconds else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard !isRefreshing, !diskOperations.isFirstAidBlocking else { continue }
            await refresh()
        }
    }

    private func scheduleRefresh(for event: DriveSystemEvent) {
        CapricornLog.inventory.info("Scheduling refresh after system event: \(event.rawValue, privacy: .public)")
        driveSystemEventDebounceTask?.cancel()
        let delay = driveSystemEventDebounceNanoseconds
        driveSystemEventDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.driveSystemEventDebounceTask = nil
            await self.refresh()
        }
    }

    func refresh(allowDuringFirstAid: Bool = false) async {
        guard allowDuringFirstAid || !diskOperations.isFirstAidBlocking else { return }
        refreshTask?.cancel()
        let refreshID = UUID()
        activeRefreshID = refreshID
        let refreshService = refreshService
        let showVirtualDisks = showVirtualDisks
        isRefreshing = true
        setSidebarRefreshStatus("Scanning disks...")
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
                self.setSidebarRefreshStatus(
                    discovery.drives.isEmpty
                        ? "No physical or network drives found."
                        : "Last refreshed \(Date().formatted(date: .omitted, time: .standard))"
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.activeRefreshID == refreshID else { return }
                let error = error as NSError
                CapricornLog.inventory.error("Drive refresh failed: \(error.domain, privacy: .public) \(error.code)")
                self.setSidebarRefreshStatus("Disk refresh failed: \(error.localizedDescription)")
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
        refreshRepresentativeVolumeSelections(for: loadedDrives)
        snapshots = Dictionary(uniqueKeysWithValues: loadedDrives.map { drive in
            let previousDrive = previousDrives.first { DriveStableIdentityMatcher.matches($0, drive) }
            if let previousDrive, let previousSnapshot = previousSnapshots[previousDrive.id] {
                return (drive.id, previousSnapshot.markingNativeSMARTRefreshing(for: drive))
            }
            return (drive.id, discovery.snapshots[drive.id] ?? SmartSnapshot.refreshingNative(for: drive))
        })
        if selectedDriveID == nil || !loadedDrives.contains(where: { $0.id == selectedDriveID }) {
            selectedDriveID = loadedDrives.first?.id
        }
        for drive in loadedDrives {
            restoreCachedSmartDiagnosticsCapabilities(for: drive)
            startAutomaticSmartSelfTestCapabilityProbe(for: drive)
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
        setSidebarRefreshStatus(loadedDrives.isEmpty ? "No physical or network drives found." : "Reading SMART data...")
    }

    private func startAutomaticSmartSelfTestCapabilityProbe(for drive: DriveDevice) {
        guard !drive.isNetwork, !drive.isMemoryCard else { return }
        guard smartSelfTestCapabilities[drive.id] == nil else { return }

        // This is a read-only capability query (`smartctl -c --json`); it never
        // starts, aborts, or otherwise changes the drive's hardware self-test.
        probeSmartSelfTestCapability(for: drive, force: false)
    }

    private func refreshRepresentativeVolumeSelections(for drives: [DriveDevice]) {
        for drive in drives {
            let key = RepresentativeVolumeResolver.preferenceKey(for: drive)
            if let activeID = activeRepresentativeVolumeIDsByDrive[key],
               drive.volumes.contains(where: {
                   $0.deviceIdentifier == activeID && RepresentativeVolumeResolver.isSelectable($0)
               }) {
                continue
            }

            let persistedID = (manuallySelectedRepresentativeVolumeKeys.contains(key)
                || representativeVolumeStartupPreference == .lastSelected)
                ? representativeVolumePreferences.selectedVolumeID(for: drive)
                : nil
            if let volume = RepresentativeVolumeResolver.resolve(for: drive, preferredVolumeID: persistedID) {
                activeRepresentativeVolumeIDsByDrive[key] = volume.deviceIdentifier
            } else {
                activeRepresentativeVolumeIDsByDrive.removeValue(forKey: key)
            }
        }
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
        let targetVolume = volumePath ?? representativeVolume(for: drive)?.mountPoint
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
            try await diskActionService.perform(
                action,
                on: drive,
                newName: newName,
                targetVolumeID: representativeVolume(for: drive)?.deviceIdentifier
            )
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
        guard !drive.isSystemDisk || allowsSystemDiskSelfTests() else {
            refreshMessage = "System-disk self-tests are disabled in Settings."
            return
        }
        refreshMessage = "Checking disk..."
        publishDiskCheckReport(DiskCheckReport(
            mode: mode,
            driveID: drive.id,
            driveName: drive.displayName,
            entries: []
        ))
        isDiskChecking = true
        let finalReport = await diskCheckService.check(
            mode,
            drive: drive,
            allowSystemDisk: allowsSystemDiskSelfTests()
        ) { [weak self] report in
            await MainActor.run {
                self?.publishDiskCheckReport(report)
            }
        }
        publishDiskCheckReport(finalReport)
        isDiskChecking = false
        refreshMessage = "Disk check completed."
    }

    private func publishDiskCheckReport(_ report: DiskCheckReport) {
        diskCheckReportsByDrive[report.driveID] = report
        diskCheckReport = report
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

    var isSmartSelfTestActive: Bool {
        smartSelfTestSession.isActive
    }

    func clearSmartSelfTestMessage() {
        smartSelfTestMessage = nil
    }

    func smartSelfTestCapability(for drive: DriveDevice) -> SmartSelfTestCapabilityState {
        smartSelfTestCapabilities[drive.id] ?? .unknown
    }

    func smartErrorLogCapability(for drive: DriveDevice) -> SmartErrorLogCapabilityState {
        smartErrorLogCapabilities[drive.id] ?? .unknown
    }

    func hasSmartDiagnosticsState(for drive: DriveDevice) -> Bool {
        smartSelfTestCapabilities[drive.id] != nil
            || smartErrorLogCapabilities[drive.id] != nil
            || smartErrorLogReports[drive.id] != nil
            || smartDiagnosticsCapabilityCache.cachedEntry(
                for: drive,
                smartctlVersion: smartctlVersion(for: drive)
            ) != nil
    }

    func clearSmartDiagnostics(for drive: DriveDevice) {
        guard !(smartSelfTestDriveID == drive.id && isSmartSelfTestActive) else { return }

        smartSelfTestCapabilityTasks[drive.id]?.cancel()
        smartSelfTestCapabilityTasks.removeValue(forKey: drive.id)
        smartErrorLogCapabilityTasks[drive.id]?.cancel()
        smartErrorLogCapabilityTasks.removeValue(forKey: drive.id)
        smartErrorLogReadTasks[drive.id]?.cancel()
        smartErrorLogReadTasks.removeValue(forKey: drive.id)

        smartSelfTestCapabilities.removeValue(forKey: drive.id)
        smartErrorLogCapabilities.removeValue(forKey: drive.id)
        smartErrorLogReports.removeValue(forKey: drive.id)
        smartDiagnosticsCapabilityCache.remove(for: drive)

        if smartSelfTestDriveID == drive.id {
            smartSelfTestSession = .idle
            smartSelfTestDriveID = nil
            smartSelfTestMessage = nil
        }
        smartErrorLogMessage = nil
        if completedSmartSelfTest?.drive.id == drive.id {
            completedSmartSelfTest = nil
        }
    }

    func clearDiskCheckReport(for drive: DriveDevice) {
        diskCheckReportsByDrive.removeValue(forKey: drive.id)
        if diskCheckReport?.driveID == drive.id {
            diskCheckReport = nil
        }
    }

    func checkSmartSelfTestCapability(for drive: DriveDevice) {
        guard !isSmartSelfTestActive else { return }
        probeSmartSelfTestCapability(for: drive, force: true)
    }

    func checkSmartErrorLogCapability(for drive: DriveDevice) {
        probeSmartErrorLogCapability(for: drive, force: true)
    }

    func readSmartErrorLog(for drive: DriveDevice) {
        smartErrorLogReadTasks[drive.id]?.cancel()
        smartErrorLogCapabilities[drive.id] = .checking
        smartErrorLogMessage = nil
        let service = smartErrorLogService
        smartErrorLogReadTasks[drive.id] = Task { [weak self] in
            for attempt in 1...3 {
                do {
                    let report = try await service.read(for: drive)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.smartErrorLogReports[drive.id] = report
                        self.smartErrorLogCapabilities[drive.id] = report.isSupported
                            ? .supported
                            : .unavailable(report.message)
                        self.smartErrorLogMessage = report.message
                        if report.isSupported {
                            self.storeErrorLogCapability(
                                status: .supported,
                                message: report.message,
                                for: drive
                            )
                        } else {
                            self.storeErrorLogCapability(
                                status: .unavailable,
                                message: report.message,
                                for: drive
                            )
                        }
                        self.smartErrorLogReadTasks[drive.id] = nil
                    }
                    return
                } catch is CancellationError {
                    await MainActor.run { [weak self] in
                        self?.smartErrorLogReadTasks[drive.id] = nil
                    }
                    return
                } catch {
                    let message = error.localizedDescription
                    if attempt < 3 {
                        await MainActor.run { [weak self] in
                            self?.smartErrorLogCapabilities[drive.id] = .retrying(
                                message: message,
                                attempt: attempt + 1
                            )
                        }
                        try? await Task.sleep(nanoseconds: Self.retryDelayNanoseconds(after: attempt))
                        continue
                    }
                    await MainActor.run { [weak self] in
                        self?.finishErrorLogCapabilityFailure(
                            error,
                            drive: drive,
                            message: message
                        )
                        self?.smartErrorLogReadTasks[drive.id] = nil
                    }
                }
            }
        }
    }

    private func restoreCachedSmartDiagnosticsCapabilities(for drive: DriveDevice) {
        let version = smartctlVersion(for: drive)
        guard let entry = smartDiagnosticsCapabilityCache.cachedEntry(
            for: drive,
            smartctlVersion: version
        ) else {
            return
        }
        let shouldRestoreSelfTest: Bool = {
            guard let state = smartSelfTestCapabilities[drive.id] else { return true }
            if case .unknown = state { return true }
            return false
        }()
        if shouldRestoreSelfTest, let record = entry.selfTest {
            switch record.status {
            case .supported:
                if let capability = record.selfTestCapability {
                    smartSelfTestCapabilities[drive.id] = .supported(capability)
                }
            case .unavailable:
                smartSelfTestCapabilities[drive.id] = .unavailable(record.message)
            }
        }
        let shouldRestoreErrorLog: Bool = {
            guard let state = smartErrorLogCapabilities[drive.id] else { return true }
            if case .unknown = state { return true }
            return false
        }()
        if shouldRestoreErrorLog, let record = entry.errorLog {
            smartErrorLogCapabilities[drive.id] = record.status == .supported
                ? .supported
                : .unavailable(record.message)
        }
    }

    private func probeSmartSelfTestCapability(for drive: DriveDevice, force: Bool) {
        if !force, smartSelfTestCapabilities[drive.id] != nil { return }
        smartSelfTestCapabilityTasks[drive.id]?.cancel()
        smartSelfTestCapabilities[drive.id] = .checking
        smartSelfTestMessage = nil
        let service = smartSelfTestService
        smartSelfTestCapabilityTasks[drive.id] = Task { [weak self] in
            do {
                let capability = try await service.capability(for: drive)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.smartSelfTestCapabilities[drive.id] = .supported(capability)
                    self.storeSelfTestCapability(
                        capability,
                        status: .supported,
                        message: capability.message,
                        for: drive
                    )
                    self.smartSelfTestCapabilityTasks[drive.id] = nil
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.smartSelfTestCapabilityTasks[drive.id] = nil
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.finishSelfTestCapabilityFailure(error, drive: drive, message: message)
                    self?.smartSelfTestCapabilityTasks[drive.id] = nil
                }
            }
        }
    }

    private func probeSmartErrorLogCapability(for drive: DriveDevice, force: Bool) {
        if !force, smartErrorLogCapabilities[drive.id] != nil { return }
        smartErrorLogCapabilityTasks[drive.id]?.cancel()
        smartErrorLogCapabilities[drive.id] = .checking
        let service = smartErrorLogService
        smartErrorLogCapabilityTasks[drive.id] = Task { [weak self] in
            do {
                try await service.capability(for: drive)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.smartErrorLogCapabilities[drive.id] = .supported
                    self.storeErrorLogCapability(
                        status: .supported,
                        message: "SMART error log capability confirmed.",
                        for: drive
                    )
                    self.smartErrorLogCapabilityTasks[drive.id] = nil
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.smartErrorLogCapabilityTasks[drive.id] = nil
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.finishErrorLogCapabilityFailure(error, drive: drive, message: message)
                    self?.smartErrorLogCapabilityTasks[drive.id] = nil
                }
            }
        }
    }

    private func finishSelfTestCapabilityFailure(
        _ error: Error,
        drive: DriveDevice,
        message: String
    ) {
        if isDefinitiveSelfTestUnsupported(error) {
            smartSelfTestCapabilities[drive.id] = .unavailable(message)
            smartSelfTestMessage = message
            storeSelfTestCapability(nil, status: .unavailable, message: message, for: drive)
        } else {
            smartSelfTestCapabilities[drive.id] = .unknown
            smartSelfTestMessage = "Self-test support could not be verified. Use Retry Self-Test Check to try again."
        }
    }

    private func finishErrorLogCapabilityFailure(
        _ error: Error,
        drive: DriveDevice,
        message: String
    ) {
        if isDefinitiveErrorLogUnsupported(error) {
            smartErrorLogCapabilities[drive.id] = .unavailable(message)
            smartErrorLogMessage = message
            storeErrorLogCapability(status: .unavailable, message: message, for: drive)
        } else {
            smartErrorLogCapabilities[drive.id] = .unknown
            smartErrorLogMessage = "SMART error log support could not be verified. Use Retry Error Log Check to try again."
        }
    }

    private func storeSelfTestCapability(
        _ capability: SmartSelfTestCapability?,
        status: SmartDiagnosticsCachedStatus,
        message: String,
        for drive: DriveDevice
    ) {
        smartDiagnosticsCapabilityCache.store(
            SmartDiagnosticsFeatureCacheRecord(
                status: status,
                message: message,
                selfTestCapability: capability,
                checkedAt: Date()
            ),
            feature: .selfTest,
            for: drive,
            smartctlVersion: smartctlVersion(for: drive)
        )
    }

    private func storeErrorLogCapability(
        status: SmartDiagnosticsCachedStatus,
        message: String,
        for drive: DriveDevice
    ) {
        smartDiagnosticsCapabilityCache.store(
            SmartDiagnosticsFeatureCacheRecord(
                status: status,
                message: message,
                selfTestCapability: nil,
                checkedAt: Date()
            ),
            feature: .errorLog,
            for: drive,
            smartctlVersion: smartctlVersion(for: drive)
        )
    }

    private func smartctlVersion(for drive: DriveDevice) -> String? {
        snapshots[drive.id]?.smartctlDiagnostics?.version
    }

    private func isDefinitiveSelfTestUnsupported(_ error: Error) -> Bool {
        guard let serviceError = error as? SmartSelfTestServiceError else { return false }
        if case .unsupported = serviceError {
            return true
        }
        return false
    }

    private func isDefinitiveErrorLogUnsupported(_ error: Error) -> Bool {
        guard let serviceError = error as? SmartErrorLogServiceError else { return false }
        if case .unsupported = serviceError {
            return true
        }
        return false
    }

    nonisolated private static func retryDelayNanoseconds(after failedAttempt: Int) -> UInt64 {
        switch failedAttempt {
        case 1: 250_000_000
        case 2: 750_000_000
        default: 1_500_000_000
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
                            self.completedSmartSelfTest = SmartSelfTestCompletion(
                                id: UUID(),
                                drive: drive,
                                report: report
                            )
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
        let baselineReport = snapshots[drive.id]?.selfTestReport
        smartSelfTestTask = Task { [weak self] in
            do {
                try await service.abort(drive: drive)
                let target = await service.targetDescriptor(for: drive)
                let snapshot = await snapshotService.snapshot(for: drive, smartctlTargetDescriptor: target)
                await MainActor.run { [weak self] in
                    guard let self, self.smartSelfTestRunID == runID else { return }
                    self.snapshots[drive.id] = snapshot
                    if let report = snapshot.selfTestReport,
                       report.state.isTerminal,
                       self.selfTestReportChanged(report, from: baselineReport) {
                        self.completedSmartSelfTest = SmartSelfTestCompletion(
                            id: UUID(),
                            drive: drive,
                            report: report
                        )
                    }
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
            benchmarkRunner: PreviewBenchmarkRunner()
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
