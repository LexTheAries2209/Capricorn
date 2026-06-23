import Foundation

enum HealthStatus: String, Codable, CaseIterable, Identifiable, Comparable {
    case good
    case warning
    case preFail
    case failed
    case unavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .good: "Good"
        case .warning: "Warning"
        case .preFail: "Pre-Fail"
        case .failed: "Failed"
        case .unavailable: "Unavailable"
        }
    }

    var symbolName: String {
        switch self {
        case .good: "checkmark.seal.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .preFail: "exclamationmark.octagon.fill"
        case .failed: "xmark.octagon.fill"
        case .unavailable: "questionmark.circle.fill"
        }
    }

    var severity: Int {
        switch self {
        case .good: 0
        case .warning: 1
        case .preFail: 2
        case .failed: 3
        case .unavailable: -1
        }
    }

    static func < (lhs: HealthStatus, rhs: HealthStatus) -> Bool {
        lhs.severity < rhs.severity
    }
}

enum ProviderState: String, Codable, CaseIterable {
    case available
    case limited
    case unavailable
    case failed
}

struct ProviderStatus: Identifiable, Codable, Hashable {
    var id: String { name }
    var name: String
    var state: ProviderState
    var message: String
}

struct DriveDevice: Identifiable, Codable, Hashable {
    struct Volume: Identifiable, Codable, Hashable {
        var id: String { deviceIdentifier }
        var deviceIdentifier: String
        var name: String
        var mountPoint: String?
        var sizeBytes: Int64
        var isWritable: Bool
        var isSystem: Bool
    }

    var id: String { bsdName }
    var bsdName: String
    var deviceNode: String
    var displayName: String
    var mediaName: String
    var protocolName: String
    var sizeBytes: Int64
    var blockSize: Int
    var isInternal: Bool
    var isRemovable: Bool
    var isSolidState: Bool
    var isWritable: Bool
    var isVirtual: Bool
    var isSystemDisk: Bool
    var smartStatusRaw: String?
    var nativeSmartKeys: [String: Int64]
    var volumes: [Volume]
    var model: String?
    var serialNumber: String?

    var benchmarkMountPoint: String? {
        volumes.first(where: { $0.isWritable && !$0.isSystem && $0.mountPoint != nil })?.mountPoint
            ?? volumes.first(where: { $0.isWritable && $0.mountPoint != nil })?.mountPoint
    }

    var primaryMountPoint: String? {
        volumes.first(where: { $0.mountPoint == "/" })?.mountPoint
            ?? volumes.first(where: { $0.mountPoint != nil })?.mountPoint
    }
}

struct SmartAttribute: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var rawValue: String
    var current: Int?
    var worst: Int?
    var threshold: Int?
    var status: HealthStatus
    var source: String
}

struct SmartSnapshot: Identifiable, Codable, Hashable {
    var id = UUID()
    var driveID: String
    var capturedAt: Date
    var health: HealthStatus
    var summary: String
    var providerStatuses: [ProviderStatus]
    var attributes: [SmartAttribute]
    var temperatureCelsius: Double?
    var lifeRemainingPercent: Int?
    var powerOnHours: Int?
    var powerCycleCount: Int?
    var mediaErrors: Int64?
    var unsafeShutdowns: Int64?
    var smartStatusRaw: String?
    var selfTestStatus: String?

    static func unavailable(for drive: DriveDevice, reason: String) -> SmartSnapshot {
        SmartSnapshot(
            driveID: drive.id,
            capturedAt: Date(),
            health: .unavailable,
            summary: reason,
            providerStatuses: [ProviderStatus(name: "SMART", state: .unavailable, message: reason)],
            attributes: [],
            temperatureCelsius: nil,
            lifeRemainingPercent: nil,
            powerOnHours: nil,
            powerCycleCount: nil,
            mediaErrors: nil,
            unsafeShutdowns: nil,
            smartStatusRaw: drive.smartStatusRaw,
            selfTestStatus: nil
        )
    }
}

enum BenchmarkAccessPattern: String, Codable, CaseIterable, Identifiable {
    case sequential
    case random

    var id: String { rawValue }
    var title: String { self == .sequential ? "SEQ" : "RND" }
}

enum BenchmarkOperation: String, Codable, CaseIterable, Identifiable {
    case read
    case write
    case mixed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .read: "Read"
        case .write: "Write"
        case .mixed: "Mixed"
        }
    }
}

enum BenchmarkDataPattern: String, Codable, CaseIterable, Identifiable {
    case random
    case zeroFill

    var id: String { rawValue }
    var title: String { self == .random ? "Random" : "0 Fill" }
}

enum BenchmarkExecutionMode: String, Codable, CaseIterable, Identifiable {
    case finite
    case loopUntilCancelled

    var id: String { rawValue }
}

