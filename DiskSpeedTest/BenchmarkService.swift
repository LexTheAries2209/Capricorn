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

struct BenchmarkRunMeasurement: Equatable {
    var megabytesPerSecond: Double
    var iops: Double
    var latencyMicroseconds: Double
    var bytesTransferred: Int64
}

enum BenchmarkMeasurementReducer {
    static func measuredRunCount(for selectedRuns: Int) -> Int {
        max(3, selectedRuns + 2)
    }

    static func summarize(_ measurements: [BenchmarkRunMeasurement]) -> BenchmarkRunMeasurement {
        guard !measurements.isEmpty else {
            return BenchmarkRunMeasurement(megabytesPerSecond: 0, iops: 0, latencyMicroseconds: 0, bytesTransferred: 0)
        }

        let averagedMeasurements: ArraySlice<BenchmarkRunMeasurement>
        if measurements.count > 2 {
            let sorted = measurements.sorted { $0.megabytesPerSecond < $1.megabytesPerSecond }
            averagedMeasurements = sorted.dropFirst().dropLast()
        } else {
            averagedMeasurements = ArraySlice(measurements)
        }

        let count = Double(averagedMeasurements.count)
        let megabytesPerSecond = averagedMeasurements.reduce(0) { $0 + $1.megabytesPerSecond } / count
        let iops = averagedMeasurements.reduce(0) { $0 + $1.iops } / count
        let latencyMicroseconds = averagedMeasurements.reduce(0) { $0 + $1.latencyMicroseconds } / count
        let bytesTransferred = averagedMeasurements.reduce(Int64(0)) { $0 + $1.bytesTransferred }

        return BenchmarkRunMeasurement(
            megabytesPerSecond: megabytesPerSecond,
            iops: iops,
            latencyMicroseconds: latencyMicroseconds,
            bytesTransferred: Int64((Double(bytesTransferred) / count).rounded())
        )
    }
}

enum BenchmarkStorageValidator {
    static let safetyMarginBytes: Int64 = 128 * 1_024 * 1_024

    static func requiredSpace(for fileSizeBytes: Int64) -> Int64 {
        fileSizeBytes + safetyMarginBytes
    }

    static func isFileSizeAvailable(_ fileSizeBytes: Int64, availableCapacity: Int64) -> Bool {
        availableCapacity >= requiredSpace(for: fileSizeBytes)
    }

    static func availableFileSizeOptions(from options: [Int64], availableCapacity: Int64) -> [Int64] {
        options.filter { isFileSizeAvailable($0, availableCapacity: availableCapacity) }
    }

    static func largestAvailableFileSize(from options: [Int64], availableCapacity: Int64) -> Int64? {
        availableFileSizeOptions(from: options, availableCapacity: availableCapacity).max()
    }

    static func availableCapacity(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values?.volumeAvailableCapacity {
            return Int64(capacity)
        }
        if let important = values?.volumeAvailableCapacityForImportantUsage {
            return Int64(important)
        }
        return 0
    }
}

final class NativeBenchmarkRunner: BenchmarkRunning, @unchecked Sendable {
    typealias OperationSleeper = (_ seconds: TimeInterval, _ isCancelled: () -> Bool) throws -> Void
    typealias BenchmarkFileEventHandler = (_ url: URL) -> Void

    private let fileManager: FileManager
    private let operationIntervalSeconds: TimeInterval
    private let passIntervalSeconds: TimeInterval
    private let operationSleeper: OperationSleeper
    private let fileEventHandler: BenchmarkFileEventHandler?
    private let lock = NSLock()
    private var cancelled = false
    private let benchmarkFilePrefix = "Disk-Speed-Test-"
    private let legacyBenchmarkFilePrefixes = [".dit-benchmark-"]

