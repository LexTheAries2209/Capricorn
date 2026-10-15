// SPDX-License-Identifier: GPL-3.0-only
import SwiftData
import XCTest
@testable import Capricorn

final class VirtualDiskTests: XCTestCase {
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
