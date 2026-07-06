// SPDX-License-Identifier: GPL-3.0-only
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
    var isNetwork: Bool = false
    var isMemoryCard: Bool = false
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

extension DriveDevice {
    private enum CodingKeys: String, CodingKey {
        case bsdName
        case deviceNode
        case displayName
        case mediaName
        case protocolName
        case sizeBytes
        case blockSize
        case isInternal
        case isRemovable
        case isSolidState
        case isWritable
        case isVirtual
        case isSystemDisk
        case isNetwork
        case isMemoryCard
        case smartStatusRaw
        case nativeSmartKeys
        case volumes
        case model
        case serialNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bsdName = try container.decode(String.self, forKey: .bsdName)
        deviceNode = try container.decode(String.self, forKey: .deviceNode)
        displayName = try container.decode(String.self, forKey: .displayName)
        mediaName = try container.decode(String.self, forKey: .mediaName)
        protocolName = try container.decode(String.self, forKey: .protocolName)
        sizeBytes = try container.decode(Int64.self, forKey: .sizeBytes)
        blockSize = try container.decode(Int.self, forKey: .blockSize)
        isInternal = try container.decode(Bool.self, forKey: .isInternal)
        isRemovable = try container.decode(Bool.self, forKey: .isRemovable)
        isSolidState = try container.decode(Bool.self, forKey: .isSolidState)
        isWritable = try container.decode(Bool.self, forKey: .isWritable)
        isVirtual = try container.decode(Bool.self, forKey: .isVirtual)
        isSystemDisk = try container.decode(Bool.self, forKey: .isSystemDisk)
        isNetwork = try container.decodeIfPresent(Bool.self, forKey: .isNetwork) ?? false
        isMemoryCard = try container.decodeIfPresent(Bool.self, forKey: .isMemoryCard) ?? false
        smartStatusRaw = try container.decodeIfPresent(String.self, forKey: .smartStatusRaw)
        nativeSmartKeys = try container.decode([String: Int64].self, forKey: .nativeSmartKeys)
        volumes = try container.decode([Volume].self, forKey: .volumes)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bsdName, forKey: .bsdName)
        try container.encode(deviceNode, forKey: .deviceNode)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(mediaName, forKey: .mediaName)
        try container.encode(protocolName, forKey: .protocolName)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encode(blockSize, forKey: .blockSize)
        try container.encode(isInternal, forKey: .isInternal)
        try container.encode(isRemovable, forKey: .isRemovable)
        try container.encode(isSolidState, forKey: .isSolidState)
        try container.encode(isWritable, forKey: .isWritable)
        try container.encode(isVirtual, forKey: .isVirtual)
        try container.encode(isSystemDisk, forKey: .isSystemDisk)
        try container.encode(isNetwork, forKey: .isNetwork)
        try container.encode(isMemoryCard, forKey: .isMemoryCard)
        try container.encodeIfPresent(smartStatusRaw, forKey: .smartStatusRaw)
        try container.encode(nativeSmartKeys, forKey: .nativeSmartKeys)
        try container.encode(volumes, forKey: .volumes)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(serialNumber, forKey: .serialNumber)
    }
}

enum BenchmarkTargetFolderMatcher {
    static func targetFolderBelongsToDrive(_ folderPath: String, drive: DriveDevice) -> Bool {
        matchingVolume(for: folderPath, drive: drive) != nil
    }

    static func matchingVolume(for folderPath: String, drive: DriveDevice) -> DriveDevice.Volume? {
        guard !folderPath.isEmpty else { return nil }
        let folderPath = normalizedPath(folderPath)
        let folderVolumeRoot = volumeRootPath(for: folderPath)
        let mountedVolumes = drive.volumes
            .compactMap { volume -> (DriveDevice.Volume, String)? in
                guard let mountPoint = volume.mountPoint else { return nil }
                return (volume, normalizedPath(mountPoint))
            }
            .sorted { $0.1.count > $1.1.count }

        for (volume, mountPath) in mountedVolumes {
            if let folderVolumeRoot,
               let mountVolumeRoot = volumeRootPath(for: mountPath),
               mountPath == mountVolumeRoot,
               folderVolumeRoot == mountVolumeRoot {
                return volume
            }
            if path(folderPath, isInsideOrEqualTo: mountPath) {
                return volume
            }
        }

        return nil
    }

    private static func normalizedPath(_ path: String) -> String {
        let resolved = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return trimmingTrailingSlash(resolved)
    }

