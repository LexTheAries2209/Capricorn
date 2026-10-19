import Darwin
import XCTest
@testable import Capricorn

final class AIOBenchmarkTransferTests: XCTestCase {
    func testRealThreadsHaveIndependentQueuesAndDisjointSequentialRanges() throws {
        for (depth, threads) in [(16, 1), (8, 2), (4, 4), (2, 8), (1, 16)] {
            let system = RecordingBenchmarkAIO()
            let budget = AIOBudget(limits: .init(process: 16, system: 90))
            let bytes = Int64(4096 * 128 + 137)
            let completed = LockedState<Int64>(0)
            let statuses = LockedState<[AIOTransferStatus]>([])
            try withDescriptor { descriptor in
                try AIOBenchmarkTransfer(transfer: AIOTransfer(budget: budget, system: system)).run(
                    descriptor: descriptor, test: test(depth: depth, threads: threads, bytes: bytes),
                    checkCancelled: {}, fill: { memset($0, 0x69, $1) },
                    completed: { count, _ in completed.withLock { $0 += Int64(count) } },
                    statusChanged: { status in statuses.withLock { $0.append(status) } }
                )
            }
            let snapshot = system.state.snapshot()
            XCTAssertEqual(snapshot.threadIDs.count, threads)
            XCTAssertEqual(snapshot.descriptors.count, threads)
            XCTAssertTrue(snapshot.peaks.values.allSatisfy { $0 == depth })
            XCTAssertLessThanOrEqual(snapshot.peakTotal, 16)
            XCTAssertEqual(completed.snapshot(), bytes)
            XCTAssertEqual(budget.occupancy, 0)
            XCTAssertTrue(snapshot.active.isEmpty)
            XCTAssertEqual(snapshot.returned, snapshot.requests.count)
            var nextOffset: Int64 = 0
            for request in snapshot.requests.sorted(by: { $0.offset < $1.offset }) {
                XCTAssertEqual(request.offset, nextOffset)
                nextOffset += Int64(request.count)
            }
            XCTAssertEqual(nextOffset, bytes)
            XCTAssertEqual(statuses.snapshot().last?.finished, true)
            XCTAssertEqual(statuses.snapshot().last?.active, 0)
            XCTAssertEqual(statuses.snapshot().last?.targetDepth, 16)
        }
    }

    func testFailureAndCancellationDrainEveryWorkerAndAllowReuse() throws {
        for injectFailure in [true, false] {
            let system = RecordingBenchmarkAIO()
            system.failWorker = injectFailure ? "Capricorn.AIO.worker.0" : nil
            let budget = AIOBudget(limits: .init(process: 4, system: 90))
            let cancelled = LockedState(false)
            let transfer = AIOBenchmarkTransfer(transfer: AIOTransfer(budget: budget, system: system))
            try withDescriptor { descriptor in
                XCTAssertThrowsError(try transfer.run(
                    descriptor: descriptor, test: test(depth: 4, threads: 4, bytes: 4096 * 128),
                    checkCancelled: { if cancelled.snapshot() { throw BenchmarkError.cancelled } },
                    fill: { memset($0, 0x69, $1) },
                    completed: { _, _ in if !injectFailure { cancelled.withLock { $0 = true } } },
                    statusChanged: { _ in }
                ))
                XCTAssertEqual(budget.occupancy, 0)
                XCTAssertTrue(system.state.snapshot().active.isEmpty)
                XCTAssertTrue(system.state.snapshot().validBuffers)
                system.failWorker = nil
                try transfer.run(
                    descriptor: descriptor, test: test(depth: 2, threads: 2, bytes: 4096 * 32),
                    checkCancelled: {}, fill: { memset($0, 0x69, $1) },
                    completed: { _, _ in }, statusChanged: { _ in }
                )
            }
            XCTAssertEqual(budget.occupancy, 0)
            XCTAssertTrue(system.state.snapshot().active.isEmpty)
        }
    }

    func testRejectsExcessiveConcurrencyBeforeStartingWorkers() throws {
        let system = RecordingBenchmarkAIO()
        try withDescriptor { descriptor in
            XCTAssertThrowsError(try AIOBenchmarkTransfer(transfer: AIOTransfer(system: system)).run(
                descriptor: descriptor, test: test(depth: 16, threads: 2, bytes: 4096 * 32),
                checkCancelled: {}, fill: { _, _ in }, completed: { _, _ in }, statusChanged: { _ in }
            ))
        }
        XCTAssertTrue(system.state.snapshot().requests.isEmpty)
    }

