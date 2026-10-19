// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation
import os

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
    case sizingFile
    case flushingReadFile
    case reading
    case writing
    case mixed
    case flushing
    case cleaningUp
    case complete
    case stopped
    case failed
}

struct DiskActivityWorkloadProgress: Equatable, Sendable {
    var operation: DiskActivityWorkloadOperation
    var phase: DiskActivityWorkloadPhase
    var loopIndex: Int
    var completedBytes: Int64
    var totalBytes: Int64
    var message: String
    var queueStatus: AIOTransferStatus? = nil
    var failedPhaseMessage: String? = nil

    var hasMeasurableByteProgress: Bool {
        ![.starting, .sizingFile, .cleaningUp].contains(phase)
    }

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

    private let transfer: AIOTransfer
    private let fileManager: FileManager
    private let fileEventHandler: WorkloadFileEventHandler?
    private let temporaryRunLeaseDirectoryURL: URL?
    private let lock = NSLock()
    private var cancelled = false
    private let workloadFilePrefix = "Capricorn-Activity-"

    init(
        fileManager: FileManager = .default,
        fileEventHandler: WorkloadFileEventHandler? = nil,
        temporaryRunLeaseDirectoryURL: URL? = nil,
        transfer: AIOTransfer = AIOTransfer()
    ) {
        self.fileManager = fileManager
        self.fileEventHandler = fileEventHandler
        self.temporaryRunLeaseDirectoryURL = temporaryRunLeaseDirectoryURL
        self.transfer = transfer
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
        let latestProgress = LockedState<DiskActivityWorkloadProgress?>(nil)
        let lastTransferProgress = LockedState<DiskActivityWorkloadProgress?>(nil)
        let report: @Sendable (DiskActivityWorkloadProgress) -> Void = { value in
            latestProgress.withLock { latest in
                if latest?.phase == .cleaningUp && value.phase != .failed { return }
                var value = value
                if value.queueStatus == nil && [.complete, .flushing, .flushingReadFile, .failed].contains(value.phase) {
                    value.queueStatus = latest?.queueStatus
                }
                if value.phase != .cleaningUp && value.phase != .failed {
                    lastTransferProgress.withLock { $0 = value }
                }
                latest = value
                progress(value)
            }
        }

        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.runBlocking(configuration: configuration, drive: drive, progress: report)
                    continuation.resume()
                } catch {
                    if case BenchmarkError.cancelled = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if var failed = lastTransferProgress.snapshot() ?? latestProgress.snapshot() {
                        failed.failedPhaseMessage = failed.message
                        failed.phase = .failed
                        failed.message = "Workload failed"
                        report(failed)
                    }
                    CapricornLog.workload.error("Workload failed: \(error.localizedDescription, privacy: .public)")
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
        notify(progress, progressValue(configuration: configuration, phase: .starting, loopIndex: 1, completedBytes: 0, totalBytes: configuration.fileSizeBytes, message: "Starting workload"))
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

        let runID = UUID().uuidString
        let runLease = try TemporaryRunLease(
            kind: .activity,
            runID: runID,
            leaseDirectoryURL: temporaryRunLeaseDirectoryURL,
            fileManager: fileManager
        )
        var preparedReadFile: DiskActivityWorkloadOpenFile?
        defer {
            preparedReadFile?.closeAndRemove()
            cleanupWorkloadFiles(in: targetURL, runID: runID)
            runLease.release(removingLeaseFile: true)
        }
        TemporaryRunLease.cleanupStaleFiles(
            in: targetURL,
            kind: .activity,
            leaseDirectoryURL: temporaryRunLeaseDirectoryURL,
            fileManager: fileManager
        )

        let available = DiskActivityWorkloadStorageValidator.availableCapacity(for: targetURL)
        let required = DiskActivityWorkloadStorageValidator.requiredSpace(
            fileSizeBytes: configuration.fileSizeBytes,
            operation: configuration.operation
        )
        if available > 0, available < required {
            throw BenchmarkError.insufficientSpace(required: required, available: available)
        }

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
        notify(progress, progressValue(configuration: configuration, phase: .sizingFile, loopIndex: loopIndex, completedBytes: 0, totalBytes: configuration.fileSizeBytes, message: "Sizing workload file"))
        let file = try openWorkloadFile(at: url, size: configuration.fileSizeBytes)
        do {
            let reporter = ByteProgressReporter(totalBytes: configuration.fileSizeBytes) { completedBytes, queueStatus in
                self.notify(progress, self.progressValue(
                    configuration: configuration,
                    phase: .preparingReadFile,
                    loopIndex: loopIndex,
                    completedBytes: completedBytes,
                    totalBytes: configuration.fileSizeBytes,
                    message: "Preparing read workload file",
                    queueStatus: queueStatus
                ))
            }
            try writeFullFile(fd: file.fd, size: configuration.fileSizeBytes, reporter: reporter)
            notify(progress, progressValue(configuration: configuration, phase: .flushingReadFile, loopIndex: loopIndex, completedBytes: configuration.fileSizeBytes, totalBytes: configuration.fileSizeBytes, message: "Flushing prepared workload file"))
            if fsync(file.fd) != 0 {
                throw flushError(fd: file.fd, stage: "prepared workload")
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
        let reporter = ByteProgressReporter(totalBytes: configuration.fileSizeBytes) { completedBytes, queueStatus in
            self.notify(progress, self.progressValue(
                configuration: configuration,
                phase: .reading,
                loopIndex: loopIndex,
                completedBytes: completedBytes,
                totalBytes: configuration.fileSizeBytes,
                message: "Reading workload file",
                queueStatus: queueStatus
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
        notify(progress, progressValue(configuration: configuration, phase: .sizingFile, loopIndex: loopIndex, completedBytes: 0, totalBytes: configuration.fileSizeBytes, message: "Sizing workload file"))
        let file = try openWorkloadFile(at: url, size: configuration.fileSizeBytes)
        defer { file.closeAndRemove() }

        let reporter = ByteProgressReporter(totalBytes: configuration.fileSizeBytes) { completedBytes, queueStatus in
            self.notify(progress, self.progressValue(
                configuration: configuration,
                phase: .writing,
                loopIndex: loopIndex,
                completedBytes: completedBytes,
                totalBytes: configuration.fileSizeBytes,
                message: "Writing workload file",
                queueStatus: queueStatus
            ))
        }
        try writeFullFile(fd: file.fd, size: configuration.fileSizeBytes, reporter: reporter)
        notify(progress, progressValue(configuration: configuration, phase: .flushing, loopIndex: loopIndex, completedBytes: configuration.fileSizeBytes, totalBytes: configuration.fileSizeBytes, message: "Flushing workload writes"))
        if fsync(file.fd) != 0 {
            throw flushError(fd: file.fd, stage: "workload")
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
        notify(progress, progressValue(configuration: configuration, phase: .sizingFile, loopIndex: loopIndex, completedBytes: 0, totalBytes: configuration.fileSizeBytes * 2, message: "Sizing workload file"))
        let writeFile = try openWorkloadFile(at: url, size: configuration.fileSizeBytes)
        defer { writeFile.closeAndRemove() }

        let totalBytes = configuration.fileSizeBytes * 2
        let reporter = ByteProgressReporter(totalBytes: totalBytes) { completedBytes, queueStatus in
            self.notify(progress, self.progressValue(
                configuration: configuration,
                phase: .mixed,
                loopIndex: loopIndex,
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                message: "Running mixed workload",
                queueStatus: queueStatus
            ))
        }
        reporter.set(0, force: true)

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
            } catch {
                record(error)
            }
        }

        group.wait()
        if let firstError = firstError.snapshot() {
            throw firstError
        }
        try checkCancelled()
        reporter.finish()
        notify(progress, progressValue(configuration: configuration, phase: .flushing, loopIndex: loopIndex, completedBytes: totalBytes, totalBytes: totalBytes, message: "Flushing workload writes"))
        if fsync(writeFile.fd) != 0 {
            throw flushError(fd: writeFile.fd, stage: "mixed workload")
        }
        try checkCancelled()
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
        let chunkSize = max(4_096, min(Self.transferChunkSizeBytes, Int(max(0, size))))
        if resetReporter {
            reporter.set(0, force: true)
        }
        try transfer.run(
            descriptor: fd, bytes: size, blockSize: chunkSize, depth: Self.requestDepth,
            checkCancelled: checkCancelled,
            operation: { offset, _ in AIOTransferOperation(offset: offset, write: shouldWrite) },
            fill: { buffer, count in memset(buffer, 0, count) },
            completed: { bytes, _ in reporter.add(Int64(bytes)) },
            statusChanged: { status in
                reporter.update(status)
                if status.finished {
                    CapricornLog.workload.info("AIO workload \(status.detail, privacy: .public)")
                }
            }
        )
        if finishReporter {
            reporter.finish()
        }
    }

    private func workloadFileURL(in targetURL: URL, runID: String, role: String, loopIndex: Int) -> URL {
        targetURL.appendingPathComponent("\(workloadFilePrefix)\(runID)-\(role)-loop\(loopIndex)-\(UUID().uuidString).tmp")
    }

    private func openWorkloadFile(at url: URL, size: Int64) throws -> DiskActivityWorkloadOpenFile {
        let path = url.path
        let fd = open(path, O_CREAT | O_EXCL | O_NOFOLLOW | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw BenchmarkError.openFailed(path) }
        fileEventHandler?(url)

        let file = DiskActivityWorkloadOpenFile(url: url, fd: fd, fileManager: fileManager)
        do {
            try AIOFilePreparation.resize(fd, bytes: size)
            _ = fcntl(fd, F_NOCACHE, 1)
            return file
        } catch {
            file.closeAndRemove()
            throw error
        }
    }

    private func flushError(fd: Int32, stage: String) -> BenchmarkError {
        let code = errno
        return .ioFailed("Could not flush \(stage) writes (fd \(fd), errno \(code)): \(String(cString: strerror(code))).")
    }

    private func cleanupWorkloadFiles(in url: URL, runID: String) {
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        // Other app instances may use the same target folder, so cleanup must remain run-scoped.
        let runPrefix = "\(workloadFilePrefix)\(runID)-"
        for file in contents where file.lastPathComponent.hasPrefix(runPrefix) {
            try? fileManager.removeItem(at: file)
        }
    }

    private func progressValue(
        configuration: DiskActivityWorkloadConfiguration,
        phase: DiskActivityWorkloadPhase,
        loopIndex: Int,
        completedBytes: Int64,
        totalBytes: Int64,
        message: String,
        queueStatus: AIOTransferStatus? = nil
    ) -> DiskActivityWorkloadProgress {
        DiskActivityWorkloadProgress(
            operation: configuration.operation,
            phase: queueStatus?.draining == true ? .cleaningUp : phase,
            loopIndex: loopIndex,
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            message: queueStatus?.draining == true ? "Waiting for pending workload I/O to finish" : message,
            queueStatus: queueStatus
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
        private let onReport: (Int64, AIOTransferStatus?) -> Void
        private let lock = NSLock()
        private var completedBytes: Int64 = 0
        private var lastReportNanoseconds = DispatchTime.now().uptimeNanoseconds
        private var queueStatus: AIOTransferStatus?

        init(totalBytes: Int64, minimumIntervalNanoseconds: UInt64 = 250_000_000, onReport: @escaping @Sendable (Int64, AIOTransferStatus?) -> Void) {
            self.totalBytes = max(0, totalBytes)
            self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
            self.onReport = onReport
        }

        func add(_ bytes: Int64) {
            lock.lock()
            defer { lock.unlock() }
            completedBytes = min(totalBytes, max(0, completedBytes + bytes))
            let now = DispatchTime.now().uptimeNanoseconds
            if completedBytes >= totalBytes || now - lastReportNanoseconds >= minimumIntervalNanoseconds {
                lastReportNanoseconds = now
                onReport(completedBytes, queueStatus)
            }
        }

        func set(_ bytes: Int64, force: Bool = false) {
            lock.lock()
            defer { lock.unlock() }
            completedBytes = min(totalBytes, max(0, bytes))
            let now = DispatchTime.now().uptimeNanoseconds
            if force || completedBytes >= totalBytes || now - lastReportNanoseconds >= minimumIntervalNanoseconds {
                lastReportNanoseconds = now
                onReport(completedBytes, queueStatus)
            }
        }

        func update(_ status: AIOTransferStatus) {
            lock.lock()
            defer { lock.unlock() }
            if queueStatus?.draining == true && !status.draining { return }
            let changedPhase = status.draining && queueStatus?.draining != true
            queueStatus = status
            let now = DispatchTime.now().uptimeNanoseconds
            if changedPhase || status.finished || now - lastReportNanoseconds >= minimumIntervalNanoseconds {
                lastReportNanoseconds = now
                onReport(completedBytes, status)
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