    init(
        fileManager: FileManager = .default,
        operationIntervalSeconds: TimeInterval = 5,
        passIntervalSeconds: TimeInterval = 1,
        operationSleeper: OperationSleeper? = nil,
        fileEventHandler: BenchmarkFileEventHandler? = nil
    ) {
        self.fileManager = fileManager
        self.operationIntervalSeconds = operationIntervalSeconds
        self.passIntervalSeconds = passIntervalSeconds
        self.operationSleeper = operationSleeper ?? Self.defaultOperationSleeper
        self.fileEventHandler = fileEventHandler
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
        let requiredSpace = BenchmarkStorageValidator.requiredSpace(for: maxTestSize)
        let available = BenchmarkStorageValidator.availableCapacity(for: volumeURL)
        if available > 0, available < requiredSpace {
            throw BenchmarkError.insufficientSpace(required: requiredSpace, available: available)
        }

        cleanupBenchmarkFiles(in: volumeURL)
        defer {
            cleanupBenchmarkFiles(in: volumeURL)
        }

        let measuredRuns = BenchmarkMeasurementReducer.measuredRunCount(for: profile.runs)
        let orderedTests = orderedTestsByProfileRows(profile.tests)
        let totalSteps = profile.tests.count * (measuredRuns + 1)
        var completedSteps = 0
        var results: [BenchmarkResult] = []
        let runID = UUID().uuidString

        for (index, test) in orderedTests.enumerated() {
            try checkCancelled()
            notify(progress, BenchmarkProgress(
                currentTestLabel: test.label,
                completed: completedSteps,
                total: totalSteps,
                message: "Preparing \(test.operation.title)"
            ))

            let completedResult = try runMeasuredTest(
                profile: profile,
                drive: drive,
                volumePath: volumePath,
                volumeURL: volumeURL,
                runID: runID,
                test: test,
                measuredRuns: measuredRuns,
                completedSteps: &completedSteps,
                totalSteps: totalSteps,
                progress: progress
            )
            results.append(completedResult)
            notify(result, completedResult)

            if index < orderedTests.count - 1 {
                try checkCancelled()
                notify(progress, BenchmarkProgress(
                    currentTestLabel: test.label,
                    completed: completedSteps,
                    total: totalSteps,
                    message: "Waiting between tests"
                ))
                try waitBetweenOperations()
            }
        }

        notify(progress, BenchmarkProgress(currentTestLabel: "Complete", completed: totalSteps, total: totalSteps, message: "Benchmark complete"))
        return results
    }

    private func orderedTestsByProfileRows(_ tests: [BenchmarkTest]) -> [BenchmarkTest] {
        tests
    }

    private func benchmarkFileURL(in volumeURL: URL, runID: String, test: BenchmarkTest, runIndex: Int) -> URL {
        let label = sanitizedFileToken(test.label)
        return volumeURL.appendingPathComponent("\(benchmarkFilePrefix)\(runID)-\(label)-\(test.operation.rawValue)-run\(runIndex)-\(UUID().uuidString).tmp")
    }

    private func sanitizedFileToken(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func withBenchmarkFile<T>(at url: URL, body: (Int32) throws -> T) throws -> T {
        let path = url.path
        let fd = open(path, O_CREAT | O_RDWR | O_TRUNC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw BenchmarkError.openFailed(path) }
        fileEventHandler?(url)
        defer {
            close(fd)
            try? fileManager.removeItem(at: url)
        }

        var noCache: Int32 = 1
        _ = fcntl(fd, F_NOCACHE, &noCache)
        return try body(fd)
    }

    private func cleanupBenchmarkFiles(in url: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        let removablePrefixes = [benchmarkFilePrefix] + legacyBenchmarkFilePrefixes
        for file in contents where removablePrefixes.contains(where: { file.lastPathComponent.hasPrefix($0) }) {
            try? fileManager.removeItem(at: file)
        }
    }

    private func resizeFile(fd: Int32, size: Int64) throws {
        if ftruncate(fd, off_t(size)) != 0 {
            throw BenchmarkError.ioFailed("Could not resize benchmark file.")
        }
    }

    private func prepareCompleteTestFile(fd: Int32, size: Int64, blockSize: Int, pattern: BenchmarkDataPattern) throws {
        try prepareCompleteTestFile(fd: fd, size: size, blockSize: blockSize, pattern: pattern, progressReporter: nil)
    }

    private func prepareCompleteTestFile(
        fd: Int32,
        size: Int64,
        blockSize: Int,
        pattern: BenchmarkDataPattern,
        progressReporter: ByteProgressReporter?,
        flushStarted: (() -> Void)? = nil
    ) throws {
        try resizeFile(fd: fd, size: 0)

        let bufferSize = max(4_096, min(blockSize, 1_048_576))
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 4_096)
        defer { buffer.deallocate() }

        var offset: Int64 = 0
        progressReporter?.set(0, force: true)
        while offset < size {
            try checkCancelled()
            let count = min(bufferSize, Int(size - offset))
            fill(buffer, count: count, pattern: pattern)
            _ = try transfer(fd: fd, buffer: buffer, count: count, offset: offset, shouldWrite: true)
            offset += Int64(count)
            progressReporter?.set(offset)
        }
        progressReporter?.finish()
        flushStarted?()
        if fsync(fd) != 0 {
            throw BenchmarkError.ioFailed("Could not flush prepared benchmark file.")
        }
    }