    func testNativeMultithreadedWritePreservesNonzeroData() throws {
        let budget = AIOBudget(limits: .current())
        try withDescriptor { descriptor in
            let bytes: Int64 = 4096 * 128 + 137
            try AIOFilePreparation.resize(descriptor, bytes: bytes)
            try AIOBenchmarkTransfer(transfer: AIOTransfer(budget: budget)).run(
                descriptor: descriptor, test: test(depth: 4, threads: 4, bytes: bytes),
                checkCancelled: {}, fill: { memset($0, 0x69, $1) },
                completed: { _, _ in }, statusChanged: { _ in }
            )
            XCTAssertEqual(fsync(descriptor), 0)
            var data = [UInt8](repeating: 0, count: Int(bytes))
            let readCount = data.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, $0.count, 0) }
            XCTAssertEqual(readCount, Int(bytes))
            XCTAssertTrue(data.allSatisfy { $0 == 0x69 })
        }
        XCTAssertEqual(budget.occupancy, 0)
    }

    private func test(depth: Int, threads: Int, bytes: Int64) -> BenchmarkTest {
        BenchmarkTest(
            id: "real-threads", label: "SEQ Q\(depth)T\(threads)", accessPattern: .sequential,
            operation: .write, blockSizeBytes: 4096, queueDepth: depth, threads: threads,
            durationSeconds: 0, testSizeBytes: bytes, dataPattern: .zeroFill, writePercentForMixed: 100
        )
    }

    private func withDescriptor(_ body: (Int32) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Capricorn-RealThreads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("Capricorn real-thread acceptance data; retained for later cleanup.\n".utf8)
            .write(to: root.appendingPathComponent("CAPRICORN_TEST_ARTIFACTS.txt"), options: .withoutOverwriting)
        let descriptor = open(root.appendingPathComponent("owned-data.bin").path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw BenchmarkError.ioFailed("Cannot create owned test file") }
        defer { close(descriptor) }
        try body(descriptor)
    }
}

private final class RecordingBenchmarkAIO: AIOSystemCalling, @unchecked Sendable {
    struct Request {
        let offset: Int64
        let count: Int
    }

    struct Active {
        let descriptor: Int32
        let worker: String
        var finished = false
    }

    struct State {
        var active: [UInt: Active] = [:]
        var requests: [Request] = []
        var threadIDs: Set<UInt64> = []
        var descriptors: Set<Int32> = []
        var peaks: [String: Int] = [:]
        var peakTotal = 0
        var returned = 0
        var validBuffers = true
    }

    let state = LockedState(State())
    var failWorker: String?

    func submit(_ control: UnsafeMutablePointer<aiocb>, write: Bool) -> AIOCallResult {
        let worker = Thread.current.name ?? ""
        var threadID: UInt64 = 0
        pthread_threadid_np(nil, &threadID)
        return state.withLock { value in
            if worker == failWorker { return .init(value: -1, error: EIO) }
            value.threadIDs.insert(threadID)
            value.descriptors.insert(control.pointee.aio_fildes)
            value.active[UInt(bitPattern: control)] = Active(descriptor: control.pointee.aio_fildes, worker: worker)
            value.requests.append(Request(offset: Int64(control.pointee.aio_offset), count: Int(control.pointee.aio_nbytes)))
            value.peaks[worker] = max(value.peaks[worker] ?? 0, value.active.values.filter { $0.worker == worker }.count)
            value.peakTotal = max(value.peakTotal, value.active.count)
            return .init(value: 0, error: 0)
        }
    }

    func status(_ control: UnsafeMutablePointer<aiocb>) -> Int32 {
        state.withLock { $0.active[UInt(bitPattern: control)]?.finished == true ? 0 : EINPROGRESS }
    }

    func result(_ control: UnsafeMutablePointer<aiocb>) -> AIOCallResult {
        state.withLock {
            let active = $0.active.removeValue(forKey: UInt(bitPattern: control))
            if active?.finished != true { $0.validBuffers = false }
            $0.returned += 1
        }
        return .init(value: Int(control.pointee.aio_nbytes), error: 0)
    }

    func wait(_ controls: [UnsafeMutablePointer<aiocb>]) -> AIOCallResult {
        state.withLock { value in
            for control in controls {
                if control.pointee.aio_buf?.load(as: UInt8.self) != 0x69 { value.validBuffers = false }
                value.active[UInt(bitPattern: control)]?.finished = true
            }
        }
        return .init(value: 0, error: 0)
    }

    func cancel(_ descriptor: Int32) -> AIOCallResult {
        .init(value: Int(AIO_NOTCANCELED), error: 0)
    }
}
