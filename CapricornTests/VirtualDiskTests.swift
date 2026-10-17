// SPDX-License-Identifier: GPL-3.0-only
import SwiftData
import XCTest
@testable import Capricorn

final class VirtualDiskTests: XCTestCase {
    func testSimulatedMediaTypesKeepExplicitClassificationAndRoundTrip() throws {
        for mediaType in VirtualDiskMediaType.allCases {
            var config = VirtualDiskConfiguration()
            config.mediaType = mediaType
            config.name = "Editable CFast SSD SD Network Name"
            let (drive, _) = try config.makeDisk()
            XCTAssertEqual(drive.mediaKind, mediaType.mediaKind)
            XCTAssertEqual(drive.isCFast, mediaType == .cfast)
            XCTAssertEqual(drive.isNetwork, mediaType == .network)
            XCTAssertEqual(drive.isMemoryCard, mediaType == .sd)
            XCTAssertEqual(drive.isSolidState, mediaType.isSolidState)
            let restored = try JSONDecoder().decode(DriveDevice.self, from: JSONEncoder().encode(drive))
            XCTAssertEqual(restored.mediaKind, mediaType.mediaKind)
            XCTAssertEqual(restored.isCFast, mediaType == .cfast)
            XCTAssertEqual(DiskSidebarActionPolicy.actions(for: drive), [.eject])
            XCTAssertEqual(drive.deviceNode, "")
            XCTAssertNil(drive.primaryMountPoint)
        }
    }

    func testBuiltInSimulationMarksSystemDiskAndKeepsPartitionsVisible() throws {
        var config = VirtualDiskConfiguration()
        config.interface = .builtIn
        config.partitions[0].capacity = "500"
        config.partitions[0].unit = .gb
        var data = VirtualDiskPartition()
        data.capacity = "500"
        data.unit = .gb
        config.partitions.append(data)
        let (drive, _) = try config.makeDisk()
        XCTAssertTrue(drive.isInternal)
        XCTAssertTrue(drive.isSystemDisk)
        XCTAssertFalse(drive.isRemovable)
        XCTAssertTrue(drive.volumes[0].isSystem)
        XCTAssertFalse(drive.volumes[1].isSystem)
        XCTAssertEqual(OverviewVolumePresentation.volumes(for: drive), drive.volumes)
        XCTAssertEqual(DiskSidebarActionPolicy.actions(for: drive), [.eject])
        XCTAssertTrue(DiskSidebarActionPolicy.isEnabled(.eject, for: drive))
        XCTAssertEqual(drive.deviceNode, "")
        XCTAssertNil(drive.primaryMountPoint)
        XCTAssertNil(drive.benchmarkMountPoint)
        XCTAssertEqual(DrivePageHeaderText.subtitle(for: drive, language: .simplifiedChinese), "内置 · SSD")
    }

