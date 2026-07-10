// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation

enum DiskActivityWorkloadOperation: String, Codable, CaseIterable, Identifiable, Sendable {
    case read
    case write
    case mixed

    var id: String { rawValue }
}

enum DiskActivityWorkloadFileSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case gib32
    case gib64
    case gib128
    case gib256
    case gib512
    case gib1024
    case fullDisk95

    var id: String { rawValue }

    var fixedBytes: Int64? {
        let gib: Int64 = 1_024 * 1_024 * 1_024
        switch self {
        case .gib32: return 32 * gib
        case .gib64: return 64 * gib
        case .gib128: return 128 * gib
        case .gib256: return 256 * gib
        case .gib512: return 512 * gib
        case .gib1024: return 1_024 * gib
        case .fullDisk95: return nil
        }
    }
}

struct DiskActivityWorkloadConfiguration: Equatable, Sendable {
    var targetFolderURL: URL
    var operation: DiskActivityWorkloadOperation
    var fileSizeOption: DiskActivityWorkloadFileSize
    var fileSizeBytes: Int64
    var loopEnabled: Bool
}

enum DiskActivityWorkloadPhase: String, Codable, Sendable {
    case starting
    case preparingReadFile
    case reading
    case writing
    case mixed
    case flushing
    case cleaningUp
    case complete
    case stopped
}

struct DiskActivityWorkloadProgress: Equatable, Sendable {
    var operation: DiskActivityWorkloadOperation
    var phase: DiskActivityWorkloadPhase
    var loopIndex: Int
    var completedBytes: Int64
    var totalBytes: Int64
    var message: String

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

enum DiskActivityWorkloadStorageValidator {
    static let safetyMarginBytes = BenchmarkStorageValidator.safetyMarginBytes
    static let fullDiskAvailableFraction = 0.95

    static func resolvedFileSize(
        for option: DiskActivityWorkloadFileSize,
        operation: DiskActivityWorkloadOperation,
        availableCapacity: Int64
    ) -> Int64? {
        if let fixedBytes = option.fixedBytes {
            return fixedBytes
        }

        guard availableCapacity > safetyMarginBytes else { return nil }
        let usableCapacity = availableCapacity - safetyMarginBytes
        let targetFootprint = Int64(Double(usableCapacity) * fullDiskAvailableFraction)
        let bytes = operation == .mixed ? targetFootprint / 2 : targetFootprint
        return roundedDownToMiB(max(0, bytes))
    }

    static func requiredSpace(fileSizeBytes: Int64, operation: DiskActivityWorkloadOperation) -> Int64 {
        let fileFootprint = operation == .mixed ? fileSizeBytes * 2 : fileSizeBytes
        return fileFootprint + safetyMarginBytes
    }

    static func isFileSizeAvailable(
        _ option: DiskActivityWorkloadFileSize,
        operation: DiskActivityWorkloadOperation,
        availableCapacity: Int64
    ) -> Bool {
        guard let fileSize = resolvedFileSize(for: option, operation: operation, availableCapacity: availableCapacity),
              fileSize > 0 else {
            return false
        }
        return availableCapacity >= requiredSpace(fileSizeBytes: fileSize, operation: operation)
    }

    static func largestAvailableFileSizeOption(
        operation: DiskActivityWorkloadOperation,
        availableCapacity: Int64
    ) -> DiskActivityWorkloadFileSize? {
        DiskActivityWorkloadFileSize.allCases.reversed().first {
            isFileSizeAvailable($0, operation: operation, availableCapacity: availableCapacity)
        }
    }

    static func availableCapacity(for url: URL) -> Int64 {
        BenchmarkStorageValidator.availableCapacity(for: url)
    }

    private static func roundedDownToMiB(_ bytes: Int64) -> Int64 {
        let mib: Int64 = 1_024 * 1_024
        return (bytes / mib) * mib
    }
}

enum DiskActivityWorkloadEvent: Sendable {
    case progress(DiskActivityWorkloadProgress)
}

protocol DiskActivityWorkloadRunning: AnyObject, Sendable {
    func run(
        configuration: DiskActivityWorkloadConfiguration,
        drive: DriveDevice,
        progress: @escaping @Sendable (DiskActivityWorkloadProgress) -> Void
    ) async throws
    func cancel()
}

final class NativeDiskActivityWorkloadRunner: DiskActivityWorkloadRunning, @unchecked Sendable {
    typealias WorkloadFileEventHandler = (_ url: URL) -> Void