    private func runMeasuredTest(
        profile: BenchmarkProfile,
        drive: DriveDevice,
        volumePath: String,
        volumeURL: URL,
        runID: String,
        test: BenchmarkTest,
        measuredRuns: Int,
        completedSteps: inout Int,
        totalSteps: Int,
        progress: @escaping (BenchmarkProgress) -> Void
    ) throws -> BenchmarkResult {
        var measurements: [BenchmarkRunMeasurement] = []

        for runIndex in 0...measuredRuns {
            try checkCancelled()
            let isWarmup = runIndex == 0
            let passMessage = passStatusMessage(for: test, runIndex: runIndex, measuredRuns: measuredRuns)
            notify(progress, BenchmarkProgress(
                currentTestLabel: test.label,
                completed: completedSteps,
                total: totalSteps,
                message: passMessage
            ))

            let testFile = benchmarkFileURL(in: volumeURL, runID: runID, test: test, runIndex: runIndex)
            let phaseCompletedSteps = completedSteps
            let measurement = try withBenchmarkFile(at: testFile) { fd in
                if test.operation != .write {
                    let prepareReporter = byteProgressReporter(
                        test: test,
                        completedSteps: phaseCompletedSteps,
                        totalSteps: totalSteps,
                        message: "Preparing complete test file",
                        progress: progress
                    )
                    notify(progress, BenchmarkProgress(
                        currentTestLabel: test.label,
                        completed: phaseCompletedSteps,
                        total: totalSteps,
                        message: "Preparing complete test file",
                        phaseCompletedBytes: 0,
                        phaseTotalBytes: test.testSizeBytes
                    ))
                    try prepareCompleteTestFile(
                        fd: fd,
                        size: test.testSizeBytes,
                        blockSize: test.blockSizeBytes,
                        pattern: test.dataPattern,
                        progressReporter: prepareReporter,
                        flushStarted: {
                            self.publishPhaseProgress(
                                test: test,
                                completedSteps: phaseCompletedSteps,
                                totalSteps: totalSteps,
                                message: "Flushing prepared test file",
                                completedBytes: test.testSizeBytes,
                                progress: progress
                            )
                        }
                    )
                } else {
                    try resizeFile(fd: fd, size: test.testSizeBytes)
                }
                notify(progress, BenchmarkProgress(
                    currentTestLabel: test.label,
                    completed: phaseCompletedSteps,
                    total: totalSteps,
                    message: passMessage,
                    phaseCompletedBytes: 0,
                    phaseTotalBytes: test.testSizeBytes
                ))
                return try perform(
                    test: test,
                    fd: fd,
                    completedSteps: phaseCompletedSteps,
                    totalSteps: totalSteps,
                    message: passMessage,
                    progress: progress
                )
            }

            if !isWarmup {
                measurements.append(measurement)
            }
            completedSteps += 1
            notify(progress, BenchmarkProgress(
                currentTestLabel: test.label,
                completed: completedSteps,
                total: totalSteps,
                message: passMessage
            ))

            if runIndex < measuredRuns {
                try checkCancelled()
                notify(progress, BenchmarkProgress(
                    currentTestLabel: test.label,
                    completed: completedSteps,
                    total: totalSteps,
                    message: "Waiting between passes"
                ))
                try waitBetweenPasses()
            }
        }

        let average = BenchmarkMeasurementReducer.summarize(measurements)
        return BenchmarkResult(
            driveID: drive.id,
            volumePath: volumePath,
            profileID: profile.id,
            profileName: profile.name,
            testID: test.id,
            testLabel: test.label,
            operation: test.operation,
            measuredAt: Date(),
            bestMegabytesPerSecond: average.megabytesPerSecond,
            iops: average.iops,
            latencyMicroseconds: average.latencyMicroseconds,
            bytesTransferred: average.bytesTransferred
        )
    }

    private func passStatusMessage(for test: BenchmarkTest, runIndex: Int, measuredRuns: Int) -> String {
        if runIndex == 0 {
            return "\(test.operation.title) warm-up"
        }
        return "\(test.operation.title) run \(runIndex)/\(measuredRuns)"
    }

    private final class ByteProgressReporter {
        private let totalBytes: Int64
        private let minimumIntervalNanoseconds: UInt64
        private let onReport: (Int64) -> Void
        private let lock = NSLock()
        private var completedBytes: Int64 = 0
        private var lastReportNanoseconds = DispatchTime.now().uptimeNanoseconds

        init(totalBytes: Int64, minimumIntervalNanoseconds: UInt64 = 250_000_000, onReport: @escaping (Int64) -> Void) {
            self.totalBytes = max(0, totalBytes)
            self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
            self.onReport = onReport
        }

