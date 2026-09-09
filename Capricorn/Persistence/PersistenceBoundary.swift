// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import OSLog
import SwiftData

enum CapricornSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            SmartHistoryRecord.self,
            BenchmarkHistoryRecord.self,
            DiskActivityHistoryRecord.self,
            AppSettingsRecord.self
        ]
    }
}

enum CapricornSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            SmartHistoryRecord.self,
            SmartSelfTestHistoryRecord.self,
            BenchmarkHistoryRecord.self,
            DiskActivityHistoryRecord.self,
            AppSettingsRecord.self
        ]
    }
}

enum CapricornSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(4, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            SmartHistoryRecord.self,
            SmartSelfTestHistoryRecord.self,
            DiskCheckHistoryRecord.self,
            BenchmarkHistoryRecord.self,
            DiskActivityHistoryRecord.self,
            AppSettingsRecord.self
        ]
    }
}

enum CapricornMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CapricornSchemaV2.self, CapricornSchemaV3.self, CapricornSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: CapricornSchemaV2.self,
                toVersion: CapricornSchemaV3.self
            ),
            .lightweight(
                fromVersion: CapricornSchemaV3.self,
                toVersion: CapricornSchemaV4.self
            )
        ]
    }
}

@MainActor
enum ModelContainerFactory {
    static let historyDirectoryName = "CapricornHistory"
    static let historyStoreFileName = "CapricornHistory.store"

    static func makeApplication() throws -> ModelContainer {
        let directory = try applicationHistoryDirectoryURL()
        let storeURL = directory.appendingPathComponent(historyStoreFileName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try makePersistent(at: storeURL)
    }

    static func applicationHistoryDirectoryURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return historyStoreURL(in: applicationSupport).deletingLastPathComponent()
    }

    static func historyStoreURL(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(historyDirectoryName, isDirectory: true)
            .appendingPathComponent(historyStoreFileName)
    }

    static func makePreview() throws -> ModelContainer {
        try make(isStoredInMemoryOnly: true)
    }

    static func makeInMemory() throws -> ModelContainer {
        try make(isStoredInMemoryOnly: true)
    }

