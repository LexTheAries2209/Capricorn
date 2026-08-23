// SPDX-License-Identifier: GPL-3.0-only
import SwiftData
import XCTest
@testable import Capricorn

extension CapricornTests {
    @MainActor
    func testAppPreferencesPreservesExistingUserDefaultsKeysAndPlainTabDefault() throws {
        let suiteName = "CapricornTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        XCTAssertTrue(preferences.usesPlainTabForFeatureSwitching)
        XCTAssertFalse(preferences.allowSystemDiskSelfTests)
        XCTAssertTrue(preferences.avoidWakingSleepingDisks)
        preferences.languageRawValue = AppLanguage.simplifiedChinese.rawValue
        preferences.showVirtualDisks = true
        preferences.smartctlPath = "/usr/bin/true"
        preferences.usesPlainTabForFeatureSwitching = false
        preferences.allowSystemDiskSelfTests = true
        preferences.avoidWakingSleepingDisks = false

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.languageRawValue, AppLanguage.simplifiedChinese.rawValue)
        XCTAssertTrue(reloaded.showVirtualDisks)
        XCTAssertEqual(reloaded.smartctlPath, "/usr/bin/true")
        XCTAssertFalse(reloaded.usesPlainTabForFeatureSwitching)
        XCTAssertTrue(reloaded.allowSystemDiskSelfTests)
        XCTAssertFalse(reloaded.avoidWakingSleepingDisks)
        reloaded.restoreAutomaticSmartctlDetection()
        XCTAssertNil(defaults.string(forKey: AppPreferences.Key.smartctlPath))
    }

    @MainActor
    func testSidebarDriveSelectionLocksToLiveActivitySessionDriveUntilStopped() {
        var firstDrive = Self.fixtureDrive(mountedAt: "/Volumes/First")
        firstDrive.bsdName = "disk8"
        var secondDrive = Self.fixtureDrive(mountedAt: "/Volumes/Second")
        secondDrive.bsdName = "disk9"
        let model = DITViewModel()
        model.drives = [firstDrive, secondDrive]
        model.selectedDriveID = firstDrive.id
        model.liveActivityDriveID = firstDrive.id

        model.isLiveActivityMonitoring = true
        model.selectDriveFromSidebar(secondDrive.id)
        XCTAssertEqual(model.selectedDriveID, firstDrive.id)

        model.isLiveActivityMonitoring = false
        model.selectDriveFromSidebar(secondDrive.id)
        XCTAssertEqual(model.selectedDriveID, secondDrive.id)
        XCTAssertEqual(model.liveActivityDriveID, firstDrive.id)

        model.isLiveActivityWorkloadRunning = true
        model.selectDriveFromSidebar(firstDrive.id)
        XCTAssertEqual(model.selectedDriveID, secondDrive.id)

        model.isLiveActivityWorkloadRunning = false
        model.selectDriveFromSidebar(firstDrive.id)
        XCTAssertEqual(model.selectedDriveID, firstDrive.id)
    }

    @MainActor
    func testRejectedCrossDriveWorkloadDoesNotReassignExistingSession() throws {
        let firstRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let secondRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }

        var firstDrive = Self.fixtureDrive(mountedAt: firstRoot.path)
        firstDrive.bsdName = "disk8"
        var secondDrive = Self.fixtureDrive(mountedAt: secondRoot.path)
        secondDrive.bsdName = "disk9"
        let model = DITViewModel()
        model.drives = [firstDrive, secondDrive]
        model.liveActivityDriveID = firstDrive.id

        model.startLiveActivityWorkload(
            configuration: DiskActivityWorkloadConfiguration(
                targetFolderURL: firstRoot,
                operation: .write,
                fileSizeOption: .gib32,
                fileSizeBytes: 16_384,
                loopEnabled: false
            ),
            drive: secondDrive,
            interval: .tenth
        )

        XCTAssertEqual(model.liveActivityDriveID, firstDrive.id)
        XCTAssertFalse(model.isLiveActivityWorkloadRunning)
        XCTAssertEqual(model.liveActivityWorkloadError, "Workload target folder must be on the selected drive.")
    }

    @MainActor
    func testLiveActivityContinueAppendsToStoppedChartForSameDrive() async {
        let drive = Self.fixtureDrive(mountedAt: "/Volumes/Unit")
        let start = Date(timeIntervalSince1970: 1_000)
        let counters = (0..<12).map { index in
            DiskActivityCounters(
                timestamp: start.addingTimeInterval(Double(index) * 0.1),
                readBytes: UInt64(index * 100_000),
                writeBytes: UInt64(index * 200_000)
            )
        }
        let model = DITViewModel(
            diskActivityProvider: FakeDiskActivityProvider(reader: FakeDiskActivityReader(counters: counters))
        )
        model.drives = [drive]
        model.liveActivityDriveID = drive.id

        model.startLiveActivityMonitoring(drive: drive, interval: .tenth)
        let initialSamplesArrived = await AsyncTestWaiter.wait {
            model.liveActivitySamples.count >= 2
        }
        XCTAssertTrue(initialSamplesArrived)
        model.stopLiveActivityMonitoring()

        let stoppedSamples = model.liveActivitySamples
        let originalStartedAt = model.liveActivityStartedAt
        XCTAssertFalse(model.isLiveActivityMonitoring)
        XCTAssertNotNil(model.liveActivityEndedAt)
        XCTAssertTrue(model.canContinueLiveActivityMonitoring(for: drive))

        var otherDrive = drive
        otherDrive.bsdName = "disk9"
        otherDrive.deviceNode = "/dev/disk9"
        XCTAssertFalse(model.canContinueLiveActivityMonitoring(for: otherDrive))

        model.continueLiveActivityMonitoring(drive: drive, interval: .tenth)
        XCTAssertTrue(model.isLiveActivityMonitoring)
        XCTAssertEqual(model.liveActivityStartedAt, originalStartedAt)
        XCTAssertNil(model.liveActivityEndedAt)

        let continuedSampleArrived = await AsyncTestWaiter.wait {
            model.liveActivitySamples.count > stoppedSamples.count
        }
        XCTAssertTrue(continuedSampleArrived)
        XCTAssertEqual(Array(model.liveActivitySamples.prefix(stoppedSamples.count)), stoppedSamples)
        model.stopLiveActivityMonitoring()
        XCTAssertTrue(model.canContinueLiveActivityMonitoring(for: drive))

        let historyRecord = DiskActivityHistoryRecord(
            drive: drive,
            samples: stoppedSamples,
            sampleInterval: .tenth,
            startedAt: originalStartedAt ?? start,
            endedAt: model.liveActivityEndedAt ?? start
        )
        model.loadLiveActivityRecord(historyRecord)
        XCTAssertFalse(model.canContinueLiveActivityMonitoring(for: drive))
    }

    @MainActor
    func testLiveActivityStartStillClearsExistingChart() {
        let drive = Self.fixtureDrive(mountedAt: "/Volumes/Unit")
        let oldStart = Date(timeIntervalSince1970: 500)
        let model = DITViewModel(
            diskActivityProvider: FakeDiskActivityProvider(reader: FakeDiskActivityReader(counters: []))
        )
        model.drives = [drive]
        model.liveActivityDriveID = drive.id
        model.liveActivityStartedAt = oldStart
        model.liveActivityEndedAt = oldStart.addingTimeInterval(10)
        model.liveActivitySamples = [
            DiskActivitySample(timestamp: oldStart, readMegabytesPerSecond: 10, writeMegabytesPerSecond: 20)
        ]

        model.startLiveActivityMonitoring(drive: drive, interval: .tenth)

        XCTAssertTrue(model.isLiveActivityMonitoring)
        XCTAssertTrue(model.liveActivitySamples.isEmpty)
        XCTAssertNil(model.currentLiveActivity)
        XCTAssertNotEqual(model.liveActivityStartedAt, oldStart)
        XCTAssertNil(model.liveActivityEndedAt)
        XCTAssertFalse(model.canContinueLiveActivityMonitoring(for: drive))
        model.stopLiveActivityMonitoring()
    }

    @MainActor
    func testLiveActivityWorkloadAutoStartsMonitoringAndStopsWithoutClearingChart() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let drive = Self.fixtureDrive(mountedAt: root.path)
        let reader = FakeDiskActivityReader(counters: [
            DiskActivityCounters(timestamp: Date(timeIntervalSince1970: 1), readBytes: 0, writeBytes: 0),
            DiskActivityCounters(timestamp: Date(timeIntervalSince1970: 2), readBytes: 1_000_000, writeBytes: 2_000_000)
        ])
        let workloadRunner = FakeDiskActivityWorkloadRunner()
        let model = DITViewModel(
            diskActivityProvider: FakeDiskActivityProvider(reader: reader),
            liveActivityWorkloadRunner: workloadRunner
        )
        model.drives = [drive]
        model.liveActivityDriveID = drive.id

        model.startLiveActivityWorkload(
            configuration: DiskActivityWorkloadConfiguration(
                targetFolderURL: root,
                operation: .write,
                fileSizeOption: .gib32,
                fileSizeBytes: 16_384,
                loopEnabled: true
            ),
            drive: drive,
            interval: .tenth
        )

        XCTAssertTrue(model.isLiveActivityWorkloadRunning)
        XCTAssertTrue(model.isLiveActivityMonitoring)

        model.stopLiveActivityWorkload()
        let didStop = await AsyncTestWaiter.wait {
            !model.isLiveActivityWorkloadRunning
        }

        XCTAssertTrue(didStop)
        XCTAssertFalse(model.isLiveActivityWorkloadRunning)
        XCTAssertTrue(model.isLiveActivityMonitoring)
        XCTAssertNil(model.liveActivityWorkloadError)
        model.stopLiveActivityMonitoring()
    }

    @MainActor
    func testLiveActivityWorkloadIgnoresLateProgressFromCancelledRunAfterRestart() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let drive = Self.fixtureDrive(mountedAt: root.path)
        let runner = RestartableLateCallbackWorkloadRunner()
        let model = DITViewModel(liveActivityWorkloadRunner: runner)
        model.drives = [drive]
        let configuration = DiskActivityWorkloadConfiguration(
            targetFolderURL: root,
            operation: .write,
            fileSizeOption: .gib32,
            fileSizeBytes: 16_384,
            loopEnabled: true
        )

        model.startLiveActivityWorkload(configuration: configuration, drive: drive, interval: .tenth)
        let firstRunStarted = await AsyncTestWaiter.wait { runner.runCount == 1 }
        XCTAssertTrue(firstRunStarted)
        model.stopLiveActivityWorkload()
        let firstRunStopped = await AsyncTestWaiter.wait { !model.isLiveActivityWorkloadRunning }
        XCTAssertTrue(firstRunStopped)

        model.startLiveActivityWorkload(configuration: configuration, drive: drive, interval: .tenth)
        let secondRunStarted = await AsyncTestWaiter.wait { runner.runCount == 2 }
        XCTAssertTrue(secondRunStarted)
        try await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertTrue(model.isLiveActivityWorkloadRunning)
        XCTAssertEqual(model.liveActivityWorkloadProgress?.message, "Run 2 active")
        model.stopLiveActivityWorkload()
    }

    @MainActor
    func testOverlappingRefreshKeepsNewestResult() async {
        var oldDrive = Self.fixtureDrive(mountedAt: "/Volumes/Old")
        oldDrive.bsdName = "disk8"
        oldDrive.deviceNode = "/dev/disk8"
        oldDrive.displayName = "Old Drive"
        var newDrive = Self.fixtureDrive(mountedAt: "/Volumes/New")
        newDrive.bsdName = "disk9"
        newDrive.deviceNode = "/dev/disk9"
        newDrive.displayName = "New Drive"

        let inventory = SequencedInventoryProvider(responses: [
            .init(delayNanoseconds: 200_000_000, drives: [oldDrive]),
            .init(delayNanoseconds: 10_000_000, drives: [newDrive])
        ])
        let smartService = SmartSnapshotService(
            nativeProvider: UnavailableSmartProvider(),
            smartctlProvider: UnavailableSmartProvider()
        )
        let model = DITViewModel(inventoryProvider: inventory, smartService: smartService)

        let first = Task { @MainActor in await model.refresh() }
        let firstRefreshStarted = await AsyncTestWaiter.wait { inventory.callCount == 1 }
        XCTAssertTrue(firstRefreshStarted)
        let second = Task { @MainActor in await model.refresh() }
        await second.value
        await first.value

        XCTAssertEqual(model.drives.map(\.displayName), ["New Drive"])
        XCTAssertEqual(model.selectedDriveID, newDrive.id)
    }

    func testDriveRefreshServiceLoadsSmartSnapshotsForEveryDrive() async throws {
        var firstDrive = Self.fixtureDrive(mountedAt: "/Volumes/First")
        firstDrive.bsdName = "disk8"
        var secondDrive = Self.fixtureDrive(mountedAt: "/Volumes/Second")
        secondDrive.bsdName = "disk9"
        let inventory = SequencedInventoryProvider(responses: [
            .init(delayNanoseconds: 0, drives: [firstDrive, secondDrive])
        ])
        let smartProvider = RecordingSmartProvider()
        let smartService = SmartSnapshotService(
            nativeProvider: smartProvider,
            smartctlProvider: UnavailableSmartProvider()
        )
        let service = DriveRefreshService(
            inventoryProvider: inventory,
            smartService: smartService,
            externalDetector: ExternalDriveSupportDetector()
        )

        let snapshot = try await service.refresh(showVirtual: false)

        XCTAssertEqual(snapshot.drives.map(\.id), [firstDrive.id, secondDrive.id])
        XCTAssertEqual(Set(snapshot.snapshots.keys), Set([firstDrive.id, secondDrive.id]))
        XCTAssertEqual(Set(smartProvider.requestedDriveIDs), Set([firstDrive.id, secondDrive.id]))
    }

    func testDiskInventoryLoadsDiskInfoConcurrently() async throws {
        let runner = ConcurrentDiskutilCommandRunner()
        let provider = DiskutilInventoryProvider(runner: runner, networkProvider: nil)

        let drives = try await provider.loadDrives(showVirtual: false)

        XCTAssertEqual(drives.map(\.bsdName), ["disk8", "disk9"])
        XCTAssertGreaterThan(runner.maximumConcurrentInfoCalls, 1)
    }

    func testSmartctlResolvesAllDriveTargetsWithOneScan() async {
        var firstDrive = Self.fixtureDrive()
        firstDrive.bsdName = "disk8"
        firstDrive.deviceNode = "/dev/disk8"
        var secondDrive = Self.fixtureDrive()
        secondDrive.bsdName = "disk9"
        secondDrive.deviceNode = "/dev/disk9"
        let runner = CountingSmartctlCommandRunner()
        let provider = SmartctlSmartProvider(
            runner: runner,
            configuredPath: "/usr/bin/true"
        )

        let targets = await provider.resolvedTargets(for: [firstDrive, secondDrive])

        XCTAssertEqual(targets[firstDrive.id], "/dev/disk8")
        XCTAssertEqual(targets[secondDrive.id], "/dev/disk9")
        XCTAssertEqual(runner.scanCallCount, 1)
    }

    func testShellCommandRunnerTerminatesProcessWhenTaskIsCancelled() async {
        let runner = ShellCommandRunner()
        let startedAt = Date()
        let task = Task {
            try await runner.run("/bin/sleep", arguments: ["2"])
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
    }

    @MainActor
    func testHistoryRepositoryPersistsAllHistoryTypesInVersionedContainer() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let repository = HistoryRepository(modelContext: container.mainContext)
        let drive = Self.fixtureDrive()
        let snapshot = Self.fixtureSnapshot(for: drive)
        let benchmark = Self.fixtureBenchmarkResult(for: drive)
        let sample = DiskActivitySample(timestamp: Date(), readMegabytesPerSecond: 1, writeMegabytesPerSecond: 2)

        try repository.saveSmart(drive: drive, snapshot: snapshot)
        try repository.saveBenchmarks(drive: drive, results: [benchmark], activitySamples: [sample])
        try repository.saveActivity(
            drive: drive,
            samples: [sample],
            sampleInterval: DiskActivitySampleInterval.default,
            startedAt: sample.timestamp,
            endedAt: sample.timestamp.addingTimeInterval(1)
        )

        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SmartHistoryRecord>()).count, 1)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<BenchmarkHistoryRecord>()).count, 1)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<DiskActivityHistoryRecord>()).count, 1)
    }

    @MainActor
    func testVersionedContainerOpensLegacyUnversionedStoreWithoutLosingHistory() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent("Capricorn.store")
        let drive = Self.fixtureDrive()

        try Self.createLegacyHistoryStore(at: storeURL, drive: drive)
        let migrated = try ModelContainerFactory.makePersistent(at: storeURL)

        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<SmartHistoryRecord>()).count, 1)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<BenchmarkHistoryRecord>()).count, 1)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<DiskActivityHistoryRecord>()).count, 1)
    }
}