    static let accessPatternLabel = "SEQ1M"
    static let queueDepth = 4
    static let threadCount = 4
    static let transferChunkSizeBytes = 4 * 1_024 * 1_024
    static let usesZeroFill = true
    static var requestDepth: Int { queueDepth * threadCount }

    private final class AIORequest {
        let controlBlock: UnsafeMutablePointer<aiocb>
        let buffer: UnsafeMutableRawPointer
        let count: Int

        init(controlBlock: UnsafeMutablePointer<aiocb>, buffer: UnsafeMutableRawPointer, count: Int) {
            self.controlBlock = controlBlock
            self.buffer = buffer
            self.count = count
        }

        func release() {
            controlBlock.deinitialize(count: 1)
            controlBlock.deallocate()
            buffer.deallocate()
        }
    }

    private let fileManager: FileManager
    private let fileEventHandler: WorkloadFileEventHandler?
    private let lock = NSLock()
    private var cancelled = false
    private let workloadFilePrefix = "Capricorn-Activity-"

    init(
        fileManager: FileManager = .default,
        fileEventHandler: WorkloadFileEventHandler? = nil
    ) {
        self.fileManager = fileManager
        self.fileEventHandler = fileEventHandler
    }

    func cancel() {
        setCancelled(true)
    }

    func run(
        configuration: DiskActivityWorkloadConfiguration,
        drive: DriveDevice,
        progress: @escaping @Sendable (DiskActivityWorkloadProgress) -> Void
    ) async throws {
        setCancelled(false)

        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.runBlocking(configuration: configuration, drive: drive, progress: progress)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runBlocking(
        configuration: DiskActivityWorkloadConfiguration,
        drive: DriveDevice,
        progress: @escaping @Sendable (DiskActivityWorkloadProgress) -> Void
    ) throws {
        let targetURL = configuration.targetFolderURL
        let targetPath = targetURL.path
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: targetPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BenchmarkError.volumeUnavailable
        }
        guard fileManager.isWritableFile(atPath: targetPath) else {
            throw BenchmarkError.volumeNotWritable(targetPath)
        }
        guard BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(targetPath, drive: drive) else {
            throw BenchmarkError.ioFailed("Workload target folder must be on the selected drive.")
        }

        cleanupWorkloadFiles(in: targetURL)
        let available = DiskActivityWorkloadStorageValidator.availableCapacity(for: targetURL)
        let required = DiskActivityWorkloadStorageValidator.requiredSpace(
            fileSizeBytes: configuration.fileSizeBytes,
            operation: configuration.operation
        )
        if available > 0, available < required {
            throw BenchmarkError.insufficientSpace(required: required, available: available)
        }

        var preparedReadFile: DiskActivityWorkloadOpenFile?
        defer {
            preparedReadFile?.closeAndRemove()
            cleanupWorkloadFiles(in: targetURL)
        }

        let runID = UUID().uuidString
        var loopIndex = 1

        repeat {
            try checkCancelled()
            switch configuration.operation {
            case .read:
                if preparedReadFile == nil {
                    preparedReadFile = try prepareReadFile(configuration: configuration, runID: runID, loopIndex: loopIndex, progress: progress)
                }
                try performRead(configuration: configuration, file: preparedReadFile!, loopIndex: loopIndex, progress: progress)
            case .write:
                try performWrite(configuration: configuration, runID: runID, loopIndex: loopIndex, progress: progress)
            case .mixed:
                if preparedReadFile == nil {
                    preparedReadFile = try prepareReadFile(configuration: configuration, runID: runID, loopIndex: loopIndex, progress: progress)
                }
                try performMixed(configuration: configuration, readFile: preparedReadFile!, runID: runID, loopIndex: loopIndex, progress: progress)
            }

            loopIndex += 1
        } while configuration.loopEnabled

        notify(progress, progressValue(configuration: configuration, phase: .complete, loopIndex: max(1, loopIndex - 1), completedBytes: configuration.fileSizeBytes, totalBytes: configuration.fileSizeBytes, message: "Workload complete"))
    }