    static func makePersistent(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CapricornSchemaV4.self)
        let configuration = ModelConfiguration(
            "Capricorn",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: CapricornMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func make(isStoredInMemoryOnly: Bool) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CapricornSchemaV4.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: CapricornMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

@MainActor
final class HistoryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func saveSmart(drive: DriveDevice, snapshot: SmartSnapshot) throws -> SmartHistoryRecord {
        let record = SmartHistoryRecord(drive: drive, snapshot: snapshot)
        modelContext.insert(record)
        try modelContext.save()
        CapricornLog.persistence.info("SMART history saved")
        return record
    }

    @discardableResult
    func saveSelfTestReport(
        drive: DriveDevice,
        report: SmartSelfTestReport
    ) throws -> SmartSelfTestHistoryRecord {
        let existing = try modelContext.fetch(FetchDescriptor<SmartSelfTestHistoryRecord>())
        let fingerprint = SmartSelfTestHistoryRecord.fingerprint(for: report)
        if let duplicate = existing.first(where: {
            HistoryDriveMatcher.matches(record: $0, drive: drive) && $0.fingerprint == fingerprint
        }) {
            return duplicate
        }
        let record = SmartSelfTestHistoryRecord(drive: drive, report: report)
        modelContext.insert(record)
        try modelContext.save()
        CapricornLog.persistence.info("SMART self-test history saved")
        return record
    }

    @discardableResult
    func saveDiskCheckReport(
        drive: DriveDevice,
        report: DiskCheckReport
    ) throws -> DiskCheckHistoryRecord? {
        guard let serialNumber = HistoryDriveMatcher.normalize(drive.serialNumber) else {
            CapricornLog.persistence.info("Disk check history skipped because the drive has no serial number")
            return nil
        }

        let existing = try modelContext.fetch(FetchDescriptor<DiskCheckHistoryRecord>())
            .first { HistoryDriveMatcher.normalize($0.serialNumber) == serialNumber }
        let record = existing ?? DiskCheckHistoryRecord(drive: drive, report: report)
        record.serialNumber = serialNumber
        record.driveName = drive.displayName
        record.capturedAt = report.capturedAt
        record.encodedReport = try JSONEncoder.dit.encode(report)
        // Quick disk checks are always current and cannot be hidden.
        record.hiddenAt = nil
        if existing == nil {
            modelContext.insert(record)
        }
        try modelContext.save()
        CapricornLog.persistence.info("Disk check history saved")
        return record
    }

    @discardableResult
    func saveBenchmarks(
        drive: DriveDevice,
        results: [BenchmarkResult],
        activitySamples: [DiskActivitySample]
    ) throws -> [BenchmarkHistoryRecord] {
        let records = results.map {
            BenchmarkHistoryRecord(drive: drive, result: $0, activitySamples: activitySamples)
        }
        records.forEach(modelContext.insert)
        try modelContext.save()
        CapricornLog.persistence.info("Benchmark history saved with \(records.count) records")
        return records
    }

    @discardableResult
    func saveActivity(
        drive: DriveDevice,
        samples: [DiskActivitySample],
        sampleInterval: DiskActivitySampleInterval,
        startedAt: Date,
        endedAt: Date
    ) throws -> DiskActivityHistoryRecord {
        let record = DiskActivityHistoryRecord(
            drive: drive,
            samples: samples,
            sampleInterval: sampleInterval,
            startedAt: startedAt,
            endedAt: endedAt
        )
        modelContext.insert(record)
        try modelContext.save()
        CapricornLog.persistence.info("Activity history saved")
        return record
    }

    func hide<T: HistoryDisplayRecord>(_ record: T, at date: Date = Date()) throws {
        HistoryVisibility.hide(record, at: date)
        try modelContext.save()
    }

    func hideAll<T: HistoryDisplayRecord>(_ records: [T], at date: Date = Date(), matching drive: DriveDevice? = nil) throws {
        HistoryVisibility.hideAll(records, at: date, matching: drive)
        try modelContext.save()
    }

    func restore<T: HistoryDisplayRecord>(_ record: T) throws {
        HistoryVisibility.restore(record)
        try modelContext.save()
    }

    func restoreAll<T: HistoryDisplayRecord>(_ records: [T], matching drive: DriveDevice? = nil) throws {
        HistoryVisibility.restoreAll(records, matching: drive)
        try modelContext.save()
    }

    /// Removes the latest quick disk-check result for the selected drive.
    /// Quick checks are intentionally not part of hidden-history management.
    @discardableResult
    func clearDiskCheckResult(for drive: DriveDevice) throws -> Int {
        let records = try modelContext.fetch(FetchDescriptor<DiskCheckHistoryRecord>())
            .filter { HistoryDriveMatcher.matches(record: $0, drive: drive) }
        records.forEach(modelContext.delete)
        try modelContext.save()
        CapricornLog.persistence.info("Quick disk check result cleared: \(records.count) records")
        return records.count
    }

    /// Removes every user-facing history record from the current SwiftData
    /// store while leaving the store itself, application settings, and schema
    /// metadata intact. This is intentionally a cache operation: the next
    /// SMART, self-test, disk-check, benchmark, or live-activity save can use
    /// the same container.
    @discardableResult
    func clearAllHistory() throws -> Int {
        let smartRecords = try modelContext.fetch(FetchDescriptor<SmartHistoryRecord>())
        let selfTestRecords = try modelContext.fetch(FetchDescriptor<SmartSelfTestHistoryRecord>())
        let diskCheckRecords = try modelContext.fetch(FetchDescriptor<DiskCheckHistoryRecord>())
        let benchmarkRecords = try modelContext.fetch(FetchDescriptor<BenchmarkHistoryRecord>())
        let activityRecords = try modelContext.fetch(FetchDescriptor<DiskActivityHistoryRecord>())

        smartRecords.forEach(modelContext.delete)
        selfTestRecords.forEach(modelContext.delete)
        diskCheckRecords.forEach(modelContext.delete)
        benchmarkRecords.forEach(modelContext.delete)
        activityRecords.forEach(modelContext.delete)
        try modelContext.save()

        let count = smartRecords.count + selfTestRecords.count + diskCheckRecords.count + benchmarkRecords.count + activityRecords.count
        CapricornLog.persistence.info("History cache cleared: \(count) records")
        return count
    }

    /// Removes every history type belonging to the selected physical drive.
    /// The matcher is applied again inside the repository so a stale view or
    /// an accidentally unfiltered query cannot delete another drive's data.
    @discardableResult
    func clearHistory(for drive: DriveDevice) throws -> HistoryClearCounts {
        let smartRecords = try modelContext.fetch(FetchDescriptor<SmartHistoryRecord>())
            .filter { HistoryDriveMatcher.matches(record: $0, drive: drive) }
        let selfTestRecords = try modelContext.fetch(FetchDescriptor<SmartSelfTestHistoryRecord>())
            .filter { HistoryDriveMatcher.matches(record: $0, drive: drive) }
        let diskCheckRecords = try modelContext.fetch(FetchDescriptor<DiskCheckHistoryRecord>())
            .filter { HistoryDriveMatcher.matches(record: $0, drive: drive) }
        let benchmarkRecords = try modelContext.fetch(FetchDescriptor<BenchmarkHistoryRecord>())
            .filter { HistoryDriveMatcher.matches(record: $0, drive: drive) }
        let activityRecords = try modelContext.fetch(FetchDescriptor<DiskActivityHistoryRecord>())
            .filter { HistoryDriveMatcher.matches(record: $0, drive: drive) }

        let visibleCount = smartRecords.filter { $0.hiddenAt == nil }.count
            + selfTestRecords.filter { $0.hiddenAt == nil }.count
            + diskCheckRecords.filter { $0.hiddenAt == nil }.count
            + benchmarkRecords.filter { $0.hiddenAt == nil }.count
            + activityRecords.filter { $0.hiddenAt == nil }.count
        let hiddenCount = smartRecords.filter { $0.hiddenAt != nil }.count
            + selfTestRecords.filter { $0.hiddenAt != nil }.count
            + diskCheckRecords.filter { $0.hiddenAt != nil }.count
            + benchmarkRecords.filter { $0.hiddenAt != nil }.count
            + activityRecords.filter { $0.hiddenAt != nil }.count
        let counts = HistoryClearCounts(visible: visibleCount, hidden: hiddenCount)

        smartRecords.forEach(modelContext.delete)
        selfTestRecords.forEach(modelContext.delete)
        diskCheckRecords.forEach(modelContext.delete)
        benchmarkRecords.forEach(modelContext.delete)
        activityRecords.forEach(modelContext.delete)
        try modelContext.save()
        CapricornLog.persistence.info("Drive history cleared: \(counts.total) records")
        return counts
    }

    /// Removes only hidden records for the selected drive. Visible records
    /// remain untouched so this action is safe to use from the hidden-records
    /// management section.
    @discardableResult
    func clearHiddenHistory(for drive: DriveDevice) throws -> HistoryClearCounts {
        let smartRecords = try modelContext.fetch(FetchDescriptor<SmartHistoryRecord>())
            .filter { $0.hiddenAt != nil && HistoryDriveMatcher.matches(record: $0, drive: drive) }
        let selfTestRecords = try modelContext.fetch(FetchDescriptor<SmartSelfTestHistoryRecord>())
            .filter { $0.hiddenAt != nil && HistoryDriveMatcher.matches(record: $0, drive: drive) }
        let diskCheckRecords = try modelContext.fetch(FetchDescriptor<DiskCheckHistoryRecord>())
            .filter { $0.hiddenAt != nil && HistoryDriveMatcher.matches(record: $0, drive: drive) }
        let benchmarkRecords = try modelContext.fetch(FetchDescriptor<BenchmarkHistoryRecord>())
            .filter { $0.hiddenAt != nil && HistoryDriveMatcher.matches(record: $0, drive: drive) }
        let activityRecords = try modelContext.fetch(FetchDescriptor<DiskActivityHistoryRecord>())
            .filter { $0.hiddenAt != nil && HistoryDriveMatcher.matches(record: $0, drive: drive) }

        let count = smartRecords.count + selfTestRecords.count + diskCheckRecords.count + benchmarkRecords.count + activityRecords.count
        smartRecords.forEach(modelContext.delete)
        selfTestRecords.forEach(modelContext.delete)
        diskCheckRecords.forEach(modelContext.delete)
        benchmarkRecords.forEach(modelContext.delete)
        activityRecords.forEach(modelContext.delete)
        try modelContext.save()
        CapricornLog.persistence.info("Hidden drive history cleared: \(count) records")
        return HistoryClearCounts(visible: 0, hidden: count)
    }
}
