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

        defaults.set("/usr/bin/true", forKey: AppPreferences.Key.legacySmartctlPath)
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertTrue(preferences.usesPlainTabForFeatureSwitching)
        XCTAssertFalse(preferences.allowSystemDiskSelfTests)
        XCTAssertFalse(preferences.showsSmartSelfTestInterface)
        XCTAssertTrue(preferences.avoidWakingSleepingDisks)
        XCTAssertFalse(preferences.redactSerialNumbers)
        XCTAssertEqual(preferences.automaticRefreshInterval, .off)
        XCTAssertFalse(preferences.showsCheckAndRepairActions)
        XCTAssertEqual(preferences.representativeVolumeStartupPreference, .largestCapacity)
        preferences.languageRawValue = AppLanguage.simplifiedChinese.rawValue
        preferences.showVirtualDisks = true
        XCTAssertNil(defaults.string(forKey: AppPreferences.Key.legacySmartctlPath))
        preferences.usesPlainTabForFeatureSwitching = false
        preferences.allowSystemDiskSelfTests = true
        preferences.showsSmartSelfTestInterface = true
        preferences.avoidWakingSleepingDisks = false
        preferences.redactSerialNumbers = true
        preferences.automaticRefreshInterval = .every15Minutes
        preferences.showsCheckAndRepairActions = true
        preferences.representativeVolumeStartupPreference = .lastSelected

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.languageRawValue, AppLanguage.simplifiedChinese.rawValue)
        XCTAssertTrue(reloaded.showVirtualDisks)
        XCTAssertNil(defaults.string(forKey: AppPreferences.Key.legacySmartctlPath))
        XCTAssertFalse(reloaded.usesPlainTabForFeatureSwitching)
        XCTAssertTrue(reloaded.allowSystemDiskSelfTests)
        XCTAssertTrue(reloaded.showsSmartSelfTestInterface)
        XCTAssertFalse(reloaded.avoidWakingSleepingDisks)
        XCTAssertTrue(reloaded.redactSerialNumbers)
        XCTAssertEqual(reloaded.automaticRefreshInterval, .every15Minutes)
        XCTAssertTrue(reloaded.showsCheckAndRepairActions)
        XCTAssertEqual(reloaded.representativeVolumeStartupPreference, .lastSelected)
    }

    func testAutomaticRefreshIntervalsContainOnlySupportedChoices() {
        XCTAssertEqual(
            DiskAutomaticRefreshInterval.allCases.map(\.rawValue),
            [0, 1, 3, 5, 10, 15, 30]
        )
        XCTAssertNil(DiskAutomaticRefreshInterval.off.nanoseconds)
        XCTAssertEqual(DiskAutomaticRefreshInterval.every3Minutes.nanoseconds, 180_000_000_000)
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
        model.loadLiveActivityRecord(historyRecord, drive: drive)
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

    @MainActor
    func testDriveSystemEventsAreDebouncedIntoOneRefresh() async {
        let drive = Self.fixtureDrive(mountedAt: "/Volumes/HotPlug")
        let inventory = SequencedInventoryProvider(responses: [
            .init(delayNanoseconds: 0, drives: [drive])
        ])
        let smartService = SmartSnapshotService(
            nativeProvider: UnavailableSmartProvider(),
            smartctlProvider: UnavailableSmartProvider()
        )
        let monitor = ManualDriveSystemEventMonitor()
        let model = DITViewModel(
            inventoryProvider: inventory,
            smartService: smartService,
            driveSystemEventMonitor: monitor,
            driveSystemEventDebounceNanoseconds: 100_000_000
        )

        model.startDriveSystemEventMonitoring()
        let subscribed = await AsyncTestWaiter.wait { monitor.hasSubscriber }
        XCTAssertTrue(subscribed)

        monitor.send(.deviceAppeared)
        monitor.send(.volumeMounted)
        monitor.send(.volumeUnmounted)
        monitor.send(.deviceTerminated)

        let refreshed = await AsyncTestWaiter.wait { inventory.callCount >= 1 }
        XCTAssertTrue(refreshed)
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(inventory.callCount, 1)
        model.stopDriveSystemEventMonitoring()
    }

    @MainActor
    func testAutomaticRefreshLoopRefreshesAndStopsWhenCancelled() async {
        let drive = Self.fixtureDrive(mountedAt: "/Volumes/Periodic")
        let inventory = SequencedInventoryProvider(responses: [
            .init(delayNanoseconds: 0, drives: [drive])
        ])
        let smartService = SmartSnapshotService(
            nativeProvider: UnavailableSmartProvider(),
            smartctlProvider: UnavailableSmartProvider()
        )
        let model = DITViewModel(
            inventoryProvider: inventory,
            smartService: smartService,
            driveSystemEventMonitor: ManualDriveSystemEventMonitor()
        )
        let task = Task { @MainActor in
            await model.runAutomaticRefresh(
                every: .everyMinute,
                intervalNanoseconds: 25_000_000
            )
        }

        let refreshed = await AsyncTestWaiter.wait { inventory.callCount >= 1 }
        XCTAssertTrue(refreshed)
        task.cancel()
        await task.value
        let callsAfterCancellation = inventory.callCount
        try? await Task.sleep(nanoseconds: 75_000_000)
        XCTAssertEqual(inventory.callCount, callsAfterCancellation)
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
            smartService: smartService
        )

        let snapshot = try await service.refresh(showVirtual: false)

        XCTAssertEqual(snapshot.drives.map(\.id), [firstDrive.id, secondDrive.id])
        XCTAssertEqual(Set(snapshot.snapshots.keys), Set([firstDrive.id, secondDrive.id]))
        XCTAssertEqual(Set(smartProvider.requestedDriveIDs), Set([firstDrive.id, secondDrive.id]))
    }

    func testDiskInventoryLoadsDiskInfoConcurrently() async throws {
        let runner = ConcurrentDiskutilCommandRunner()
        let provider = DiskutilInventoryProvider(
            runner: runner,
            networkProvider: nil,
            serialNumberProvider: StaticDriveSerialProvider(
                serialNumbersByBSDName: ["disk8": "SERIAL-8", "disk9": "SERIAL-9", "disk10": "SERIAL-10"]
            )
        )

        let drives = try await provider.loadDrives(showVirtual: false)

        XCTAssertEqual(drives.map(\.bsdName), ["disk8", "disk9", "disk10"])
        XCTAssertEqual(drives.map(\.serialNumber), ["SERIAL-8", "SERIAL-9", "SERIAL-10"])
        XCTAssertEqual(runner.maximumConcurrentInfoCalls, 2)
    }

    func testDiskInventoryKeepsPhysicalDriveWhenItsInfoCallTimesOut() async throws {
        let listData = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>WholeDisks</key><array><string>disk0</string><string>disk10</string></array>
          <key>AllDisksAndPartitions</key><array>
            <dict><key>DeviceIdentifier</key><string>disk0</string><key>Size</key><integer>1000000</integer></dict>
            <dict><key>DeviceIdentifier</key><string>disk10</string><key>Size</key><integer>4000000</integer></dict>
          </array>
        </dict></plist>
        """.utf8)
        let disk0Info = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>DeviceIdentifier</key><string>disk0</string>
          <key>DeviceNode</key><string>/dev/disk0</string>
          <key>WholeDisk</key><true/>
          <key>MediaName</key><string>System SSD</string>
          <key>BusProtocol</key><string>NVMe</string>
          <key>TotalSize</key><integer>1000000</integer>
          <key>Internal</key><true/>
          <key>SolidState</key><true/>
        </dict></plist>
        """.utf8)
        let runner = HangingDiskInfoCommandRunner(
            listData: listData,
            physicalListData: listData,
            infoDataByDisk: ["disk0": disk0Info]
        )
        let provider = DiskutilInventoryProvider(
            runner: runner,
            networkProvider: nil,
            serialNumberProvider: StaticDriveSerialProvider(serialNumbersByBSDName: [:])
        )

        let drives = try await provider.loadDrives(showVirtual: false)

        XCTAssertEqual(drives.map(\.bsdName), ["disk0", "disk10"])
        let fallback = try XCTUnwrap(drives.first(where: { $0.bsdName == "disk10" }))
        XCTAssertEqual(fallback.sizeBytes, 4_000_000)
        XCTAssertEqual(fallback.deviceNode, "/dev/disk10")
        XCTAssertEqual(fallback.protocolName, "Unknown")
    }

    func testDriveRefreshPublishesFastNativeSnapshotBeforeSlowExternalDrive() async throws {
        var systemDrive = Self.fixtureDrive()
        systemDrive.bsdName = "disk0"
        systemDrive.isSystemDisk = true
        systemDrive.isSolidState = true

        var externalSSD = Self.fixtureDrive()
        externalSSD.bsdName = "disk10"
        externalSSD.isSystemDisk = false
        externalSSD.isInternal = false
        externalSSD.isSolidState = true

        var hardDrive = Self.fixtureDrive()
        hardDrive.bsdName = "disk11"
        hardDrive.isSystemDisk = false
        hardDrive.isInternal = false
        hardDrive.isSolidState = false

        let provider = DelayedSmartProvider(
            delays: [systemDrive.id: 10_000_000, externalSSD.id: 300_000_000]
        ) { drive in
            var snapshot = Self.fixtureSnapshot(for: drive)
            snapshot.providerStatuses = [ProviderStatus(name: "Native macOS", state: .available, message: "Verified")]
            return snapshot
        }
        let service = DriveRefreshService(
            inventoryProvider: SequencedInventoryProvider(responses: [.init(delayNanoseconds: 0, drives: [])]),
            smartService: SmartSnapshotService(
                nativeProvider: provider,
                smartctlProvider: UnavailableSmartProvider()
            ),
            maximumConcurrentSnapshots: 2
        )

        let startedAt = Date()
        let stream = await service.snapshotUpdates(for: [hardDrive, externalSSD, systemDrive])
        var iterator = stream.makeAsyncIterator()
        let firstUpdate = await iterator.next()
        let first = try XCTUnwrap(firstUpdate)

        XCTAssertEqual(first.phase, .native)
        XCTAssertEqual(first.driveID, systemDrive.id)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.2)
        XCTAssertEqual(Set(provider.requestedDriveIDs.prefix(2)), Set([systemDrive.id, externalSSD.id]))
    }

    @MainActor
    func testAppModelPublishesDriveDiscoveryBeforeSnapshotUpdatesFinish() async {
        let drive = Self.fixtureDrive()
        let completed = Self.fixtureSnapshot(for: drive)
        let service = StagedDriveRefreshService(
            discovery: DriveRefreshSnapshot(
                drives: [drive],
                snapshots: [drive.id: .refreshingNative(for: drive)]
            ),
            updateDelayNanoseconds: 250_000_000,
            updates: [DriveSnapshotUpdate(driveID: drive.id, snapshot: completed, phase: .complete)]
        )
        let model = DITViewModel(refreshService: service)

        let task = Task { @MainActor in await model.refresh() }
        let discoveryPublished = await AsyncTestWaiter.wait(timeout: 0.15) {
            !model.drives.isEmpty
        }

        XCTAssertTrue(discoveryPublished)
        XCTAssertTrue(model.isRefreshing)
        XCTAssertEqual(model.snapshots[drive.id]?.providerStatuses.first?.message, "Refreshing Native SMART data...")
        await task.value
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(model.snapshots[drive.id]?.capturedAt, completed.capturedAt)
    }

    func testSmartctlResolvesAllDriveTargetsWithOneScan() async {
        var firstDrive = Self.fixtureDrive()
        firstDrive.bsdName = "disk8"
        firstDrive.deviceNode = "/dev/disk8"
        var secondDrive = Self.fixtureDrive()
        secondDrive.bsdName = "disk9"
        secondDrive.deviceNode = "/dev/disk9"
        let runner = CountingSmartctlCommandRunner()
        let provider = Self.testSmartctlProvider(runner: runner)

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

    func testShellCommandRunnerTerminatesAndReapsTimedOutProcess() async {
        let runner = ShellCommandRunner()
        let startedAt = Date()

        do {
            _ = try await runner.run("/bin/sleep", arguments: ["5"], timeout: 0.1)
            XCTFail("Expected timeout")
        } catch let CommandError.timedOut(executable, seconds) {
            XCTAssertEqual(executable, "/bin/sleep")
            XCTAssertEqual(seconds, 0.1, accuracy: 0.001)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
    }

    @MainActor
    func testHistoryRepositoryPersistsAllHistoryTypesInVersionedContainer() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let repository = HistoryRepository(modelContext: container.mainContext)
        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(
                deviceIdentifier: "disk0s2",
                name: "Data",
                mountPoint: "/System/Volumes/Data",
                sizeBytes: drive.sizeBytes,
                isWritable: true,
                isSystem: false,
                volumeUUID: "persisted-volume"
            )
        ]
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

        let smartRecords = try container.mainContext.fetch(FetchDescriptor<SmartHistoryRecord>())
        let benchmarkRecords = try container.mainContext.fetch(FetchDescriptor<BenchmarkHistoryRecord>())
        let activityRecords = try container.mainContext.fetch(FetchDescriptor<DiskActivityHistoryRecord>())
        XCTAssertEqual(smartRecords.count, 1)
        XCTAssertEqual(benchmarkRecords.count, 1)
        XCTAssertEqual(activityRecords.count, 1)
        XCTAssertEqual(smartRecords.first?.volumeUUIDs, ["PERSISTED-VOLUME"])
        XCTAssertEqual(benchmarkRecords.first?.volumeUUIDs, ["PERSISTED-VOLUME"])
        XCTAssertEqual(activityRecords.first?.volumeUUIDs, ["PERSISTED-VOLUME"])
    }

    @MainActor
    func testHistoryRepositoryClearsHistoryRecordsWithoutRemovingTheContainer() throws {
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

        let removedCount = try repository.clearAllHistory()

        XCTAssertEqual(removedCount, 3)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<SmartHistoryRecord>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<BenchmarkHistoryRecord>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<DiskActivityHistoryRecord>()).isEmpty)

        // The same context remains usable after clearing the cache.
        _ = try repository.saveSmart(drive: drive, snapshot: snapshot)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SmartHistoryRecord>()).count, 1)
    }

    @MainActor
    func testHistoryRepositoryClearsOnlySelectedDriveAndCanClearHiddenOnly() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let repository = HistoryRepository(modelContext: container.mainContext)
        let selectedDrive = Self.fixtureDrive()
        var otherDrive = Self.fixtureDrive()
        otherDrive.bsdName = "disk1"
        otherDrive.serialNumber = "OTHER"

        let selectedSnapshot = try repository.saveSmart(
            drive: selectedDrive,
            snapshot: Self.fixtureSnapshot(for: selectedDrive)
        )
        _ = try repository.saveSmart(
            drive: otherDrive,
            snapshot: Self.fixtureSnapshot(for: otherDrive)
        )
        _ = try repository.saveBenchmarks(
            drive: selectedDrive,
            results: [Self.fixtureBenchmarkResult(for: selectedDrive)],
            activitySamples: []
        )
        try repository.hide(selectedSnapshot)

        let hiddenCounts = try repository.clearHiddenHistory(for: selectedDrive)
        XCTAssertEqual(hiddenCounts.visible, 0)
        XCTAssertEqual(hiddenCounts.hidden, 1)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SmartHistoryRecord>()).count, 1)

        let driveCounts = try repository.clearHistory(for: selectedDrive)
        XCTAssertEqual(driveCounts.visible, 1)
        XCTAssertEqual(driveCounts.hidden, 0)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SmartHistoryRecord>()).count, 1)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<BenchmarkHistoryRecord>()).isEmpty)
    }

    @MainActor
    func testHistoryStoreUsesDedicatedCapricornDirectory() {
        let applicationSupport = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)
        let storeURL = ModelContainerFactory.historyStoreURL(in: applicationSupport)

        XCTAssertEqual(storeURL.deletingLastPathComponent().lastPathComponent, "CapricornHistory")
        XCTAssertEqual(storeURL.lastPathComponent, "CapricornHistory.store")
    }

    @MainActor
    func testApplicationHistoryDirectoryMatchesPersistentStoreParent() throws {
        let directory = try ModelContainerFactory.applicationHistoryDirectoryURL()
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        XCTAssertEqual(
            directory,
            ModelContainerFactory.historyStoreURL(in: applicationSupport).deletingLastPathComponent()
        )
        XCTAssertEqual(directory.lastPathComponent, "CapricornHistory")
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.t("Open History Database Location"),
            "打开历史数据库位置"
        )
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.t("Clear History Database"),
            "清理历史数据库"
        )
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.t("This permanently removes all SMART, benchmark, and live-activity history from the current database. It cannot be undone."),
            "这会永久删除当前数据库中的所有 SMART、测速和实时活动历史记录，且无法撤销。"
        )
    }
}
