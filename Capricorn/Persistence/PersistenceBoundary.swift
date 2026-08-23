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

enum CapricornMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CapricornSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

@MainActor
enum ModelContainerFactory {
    static let historyDirectoryName = "CapricornHistory"
    static let historyStoreFileName = "CapricornHistory.store"

    static func makeApplication() throws -> ModelContainer {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeURL = historyStoreURL(in: applicationSupport)
        let directory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try makePersistent(at: storeURL)
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
        let schema = Schema(versionedSchema: CapricornSchemaV2.self)
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
        let schema = Schema(versionedSchema: CapricornSchemaV2.self)
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
}
