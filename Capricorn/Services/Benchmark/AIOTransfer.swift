import Darwin
import Foundation

struct AIOSystemLimits: Equatable, Sendable {
    let process: Int
    let system: Int
    var budget: Int { max(1, min(process, system)) }

    static func current() -> AIOSystemLimits {
        func read(_ name: String) -> Int {
            var value: Int32 = 0
            var length = MemoryLayout<Int32>.size
            return sysctlbyname(name, &value, &length, nil, 0) == 0 ? max(1, Int(value)) : 1
        }
        return AIOSystemLimits(process: read("kern.aioprocmax"), system: read("kern.aiomax"))
    }
}

final class AIOBudget: @unchecked Sendable {
    static let shared = AIOBudget(limits: .current())
    let limits: AIOSystemLimits
    private let condition = NSCondition()
    private var owners: [UUID: Int] = [:]
    private var waiting: [UUID] = []
    private var used = 0

    init(limits: AIOSystemLimits) { self.limits = limits }

    var occupancy: Int {
        condition.lock()
        defer { condition.unlock() }
        return used
    }

    func register() -> UUID {
        condition.lock()
        defer { condition.unlock() }
        let client = UUID()
        owners[client] = 0
        return client
    }

    func acquire(_ client: UUID) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        precondition(owners[client] != nil)
        if !waiting.contains(client) { waiting.append(client) }
        guard used < limits.budget, waiting.first == client else { return false }
        waiting.removeFirst()
        owners[client, default: 0] += 1
        used += 1
        return true
    }

    func release(_ client: UUID) {
        condition.lock()
        defer { condition.unlock() }
        precondition((owners[client] ?? 0) > 0)
        owners[client, default: 0] -= 1
        used -= 1
        condition.broadcast()
    }

    func unregister(_ client: UUID) {
        condition.lock()
        defer { condition.unlock() }
        precondition(owners[client] == 0)
        owners.removeValue(forKey: client)
        waiting.removeAll { $0 == client }
        condition.broadcast()
    }

    func withdraw(_ client: UUID) {
        condition.lock()
        waiting.removeAll { $0 == client }
        condition.broadcast()
        condition.unlock()
    }

    func wait(_ seconds: Double) {
        condition.lock()
        _ = condition.wait(until: Date(timeIntervalSinceNow: seconds))
        condition.unlock()
    }
}

struct AIOCallResult {
    let value: Int
    let error: Int32
}

protocol AIOSystemCalling: Sendable {
    func submit(_ control: UnsafeMutablePointer<aiocb>, write: Bool) -> AIOCallResult
    func status(_ control: UnsafeMutablePointer<aiocb>) -> Int32
    func result(_ control: UnsafeMutablePointer<aiocb>) -> AIOCallResult
    func wait(_ controls: [UnsafeMutablePointer<aiocb>]) -> AIOCallResult
    func cancel(_ descriptor: Int32) -> AIOCallResult
}

struct DarwinAIOSystem: AIOSystemCalling {
    func submit(_ control: UnsafeMutablePointer<aiocb>, write: Bool) -> AIOCallResult {
        let value = write ? aio_write(control) : aio_read(control)
        return AIOCallResult(value: Int(value), error: value == 0 ? 0 : errno)
    }
    func status(_ control: UnsafeMutablePointer<aiocb>) -> Int32 { aio_error(control) }
    func result(_ control: UnsafeMutablePointer<aiocb>) -> AIOCallResult {
        let value = aio_return(control)
        return AIOCallResult(value: value, error: value < 0 ? errno : 0)
    }
    func wait(_ controls: [UnsafeMutablePointer<aiocb>]) -> AIOCallResult {
        guard !controls.isEmpty else { return AIOCallResult(value: 0, error: 0) }
        let pointers = controls.map { Optional(UnsafePointer($0)) }
        var timeout = timespec(tv_sec: 0, tv_nsec: 50_000_000)
        let value = pointers.withUnsafeBufferPointer { aio_suspend($0.baseAddress, Int32($0.count), &timeout) }
        return AIOCallResult(value: Int(value), error: value == 0 ? 0 : errno)
    }
    func cancel(_ descriptor: Int32) -> AIOCallResult {
        let value = aio_cancel(descriptor, nil)
        return AIOCallResult(value: Int(value), error: value < 0 ? errno : 0)
    }
}

