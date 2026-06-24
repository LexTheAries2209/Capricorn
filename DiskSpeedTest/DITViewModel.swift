import Combine
import Foundation

@MainActor
final class DITViewModel: ObservableObject {
    @Published var drives: [DriveDevice] = []
    @Published var snapshots: [String: SmartSnapshot] = [:]
    @Published var selectedDriveID: String?
    @Published var isRefreshing = false
    @Published var refreshMessage: String?
    @Published var benchmarkProgress: BenchmarkProgress?
    @Published var benchmarkResults: [BenchmarkResult] = []
    @Published var benchmarkError: String?
    @Published var isBenchmarking = false
    @Published var diskActivitySamples: [DiskActivitySample] = []
    @Published var currentDiskActivity: DiskActivitySample?
    @Published var liveActivitySamples: [DiskActivitySample] = []
    @Published var currentLiveActivity: DiskActivitySample?
    @Published var isLiveActivityMonitoring = false
    @Published var liveActivitySelectedDriveID: String?
    @Published var liveActivityStartedAt: Date?
    @Published var liveActivityEndedAt: Date?
    @Published var liveActivityError: String?
    @Published var liveActivityWorkloadProgress: DiskActivityWorkloadProgress?
    @Published var liveActivityWorkloadError: String?
    @Published var isLiveActivityWorkloadRunning = false
    @Published var externalSupport: ExternalSupportStatus
    @Published var showVirtualDisks = false

    static let benchmarkActivityInterval = DiskActivitySampleInterval.default

    private let inventoryProvider: DiskInventoryProviding
    private let smartService: SmartSnapshotService
    private let benchmarkRunner: BenchmarkRunning
    private let diskActivityProvider: DiskActivityProviding
    private let liveActivityWorkloadRunner: DiskActivityWorkloadRunning
    private let externalDetector: ExternalDriveSupportDetector
    private let notificationCoordinator: NotificationCoordinator
    private var diskActivityTask: Task<Void, Never>?
    private var liveActivityTask: Task<Void, Never>?
    private var liveActivityWorkloadTask: Task<Void, Never>?

    init(
        inventoryProvider: DiskInventoryProviding = DiskutilInventoryProvider(),
        smartService: SmartSnapshotService = SmartSnapshotService(),
        benchmarkRunner: BenchmarkRunning = BenchmarkRunnerRouter(),
        diskActivityProvider: DiskActivityProviding = IOKitDiskActivityProvider(),
        liveActivityWorkloadRunner: DiskActivityWorkloadRunning = NativeDiskActivityWorkloadRunner(),
        externalDetector: ExternalDriveSupportDetector = ExternalDriveSupportDetector(),
        notificationCoordinator: NotificationCoordinator = NotificationCoordinator()
    ) {
        self.inventoryProvider = inventoryProvider
        self.smartService = smartService
        self.benchmarkRunner = benchmarkRunner
        self.diskActivityProvider = diskActivityProvider
        self.liveActivityWorkloadRunner = liveActivityWorkloadRunner
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

    func refreshIfNeeded() async {
        guard drives.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        isRefreshing = true
        refreshMessage = "Scanning disks..."
        benchmarkError = nil
        externalSupport = externalDetector.detect()
        notificationCoordinator.requestAuthorizationIfNeeded()

        do {
            let loadedDrives = try await inventoryProvider.loadDrives(showVirtual: showVirtualDisks)
            drives = loadedDrives
            if selectedDriveID == nil || !loadedDrives.contains(where: { $0.id == selectedDriveID }) {
                selectedDriveID = loadedDrives.first?.id
            }
            if liveActivitySelectedDriveID == nil || !loadedDrives.contains(where: { $0.id == liveActivitySelectedDriveID }) {
                liveActivitySelectedDriveID = selectedDriveID ?? loadedDrives.first?.id
            }

            refreshMessage = "Reading SMART data..."
            var nextSnapshots: [String: SmartSnapshot] = [:]
            for drive in loadedDrives {
                let snapshot = await smartService.snapshot(for: drive)
                nextSnapshots[drive.id] = snapshot
                notificationCoordinator.notifyIfNeeded(drive: drive, snapshot: snapshot)
            }
            snapshots = nextSnapshots
            refreshMessage = loadedDrives.isEmpty ? "No physical or network drives found." : "Last refreshed \(Date().formatted(date: .omitted, time: .standard))"
        } catch {
            refreshMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    func runBenchmark(profile: BenchmarkProfile, volumePath: String? = nil) async {
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
        isBenchmarking = true
        let measuredRuns = BenchmarkMeasurementReducer.measuredRunCount(for: profile.runs, usesTrimmedAverage: profile.usesTrimmedAverage)
        let isLooping = profile.executionMode == .loopUntilCancelled
        benchmarkProgress = BenchmarkProgress(
            currentTestLabel: "Starting",
            completed: 0,
            total: isLooping ? max(1, profile.tests.count) : profile.tests.count * (measuredRuns + 1),
            message: isLooping ? "Loop running" : "Preparing complete test file"
        )
        startDiskActivityMonitoring(for: drive)
        replaceBenchmarkResults(driveID: drive.id, profileID: profile.id, with: [])
        defer {
            stopDiskActivityMonitoring()
            isBenchmarking = false
        }

        do {
            let results = try await benchmarkRunner.run(
                profile: profile,
                drive: drive,
                volumePath: targetVolume,
                progress: { [weak self] progress in
                    self?.benchmarkProgress = progress
                },
                result: { [weak self] result in
                    self?.upsertBenchmarkResult(result)
                }
            )
            replaceBenchmarkResults(driveID: drive.id, profileID: profile.id, with: results)
        } catch {
            benchmarkError = error.localizedDescription
        }
    }

    func cancelBenchmark() {
        benchmarkRunner.cancel()
        stopDiskActivityMonitoring()
    }

    func startLiveActivityMonitoring(drive: DriveDevice, interval: DiskActivitySampleInterval) {
        guard !isLiveActivityWorkloadRunning else { return }
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
        isLiveActivityWorkloadRunning = true

        if !isLiveActivityMonitoring, !drive.isNetwork {
            startLiveActivityMonitoringForWorkload(drive: drive, interval: interval)
        } else if drive.isNetwork {
            liveActivityError = "Network drives do not provide per-disk IOKit activity counters."
        }

        let runner = liveActivityWorkloadRunner
        liveActivityWorkloadTask = Task { [weak self] in
            do {
                try await runner.run(configuration: configuration, drive: drive) { progress in
                    Task { @MainActor [weak self] in
                        self?.liveActivityWorkloadProgress = progress
                    }
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
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
                }
            } catch BenchmarkError.cancelled {
                await MainActor.run { [weak self] in
                    guard let self else { return }
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
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.liveActivityWorkloadError = error.localizedDescription
                    self.isLiveActivityWorkloadRunning = false
                    self.liveActivityWorkloadTask = nil
                }
            }
        }
    }

    func stopLiveActivityWorkload() {
        guard isLiveActivityWorkloadRunning else { return }
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

    private func startDiskActivityMonitoring(for drive: DriveDevice) {
        stopDiskActivityMonitoring()
        diskActivitySamples = []
        currentDiskActivity = nil
        guard !drive.isNetwork else { return }
        diskActivityTask = makeDiskActivityTask(for: drive, interval: Self.benchmarkActivityInterval) { [weak self] sample in
            guard let self else { return }
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
        progress: @escaping (BenchmarkProgress) -> Void,
        result: @escaping (BenchmarkResult) -> Void
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
