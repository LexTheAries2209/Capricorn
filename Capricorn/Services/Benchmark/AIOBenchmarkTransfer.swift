import Darwin
import Foundation

final class AIOBenchmarkTransfer: Sendable {
    private struct State {
        var failure: Error?
        var statuses: [AIOTransferStatus?]
        var peakActive = 0
    }

    private let transfer: AIOTransfer

    init(transfer: AIOTransfer) {
        self.transfer = transfer
    }

    func run(
        descriptor: Int32,
        test: BenchmarkTest,
        checkCancelled: @escaping @Sendable () throws -> Void,
        fill: @escaping @Sendable (UnsafeMutableRawPointer, Int) -> Void,
        completed: @escaping @Sendable (Int, Double) -> Void,
        statusChanged: @escaping @Sendable (AIOTransferStatus) -> Void
    ) throws {
        guard test.queueDepth > 0, test.threads > 0,
              test.threads <= 16, test.queueDepth <= 16 / test.threads else {
            throw BenchmarkError.ioFailed("Benchmark queue depth × thread count must not exceed 16.")
        }
        let state = LockedState(State(statuses: Array(repeating: nil, count: test.threads)))
        let gate = NSCondition()
        let ready = LockedState(0)
        let workers = DispatchGroup()
        let blockSize = max(512, test.blockSizeBytes)
        let blockCount = test.testSizeBytes / Int64(blockSize) + (test.testSizeBytes % Int64(blockSize) == 0 ? 0 : 1)

        for workerIndex in 0..<test.threads {
            workers.enter()
            let worker = Thread { [transfer] in
                defer { workers.leave() }
                let workerDescriptor = dup(descriptor)
                let descriptorError = errno
                defer { if workerDescriptor >= 0 { close(workerDescriptor) } }
                gate.lock()
                let count = ready.withLock { value in
                    value += 1
                    return value
                }
                if count == test.threads { gate.broadcast() }
                while ready.snapshot() < test.threads { gate.wait() }
                gate.unlock()

                do {
                    try checkCancelled()
                    guard workerDescriptor >= 0 else {
                        throw BenchmarkError.ioFailed("Could not duplicate benchmark file descriptor (errno \(descriptorError)).")
                    }
                    let startBlock = blockCount * Int64(workerIndex) / Int64(test.threads)
                    let endBlock = blockCount * Int64(workerIndex + 1) / Int64(test.threads)
                    let startOffset = min(test.testSizeBytes, startBlock * Int64(blockSize))
                    let endOffset = min(test.testSizeBytes, endBlock * Int64(blockSize))
                    let workerBytes = endOffset - startOffset
                    try transfer.run(
                        descriptor: workerDescriptor, bytes: workerBytes, blockSize: blockSize,
                        depth: test.queueDepth,
                        checkCancelled: {
                            try checkCancelled()
                            if let failure = state.withLock({ $0.failure }) { throw failure }
                        },
                        operation: { offset, count in
                            let position: Int64
                            if test.accessPattern == .sequential {
                                position = startOffset + offset
                            } else {
                                let lastBlock = max(0, workerBytes - Int64(count)) / Int64(blockSize)
                                position = startOffset + Int64.random(in: 0...lastBlock) * Int64(blockSize)
                            }
                            let write = test.operation == .write
                                || (test.operation == .mixed && Int.random(in: 0..<100) < test.writePercentForMixed)
                            return AIOTransferOperation(offset: position, write: write)
                        },
                        fill: fill, completed: completed,
                        statusChanged: { status in
                            state.withLock { value in
                                value.statuses[workerIndex] = status
                                let statuses = value.statuses.compactMap { $0 }
                                let occupancy = transfer.budget.occupancy
                                let active = min(occupancy, statuses.reduce(0) { $0 + $1.active })
                                value.peakActive = max(value.peakActive, active)
                                statusChanged(AIOTransferStatus(
                                    targetDepth: test.queueDepth * test.threads,
                                    active: active, peakActive: value.peakActive,
                                    processUsed: occupancy, processLimit: transfer.budget.limits.process,
                                    systemLimit: transfer.budget.limits.system,
                                    retries: statuses.reduce(0) { $0 + $1.retries },
                                    waitMilliseconds: statuses.reduce(0) { $0 + $1.waitMilliseconds },
                                    draining: statuses.contains { $0.draining && !$0.finished },
                                    cancelResult: statuses.compactMap(\.cancelResult).last,
                                    finished: statuses.count == test.threads && statuses.allSatisfy(\.finished)
                                ))
                            }
                        }
                    )
                } catch {
                    state.withLock { if $0.failure == nil { $0.failure = error } }
                }
            }
            worker.name = "Capricorn.AIO.worker.\(workerIndex)"
            worker.start()
        }
        workers.wait()
        if let failure = state.withLock({ $0.failure }) { throw failure }
    }
}