        func add(_ bytes: Int64) {
            let reportBytes: Int64?
            lock.lock()
            completedBytes = min(totalBytes, max(0, completedBytes + bytes))
            let now = DispatchTime.now().uptimeNanoseconds
            if completedBytes >= totalBytes || now - lastReportNanoseconds >= minimumIntervalNanoseconds {
                lastReportNanoseconds = now
                reportBytes = completedBytes
            } else {
                reportBytes = nil
            }
            lock.unlock()

            if let reportBytes {
                onReport(reportBytes)
            }
        }

        func set(_ bytes: Int64, force: Bool = false) {
            let reportBytes: Int64?
            lock.lock()
            completedBytes = min(totalBytes, max(0, bytes))
            let now = DispatchTime.now().uptimeNanoseconds
            if force || completedBytes >= totalBytes || now - lastReportNanoseconds >= minimumIntervalNanoseconds {
                lastReportNanoseconds = now
                reportBytes = completedBytes
            } else {
                reportBytes = nil
            }
            lock.unlock()

            if let reportBytes {
                onReport(reportBytes)
            }
        }

        func finish() {
            set(totalBytes, force: true)
        }
    }

    private func byteProgressReporter(
        test: BenchmarkTest,
        completedSteps: Int,
        totalSteps: Int,
        message: String,
        progress: @escaping (BenchmarkProgress) -> Void
    ) -> ByteProgressReporter {
        ByteProgressReporter(totalBytes: test.testSizeBytes) { [weak self] completedBytes in
            guard let self else { return }
            self.notify(progress, BenchmarkProgress(
                currentTestLabel: test.label,
                completed: completedSteps,
                total: totalSteps,
                message: message,
                phaseCompletedBytes: completedBytes,
                phaseTotalBytes: test.testSizeBytes
            ))
        }
    }

    private func publishPhaseProgress(
        test: BenchmarkTest,
        completedSteps: Int,
        totalSteps: Int,
        message: String,
        completedBytes: Int64,
        progress: @escaping (BenchmarkProgress) -> Void
    ) {
        notify(progress, BenchmarkProgress(
            currentTestLabel: test.label,
            completed: completedSteps,
            total: totalSteps,
            message: message,
            phaseCompletedBytes: completedBytes,
            phaseTotalBytes: test.testSizeBytes
        ))
    }

    private struct TransferRequest {
        var offset: Int64
        var count: Int
    }

    private func perform(
        test: BenchmarkTest,
        fd: Int32,
        completedSteps: Int,
        totalSteps: Int,
        message: String,
        progress: @escaping (BenchmarkProgress) -> Void
    ) throws -> BenchmarkRunMeasurement {
        let threadCount = max(1, test.threads)
        let queueDepth = max(1, test.queueDepth)
        let blockSize = max(512, test.blockSizeBytes)
        let fileSize = max(Int64(blockSize), test.testSizeBytes)
        let aggregateLock = NSLock()
        let progressReporter = byteProgressReporter(
            test: test,
            completedSteps: completedSteps,
            totalSteps: totalSteps,
            message: message,
            progress: progress
        )
        var assignedBytes: Int64 = 0
        var nextSequentialOffset: Int64 = 0
        var totalBytes: Int64 = 0
        var totalOperations: Int64 = 0
        var minLatencyMicros = Double.greatestFiniteMagnitude
        var firstError: Error?

        progressReporter.set(0, force: true)
        let started = DispatchTime.now().uptimeNanoseconds
        DispatchQueue.concurrentPerform(iterations: threadCount) { _ in
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: blockSize, alignment: 4_096)
            defer { buffer.deallocate() }

            var localBytes: Int64 = 0
            var localOperations: Int64 = 0
            var localMinLatency = Double.greatestFiniteMagnitude

            while true {
                if isCancelled() {
                    aggregateLock.lock()
                    if firstError == nil {
                        firstError = BenchmarkError.cancelled
                    }
                    aggregateLock.unlock()
                    return
                }

                for _ in 0..<queueDepth {
                    let request: TransferRequest?
                    aggregateLock.lock()
                    if firstError != nil || assignedBytes >= test.testSizeBytes {
                        request = nil
                    } else {
                        let count = min(blockSize, Int(test.testSizeBytes - assignedBytes))
                        let offset = offsetFor(test: test, fileSize: fileSize, count: count, nextSequentialOffset: &nextSequentialOffset)
                        assignedBytes += Int64(count)
                        request = TransferRequest(offset: offset, count: count)
                    }
                    aggregateLock.unlock()

                    guard let request else { break }

                    let shouldWrite = shouldWrite(test: test)
                    let opStarted = DispatchTime.now().uptimeNanoseconds
                    do {
                        if shouldWrite {
                            fill(buffer, count: request.count, pattern: test.dataPattern)
                        }
                        let transferred = try transfer(fd: fd, buffer: buffer, count: request.count, offset: request.offset, shouldWrite: shouldWrite)
                        let opFinished = DispatchTime.now().uptimeNanoseconds

                        localBytes += Int64(transferred)
                        localOperations += 1
                        localMinLatency = min(localMinLatency, Double(opFinished - opStarted) / 1_000)
                        progressReporter.add(Int64(transferred))
                    } catch {
                        aggregateLock.lock()
                        if firstError == nil {
                            firstError = error
                        }
                        aggregateLock.unlock()
                        return
                    }
                }

                aggregateLock.lock()
                let shouldStop = firstError != nil || assignedBytes >= test.testSizeBytes
                aggregateLock.unlock()
                if shouldStop {
                    break
                }
            }

            aggregateLock.lock()
            totalBytes += localBytes
            totalOperations += localOperations
            minLatencyMicros = min(minLatencyMicros, localMinLatency)
            aggregateLock.unlock()
        }

