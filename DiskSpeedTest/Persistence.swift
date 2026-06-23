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

    init(drive: DriveDevice, result: BenchmarkResult) {
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
    }

    var operation: BenchmarkOperation {
        BenchmarkOperation(rawValue: operationRaw) ?? .read
    }
}

protocol HistoryDisplayRecord: AnyObject {
    var driveID: String { get }
    var hiddenAt: Date? { get set }
}

extension SmartHistoryRecord: HistoryDisplayRecord {}
extension BenchmarkHistoryRecord: HistoryDisplayRecord {}

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

enum ReportExporter {
    struct Report: Codable {
        var generatedAt: Date
        var drive: DriveDevice
        var snapshot: SmartSnapshot?
        var benchmarkResults: [BenchmarkResult]
    }

    static func jsonReport(
        drive: DriveDevice,
        snapshot: SmartSnapshot?,
        benchmarkResults: [BenchmarkResult],
        includeSerial: Bool
    ) -> String {
        let redactedDrive = redacted(drive, includeSerial: includeSerial)
        let report = Report(generatedAt: Date(), drive: redactedDrive, snapshot: snapshot, benchmarkResults: benchmarkResults)
        guard let data = try? JSONEncoder.dit.encode(report) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func csvReport(results: [BenchmarkResult]) -> String {
        var lines = ["date,profile,test,operation,volume,mbs,iops,latency_us"]
        lines += results.map {
            [
                ISO8601DateFormatter().string(from: $0.measuredAt),
                $0.profileName,
                $0.testLabel,
                $0.operation.title,
                $0.volumePath,
                String(format: "%.2f", $0.bestMegabytesPerSecond),
                String(format: "%.1f", $0.iops),
                String(format: "%.2f", $0.latencyMicroseconds)
            ]
            .map(escapeCSV)
            .joined(separator: ",")
        }
        return lines.joined(separator: "\n")
    }

    static func textReport(drive: DriveDevice, snapshot: SmartSnapshot?, results: [BenchmarkResult], includeSerial: Bool) -> String {
        let redactedDrive = redacted(drive, includeSerial: includeSerial)
        var lines = [
            "DiskSmart Report",
            "Generated: \(Date().formatted())",
            "Drive: \(redactedDrive.displayName) (\(redactedDrive.bsdName))",
            "Protocol: \(redactedDrive.protocolName)",
            "Capacity: \(formatByteCount(redactedDrive.sizeBytes))"
        ]
        if let serial = redactedDrive.serialNumber {
            lines.append("Serial: \(serial)")
        }
        if let snapshot {
            lines += [
                "Health: \(snapshot.health.title)",
                "Summary: \(snapshot.summary)"
            ]
            if let temp = snapshot.temperatureCelsius {
                lines.append(String(format: "Temperature: %.1f C", temp))
            }
            if let life = snapshot.lifeRemainingPercent {
                lines.append("Life Remaining: \(life)%")
            }
        }
        if !results.isEmpty {
            lines.append("")
            lines.append("Benchmark")
            for result in results {
                lines.append(String(format: "%@ %@: %.2f MB/s, %.1f IOPS, %.2f us",
                                    result.testLabel,
                                    result.operation.title,
                                    result.bestMegabytesPerSecond,
                                    result.iops,
                                    result.latencyMicroseconds))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func redacted(_ drive: DriveDevice, includeSerial: Bool) -> DriveDevice {
        guard !includeSerial else { return drive }
        var copy = drive
        if copy.serialNumber != nil {
            copy.serialNumber = "REDACTED"
        }
        return copy
    }

    private static func escapeCSV(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