    private func prepareReadFile(
        configuration: DiskActivityWorkloadConfiguration,
        runID: String,
        loopIndex: Int,
        progress: @escaping @Sendable (DiskActivityWorkloadProgress) -> Void
    ) throws -> DiskActivityWorkloadOpenFile {
        let url = workloadFileURL(in: configuration.targetFolderURL, runID: runID, role: "read-source", loopIndex: loopIndex)
        let file = try openWorkloadFile(at: url)
        do {
            let reporter = ByteProgressReporter(totalBytes: configuration.fileSizeBytes) { completedBytes in
                self.notify(progress, self.progressValue(
                    configuration: configuration,
                    phase: .preparingReadFile,
                    loopIndex: loopIndex,
                    completedBytes: completedBytes,
                    totalBytes: configuration.fileSizeBytes,
                    message: "Preparing read workload file"
                ))
            }
            try writeFullFile(fd: file.fd, size: configuration.fileSizeBytes, reporter: reporter)
            notify(progress, progressValue(configuration: configuration, phase: .flushing, loopIndex: loopIndex, completedBytes: configuration.fileSizeBytes, totalBytes: configuration.fileSizeBytes, message: "Flushing workload writes"))
            if fsync(file.fd) != 0 {
                throw BenchmarkError.ioFailed("Could not flush workload writes.")
            }
            return file
        } catch {
            file.closeAndRemove()
            throw error
        }
    }

    private func performRead(
        configuration: DiskActivityWorkloadConfiguration,
        file: DiskActivityWorkloadOpenFile,
        loopIndex: Int,
        progress: @escaping @Sendable (DiskActivityWorkloadProgress) -> Void
    ) throws {
        let reporter = ByteProgressReporter(totalBytes: configuration.fileSizeBytes) { completedBytes in
            self.notify(progress, self.progressValue(
                configuration: configuration,
                phase: .reading,
                loopIndex: loopIndex,
                completedBytes: completedBytes,
                totalBytes: configuration.fileSizeBytes,
                message: "Reading workload file"
            ))
        }
        try readFullFile(fd: file.fd, size: configuration.fileSizeBytes, reporter: reporter)
    }

    private func performWrite(
        configuration: DiskActivityWorkloadConfiguration,
        runID: String,
        loopIndex: Int,
        progress: @escaping @Sendable (DiskActivityWorkloadProgress) -> Void
    ) throws {
        let url = workloadFileURL(in: configuration.targetFolderURL, runID: runID, role: "write", loopIndex: loopIndex)
        let file = try openWorkloadFile(at: url)
        defer { file.closeAndRemove() }

        let reporter = ByteProgressReporter(totalBytes: configuration.fileSizeBytes) { completedBytes in
            self.notify(progress, self.progressValue(
                configuration: configuration,
                phase: .writing,
                loopIndex: loopIndex,
                completedBytes: completedBytes,
                totalBytes: configuration.fileSizeBytes,
                message: "Writing workload file"
            ))
        }
        try writeFullFile(fd: file.fd, size: configuration.fileSizeBytes, reporter: reporter)
        notify(progress, progressValue(configuration: configuration, phase: .flushing, loopIndex: loopIndex, completedBytes: configuration.fileSizeBytes, totalBytes: configuration.fileSizeBytes, message: "Flushing workload writes"))
        if fsync(file.fd) != 0 {
            throw BenchmarkError.ioFailed("Could not flush workload writes.")
        }
    }

    private func performMixed(
        configuration: DiskActivityWorkloadConfiguration,
        readFile: DiskActivityWorkloadOpenFile,
        runID: String,
        loopIndex: Int,
        progress: @escaping @Sendable (DiskActivityWorkloadProgress) -> Void
    ) throws {
        let url = workloadFileURL(in: configuration.targetFolderURL, runID: runID, role: "mixed-write", loopIndex: loopIndex)
        let writeFile = try openWorkloadFile(at: url)
        defer { writeFile.closeAndRemove() }

        let totalBytes = configuration.fileSizeBytes * 2
        let reporter = ByteProgressReporter(totalBytes: totalBytes) { completedBytes in
            self.notify(progress, self.progressValue(
                configuration: configuration,
                phase: .mixed,
                loopIndex: loopIndex,
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                message: "Running mixed workload"
            ))
        }

        let firstError = LockedState<Error?>(nil)
        let group = DispatchGroup()

        let record: @Sendable (Error) -> Void = { [weak self] error in
            let isFirst = firstError.withLock { storedError -> Bool in
                guard storedError == nil else { return false }
                storedError = error
                return true
            }
            if isFirst {
                self?.setCancelled(true)
            }
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            do {
                try self.transferFullFile(fd: readFile.fd, size: configuration.fileSizeBytes, shouldWrite: false, reporter: reporter, resetReporter: false, finishReporter: false)
            } catch {
                record(error)
            }
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            do {
                try self.transferFullFile(fd: writeFile.fd, size: configuration.fileSizeBytes, shouldWrite: true, reporter: reporter, resetReporter: false, finishReporter: false)
                self.notify(progress, self.progressValue(configuration: configuration, phase: .flushing, loopIndex: loopIndex, completedBytes: totalBytes, totalBytes: totalBytes, message: "Flushing workload writes"))
                if fsync(writeFile.fd) != 0 {
                    throw BenchmarkError.ioFailed("Could not flush workload writes.")
                }
            } catch {
                record(error)
            }
        }

        group.wait()
        if let firstError = firstError.snapshot() {
            throw firstError
        }
        reporter.finish()
    }

