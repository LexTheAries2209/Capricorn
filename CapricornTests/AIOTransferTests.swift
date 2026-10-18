import Darwin
import XCTest
@testable import Capricorn

final class AIOTransferTests: XCTestCase {
    func testSharedBudgetIsFIFOAndNeverExceedsLimit() {
        let budget = AIOBudget(limits: .init(process: 2, system: 90))
        let first = budget.register()
        let second = budget.register()
        let third = budget.register()
        XCTAssertTrue(budget.acquire(first))
        XCTAssertTrue(budget.acquire(first))
        XCTAssertFalse(budget.acquire(second))
        XCTAssertFalse(budget.acquire(third))
        budget.release(first)
        XCTAssertFalse(budget.acquire(first))
        XCTAssertFalse(budget.acquire(third))
        XCTAssertTrue(budget.acquire(second))
        budget.release(first)
        XCTAssertTrue(budget.acquire(third))
        XCTAssertEqual(budget.occupancy, 2)
        budget.release(second)
        budget.release(third)
        budget.unregister(first)
        budget.unregister(second)
        budget.unregister(third)
        XCTAssertEqual(budget.occupancy, 0)
    }

    func testEmptyQueueRetriesTransientErrorsWithoutAdvancingOffset() throws {
        for code in [EAGAIN, ENOMEM, ENOBUFS] {
            let system = SimulatedAIO()
            system.submitErrors = [code, code]
            let budget = makeBudget()
            var offsets: [Int64] = []
            var completed = 0
            try AIOTransfer(budget: budget, system: system).run(
                descriptor: 100, bytes: 8192, blockSize: 4096, depth: 16,
                checkCancelled: {},
                operation: { offset, _ in
                    offsets.append(offset)
                    return .init(offset: offset, write: true)
                },
                fill: { memset($0, 0x69, $1) },
                completed: { count, _ in completed += count }
            )
            XCTAssertEqual(offsets, [0, 4096])
            XCTAssertEqual(completed, 8192)
            XCTAssertEqual(system.returned, 2)
            XCTAssertEqual(budget.occupancy, 0)
        }
    }

    func testPermanentSubmitFailureIsNotRetriedAndDrainsEarlierRequests() {
        let system = SimulatedAIO()
        system.submitErrors = [0, EIO]
        let budget = makeBudget()
        XCTAssertThrowsError(try run(system, budget: budget)) { error in
            let failure = error as? AIOTransferFailure
            XCTAssertEqual(failure?.stage, "submit")
            XCTAssertEqual(failure?.code, EIO)
            XCTAssertEqual(failure?.offset, 4096)
        }
        XCTAssertEqual(system.attempts, 2)
        XCTAssertEqual(system.returned, 1)
        XCTAssertEqual(system.cancelCount, 1)
        XCTAssertTrue(system.bufferValidDuringDrain)
        XCTAssertEqual(budget.occupancy, 0)
    }

    func testNotCancelledRequestsAreDrainedBeforeReuse() throws {
        let system = SimulatedAIO()
        let budget = makeBudget()
        var shouldCancel = false
        XCTAssertThrowsError(try AIOTransfer(budget: budget, system: system).run(
            descriptor: 100, bytes: 32768, blockSize: 4096, depth: 16,
            checkCancelled: { if shouldCancel { throw BenchmarkError.cancelled } },
            operation: { offset, _ in .init(offset: offset, write: true) },
            fill: { memset($0, 0x69, $1) },
            completed: { _, _ in },
            statusChanged: { if $0.active > 0 { shouldCancel = true } }
        ))
        XCTAssertGreaterThan(system.waitsAfterCancel, 0)
        XCTAssertEqual(system.returned, 4)
        XCTAssertEqual(budget.occupancy, 0)
        XCTAssertTrue(system.bufferValidDuringDrain)
        try run(system, budget: budget)
        XCTAssertEqual(system.returned, 12)
        XCTAssertEqual(budget.occupancy, 0)
    }

    func testShortWriteFailsAndDoesNotPublishFullCompletion() {
        let system = SimulatedAIO()
        system.shortResult = true
        let budget = makeBudget()
        var completed = 0
        XCTAssertThrowsError(try run(system, budget: budget, completed: { completed += $0 })) { error in
            XCTAssertEqual((error as? AIOTransferFailure)?.stage, "completion")
        }
        XCTAssertEqual(completed, 0)
        XCTAssertEqual(system.returned, 4)
        XCTAssertEqual(budget.occupancy, 0)
    }

    func testCompletionErrorAndWaitErrorDrainAllRequests() {
        for injectWaitFailure in [true, false] {
            let system = SimulatedAIO()
            system.waitFailure = injectWaitFailure
            system.completionError = injectWaitFailure ? 0 : EIO
            let budget = makeBudget()
            XCTAssertThrowsError(try run(system, budget: budget))
            XCTAssertEqual(system.returned, 4)
            XCTAssertEqual(budget.occupancy, 0)
        }
    }

