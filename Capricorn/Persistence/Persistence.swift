// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftData

@Model
final class SmartHistoryRecord {
    @Attribute(.unique) var id: UUID
    var driveID: String
    var driveName: String
    var capturedAt: Date
    var healthRaw: String
    var temperatureCelsius: Double?
    var lifeRemainingPercent: Int?
    var summary: String
    var encodedSnapshot: Data?
    var hiddenAt: Date?

    init(drive: DriveDevice, snapshot: SmartSnapshot) {
        self.id = UUID()
        self.driveID = drive.id
        self.driveName = drive.displayName
        self.capturedAt = snapshot.capturedAt
        self.healthRaw = snapshot.health.rawValue
        self.temperatureCelsius = snapshot.temperatureCelsius
        self.lifeRemainingPercent = snapshot.lifeRemainingPercent
        self.summary = snapshot.summary
        self.encodedSnapshot = try? JSONEncoder.dit.encode(snapshot)
        self.hiddenAt = nil
    }

    var health: HealthStatus {
        HealthStatus(rawValue: healthRaw) ?? .unavailable
    }
}

@Model
final class BenchmarkHistoryRecord {
    @Attribute(.unique) var id: UUID
    var driveID: String
    var driveName: String
    var volumePath: String
    var profileName: String
    var testLabel: String
    var operationRaw: String
    var measuredAt: Date
    var bestMegabytesPerSecond: Double
    var iops: Double
    var latencyMicroseconds: Double
    var hiddenAt: Date?
    var encodedActivitySamples: Data?

    init(drive: DriveDevice, result: BenchmarkResult, activitySamples: [DiskActivitySample] = []) {
        self.id = UUID()
        self.driveID = drive.id
        self.driveName = drive.displayName
        self.volumePath = result.volumePath
        self.profileName = result.profileName
        self.testLabel = result.testLabel
        self.operationRaw = result.operation.rawValue
        self.measuredAt = result.measuredAt
        self.bestMegabytesPerSecond = result.bestMegabytesPerSecond
        self.iops = result.iops
        self.latencyMicroseconds = result.latencyMicroseconds
        self.hiddenAt = nil
        self.encodedActivitySamples = activitySamples.isEmpty ? nil : try? DiskActivitySampleCoders.encode(activitySamples)
    }

    var operation: BenchmarkOperation {
        BenchmarkOperation(rawValue: operationRaw) ?? .read
    }

    var activitySamples: [DiskActivitySample] {
        guard let encodedActivitySamples,
              let decoded = DiskActivitySampleCoders.decode(encodedActivitySamples) else {
            return []
        }
        return decoded
    }
}

@Model
final class DiskActivityHistoryRecord {
    @Attribute(.unique) var id: UUID
    var driveID: String
    var driveName: String
    var bsdName: String
    var startedAt: Date
    var endedAt: Date
    var sampleIntervalSeconds: Double
    var durationSeconds: Double
    var peakReadMegabytesPerSecond: Double
    var peakWriteMegabytesPerSecond: Double
    var averageReadMegabytesPerSecond: Double
    var averageWriteMegabytesPerSecond: Double
    var sampleCount: Int
    var encodedSamples: Data?
    var hiddenAt: Date?

    init(
        drive: DriveDevice,
        samples: [DiskActivitySample],
        sampleInterval: DiskActivitySampleInterval,
        startedAt: Date,
        endedAt: Date
    ) {
        let summary = DiskActivityStatistics.summarize(samples: samples, startedAt: startedAt, endedAt: endedAt)
        self.id = UUID()
        self.driveID = drive.id
        self.driveName = drive.displayName
        self.bsdName = drive.bsdName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sampleIntervalSeconds = sampleInterval.seconds
        self.durationSeconds = summary.durationSeconds
        self.peakReadMegabytesPerSecond = summary.peakReadMegabytesPerSecond
        self.peakWriteMegabytesPerSecond = summary.peakWriteMegabytesPerSecond
        self.averageReadMegabytesPerSecond = summary.averageReadMegabytesPerSecond
        self.averageWriteMegabytesPerSecond = summary.averageWriteMegabytesPerSecond
        self.sampleCount = summary.sampleCount
        self.encodedSamples = try? DiskActivitySampleCoders.encode(samples)
        self.hiddenAt = nil
    }

    var sampleInterval: DiskActivitySampleInterval {
        DiskActivitySampleInterval(rawValue: sampleIntervalSeconds) ?? .default
    }

