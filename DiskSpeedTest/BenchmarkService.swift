import Darwin
import Foundation

protocol BenchmarkRunning {
    func run(
        profile: BenchmarkProfile,
        drive: DriveDevice,
        volumePath: String,
        progress: @escaping (BenchmarkProgress) -> Void,
        result: @escaping (BenchmarkResult) -> Void
    ) async throws -> [BenchmarkResult]
    func cancel()
}

enum BenchmarkError: Error, LocalizedError {
    case volumeUnavailable
    case volumeNotWritable(String)
    case insufficientSpace(required: Int64, available: Int64)
    case openFailed(String)
    case cancelled
    case ioFailed(String)

    var errorDescription: String? {
        switch self {
        case .volumeUnavailable:
            "Select a target folder before running a benchmark."
        case let .volumeNotWritable(path):
            "\(path) is not writable."
        case let .insufficientSpace(required, available):
            "Insufficient free space. Required \(formatByteCount(required)), available \(formatByteCount(available))."
        case let .openFailed(path):
            "Could not create benchmark file at \(path)."
        case .cancelled:
            "Benchmark cancelled."
        case let .ioFailed(message):
            message
        }
    }
}

final class NativeBenchmarkRunner: BenchmarkRunning, @unchecked Sendable {
    private let fileManager: FileManager
    private let lock = NSLock()
    private var cancelled = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func cancel() {
        setCancelled(true)
    }

    func run(
        profile: BenchmarkProfile,
        drive: DriveDevice,
        volumePath: String,
        progress: @escaping (BenchmarkProgress) -> Void,
        result: @escaping (BenchmarkResult) -> Void
    ) async throws -> [BenchmarkResult] {
        setCancelled(false)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let results = try self.runBlocking(profile: profile, drive: drive, volumePath: volumePath, progress: progress, result: result)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runBlocking(
        profile: BenchmarkProfile,
        drive: DriveDevice,
        volumePath: String,
        progress: @escaping (BenchmarkProgress) -> Void,
        result: @escaping (BenchmarkResult) -> Void
    ) throws -> [BenchmarkResult] {
        let volumeURL = URL(fileURLWithPath: volumePath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: volumePath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BenchmarkError.volumeUnavailable
        }
        guard fileManager.isWritableFile(atPath: volumePath) else {
            throw BenchmarkError.volumeNotWritable(volumePath)
        }

        let maxTestSize = profile.tests.map(\.testSizeBytes).max() ?? profile.testFileSizeBytes
        let requiredSpace = maxTestSize + 128 * 1_024 * 1_024
        let available = availableCapacity(for: volumeURL)
        if available > 0, available < requiredSpace {
            throw BenchmarkError.insufficientSpace(required: requiredSpace, available: available)
        }

        let testFile = volumeURL.appendingPathComponent(".dit-benchmark-\(UUID().uuidString).tmp")
        let path = testFile.path
        let fd = open(path, O_CREAT | O_RDWR | O_TRUNC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw BenchmarkError.openFailed(path) }
        defer {
            close(fd)
            try? fileManager.removeItem(at: testFile)
        }

        var noCache: Int32 = 1
        _ = fcntl(fd, F_NOCACHE, &noCache)

        let totalSteps = profile.tests.count * max(1, profile.runs)
        var completedSteps = 0
        var results: [BenchmarkResult] = []

        for test in profile.tests {
            try checkCancelled()
            notify(progress, BenchmarkProgress(currentTestLabel: test.label, completed: completedSteps, total: totalSteps, message: "Preparing \(test.operation.title)"))
            try prepareTestFile(fd: fd, test: test)

            var bestMBs = 0.0
            var bestIOPS = 0.0
            var minLatency = Double.greatestFiniteMagnitude
            var bestBytes: Int64 = 0

            for runIndex in 0...profile.runs {
                try checkCancelled()
                let isWarmup = runIndex == 0
                let measurement = try perform(test: test, fd: fd)
                if !isWarmup {
                    completedSteps += 1
                    if measurement.megabytesPerSecond > bestMBs {
                        bestMBs = measurement.megabytesPerSecond
                        bestIOPS = measurement.iops
                        bestBytes = measurement.bytesTransferred
                    }
                    if measurement.latencyMicroseconds < minLatency {
                        minLatency = measurement.latencyMicroseconds
                    }
                    notify(progress, BenchmarkProgress(
                        currentTestLabel: test.label,
                        completed: completedSteps,
                        total: totalSteps,
                        message: "\(test.operation.title) run \(runIndex)/\(profile.runs)"
                    ))
                }
            }

            let completedResult = BenchmarkResult(
                driveID: drive.id,
                volumePath: volumePath,
                profileID: profile.id,
                profileName: profile.name,
                testID: test.id,
                testLabel: test.label,
                operation: test.operation,
                measuredAt: Date(),
                bestMegabytesPerSecond: bestMBs,
                iops: bestIOPS,
                latencyMicroseconds: minLatency.isFinite ? minLatency : 0,
                bytesTransferred: bestBytes
            )
            results.append(completedResult)
            notify(result, completedResult)
        }

        notify(progress, BenchmarkProgress(currentTestLabel: "Complete", completed: totalSteps, total: totalSteps, message: "Benchmark complete"))
        return results
    }

    private func availableCapacity(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage {
            return Int64(important)
        }
        if let capacity = values?.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return 0
    }

    private func prepareTestFile(fd: Int32, test: BenchmarkTest) throws {
        if ftruncate(fd, off_t(test.testSizeBytes)) != 0 {
            throw BenchmarkError.ioFailed("Could not preallocate benchmark file.")
        }

        guard test.operation == .read || test.operation == .mixed else { return }

        let bufferSize = max(4_096, min(test.blockSizeBytes, 1_048_576))
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 4_096)
        defer { buffer.deallocate() }
        fill(buffer, count: bufferSize, pattern: test.dataPattern)

        var offset: Int64 = 0
        while offset < test.testSizeBytes {
            try checkCancelled()
            let count = min(bufferSize, Int(test.testSizeBytes - offset))
            let written = pwrite(fd, buffer, count, off_t(offset))
            guard written == count else {
                throw BenchmarkError.ioFailed("Could not prepare read-test data.")
            }
            offset += Int64(count)
        }
        fsync(fd)
    }