    func testLegacyDrivesDecodeWithoutSimulatedMediaMetadata() throws {
        let (drive, _) = try VirtualDiskConfiguration().makeDisk()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(drive)) as? [String: Any])
        json.removeValue(forKey: "simulatedMediaKind")
        let restored = try JSONDecoder().decode(DriveDevice.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.simulatedMediaKind)
        XCTAssertEqual(restored.mediaKind, .ssd)
    }

    func testAutomaticHealthIsDefaultAndUsesOverviewMetrics() throws {
        var config = VirtualDiskConfiguration()
        XCTAssertNil(config.health)
        XCTAssertEqual(try config.makeDisk().snapshot.health, .good)

        let cases: [(life: String, mediaErrors: String, expected: HealthStatus)] = [
            ("100", "0", .good), ("21", "0", .good),
            ("20", "0", .warning), ("11", "0", .warning),
            ("10", "0", .preFail), ("1", "0", .preFail),
            ("0", "0", .failed), ("100", "1", .preFail),
            ("20", "1", .preFail), ("0", "1", .failed),
            ("", "1", .preFail), ("", "", .good)
        ]
        for item in cases {
            config.lifeRemaining = item.life
            config.mediaErrors = item.mediaErrors
            XCTAssertEqual(
                try config.makeDisk().snapshot.health, item.expected,
                "Life: \(item.life), media errors: \(item.mediaErrors)"
            )
        }
    }

    func testAutomaticHealthKeepsTemperatureAndUsageCountersSeparate() throws {
        var config = VirtualDiskConfiguration()
        config.powerOnHours = "100000"
        config.powerCycleCount = "10000"
        config.unsafeShutdowns = "1000"
        for temperature in ["", "35", "70", "85"] {
            config.temperature = temperature
            XCTAssertEqual(try config.makeDisk().snapshot.health, .good, temperature)
        }
    }

    func testManualHealthOverridesAutomaticEvaluationUntilAutomaticIsReselected() throws {
        var config = VirtualDiskConfiguration()
        config.lifeRemaining = "0"
        config.mediaErrors = "1"
        for status in HealthStatus.allCases {
            config.health = status
            XCTAssertEqual(try config.makeDisk().snapshot.health, status)
        }
        config.health = nil
        XCTAssertEqual(try config.makeDisk().snapshot.health, .failed)
    }

    @MainActor
    func testEditingAutomaticHealthRecalculatesAndPreservesSelection() throws {
        let model = AppModel()
        let drive = try model.addSimulatedDisk(VirtualDiskConfiguration())
        var config = try XCTUnwrap(model.simulatedDiskConfiguration(for: drive.id))
        XCTAssertNil(config.health)
        XCTAssertEqual(model.snapshots[drive.id]?.health, .good)

        config.lifeRemaining = "20"
        try model.updateSimulatedDisk(drive.id, configuration: config)
        XCTAssertEqual(model.snapshots[drive.id]?.health, .warning)
        XCTAssertNil(model.simulatedDiskConfiguration(for: drive.id)?.health)

        config.health = .good
        config.lifeRemaining = "0"
        try model.updateSimulatedDisk(drive.id, configuration: config)
        XCTAssertEqual(model.snapshots[drive.id]?.health, .good)
        XCTAssertEqual(model.simulatedDiskConfiguration(for: drive.id)?.health, .good)

        config.health = nil
        try model.updateSimulatedDisk(drive.id, configuration: config)
        XCTAssertEqual(model.snapshots[drive.id]?.health, .failed)
        XCTAssertNil(model.simulatedDiskConfiguration(for: drive.id)?.health)
        XCTAssertEqual(model.selectedDriveID, drive.id)
    }

    func testConfigurationBuildsOverviewWithoutRealStorageTargets() throws {
        var config = VirtualDiskConfiguration()
        config.name = "Preview SSD"
        config.serialNumber = "SAME-AS-REAL"
        config.model = "Test Model"
        config.partitions[0].capacity = "600"
        config.partitions[0].unit = .gb
        config.partitions[0].usedCapacity = "250"
        config.temperature = "42.5"
        config.powerOnHours = "123"
        let (drive, snapshot) = try config.makeDisk()

        XCTAssertTrue(drive.isVirtual)
        XCTAssertEqual(drive.displayName, "Preview SSD")
        XCTAssertEqual(drive.serialNumber, "SAME-AS-REAL")
        XCTAssertEqual(drive.sizeBytes, 1_000_000_000_000)
        XCTAssertEqual(drive.capacityUsage?.usedBytes, 250_000_000_000)
        XCTAssertEqual(config.unallocatedBytes, 400_000_000_000)
        XCTAssertEqual(snapshot.temperatureCelsius, 42.5)
        XCTAssertEqual(snapshot.powerOnHours, 123)
        XCTAssertEqual(snapshot.selectedProvider, "Simulation")
        XCTAssertEqual(drive.deviceNode, "")
        XCTAssertNil(drive.primaryMountPoint)
        XCTAssertTrue(drive.volumeUUIDs.isEmpty)
        XCTAssertNil(drive.benchmarkMountPoint)
        XCTAssertEqual(DiskSidebarActionPolicy.actions(for: drive), [.eject])
        for action in DiskSidebarAction.allCases {
            XCTAssertEqual(DiskSidebarActionPolicy.isEnabled(action, for: drive), action == .eject)
        }
    }

    func testValidationRejectsOverflowInvalidMetricsAndOverallocatedPartitions() throws {
        for capacity in ["NaN", "inf", "-1", "0", "1e100", "junk", ""] {
            var config = VirtualDiskConfiguration()
            config.capacity = capacity
            XCTAssertNotNil(config.validationMessage, capacity)
            XCTAssertThrowsError(try config.makeDisk())
        }
        var config = VirtualDiskConfiguration()
        config.partitions.append(VirtualDiskPartition())
        XCTAssertNotNil(config.validationMessage)
        config.partitions.removeLast()
        config.partitions[0].usedCapacity = "2"
        XCTAssertNotNil(config.validationMessage)
        config.partitions[0].usedCapacity = "0"
        config.lifeRemaining = "101"
        XCTAssertNotNil(config.validationMessage)
        config.lifeRemaining = ""
        config.temperature = "nan"
        XCTAssertNotNil(config.validationMessage)
        config.temperature = ""
        config.mediaErrors = "-1"
        XCTAssertNotNil(config.validationMessage)
        config.mediaErrors = ""
        config.serialNumber = ""
        config.partitions = []
        XCTAssertNil(config.validationMessage)
        let (drive, snapshot) = try config.makeDisk()
        XCTAssertNil(drive.serialNumber)
        XCTAssertTrue(drive.volumes.isEmpty)
        XCTAssertNil(snapshot.temperatureCelsius)
        XCTAssertNil(snapshot.lifeRemainingPercent)
        XCTAssertNil(snapshot.mediaErrors)
    }

    @MainActor
    func testEditingUpdatesConfigurationAndOverviewWithoutReplacingSessionIdentity() async throws {
        let refresh = StagedDriveRefreshService(
            discovery: DriveRefreshSnapshot(drives: [], snapshots: [:]),
            updateDelayNanoseconds: 0, updates: []
        )
        let model = AppModel(refreshService: refresh)
        let original = VirtualDiskConfiguration()
        let first = try model.addSimulatedDisk(original)
        let second = try model.addSimulatedDisk(original)
        model.selectedDriveID = first.id
        var edited = try XCTUnwrap(model.simulatedDiskConfiguration(for: first.id))
        edited.name = "Edited HDD"
        edited.model = "Simulated Model"
        edited.serialNumber = "SHARED-SERIAL"
        edited.capacity = "2048"
        edited.unit = .gb
        edited.mediaType = .hdd
        edited.interface = .usb
        edited.blockSize = 4096
        edited.partitions[0].name = "Archive"
        edited.partitions[0].capacity = "512"
        edited.partitions[0].unit = .gb
        edited.partitions[0].usedCapacity = "123"
        edited.partitions[0].format = .exfat
        var extra = VirtualDiskPartition()
        extra.name = "Raw"
        extra.capacity = "500"
        extra.unit = .mb
        extra.format = .unformatted
        edited.partitions.append(extra)
        edited.health = .warning
        edited.temperature = "47.5"
        edited.lifeRemaining = "82"
        edited.powerOnHours = "1234"
        edited.powerCycleCount = "45"
        edited.mediaErrors = "6"
        edited.unsafeShutdowns = "7"

        try model.updateSimulatedDisk(first.id, configuration: edited)

        XCTAssertEqual(model.drives.map(\.id), [first.id, second.id])
        XCTAssertEqual(model.selectedDriveID, first.id)
        let drive = try XCTUnwrap(model.selectedDrive)
        XCTAssertEqual(drive.displayName, edited.name)
        XCTAssertEqual(drive.model, edited.model)
        XCTAssertEqual(drive.serialNumber, edited.serialNumber)
        XCTAssertEqual(drive.sizeBytes, 2_048_000_000_000)
        XCTAssertEqual(drive.isSolidState, false)
        XCTAssertEqual(drive.protocolName, "USB")
        XCTAssertEqual(drive.blockSize, 4096)
        XCTAssertEqual(drive.volumes.map(\.name), ["Archive", "Raw"])
        XCTAssertEqual(drive.volumes[0].fileSystemType, "ExFAT")
        XCTAssertNil(drive.volumes[1].fileSystemType)
        XCTAssertEqual(drive.capacityUsage?.usedBytes, 123_000_000_000)
        let snapshot = try XCTUnwrap(model.snapshots[first.id])
        XCTAssertEqual(snapshot.driveID, first.id)
        XCTAssertEqual(snapshot.health, .warning)
        XCTAssertEqual(snapshot.temperatureCelsius, 47.5)
        XCTAssertEqual(snapshot.lifeRemainingPercent, 82)
        XCTAssertEqual(snapshot.powerOnHours, 1234)
        XCTAssertEqual(snapshot.powerCycleCount, 45)
        XCTAssertEqual(snapshot.mediaErrors, 6)
        XCTAssertEqual(snapshot.unsafeShutdowns, 7)
        let saved = try XCTUnwrap(model.simulatedDiskConfiguration(for: first.id))
        XCTAssertEqual(saved.capacity, "2048")
        XCTAssertEqual(saved.unit, .gb)
        XCTAssertEqual(saved.partitions.map(\.id), edited.partitions.map(\.id))
        XCTAssertEqual(saved.partitions[1].unit, .mb)
        XCTAssertEqual(model.drives[1], second)
        XCTAssertEqual(model.simulatedDiskConfiguration(for: second.id)?.name, original.name)

        await model.refresh()
        XCTAssertEqual(model.drives.map(\.id), [first.id, second.id])
        XCTAssertEqual(model.selectedDrive, drive)
        XCTAssertEqual(model.snapshots[first.id], snapshot)
        await model.performDiskAction(.eject, on: drive)
        XCTAssertNil(model.simulatedDiskConfiguration(for: first.id))
        XCTAssertNil(model.snapshots[first.id])
        XCTAssertEqual(model.drives, [second])
    }

    @MainActor
    func testEditingRejectsInvalidLockedPhysicalAndEjectedTargetsWithoutChangingState() async throws {
        let model = AppModel()
        let original = VirtualDiskConfiguration()
        let drive = try model.addSimulatedDisk(original)
        let snapshot = model.snapshots[drive.id]
        var invalid = original
        invalid.capacity = "0"
        XCTAssertThrowsError(try model.updateSimulatedDisk(drive.id, configuration: invalid))
        XCTAssertEqual(model.drives, [drive])
        XCTAssertEqual(model.snapshots[drive.id], snapshot)
        XCTAssertEqual(model.simulatedDiskConfiguration(for: drive.id)?.capacity, original.capacity)

        var edited = original
        edited.name = "Blocked edit"
        model.isLiveActivityMonitoring = true
        XCTAssertThrowsError(try model.updateSimulatedDisk(drive.id, configuration: edited))
        XCTAssertEqual(model.selectedDrive, drive)
        model.isLiveActivityMonitoring = false

        let physical = CapricornTests.fixtureDrive()
        model.drives.append(physical)
        XCTAssertNil(model.simulatedDiskConfiguration(for: physical.id))
        XCTAssertThrowsError(try model.updateSimulatedDisk(physical.id, configuration: edited))
        XCTAssertEqual(model.drives, [drive, physical])
        await model.performDiskAction(.eject, on: drive)
        XCTAssertNil(model.simulatedDiskConfiguration(for: drive.id))
        XCTAssertThrowsError(try model.updateSimulatedDisk(drive.id, configuration: edited))
        XCTAssertEqual(model.drives, [physical])
        XCTAssertNil(model.snapshots[drive.id])
    }

    @MainActor
    func testRefreshRetainsSimulationAndEjectDeletesItWithoutResurrection() async throws {
        var physical = CapricornTests.fixtureDrive()
        physical.isSystemDisk = true
        let refreshService = StagedDriveRefreshService(
            discovery: DriveRefreshSnapshot(drives: [physical], snapshots: [:]),
            updateDelayNanoseconds: 0, updates: []
        )
        let model = AppModel(refreshService: refreshService)
        for serial in ["", physical.serialNumber ?? "SN"] {
            var config = VirtualDiskConfiguration()
            config.serialNumber = serial
            let virtual = try model.addSimulatedDisk(config)
            let snapshot = model.snapshots[virtual.id]
            await model.refresh()
            XCTAssertEqual(model.drives.map(\.id), [physical.id, virtual.id])
            XCTAssertEqual(model.selectedDriveID, virtual.id)
            XCTAssertEqual(model.snapshots[virtual.id], snapshot)
            XCTAssertFalse(DriveStableIdentityMatcher.matches(virtual, physical))
            XCTAssertFalse(model.startBenchmark(profile: .default))
            await model.runDiskCheck(.ordinary, on: virtual)
            await model.inspectOpenFiles(on: virtual)
            model.readSmartErrorLog(for: virtual)
            XCTAssertFalse(model.isDiskChecking)
            XCTAssertNil(model.diskOpenFileInspection)
            XCTAssertTrue(model.smartErrorLogCapabilities.isEmpty)
            await model.performDiskAction(.eject, on: virtual)
            XCTAssertEqual(model.drives.map(\.id), [physical.id])
            XCTAssertNil(model.snapshots[virtual.id])
            XCTAssertEqual(model.selectedDriveID, physical.id)
            await model.refresh()
            XCTAssertFalse(model.drives.contains { $0.id == virtual.id })
        }
        let reloaded = AppModel(refreshService: refreshService)
        await reloaded.refresh()
        XCTAssertEqual(reloaded.drives.map(\.id), [physical.id])
    }

    @MainActor
    func testBulkEjectRemovesAllSimulationsWhilePhysicalMonitoringRemainsActive() async throws {
        var physical = CapricornTests.fixtureDrive()
        physical.isSystemDisk = true
        let refresh = StagedDriveRefreshService(
            discovery: DriveRefreshSnapshot(drives: [physical], snapshots: [:]),
            updateDelayNanoseconds: 0, updates: []
        )
        let model = AppModel(refreshService: refresh)
        await model.refresh()
        let originalSnapshot = model.snapshots[physical.id]
        var configuration = VirtualDiskConfiguration()
        let first = try model.addSimulatedDisk(configuration)
        configuration.serialNumber = physical.serialNumber ?? "SN"
        let second = try model.addSimulatedDisk(configuration)
        model.selectedDriveID = physical.id
        model.selectedFeatureTab = .liveActivity
        model.isLiveActivityMonitoring = true

        model.ejectAllSimulatedDisks()

        XCTAssertEqual(model.drives.map(\.id), [physical.id])
        XCTAssertNil(model.snapshots[first.id])
        XCTAssertNil(model.snapshots[second.id])
        XCTAssertNil(model.simulatedDiskConfiguration(for: first.id))
        XCTAssertNil(model.simulatedDiskConfiguration(for: second.id))
        XCTAssertEqual(model.snapshots[physical.id], originalSnapshot)
        XCTAssertEqual(model.selectedDriveID, physical.id)
        XCTAssertEqual(model.selectedFeatureTab, .liveActivity)
        XCTAssertTrue(model.isLiveActivityMonitoring)
        model.isLiveActivityMonitoring = false
        await model.refresh()
        XCTAssertEqual(model.drives.map(\.id), [physical.id])
        model.ejectAllSimulatedDisks()
        XCTAssertEqual(model.drives.map(\.id), [physical.id])
    }

    @MainActor
    func testDuplicateNamesAndSerialsHaveIndependentSessionIdentities() async throws {
        let refresh = StagedDriveRefreshService(
            discovery: DriveRefreshSnapshot(drives: [], snapshots: [:]),
            updateDelayNanoseconds: 0, updates: []
        )
        for serial in ["", "DUPLICATE-SERIAL"] {
            let model = AppModel(refreshService: refresh)
            var configuration = VirtualDiskConfiguration()
            configuration.serialNumber = serial
            let first = try model.addSimulatedDisk(configuration)
            let second = try model.addSimulatedDisk(configuration)
            XCTAssertNotEqual(first.id, second.id)
            XCTAssertFalse(DriveStableIdentityMatcher.matches(first, second))
            await model.refresh()
            XCTAssertEqual(model.drives.map(\.id), [first.id, second.id])
            await model.performDiskAction(.eject, on: first)
            XCTAssertEqual(model.drives.map(\.id), [second.id])
            XCTAssertNotNil(model.snapshots[second.id])
            let recreated = try model.addSimulatedDisk(configuration)
            XCTAssertNotEqual(recreated.id, first.id)
            XCTAssertFalse(model.drives.contains { $0.id == first.id })
        }
    }

    @MainActor
    func testSimulationNeverReadsOrWritesRealHistoryAndCachesEvenWithSameSerial() throws {
        let suite = "CapricornTests.virtualLifetime.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = SmartDiagnosticsCapabilityCache(defaults: defaults)
        let container = try ModelContainerFactory.makeInMemory()
        let repository = HistoryRepository(modelContext: container.mainContext)
        let physical = CapricornTests.fixtureDrive()
        let physicalRecord = try repository.saveSmart(
            drive: physical, snapshot: CapricornTests.fixtureSnapshot(for: physical)
        )
        let cacheRecord = SmartDiagnosticsFeatureCacheRecord(
            status: .unavailable, message: "Physical cache", selfTestCapability: nil, checkedAt: Date()
        )
        cache.store(cacheRecord, feature: .selfTest, for: physical, smartctlVersion: nil)
        let persistedCache = defaults.data(forKey: SmartDiagnosticsCapabilityCache.defaultsKey)
        for serial in ["", physical.serialNumber ?? "SN"] {
            var config = VirtualDiskConfiguration()
            config.serialNumber = serial
            let (drive, snapshot) = try config.makeDisk()
            XCTAssertFalse(HistoryDriveMatcher.matches(record: physicalRecord, drive: drive))
            XCTAssertThrowsError(try repository.saveSmart(drive: drive, snapshot: snapshot))
            XCTAssertThrowsError(try repository.saveBenchmarks(drive: drive, results: [], activitySamples: []))
            XCTAssertThrowsError(try repository.saveDiskCheckReport(
                drive: drive,
                report: DiskCheckReport(mode: .ordinary, driveID: drive.id, driveName: drive.displayName, entries: [])
            ))
            XCTAssertThrowsError(try repository.saveActivity(
                drive: drive, samples: [], sampleInterval: .fifth, startedAt: Date(), endedAt: Date()
            ))
            XCTAssertThrowsError(try repository.saveSelfTestReport(
                drive: drive,
                report: SmartSelfTestReport(
                    state: .passed, currentKind: nil, currentRemainingPercent: nil,
                    entries: [], shortSupported: false, longSupported: false, capturedAt: Date()
                )
            ))
            cache.store(cacheRecord, feature: .errorLog, for: drive, smartctlVersion: nil)
            XCTAssertNil(cache.cachedEntry(for: drive, smartctlVersion: nil))
            cache.remove(for: drive)
            XCTAssertEqual(defaults.data(forKey: SmartDiagnosticsCapabilityCache.defaultsKey), persistedCache)
            var volumes = RepresentativeVolumePreferences()
            volumes.setSelectedVolumeID(drive.volumes[0].id, for: drive)
            XCTAssertTrue(volumes.selectionsByDrive.isEmpty)
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SmartHistoryRecord>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SmartSelfTestHistoryRecord>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<DiskCheckHistoryRecord>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<BenchmarkHistoryRecord>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<DiskActivityHistoryRecord>()), 0)
    }
}