struct BenchmarkTest: Identifiable, Codable, Hashable {
    var id: String
    var label: String
    var accessPattern: BenchmarkAccessPattern
    var operation: BenchmarkOperation
    var blockSizeBytes: Int
    var queueDepth: Int
    var threads: Int
    var durationSeconds: TimeInterval
    var testSizeBytes: Int64
    var dataPattern: BenchmarkDataPattern
    var writePercentForMixed: Int

    var operationsDescription: String {
        "\(accessPattern.title) \(formatBytes(blockSizeBytes)) Q\(queueDepth)T\(threads)"
    }
}

struct BenchmarkProfile: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var testFileSizeBytes: Int64
    var runs: Int
    var usesTrimmedAverage: Bool = false
    var executionMode: BenchmarkExecutionMode = .finite
    var tests: [BenchmarkTest]

    static let defaultTestSize: Int64 = 1_073_741_824
    static let defaultRuns = 3
    static let defaultDataPattern = BenchmarkDataPattern.random
    static let defaultUsesTrimmedAverage = false
    static let runCountOptions = Array(1...9)
    static let fileSizeOptions: [Int64] = [
        16 * 1_024 * 1_024,
        64 * 1_024 * 1_024,
        256 * 1_024 * 1_024,
        1_024 * 1_024 * 1_024,
        2 * 1_024 * 1_024 * 1_024,
        4 * 1_024 * 1_024 * 1_024,
        8 * 1_024 * 1_024 * 1_024,
        16 * 1_024 * 1_024 * 1_024,
        32 * 1_024 * 1_024 * 1_024,
        64 * 1_024 * 1_024 * 1_024
    ]

    var baseProfileID: String {
        id.components(separatedBy: "@").first ?? id
    }

    static var presets: [BenchmarkProfile] {
        [.default, .peakNVMe, .realWorld, .demoLight, .custom, .loop]
    }

    static var `default`: BenchmarkProfile {
        makeProfile(
            id: "default",
            name: "Default",
            testSize: defaultTestSize,
            runs: defaultRuns,
            duration: 5,
            rows: [
                (.sequential, 1_048_576, 8, 1),
                (.sequential, 1_048_576, 1, 1),
                (.random, 4_096, 32, 1),
                (.random, 4_096, 1, 1)
            ]
        )
    }

    static var peakNVMe: BenchmarkProfile {
        makeProfile(
            id: "peak-nvme",
            name: "Peak / NVMe",
            testSize: 2_147_483_648,
            runs: 3,
            duration: 5,
            rows: [
                (.sequential, 1_048_576, 8, 1),
                (.sequential, 131_072, 32, 1),
                (.random, 4_096, 32, 16),
                (.random, 4_096, 1, 1)
            ]
        )
    }

    static var realWorld: BenchmarkProfile {
        makeProfile(
            id: "real-world",
            name: "RealWorld",
            testSize: 536_870_912,
            runs: 2,
            duration: 3,
            rows: [
                (.sequential, 1_048_576, 1, 1),
                (.random, 65_536, 4, 2),
                (.random, 4_096, 4, 1),
                (.random, 4_096, 1, 1)
            ],
            includeMixed: true
        )
    }

    static var demoLight: BenchmarkProfile {
        makeProfile(
            id: "demo",
            name: "Demo / Light",
            testSize: 67_108_864,
            runs: 1,
            duration: 1,
            rows: [
                (.sequential, 1_048_576, 1, 1),
                (.random, 4_096, 1, 1)
            ]
        )
    }

    static var custom: BenchmarkProfile {
        makeProfile(
            id: "custom",
            name: "Custom",
            testSize: 268_435_456,
            runs: 2,
            duration: 2,
            rows: [
                (.sequential, 1_048_576, 1, 1),
                (.random, 4_096, 4, 1)
            ],
            includeMixed: true
        )
    }

    static var loop: BenchmarkProfile {
        makeProfile(
            id: "loop",
            name: "Loop",
            testSize: defaultTestSize,
            runs: 1,
            duration: 5,
            rows: [
                (.sequential, 1_048_576, 1, 1),
                (.sequential, 1_048_576, 8, 1)
            ],
            executionMode: .loopUntilCancelled
        )
    }

    static func makeProfile(
        id: String,
        name: String,
        testSize: Int64,
        runs: Int,
        duration: TimeInterval,
        rows: [(BenchmarkAccessPattern, Int, Int, Int)],
        includeMixed: Bool = false,
        executionMode: BenchmarkExecutionMode = .finite
    ) -> BenchmarkProfile {
        var tests: [BenchmarkTest] = []
        for (index, row) in rows.enumerated() {
            let base = "\(row.0.title)\(formatBytes(row.1).replacingOccurrences(of: " ", with: "")) Q\(row.2)T\(row.3)"
            tests.append(BenchmarkTest(
                id: "\(id)-read-\(index)",
                label: base,
                accessPattern: row.0,
                operation: .read,
                blockSizeBytes: row.1,
                queueDepth: row.2,
                threads: row.3,
                durationSeconds: duration,
                testSizeBytes: testSize,
                dataPattern: .random,
                writePercentForMixed: 0
            ))
            tests.append(BenchmarkTest(
                id: "\(id)-write-\(index)",
                label: base,
                accessPattern: row.0,
                operation: .write,
                blockSizeBytes: row.1,
                queueDepth: row.2,
                threads: row.3,
                durationSeconds: duration,
                testSizeBytes: testSize,
                dataPattern: .random,
                writePercentForMixed: 100
            ))
            if includeMixed {
                tests.append(BenchmarkTest(
                    id: "\(id)-mixed-\(index)",
                    label: "\(base) Mix",
                    accessPattern: row.0,
                    operation: .mixed,
                    blockSizeBytes: row.1,
                    queueDepth: row.2,
                    threads: row.3,
                    durationSeconds: duration,
                    testSizeBytes: testSize,
                    dataPattern: .random,
                    writePercentForMixed: 30
                ))
            }
        }
        return BenchmarkProfile(
            id: id,
            name: name,
            testFileSizeBytes: testSize,
            runs: runs,
            usesTrimmedAverage: defaultUsesTrimmedAverage,
            executionMode: executionMode,
            tests: tests
        )
    }

    func configured(
        runs requestedRuns: Int,
        fileSizeBytes requestedFileSizeBytes: Int64,
        dataPattern: BenchmarkDataPattern,
        usesTrimmedAverage: Bool = defaultUsesTrimmedAverage
    ) -> BenchmarkProfile {
        let isLooping = executionMode == .loopUntilCancelled
        let safeRuns = isLooping ? 1 : min(max(requestedRuns, Self.runCountOptions.first ?? 1), Self.runCountOptions.last ?? 9)
        let safeFileSizeBytes = max(Self.fileSizeOptions.first ?? Self.defaultTestSize, requestedFileSizeBytes)
        let safeUsesTrimmedAverage = isLooping ? false : usesTrimmedAverage
        let fingerprint: String
        if isLooping {
            fingerprint = "loop-s\(safeFileSizeBytes)-\(dataPattern.rawValue)"
        } else {
            let averageMode = safeUsesTrimmedAverage ? "trim" : "plain"
            fingerprint = "r\(safeRuns)-s\(safeFileSizeBytes)-\(dataPattern.rawValue)-\(averageMode)"
        }
        let configuredTests = tests.map { test in
            var configuredTest = test
            let baseTestID = test.id.components(separatedBy: "@").first ?? test.id
            configuredTest.id = "\(baseTestID)@\(fingerprint)"
            configuredTest.testSizeBytes = safeFileSizeBytes
            configuredTest.dataPattern = dataPattern
            return configuredTest
        }
        return BenchmarkProfile(
            id: "\(baseProfileID)@\(fingerprint)",
            name: name,
            testFileSizeBytes: safeFileSizeBytes,
            runs: safeRuns,
            usesTrimmedAverage: safeUsesTrimmedAverage,
            executionMode: executionMode,
            tests: configuredTests
        )
    }
}