    func testPersistentResourceErrorHasBoundedTimeout() {
        let system = SimulatedAIO()
        system.alwaysUnavailable = true
        let budget = makeBudget()
        let started = Date()
        XCTAssertThrowsError(try run(system, budget: budget, timeout: 0.02)) { error in
            XCTAssertEqual((error as? AIOTransferFailure)?.code, EAGAIN)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        XCTAssertEqual(system.returned, 0)
        XCTAssertEqual(budget.occupancy, 0)
    }

    func testOccupiedBudgetCanBeCancelledWithNoRequests() {
        let budget = AIOBudget(limits: .init(process: 1, system: 90))
        let owner = budget.register()
        XCTAssertTrue(budget.acquire(owner))
        let system = SimulatedAIO()
        var calls = 0
        XCTAssertThrowsError(try AIOTransfer(budget: budget, system: system).run(
            descriptor: 100, bytes: 4096, blockSize: 4096, depth: 1,
            checkCancelled: {
                calls += 1
                if calls > 5 { throw BenchmarkError.cancelled }
            },
            operation: { offset, _ in .init(offset: offset, write: false) },
            fill: { _, _ in }, completed: { _, _ in }
        ))
        XCTAssertEqual(system.attempts, 0)
        XCTAssertEqual(budget.occupancy, 1)
        budget.release(owner)
        budget.unregister(owner)
        XCTAssertEqual(budget.occupancy, 0)
    }

    func testLimitsUseBothSystemAndProcessCaps() {
        XCTAssertEqual(AIOSystemLimits(process: 16, system: 8).budget, 8)
        XCTAssertEqual(AIOSystemLimits(process: 0, system: 90).budget, 1)
    }

    private func makeBudget() -> AIOBudget { AIOBudget(limits: .init(process: 4, system: 90)) }

    private func run(
        _ system: SimulatedAIO, budget: AIOBudget, timeout: Double = 5,
        completed: (Int) -> Void = { _ in }
    ) throws {
        try AIOTransfer(budget: budget, system: system, retryTimeout: timeout).run(
            descriptor: 100, bytes: 32768, blockSize: 4096, depth: 16,
            checkCancelled: {},
            operation: { offset, _ in .init(offset: offset, write: true) },
            fill: { memset($0, 0x69, $1) },
            completed: { count, _ in completed(count) }
        )
    }
}

private final class SimulatedAIO: AIOSystemCalling, @unchecked Sendable {
    var submitErrors: [Int32] = []
    var completionError: Int32 = 0
    var alwaysUnavailable = false
    var shortResult = false
    var waitFailure = false
    var attempts = 0
    var returned = 0
    var cancelCount = 0
    var waitsAfterCancel = 0
    var bufferValidDuringDrain = true
    private var remaining: [UInt: Int] = [:]

    func submit(_ control: UnsafeMutablePointer<aiocb>, write: Bool) -> AIOCallResult {
        attempts += 1
        let error = alwaysUnavailable ? EAGAIN : (submitErrors.isEmpty ? 0 : submitErrors.removeFirst())
        if error == 0 { remaining[UInt(bitPattern: control)] = 2 }
        return .init(value: error == 0 ? 0 : -1, error: error)
    }
    func status(_ control: UnsafeMutablePointer<aiocb>) -> Int32 {
        (remaining[UInt(bitPattern: control)] ?? 0) > 0 ? EINPROGRESS : completionError
    }
    func result(_ control: UnsafeMutablePointer<aiocb>) -> AIOCallResult {
        let key = UInt(bitPattern: control)
        precondition(remaining[key] == 0, "Premature or duplicate result retrieval")
        remaining.removeValue(forKey: key)
        returned += 1
        return .init(value: completionError != 0 ? -1 : (shortResult ? 1 : Int(control.pointee.aio_nbytes)), error: completionError)
    }
    func wait(_ controls: [UnsafeMutablePointer<aiocb>]) -> AIOCallResult {
        precondition(!controls.isEmpty)
        if cancelCount > 0 { waitsAfterCancel += 1 }
        for control in controls {
            if control.pointee.aio_buf!.load(as: UInt8.self) != 0x69 { bufferValidDuringDrain = false }
            let key = UInt(bitPattern: control)
            remaining[key] = max(0, (remaining[key] ?? 0) - 1)
        }
        if waitFailure {
            waitFailure = false
            return .init(value: -1, error: EIO)
        }
        return .init(value: 0, error: 0)
    }
    func cancel(_ descriptor: Int32) -> AIOCallResult {
        cancelCount += 1
        return .init(value: Int(AIO_NOTCANCELED), error: 0)
    }
}