    private func writeFullFile(fd: Int32, size: Int64, reporter: ByteProgressReporter) throws {
        try transferFullFile(fd: fd, size: size, shouldWrite: true, reporter: reporter)
    }

    private func readFullFile(fd: Int32, size: Int64, reporter: ByteProgressReporter) throws {
        try transferFullFile(fd: fd, size: size, shouldWrite: false, reporter: reporter)
    }

    private func transferFullFile(
        fd: Int32,
        size: Int64,
        shouldWrite: Bool,
        reporter: ByteProgressReporter,
        resetReporter: Bool = true,
        finishReporter: Bool = true
    ) throws {
        let requestDepth = Self.requestDepth
        let chunkSize = max(4_096, min(Self.transferChunkSizeBytes, Int(max(0, size))))
        var assignedBytes: Int64 = 0
        var activeRequests: [AIORequest] = []
        var firstError: Error?

        if resetReporter {
            reporter.set(0, force: true)
        }

        func reapCompletedRequests() throws {
            var completedIndexes: [Int] = []
            for (index, request) in activeRequests.enumerated() {
                let error = aio_error(request.controlBlock)
                if error == EINPROGRESS {
                    continue
                }

                let returned = aio_return(request.controlBlock)
                if error != 0 {
                    firstError = BenchmarkError.ioFailed(errorMessage(for: error, shouldWrite: shouldWrite))
                } else if returned <= 0 {
                    firstError = BenchmarkError.ioFailed(shouldWrite ? "Write workload failed." : "Read workload failed.")
                } else {
                    let transferred = min(returned, request.count)
                    reporter.add(Int64(transferred))
                }
                completedIndexes.append(index)
            }

            for index in completedIndexes.reversed() {
                let request = activeRequests.remove(at: index)
                request.release()
            }

            if let firstError {
                throw firstError
            }
        }

        func releaseActiveRequests() {
            if !activeRequests.isEmpty {
                _ = aio_cancel(fd, nil)
            }
            activeRequests.forEach { $0.release() }
            activeRequests.removeAll()
        }

        defer {
            releaseActiveRequests()
        }

        while assignedBytes < size || !activeRequests.isEmpty {
            try checkCancelled()

            while activeRequests.count < requestDepth && assignedBytes < size {
                try checkCancelled()
                let count = min(chunkSize, Int(size - assignedBytes))
                let offset = assignedBytes
                let request = makeRequest(fd: fd, count: count, offset: offset, shouldWrite: shouldWrite)
                let submitResult = shouldWrite ? aio_write(request.controlBlock) : aio_read(request.controlBlock)
                guard submitResult == 0 else {
                    let submitError = errno
                    request.release()

                    if isAIOResourceLimit(submitError), !activeRequests.isEmpty {
                        try waitForAnyCompletion(activeRequests)
                        try reapCompletedRequests()
                        continue
                    }

                    throw BenchmarkError.ioFailed(submitErrorMessage(
                        for: submitError,
                        shouldWrite: shouldWrite,
                        activeRequests: activeRequests.count,
                        targetDepth: requestDepth
                    ))
                }
                assignedBytes += Int64(count)
                activeRequests.append(request)
            }

            if activeRequests.isEmpty {
                continue
            }

            try waitForAnyCompletion(activeRequests)
            try reapCompletedRequests()
        }

        if finishReporter {
            reporter.finish()
        }
    }

    private func makeRequest(fd: Int32, count: Int, offset: Int64, shouldWrite: Bool) -> AIORequest {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 4_096)
        if shouldWrite {
            memset(buffer, 0, count)
        }