struct AIOTransferStatus: Equatable, Sendable {
    var targetDepth: Int
    var active: Int
    var peakActive: Int
    var processUsed: Int
    var processLimit: Int
    var systemLimit: Int
    var retries: Int
    var waitMilliseconds: Int
    var draining = false
    var cancelResult: Int?
    var finished = false

    var detail: String {
        "target Q\(targetDepth), active \(active), peak \(peakActive), process \(processUsed)/\(processLimit), system limit \(systemLimit), retries \(retries), wait \(waitMilliseconds) ms, draining \(draining), cancel \(cancelResult.map(String.init) ?? "none")"
    }
}

struct AIOTransferFailure: Error, LocalizedError {
    let stage: String
    let operation: String
    let offset: Int64
    let code: Int32
    let status: AIOTransferStatus
    let file: String

    var errorDescription: String? {
        "Async \(operation) \(stage) failed at offset \(offset): \(String(cString: strerror(code))) (errno \(code); \(status.detail); file \(file))."
    }
}

struct AIOTransferOperation {
    let offset: Int64
    let write: Bool
}

final class AIOTransfer: @unchecked Sendable {
    private final class Request {
        let control: UnsafeMutablePointer<aiocb>
        let buffer: UnsafeMutableRawPointer
        let count: Int
        let operation: AIOTransferOperation
        let submittedAt = DispatchTime.now().uptimeNanoseconds

        init(descriptor: Int32, count: Int, operation: AIOTransferOperation, fill: (UnsafeMutableRawPointer, Int) -> Void) {
            self.count = count
            self.operation = operation
            buffer = .allocate(byteCount: count, alignment: 4096)
            if operation.write { fill(buffer, count) }
            control = .allocate(capacity: 1)
            control.initialize(to: aiocb())
            control.pointee.aio_fildes = descriptor
            control.pointee.aio_offset = off_t(operation.offset)
            control.pointee.aio_buf = buffer
            control.pointee.aio_nbytes = count
            control.pointee.aio_sigevent.sigev_notify = SIGEV_NONE
        }

        deinit {
            control.deinitialize(count: 1)
            control.deallocate()
            buffer.deallocate()
        }
    }

    let budget: AIOBudget
    private let system: any AIOSystemCalling
    private let retryTimeout: Double

    init(budget: AIOBudget = .shared, system: any AIOSystemCalling = DarwinAIOSystem(), retryTimeout: Double = 5) {
        self.budget = budget
        self.system = system
        self.retryTimeout = retryTimeout
    }