    var samples: [DiskActivitySample] {
        guard let encodedSamples,
              let decoded = DiskActivitySampleCoders.decode(encodedSamples) else {
            return []
        }
        return decoded
    }
}

protocol HistoryDisplayRecord: AnyObject {
    var driveID: String { get }
    var hiddenAt: Date? { get set }
}

extension SmartHistoryRecord: HistoryDisplayRecord {}
extension BenchmarkHistoryRecord: HistoryDisplayRecord {}
extension DiskActivityHistoryRecord: HistoryDisplayRecord {}

enum HistoryVisibility {
    static func visible<T: HistoryDisplayRecord>(_ records: [T]) -> [T] {
        records.filter { $0.hiddenAt == nil }
    }

    static func hidden<T: HistoryDisplayRecord>(_ records: [T]) -> [T] {
        records.filter { $0.hiddenAt != nil }
    }

    static func hide<T: HistoryDisplayRecord>(_ record: T, at date: Date = Date()) {
        record.hiddenAt = date
    }

    static func hideAll<T: HistoryDisplayRecord>(_ records: [T], at date: Date = Date(), driveID: String? = nil) {
        for record in records where driveID == nil || record.driveID == driveID {
            record.hiddenAt = date
        }
    }

    static func restore<T: HistoryDisplayRecord>(_ record: T) {
        record.hiddenAt = nil
    }

    static func restoreAll<T: HistoryDisplayRecord>(_ records: [T], driveID: String? = nil) {
        for record in records where driveID == nil || record.driveID == driveID {
            record.hiddenAt = nil
        }
    }
}

@Model
final class AppSettingsRecord {
    @Attribute(.unique) var id: String
    var smartctlPath: String?
    var includeSerialsInReports: Bool
    var showVirtualDisks: Bool
    var lastUpdated: Date

    init(
        id: String = "global",
        smartctlPath: String? = nil,
        includeSerialsInReports: Bool = false,
        showVirtualDisks: Bool = false
    ) {
        self.id = id
        self.smartctlPath = smartctlPath
        self.includeSerialsInReports = includeSerialsInReports
        self.showVirtualDisks = showVirtualDisks
        self.lastUpdated = Date()
    }
}

extension JSONEncoder {
    static var dit: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var dit: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum DiskActivitySampleCoders {
    static func encode(_ samples: [DiskActivitySample]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(samples)
    }

    static func decode(_ data: Data) -> [DiskActivitySample]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let decoded = try? decoder.decode([DiskActivitySample].self, from: data) {
            return decoded
        }
        return try? JSONDecoder.dit.decode([DiskActivitySample].self, from: data)
    }
}

enum ReportExporter {
    /// Exports the SMART attribute table as a compact CSV document. Snapshot
    /// metadata is intentionally omitted; localized names and descriptions are
    /// resolved from the same catalog used by the SMART table UI.
    static func smartSnapshotCSVReport(snapshot: SmartSnapshot, language: AppLanguage) -> String {
        var header = ["attribute_id", "attribute_name"]
        if language == .simplifiedChinese {
            header.append("chinese_name")
        }
        header += [
            "description", "raw_value", "current", "worst", "threshold", "status", "source"
        ]
        var lines = [header.map(escapeCSV).joined(separator: ",")]
        lines += snapshot.attributes.map { attribute in
            let display = SmartAttributeCatalog.display(for: attribute, language: language)
            var values = [
                attribute.id,
                attribute.name,
            ]
            if language == .simplifiedChinese {
                values.append(display.title)
            }
            values += [
                display.subtitle,
                attribute.rawValue,
                attribute.current.map(String.init) ?? "",
                attribute.worst.map(String.init) ?? "",
                attribute.threshold.map(String.init) ?? "",
                attribute.status.title,
                attribute.source
            ]
            return values.map(escapeCSV).joined(separator: ",")
        }
        return lines.joined(separator: "\n")
    }

    static func smartSnapshotFileName(drive: DriveDevice, date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = language == .simplifiedChinese
            ? TimeZone(secondsFromGMT: 8 * 60 * 60)
            : TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"

        let timeZoneLabel = language == .simplifiedChinese ? "+0800-UTC+8" : "Z-UTC+0"
        let safeName = drive.displayName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "Capricorn-\(safeName.isEmpty ? drive.bsdName : safeName)-\(formatter.string(from: date))\(timeZoneLabel).csv"
    }

    private static func escapeCSV(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