        let controlBlock = UnsafeMutablePointer<aiocb>.allocate(capacity: 1)
        controlBlock.initialize(to: aiocb())
        controlBlock.pointee.aio_fildes = fd
        controlBlock.pointee.aio_offset = off_t(offset)
        controlBlock.pointee.aio_buf = buffer
        controlBlock.pointee.aio_nbytes = count
        controlBlock.pointee.aio_reqprio = 0
        return AIORequest(controlBlock: controlBlock, buffer: buffer, count: count)
    }

    private func waitForAnyCompletion(_ requests: [AIORequest]) throws {
        let pointers: [UnsafePointer<aiocb>?] = requests.map { UnsafePointer($0.controlBlock) }
        let result = pointers.withUnsafeBufferPointer { buffer in
            aio_suspend(buffer.baseAddress, Int32(buffer.count), nil)
        }
        if result != 0, errno != EINTR {
            throw BenchmarkError.ioFailed("Async workload wait failed.")
        }
    }

    private func errorMessage(for error: Int32, shouldWrite: Bool) -> String {
        let operationName = shouldWrite ? "write" : "read"
        let reason = strerror(error).map { String(cString: $0) } ?? "unknown error"
        return "Async workload \(operationName) failed: \(reason)."
    }

    private func submitErrorMessage(for error: Int32, shouldWrite: Bool, activeRequests: Int, targetDepth: Int) -> String {
        let operationName = shouldWrite ? "write" : "read"
        let reason = strerror(error).map { String(cString: $0) } ?? "unknown error"
        return "Async workload \(operationName) failed to submit: \(reason) (errno \(error), active \(activeRequests)/Q\(targetDepth))."
    }

    private func isAIOResourceLimit(_ error: Int32) -> Bool {
        error == EAGAIN || error == ENOMEM || error == ENOBUFS
    }

    private func workloadFileURL(in targetURL: URL, runID: String, role: String, loopIndex: Int) -> URL {
        targetURL.appendingPathComponent("\(workloadFilePrefix)\(runID)-\(role)-loop\(loopIndex)-\(UUID().uuidString).tmp")
    }

    private func openWorkloadFile(at url: URL) throws -> DiskActivityWorkloadOpenFile {
        let path = url.path
        let fd = open(path, O_CREAT | O_RDWR | O_TRUNC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw BenchmarkError.openFailed(path) }
        fileEventHandler?(url)

        var noCache: Int32 = 1
        _ = fcntl(fd, F_NOCACHE, &noCache)
        return DiskActivityWorkloadOpenFile(url: url, fd: fd, fileManager: fileManager)
    }

    private func cleanupWorkloadFiles(in url: URL) {
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for file in contents where file.lastPathComponent.hasPrefix(workloadFilePrefix) {
            try? fileManager.removeItem(at: file)
        }
    }

    private func progressValue(
        configuration: DiskActivityWorkloadConfiguration,
        phase: DiskActivityWorkloadPhase,
        loopIndex: Int,
        completedBytes: Int64,
        totalBytes: Int64,
        message: String
    ) -> DiskActivityWorkloadProgress {
        DiskActivityWorkloadProgress(
            operation: configuration.operation,
            phase: phase,
            loopIndex: loopIndex,
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            message: message
        )
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

    private func notify(_ progress: @escaping @Sendable (DiskActivityWorkloadProgress) -> Void, _ value: DiskActivityWorkloadProgress) {
        progress(value)
    }

    private final class ByteProgressReporter: @unchecked Sendable {
        private let totalBytes: Int64
        private let minimumIntervalNanoseconds: UInt64
        private let onReport: (Int64) -> Void
        private let lock = NSLock()
        private var completedBytes: Int64 = 0
        private var lastReportNanoseconds = DispatchTime.now().uptimeNanoseconds

        init(totalBytes: Int64, minimumIntervalNanoseconds: UInt64 = 250_000_000, onReport: @escaping @Sendable (Int64) -> Void) {
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
}

private final class DiskActivityWorkloadOpenFile: @unchecked Sendable {
    let url: URL
    let fd: Int32
    private let fileManager: FileManager
    private var isClosed = false

    init(url: URL, fd: Int32, fileManager: FileManager) {
        self.url = url
        self.fd = fd
        self.fileManager = fileManager
    }

    deinit {
        closeAndRemove()
    }

    func closeAndRemove() {
        guard !isClosed else { return }
        isClosed = true
        close(fd)
        try? fileManager.removeItem(at: url)
    }
}