    func run(
        descriptor: Int32,
        bytes: Int64,
        blockSize: Int,
        depth: Int,
        checkCancelled: () throws -> Void,
        operation: (Int64, Int) -> AIOTransferOperation,
        fill: (UnsafeMutableRawPointer, Int) -> Void,
        completed: (Int, Double) -> Void,
        statusChanged: (AIOTransferStatus) -> Void = { _ in }
    ) throws {
        let client = budget.register()
        var active: [Request] = []
        var assigned: Int64 = 0
        var pending: AIOTransferOperation?
        var retryStarted: TimeInterval?
        var retries = 0
        var waitMilliseconds = 0
        var peak = 0
        var draining = false
        var cancelResult: Int?
        var firstFailure: Error?
        var finished = false
        let target = max(1, depth)

        func status() -> AIOTransferStatus {
            AIOTransferStatus(
                targetDepth: target, active: active.count, peakActive: peak,
                processUsed: budget.occupancy, processLimit: budget.limits.process,
                systemLimit: budget.limits.system, retries: retries,
                waitMilliseconds: waitMilliseconds, draining: draining, cancelResult: cancelResult, finished: finished
            )
        }

        func failure(_ stage: String, _ request: AIOTransferOperation, _ code: Int32) -> Error {
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let hasPath = fcntl(descriptor, F_GETPATH, &path) == 0
            let name = hasPath ? String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : "fd \(descriptor)"
            return AIOTransferFailure(stage: stage, operation: request.write ? "write" : "read", offset: request.offset, code: code, status: status(), file: name)
        }

        func reap() {
            var remaining: [Request] = []
            for request in active {
                let error = system.status(request.control)
                if error == EINPROGRESS {
                    remaining.append(request)
                    continue
                }
                let returned = system.result(request.control)
                // A slot and its buffers remain owned until the terminal result is collected.
                budget.release(client)
                if !draining {
                    if error != 0 || returned.value != request.count {
                        if firstFailure == nil {
                            firstFailure = failure("completion", request.operation, error != 0 ? error : (returned.error != 0 ? returned.error : EIO))
                        }
                    } else {
                        completed(returned.value, Double(DispatchTime.now().uptimeNanoseconds - request.submittedAt) / 1000)
                    }
                }
            }
            active = remaining
            statusChanged(status())
        }

        defer {
            budget.withdraw(client)
            if !active.isEmpty {
                draining = true
                cancelResult = system.cancel(descriptor).value
                statusChanged(status())
                // Cancellation may leave running requests. Never free their storage on a timeout.
                while !active.isEmpty {
                    _ = system.wait(active.map(\.control))
                    reap()
                    if !active.isEmpty { Thread.sleep(forTimeInterval: 0.001) }
                }
            }
            budget.unregister(client)
            finished = true
            statusChanged(status())
        }

        statusChanged(status())
        while assigned < bytes || !active.isEmpty {
            try checkCancelled()
            reap()
            if let firstFailure { throw firstFailure }
            while assigned < bytes && active.count < min(target, budget.limits.budget) {
                try checkCancelled()
                let count = min(max(1, blockSize), Int(bytes - assigned))
                if pending == nil { pending = operation(assigned, count) }
                guard budget.acquire(client) else { break }
                let request = Request(descriptor: descriptor, count: count, operation: pending!, fill: fill)
                let result = system.submit(request.control, write: request.operation.write)
                if result.value != 0 {
                    budget.release(client)
                    guard [EAGAIN, ENOMEM, ENOBUFS].contains(result.error) else {
                        throw failure("submit", request.operation, result.error)
                    }
                    retries += 1
                    if retryStarted == nil { retryStarted = ProcessInfo.processInfo.systemUptime }
                    if ProcessInfo.processInfo.systemUptime - retryStarted! >= retryTimeout {
                        throw failure("submit timeout", request.operation, result.error)
                    }
                    break
                }
                retryStarted = nil
                pending = nil
                active.append(request)
                peak = max(peak, active.count)
                assigned += Int64(count)
            }
            statusChanged(status())
            if !active.isEmpty {
                let started = ProcessInfo.processInfo.systemUptime
                let result = system.wait(active.map(\.control))
                waitMilliseconds += Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                if result.value != 0 && ![EAGAIN, EINTR].contains(result.error) {
                    throw failure("wait", active[0].operation, result.error)
                }
            } else if assigned < bytes {
                if retryStarted == nil { retryStarted = ProcessInfo.processInfo.systemUptime }
                if ProcessInfo.processInfo.systemUptime - retryStarted! >= retryTimeout {
                    throw failure("budget timeout", pending!, EAGAIN)
                }
                let delay = min(0.1, 0.001 * pow(2, Double(min(retries, 7))))
                let started = ProcessInfo.processInfo.systemUptime
                budget.wait(delay)
                waitMilliseconds += Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                try checkCancelled()
            }
        }
    }
}

enum AIOFilePreparation {
    static func resize(_ descriptor: Int32, bytes: Int64) throws {
        guard ftruncate(descriptor, off_t(bytes)) == 0 else {
            let code = errno
            throw BenchmarkError.ioFailed("Could not size workload file to \(bytes) bytes: \(String(cString: strerror(code))) (errno \(code)).")
        }
    }
}