struct BenchmarkResult: Identifiable, Codable, Hashable {
    var id = UUID()
    var driveID: String
    var volumePath: String
    var profileID: String
    var profileName: String
    var testID: String
    var testLabel: String
    var operation: BenchmarkOperation
    var measuredAt: Date
    var bestMegabytesPerSecond: Double
    var iops: Double
    var latencyMicroseconds: Double
    var bytesTransferred: Int64
}

struct BenchmarkProgress: Equatable {
    var currentTestLabel: String
    var completed: Int
    var total: Int
    var message: String
    var phaseCompletedBytes: Int64 = 0
    var phaseTotalBytes: Int64 = 0

    var fraction: Double {
        guard total > 0 else { return 0 }
        let phaseFraction: Double
        if phaseTotalBytes > 0 {
            phaseFraction = min(1, max(0, Double(phaseCompletedBytes) / Double(phaseTotalBytes)))
        } else {
            phaseFraction = 0
        }
        return min(1, max(0, (Double(completed) + phaseFraction) / Double(total)))
    }
}

func formatBytes(_ bytes: Int) -> String {
    if bytes >= 1_048_576 && bytes % 1_048_576 == 0 {
        return "\(bytes / 1_048_576) MiB"
    }
    if bytes >= 1_024 && bytes % 1_024 == 0 {
        return "\(bytes / 1_024) KiB"
    }
    return "\(bytes) B"
}

func formatByteCount(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func formatBenchmarkFileSize(_ bytes: Int64) -> String {
    let gib: Int64 = 1_024 * 1_024 * 1_024
    let mib: Int64 = 1_024 * 1_024
    if bytes >= gib, bytes % gib == 0 {
        return "\(bytes / gib) GiB"
    }
    if bytes >= mib, bytes % mib == 0 {
        return "\(bytes / mib) MiB"
    }
    return formatByteCount(bytes)
}
