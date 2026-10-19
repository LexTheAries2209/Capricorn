import Darwin
import Foundation

// Standalone acceptance uses the production AIO and worker sources; only app model dependencies are stubbed.
enum BenchmarkError: Error {
    case ioFailed(String)
}

enum BenchmarkConcurrency {
    static let maximumRequests = 16
}

enum BenchmarkAccessPattern: Sendable {
    case sequential
    case random
}

enum BenchmarkOperation: Sendable {
    case read
    case write
    case mixed
}

struct BenchmarkTest: Sendable {
    var queueDepth: Int
    var threads: Int
    var blockSizeBytes: Int
    var testSizeBytes: Int64
    var accessPattern = BenchmarkAccessPattern.sequential
    var operation = BenchmarkOperation.write
    var writePercentForMixed = 100
}

final class ObservedAIO: AIOSystemCalling, @unchecked Sendable {
    struct State {
        var active: [UInt: String] = [:]
        var threadIDs: Set<UInt64> = []
        var peakByWorker: [String: Int] = [:]
        var peakTotal = 0
        var returned = 0
    }

    let state = LockedState(State())
    private let native = DarwinAIOSystem()

    func submit(_ control: UnsafeMutablePointer<aiocb>, write: Bool) -> AIOCallResult {
        state.withLock { value in
            let result = native.submit(control, write: write)
            if result.value == 0 {
                let worker = Thread.current.name ?? "unknown"
                var threadID: UInt64 = 0
                pthread_threadid_np(nil, &threadID)
                value.threadIDs.insert(threadID)
                value.active[UInt(bitPattern: control)] = worker
                value.peakByWorker[worker] = max(
                    value.peakByWorker[worker] ?? 0, value.active.values.filter { $0 == worker }.count
                )
                value.peakTotal = max(value.peakTotal, value.active.count)
            }
            return result
        }
    }

    func status(_ control: UnsafeMutablePointer<aiocb>) -> Int32 { native.status(control) }

    func result(_ control: UnsafeMutablePointer<aiocb>) -> AIOCallResult {
        state.withLock { value in
            let result = native.result(control)
            value.active.removeValue(forKey: UInt(bitPattern: control))
            value.returned += 1
            return result
        }
    }

    func wait(_ controls: [UnsafeMutablePointer<aiocb>]) -> AIOCallResult { native.wait(controls) }
    func cancel(_ descriptor: Int32) -> AIOCallResult { native.cancel(descriptor) }
}

@main
enum RealThreadAcceptance {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw BenchmarkError.ioFailed("Supply a new owned acceptance directory") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard root.path.hasPrefix("/Volumes/40G4T_NTFS_E/Capricorn-RealThreads-"),
              mkdir(root.path, 0o700) == 0 else {
            throw BenchmarkError.ioFailed("Refused existing or unexpected acceptance directory")
        }
        let marker: [String: Any] = [
            "purpose": "Capricorn real-thread acceptance", "root": root.path,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "cleanup": "All files are newly created test data and intentionally retained."
        ]
        try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("CAPRICORN_TEST_ARTIFACTS.json"), options: .withoutOverwriting)
        try Data("Capricorn real-thread acceptance\n".utf8)
            .write(to: root.appendingPathComponent("CAPRICORN_TEST_ARTIFACTS.txt"), options: .withoutOverwriting)
        let budget = AIOBudget(limits: .current())
        var results: [[String: Any]] = []
        for cached in [true, false] {
            for (depth, threads) in [(16, 1), (8, 2), (4, 4), (2, 8), (1, 16)] {
                let name = "owned-Q\(depth)T\(threads)-cache\(cached).bin"
                let descriptor = open(root.appendingPathComponent(name).path, O_CREAT | O_EXCL | O_NOFOLLOW | O_RDWR, 0o600)
                guard descriptor >= 0 else { throw BenchmarkError.ioFailed("Cannot create \(name)") }
                defer { close(descriptor) }
                let bytes: Int64 = 8 * 1024 * 1024 + 137
                try AIOFilePreparation.resize(descriptor, bytes: bytes)
                guard fcntl(descriptor, F_NOCACHE, cached ? 0 : 1) == 0 else {
                    throw BenchmarkError.ioFailed("Cannot configure cache mode")
                }
                let system = ObservedAIO()
                let completed = LockedState<Int64>(0)
                let finalStatus = LockedState<AIOTransferStatus?>(nil)
                let started = Date()
                try AIOBenchmarkTransfer(transfer: AIOTransfer(budget: budget, system: system)).run(
                    descriptor: descriptor,
                    test: BenchmarkTest(queueDepth: depth, threads: threads, blockSizeBytes: 65536, testSizeBytes: bytes),
                    checkCancelled: {}, fill: { memset($0, 0xa7, $1) },
                    completed: { count, _ in completed.withLock { $0 += Int64(count) } },
                    statusChanged: { status in finalStatus.withLock { $0 = status } }
                )
                guard fsync(descriptor) == 0 else { throw BenchmarkError.ioFailed("Cannot flush \(name)") }
                let reader = open(root.appendingPathComponent(name).path, O_RDONLY | O_NOFOLLOW)
                guard reader >= 0 else { throw BenchmarkError.ioFailed("Cannot reopen \(name)") }
                defer { close(reader) }
                var data = [UInt8](repeating: 0, count: Int(bytes))
                let readCount = data.withUnsafeMutableBytes { pread(reader, $0.baseAddress, $0.count, 0) }
                let observed = system.state.snapshot()
                guard readCount == Int(bytes), data.allSatisfy({ $0 == 0xa7 }),
                      completed.snapshot() == bytes, observed.threadIDs.count == threads,
                      observed.peakByWorker.values.allSatisfy({ $0 <= depth }),
                      observed.peakTotal <= 16, observed.active.isEmpty, budget.occupancy == 0,
                      finalStatus.snapshot()?.finished == true else {
                    throw BenchmarkError.ioFailed("Acceptance failed: \(name)")
                }
                let record: [String: Any] = [
                    "file": name, "bytes": bytes, "q": depth, "t": threads, "cached": cached,
                    "observedThreads": observed.threadIDs.count, "peakOutstanding": observed.peakTotal,
                    "peakByWorker": observed.peakByWorker, "returned": observed.returned,
                    "budgetAfter": budget.occupancy, "nonzeroReadback": true,
                    "seconds": Date().timeIntervalSince(started)
                ]
                results.append(record)
                print("PASS \(name): \(observed.threadIDs.count) threads, peak \(observed.peakTotal), retained")
            }
        }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("verification.json"), options: .withoutOverwriting)
        print("All \(results.count) cases passed; retained artifacts: \(root.path)")
    }
}