    private struct Measurement {
        var megabytesPerSecond: Double
        var iops: Double
        var latencyMicroseconds: Double
        var bytesTransferred: Int64
    }

    private func perform(test: BenchmarkTest, fd: Int32) throws -> Measurement {
        let duration = max(0.05, test.durationSeconds)
        let threadCount = max(1, test.threads)
        let queueDepth = max(1, test.queueDepth)
        let blockSize = max(512, test.blockSizeBytes)
        let fileSize = max(Int64(blockSize), test.testSizeBytes)
        let deadline = Date().addingTimeInterval(duration)
        let aggregateLock = NSLock()
        var totalBytes: Int64 = 0
        var totalOperations: Int64 = 0
        var minLatencyMicros = Double.greatestFiniteMagnitude
        var firstError: Error?

        let started = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.concurrentPerform(iterations: threadCount) { threadIndex in
            guard firstError == nil else { return }
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: blockSize, alignment: 4_096)
            defer { buffer.deallocate() }
            fill(buffer, count: blockSize, pattern: test.dataPattern)

            var localBytes: Int64 = 0
            var localOperations: Int64 = 0
            var localMinLatency = Double.greatestFiniteMagnitude
            var sequentialOffset = Int64(threadIndex * blockSize)

            while Date() < deadline {
                if isCancelled() {
                    aggregateLock.lock()
                    firstError = BenchmarkError.cancelled
                    aggregateLock.unlock()
                    return
                }

                for _ in 0..<queueDepth {
                    let offset = offsetFor(test: test, fileSize: fileSize, blockSize: blockSize, sequentialOffset: &sequentialOffset, threadCount: threadCount)
                    let shouldWrite = shouldWrite(test: test)
                    let opStarted = DispatchTime.now().uptimeNanoseconds
                    let count: Int
                    if shouldWrite {
                        count = pwrite(fd, buffer, blockSize, off_t(offset))
                    } else {
                        count = pread(fd, buffer, blockSize, off_t(offset))
                    }
                    let opFinished = DispatchTime.now().uptimeNanoseconds

                    guard count > 0 else {
                        aggregateLock.lock()
                        if firstError == nil {
                            firstError = BenchmarkError.ioFailed(shouldWrite ? "Write test failed." : "Read test failed.")
                        }
                        aggregateLock.unlock()
                        return
                    }

                    localBytes += Int64(count)
                    localOperations += 1
                    localMinLatency = min(localMinLatency, Double(opFinished - opStarted) / 1_000)
                }
            }

            aggregateLock.lock()
            totalBytes += localBytes
            totalOperations += localOperations
            minLatencyMicros = min(minLatencyMicros, localMinLatency)
            aggregateLock.unlock()
        }

        if let firstError { throw firstError }

        if test.operation == .write || test.operation == .mixed {
            fsync(fd)
        }

        let finished = DispatchTime.now().uptimeNanoseconds
        let elapsed = max(0.001, Double(finished - started) / 1_000_000_000)
        return Measurement(
            megabytesPerSecond: Double(totalBytes) / elapsed / 1_000_000,
            iops: Double(totalOperations) / elapsed,
            latencyMicroseconds: minLatencyMicros.isFinite ? minLatencyMicros : 0,
            bytesTransferred: totalBytes
        )
    }

    private func offsetFor(
        test: BenchmarkTest,
        fileSize: Int64,
        blockSize: Int,
        sequentialOffset: inout Int64,
        threadCount: Int
    ) -> Int64 {
        let maxOffset = max(Int64(0), fileSize - Int64(blockSize))
        switch test.accessPattern {
        case .sequential:
            let offset = sequentialOffset > maxOffset ? 0 : sequentialOffset
            sequentialOffset = offset + Int64(blockSize * threadCount)
            return offset
        case .random:
            let blocks = max(1, UInt32(maxOffset / Int64(blockSize)))
            return Int64(arc4random_uniform(blocks)) * Int64(blockSize)
        }
    }

    private func shouldWrite(test: BenchmarkTest) -> Bool {
        switch test.operation {
        case .read:
            false
        case .write:
            true
        case .mixed:
            Int(arc4random_uniform(100)) < test.writePercentForMixed
        }
    }

    private func fill(_ buffer: UnsafeMutableRawPointer, count: Int, pattern: BenchmarkDataPattern) {
        switch pattern {
        case .random:
            arc4random_buf(buffer, count)
        case .zeroFill:
            memset(buffer, 0, count)
        }
    }

    private func checkCancelled() throws {
        if isCancelled() {
            throw BenchmarkError.cancelled
        }
    }

    private func setCancelled(_ value: Bool) {
        lock.lock()
        cancelled = value
        lock.unlock()
    }

    private func isCancelled() -> Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }

    private func notify(_ progress: @escaping (BenchmarkProgress) -> Void, _ value: BenchmarkProgress) {
        DispatchQueue.main.async {
            progress(value)
        }
    }

    private func notify(_ result: @escaping (BenchmarkResult) -> Void, _ value: BenchmarkResult) {
        DispatchQueue.main.sync {
            result(value)
        }
    }
}