        if let firstError { throw firstError }

        progressReporter.finish()
        if test.operation == .write || test.operation == .mixed {
            publishPhaseProgress(
                test: test,
                completedSteps: completedSteps,
                totalSteps: totalSteps,
                message: "Flushing writes",
                completedBytes: test.testSizeBytes,
                progress: progress
            )
            if fsync(fd) != 0 {
                throw BenchmarkError.ioFailed("Could not flush benchmark writes.")
            }
        }

        let finished = DispatchTime.now().uptimeNanoseconds
        let elapsed = max(0.001, Double(finished - started) / 1_000_000_000)
        return BenchmarkRunMeasurement(
            megabytesPerSecond: Double(totalBytes) / elapsed / 1_000_000,
            iops: Double(totalOperations) / elapsed,
            latencyMicroseconds: minLatencyMicros.isFinite ? minLatencyMicros : 0,
            bytesTransferred: totalBytes
        )
    }

    private func perform(test: BenchmarkTest, fd: Int32) throws -> BenchmarkRunMeasurement {
        try perform(
            test: test,
            fd: fd,
            completedSteps: 0,
            totalSteps: 0,
            message: test.operation.title,
            progress: { _ in }
        )
    }

    private func offsetFor(
        test: BenchmarkTest,
        fileSize: Int64,
        count: Int,
        nextSequentialOffset: inout Int64
    ) -> Int64 {
        let maxOffset = max(Int64(0), fileSize - Int64(count))
        switch test.accessPattern {
        case .sequential:
            let offset = min(nextSequentialOffset, maxOffset)
            nextSequentialOffset = offset + Int64(count)
            return offset
        case .random:
            let blockSize = max(1, test.blockSizeBytes)
            let blocks = max(1, UInt32(maxOffset / Int64(blockSize) + 1))
            return Int64(arc4random_uniform(blocks)) * Int64(blockSize)
        }
    }

    private func transfer(fd: Int32, buffer: UnsafeMutableRawPointer, count: Int, offset: Int64, shouldWrite: Bool) throws -> Int {
        var transferred = 0
        while transferred < count {
            try checkCancelled()
            let pointer = buffer.advanced(by: transferred)
            let remaining = count - transferred
            let position = off_t(offset + Int64(transferred))
            let result = shouldWrite
                ? pwrite(fd, pointer, remaining, position)
                : pread(fd, pointer, remaining, position)
            guard result > 0 else {
                throw BenchmarkError.ioFailed(shouldWrite ? "Write test failed." : "Read test failed.")
            }
            transferred += result
        }
        return transferred
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

    private func waitBetweenOperations() throws {
        guard operationIntervalSeconds > 0 else { return }
        try operationSleeper(operationIntervalSeconds) { self.isCancelled() }
        try checkCancelled()
    }

    private func waitBetweenPasses() throws {
        guard passIntervalSeconds > 0 else { return }
        try operationSleeper(passIntervalSeconds) { self.isCancelled() }
        try checkCancelled()
    }

    private static func defaultOperationSleeper(seconds: TimeInterval, isCancelled: () -> Bool) throws {
        let durationNanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        let deadline = DispatchTime.now().uptimeNanoseconds + durationNanoseconds
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { break }
            if isCancelled() {
                throw BenchmarkError.cancelled
            }
            let remainingSeconds = Double(deadline - now) / 1_000_000_000
            Thread.sleep(forTimeInterval: min(0.1, max(0, remainingSeconds)))
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
