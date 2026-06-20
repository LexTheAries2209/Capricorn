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
    @Published var externalSupport: ExternalSupportStatus
    @Published var showVirtualDisks = false

    private let inventoryProvider: DiskInventoryProviding
    private let smartService: SmartSnapshotService
    private let benchmarkRunner: BenchmarkRunning
    private let externalDetector: ExternalDriveSupportDetector
    private let notificationCoordinator: NotificationCoordinator

    init(
        inventoryProvider: DiskInventoryProviding = DiskutilInventoryProvider(),
        smartService: SmartSnapshotService = SmartSnapshotService(),
        benchmarkRunner: BenchmarkRunning = NativeBenchmarkRunner(),
        externalDetector: ExternalDriveSupportDetector = ExternalDriveSupportDetector(),
        notificationCoordinator: NotificationCoordinator = NotificationCoordinator()
    ) {
        self.inventoryProvider = inventoryProvider
        self.smartService = smartService
        self.benchmarkRunner = benchmarkRunner
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

            refreshMessage = "Reading SMART data..."
            var nextSnapshots: [String: SmartSnapshot] = [:]
            for drive in loadedDrives {
                let snapshot = await smartService.snapshot(for: drive)
                nextSnapshots[drive.id] = snapshot
                notificationCoordinator.notifyIfNeeded(drive: drive, snapshot: snapshot)
            }
            snapshots = nextSnapshots
            refreshMessage = loadedDrives.isEmpty ? "No physical drives found." : "Last refreshed \(Date().formatted(date: .omitted, time: .standard))"
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
        benchmarkProgress = BenchmarkProgress(currentTestLabel: "Starting", completed: 0, total: profile.tests.count * max(1, profile.runs), message: "Creating benchmark file")
        defer {
            isBenchmarking = false
        }

        do {
            let results = try await benchmarkRunner.run(profile: profile, drive: drive, volumePath: targetVolume) { [weak self] progress in
                self?.benchmarkProgress = progress
            }
            benchmarkResults = results
        } catch {
            benchmarkError = error.localizedDescription
        }
    }

    func cancelBenchmark() {
        benchmarkRunner.cancel()
    }

    func refreshExternalSupport() {
        externalSupport = externalDetector.detect()
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
        progress: @escaping (BenchmarkProgress) -> Void
    ) async throws -> [BenchmarkResult] {
        progress(BenchmarkProgress(currentTestLabel: "Preview", completed: 1, total: 1, message: "Preview complete"))
        return [
            BenchmarkResult(
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
        ]
    }

    func cancel() {}
}