    private static func volumeRootPath(for path: String) -> String? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let values = try? url.resourceValues(forKeys: [.volumeURLKey]),
              let volumeURL = values.allValues[.volumeURLKey] as? URL else {
            return nil
        }
        return trimmingTrailingSlash(volumeURL.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    private static func path(_ path: String, isInsideOrEqualTo parentPath: String) -> Bool {
        if parentPath == "/" {
            return path == "/" || path.hasPrefix("/")
        }
        return path == parentPath || path.hasPrefix(parentPath + "/")
    }

    private static func trimmingTrailingSlash(_ path: String) -> String {
        guard path.count > 1 else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
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

enum BenchmarkEngine: String, Codable, CaseIterable, Identifiable {
    case synchronous
    case asyncQueue

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

struct BenchmarkCustomRow: Identifiable, Codable, Hashable {
    var id: String
    var accessPattern: BenchmarkAccessPattern
    var blockSizeBytes: Int
    var queueDepth: Int
    var threads: Int
    var includeMixed: Bool

    static let maxRows = 4
    static let blockSizeOptions = [
        4_096,
        16_384,
        65_536,
        131_072,
        1_048_576,
        4_194_304,
        16_777_216,
        134_217_728
    ]
    static let queueDepthOptions = [1, 2, 4, 8, 16, 32]
    static let threadOptions = [1, 2, 4, 8, 16]

    static let defaultRows = [
        BenchmarkCustomRow(id: "custom-default-seq", accessPattern: .sequential, blockSizeBytes: 1_048_576, queueDepth: 1, threads: 1, includeMixed: true),
        BenchmarkCustomRow(id: "custom-default-rnd", accessPattern: .random, blockSizeBytes: 4_096, queueDepth: 4, threads: 1, includeMixed: true)
    ]

    var label: String {
        "\(accessPattern.title)\(formatBytes(blockSizeBytes).replacingOccurrences(of: " ", with: "")) Q\(queueDepth)T\(threads)"
    }

    var fingerprint: String {
        "\(accessPattern.rawValue)-b\(blockSizeBytes)-q\(queueDepth)-t\(threads)-\(includeMixed ? "mix" : "plain")"
    }

    static func newRow(index: Int) -> BenchmarkCustomRow {
        var row = defaultRows[min(max(0, index), defaultRows.count - 1)]
        row.id = UUID().uuidString
        return row
    }

    static func sanitized(_ rows: [BenchmarkCustomRow]) -> [BenchmarkCustomRow] {
        let candidates = rows.isEmpty ? defaultRows : rows
        return Array(candidates.prefix(maxRows)).enumerated().map { index, row in
            BenchmarkCustomRow(
                id: row.id.isEmpty ? "custom-row-\(index)" : row.id,
                accessPattern: row.accessPattern,
                blockSizeBytes: blockSizeOptions.contains(row.blockSizeBytes) ? row.blockSizeBytes : 1_048_576,
                queueDepth: queueDepthOptions.contains(row.queueDepth) ? row.queueDepth : 1,
                threads: threadOptions.contains(row.threads) ? row.threads : 1,
                includeMixed: row.includeMixed
            )
        }
    }

    static func decodeList(from json: String) -> [BenchmarkCustomRow] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([BenchmarkCustomRow].self, from: data) else {
            return defaultRows
        }
        return sanitized(decoded)
    }

    static func encodeList(_ rows: [BenchmarkCustomRow]) -> String {
        let sanitizedRows = sanitized(rows)
        guard let data = try? JSONEncoder().encode(sanitizedRows),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }
}

struct BenchmarkProfile: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var testFileSizeBytes: Int64
    var runs: Int
    var usesTrimmedAverage: Bool = false
    var executionMode: BenchmarkExecutionMode = .finite
    var engine: BenchmarkEngine = .synchronous
    var tests: [BenchmarkTest]

    static let defaultTestSize: Int64 = 1_073_741_824
    static let defaultRuns = 3
    static let defaultDataPattern = BenchmarkDataPattern.random
    static let defaultUsesTrimmedAverage = false
    static let runCountOptions = Array(1...9)
    static let fileSizeOptions: [Int64] = [
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
        [.default, .peakNVMe, .realWorld, .demoLight, .custom]
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
            ],
            engine: .asyncQueue
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
            ],
            engine: .asyncQueue
        )
    }

    static var realWorld: BenchmarkProfile {
        makeProfile(
            id: "real-world",
            name: "RealWorld",
            testSize: defaultTestSize,
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
            testSize: defaultTestSize,
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
            testSize: defaultTestSize,
            runs: 2,
            duration: 2,
            rows: [
                (.sequential, 1_048_576, 1, 1),
                (.random, 4_096, 4, 1)
            ],
            includeMixed: true
        )
    }

    static func custom(
        rows: [BenchmarkCustomRow],
        engine: BenchmarkEngine = .synchronous,
        executionMode: BenchmarkExecutionMode = .finite
    ) -> BenchmarkProfile {
        makeCustomProfile(
            id: "custom",
            name: "Custom",
            testSize: defaultTestSize,
            runs: 2,
            duration: 2,
            rows: rows,
            executionMode: executionMode,
            engine: engine
        )
    }

    static var asyncTest: BenchmarkProfile {
        makeProfile(
            id: "test",
            name: "Test",
            testSize: defaultTestSize,
            runs: defaultRuns,
            duration: 5,
            rows: [
                (.sequential, 1_048_576, 1, 1),
                (.sequential, 1_048_576, 1, 2),
                (.sequential, 1_048_576, 1, 4),
                (.sequential, 1_048_576, 8, 1),
                (.sequential, 1_048_576, 8, 2),
                (.sequential, 1_048_576, 8, 4)
            ],
            engine: .asyncQueue
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

    static var extremeLoop: BenchmarkProfile {
        makeProfile(
            id: "loop-extreme",
            name: "Extreme Loop",
            testSize: defaultTestSize,
            runs: 1,
            duration: 5,
            rows: [
                (.sequential, 1_048_576, 8, 1),
                (.sequential, 4_194_304, 8, 4),
                (.sequential, 1_048_576, 32, 4)
            ],
            executionMode: .loopUntilCancelled
        )
    }

    static func makeCustomProfile(
        id: String,
        name: String,
        testSize: Int64,
        runs: Int,
        duration: TimeInterval,
        rows requestedRows: [BenchmarkCustomRow],
        executionMode: BenchmarkExecutionMode = .finite,
        engine: BenchmarkEngine = .synchronous
    ) -> BenchmarkProfile {
        let rows = BenchmarkCustomRow.sanitized(requestedRows)
        let rowFingerprint = rows.map(\.fingerprint).joined(separator: "_")
        var tests: [BenchmarkTest] = []
        for (index, row) in rows.enumerated() {
            let base = row.label
            let testIDPrefix = "\(id)-row\(index)-\(row.fingerprint)"
            tests.append(BenchmarkTest(
                id: "\(testIDPrefix)-read",
                label: base,
                accessPattern: row.accessPattern,
                operation: .read,
                blockSizeBytes: row.blockSizeBytes,
                queueDepth: row.queueDepth,
                threads: row.threads,
                durationSeconds: duration,
                testSizeBytes: testSize,
                dataPattern: .random,
                writePercentForMixed: 0
            ))
            tests.append(BenchmarkTest(
                id: "\(testIDPrefix)-write",
                label: base,
                accessPattern: row.accessPattern,
                operation: .write,
                blockSizeBytes: row.blockSizeBytes,
                queueDepth: row.queueDepth,
                threads: row.threads,
                durationSeconds: duration,
                testSizeBytes: testSize,
                dataPattern: .random,
                writePercentForMixed: 100
            ))
            if row.includeMixed {
                tests.append(BenchmarkTest(
                    id: "\(testIDPrefix)-mixed",
                    label: "\(base) Mix",
                    accessPattern: row.accessPattern,
                    operation: .mixed,
                    blockSizeBytes: row.blockSizeBytes,
                    queueDepth: row.queueDepth,
                    threads: row.threads,
                    durationSeconds: duration,
                    testSizeBytes: testSize,
                    dataPattern: .random,
                    writePercentForMixed: 30
                ))
            }
        }
        return BenchmarkProfile(
            id: "\(id)@rows-\(rowFingerprint)",
            name: name,
            testFileSizeBytes: testSize,
            runs: runs,
            usesTrimmedAverage: defaultUsesTrimmedAverage,
            executionMode: executionMode,
            engine: engine,
            tests: tests
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
        executionMode: BenchmarkExecutionMode = .finite,
        engine: BenchmarkEngine = .synchronous
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
            engine: engine,
            tests: tests
        )
    }

    func applying(engine nextEngine: BenchmarkEngine) -> BenchmarkProfile {
        var profile = self
        profile.engine = nextEngine
        return profile
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
        let rowFingerprint = id
            .components(separatedBy: "@")
            .dropFirst()
            .first { $0.hasPrefix("rows-") }
        let engineFingerprint = engine == .synchronous ? nil : "engine-\(engine.rawValue)"
        if isLooping {
            let loopFingerprint = "loop-s\(safeFileSizeBytes)-\(dataPattern.rawValue)"
            fingerprint = [rowFingerprint, loopFingerprint, engineFingerprint].compactMap { $0 }.joined(separator: "-")
        } else {
            let averageMode = safeUsesTrimmedAverage ? "trim" : "plain"
            let runFingerprint = "r\(safeRuns)-s\(safeFileSizeBytes)-\(dataPattern.rawValue)-\(averageMode)"
            fingerprint = [rowFingerprint, runFingerprint, engineFingerprint].compactMap { $0 }.joined(separator: "-")
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
            engine: engine,
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
    var transferMegabytesPerSecond: Double? = nil
    var flushMilliseconds: Double? = nil
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
