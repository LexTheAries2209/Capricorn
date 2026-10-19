import Darwin
import XCTest
@testable import Capricorn

final class AIOAcceptanceTests: XCTestCase {
    private var externalRoot: URL? {
        ProcessInfo.processInfo.environment["CAPRICORN_AIO_TEST_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func folder(_ label: String) throws -> URL {
        let parent: URL
        if let root = externalRoot {
            let marker = root.appendingPathComponent("CAPRICORN_TEST_ARTIFACTS.json")
            let data = try Data(contentsOf: marker)
            let properties = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(properties["purpose"] as? String, "Capricorn AIO P0-P1 acceptance")
            guard root.path.hasPrefix("/Volumes/40G4T_NTFS_E/Capricorn-AIO-P0P1-"),
                  properties["root"] as? String == root.path else {
                throw BenchmarkError.ioFailed("Unmarked acceptance target")
            }
            parent = root
        } else {
            parent = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        }
        let root = parent.appendingPathComponent("Capricorn-AIO-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let marker = ["purpose": "Capricorn AIO P0-P1 acceptance", "root": root.path]
        try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("CAPRICORN_TEST_ARTIFACTS.json"), options: .withoutOverwriting)
        return root
    }

    func testPresizedNonzeroPatternsAtAllQueueDepthsAndCacheModes() throws {
        let root = try folder("patterns")
        let budget = AIOBudget(limits: .current())
        let blockSize = externalRoot == nil ? 4096 : 4 * 1024 * 1024
        let bytes = Int64(blockSize * 32)
        for cached in [false, true] {
            for depth in [1, 2, 4, 8, 16] {
                for iteration in 1...3 {
                    let url = root.appendingPathComponent("owned-q\(depth)-cache\(cached)-\(iteration).bin")
                    let descriptor = open(url.path, O_CREAT | O_EXCL | O_NOFOLLOW | O_RDWR, 0o600)
                    XCTAssertGreaterThanOrEqual(descriptor, 0)
                    guard descriptor >= 0 else { return }
                    defer { close(descriptor) }
                    try AIOFilePreparation.resize(descriptor, bytes: bytes)
                    XCTAssertEqual(fcntl(descriptor, F_NOCACHE, cached ? 0 : 1), 0)
                    var currentOffset: Int64 = 0
                    var completed = 0
                    try AIOTransfer(budget: budget).run(
                        descriptor: descriptor, bytes: bytes, blockSize: blockSize, depth: depth,
                        checkCancelled: {},
                        operation: { offset, _ in
                            currentOffset = offset
                            return .init(offset: offset, write: true)
                        },
                        fill: { buffer, count in
                            memset(buffer, Int32((currentOffset / Int64(blockSize) * 37 + 11) % 251 + 1), count)
                        },
                        completed: { count, _ in completed += count }
                    )
                    XCTAssertEqual(completed, Int(bytes))
                    XCTAssertEqual(fsync(descriptor), 0)
                    let reader = open(url.path, O_RDONLY | O_NOFOLLOW)
                    guard reader >= 0 else { XCTFail("Cannot reopen test file"); return }
                    defer { close(reader) }
                    var buffer = [UInt8](repeating: 0, count: blockSize)
                    for index in 0..<32 {
                        let readCount = buffer.withUnsafeMutableBytes {
                            pread(reader, $0.baseAddress, blockSize, off_t(index * blockSize))
                        }
                        XCTAssertEqual(readCount, blockSize)
                        let expected = UInt8((index * 37 + 11) % 251 + 1)
                        XCTAssertTrue(buffer.allSatisfy { $0 == expected }, "\(url.lastPathComponent) block \(index)")
                    }
                    XCTAssertEqual(budget.occupancy, 0)
                }
            }
        }
    }

    func testMixedServiceRepeatsWithoutStaleProgressOrSlots() async throws {
        let root = try folder("mixed")
        let budget = AIOBudget(limits: .current())
        for index in 0..<8 {
            let caseRoot = root.appendingPathComponent("case-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: caseRoot, withIntermediateDirectories: false)
            let manager = try AIOPreservingFileManager(root: caseRoot)
            let updates = LockedState<[DiskActivityWorkloadProgress]>([])
            let runner = NativeDiskActivityWorkloadRunner(
                fileManager: manager, temporaryRunLeaseDirectoryURL: caseRoot.appendingPathComponent("leases"),
                transfer: AIOTransfer(budget: budget)
            )
            let bytes: Int64 = externalRoot == nil ? 65536 : (index < 5 ? 256 * 1024 * 1024 : 1024 * 1024 * 1024)
            try await runner.run(configuration: configuration(caseRoot, operation: .mixed, bytes: bytes), drive: CapricornTests.fixtureDrive(mountedAt: caseRoot.path)) { update in
                updates.withLock { $0.append(update) }
            }
            let values = updates.snapshot()
            XCTAssertEqual(values.last?.phase, .complete)
            XCTAssertNotNil(values.last?.queueStatus)
            XCTAssertGreaterThan(values.last?.queueStatus?.peakActive ?? 0, 0)
            let firstMixed = try XCTUnwrap(values.firstIndex { $0.phase == .mixed })
            XCTAssertEqual(values[firstMixed].completedBytes, 0)
            XCTAssertEqual(values[firstMixed].totalBytes, bytes * 2)
            XCTAssertTrue(values[..<firstMixed].contains { $0.phase == .flushingReadFile })
            XCTAssertTrue(values[firstMixed...].contains { $0.phase == .flushing && $0.completedBytes == bytes * 2 })
            XCTAssertFalse(values[firstMixed...].contains { $0.phase == .preparingReadFile || $0.phase == .flushingReadFile })
            XCTAssertEqual(budget.occupancy, 0)
            let files = try FileManager.default.contentsOfDirectory(at: manager.retained, includingPropertiesForKeys: nil).filter { $0.pathExtension == "tmp" }
            XCTAssertEqual(files.count, 2)
            for file in files {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
                XCTAssertEqual(Int64(size ?? -1), bytes)
            }
        }
    }

    func testRealCancellationAndRerunKeepAllSlots() async throws {
        let root = try folder("cancel")
        let budget = AIOBudget(limits: .current())
        for index in 0..<5 {
            let caseRoot = root.appendingPathComponent("case-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: caseRoot, withIntermediateDirectories: false)
            let manager = try AIOPreservingFileManager(root: caseRoot)
            let system = CancelOnSubmitAIO()
            let runner = NativeDiskActivityWorkloadRunner(
                fileManager: manager, temporaryRunLeaseDirectoryURL: caseRoot.appendingPathComponent("leases"),
                transfer: AIOTransfer(budget: budget, system: system)
            )
            system.onSubmit = { [weak runner] in runner?.cancel() }
            let updates = LockedState<[DiskActivityWorkloadProgress]>([])
            do {
                try await runner.run(
                    configuration: configuration(caseRoot, operation: .write, bytes: 32 * 1024 * 1024),
                    drive: CapricornTests.fixtureDrive(mountedAt: caseRoot.path)
                ) { update in updates.withLock { $0.append(update) } }
                XCTFail("Cancellation must be propagated")
            } catch BenchmarkError.cancelled {}
            XCTAssertEqual(budget.occupancy, 0)
            XCTAssertTrue(updates.snapshot().contains { $0.phase == .cleaningUp })
            system.onSubmit = nil
            try await runner.run(
                configuration: configuration(caseRoot, operation: .mixed, bytes: 1024 * 1024),
                drive: CapricornTests.fixtureDrive(mountedAt: caseRoot.path), progress: { _ in }
            )
            XCTAssertEqual(budget.occupancy, 0)
        }
    }

    func testBenchmarkAndWorkloadShareOneBudgetConcurrently() async throws {
        let root = try folder("concurrent")
        let benchmarkRoot = root.appendingPathComponent("benchmark", isDirectory: true)
        let workloadRoot = root.appendingPathComponent("workload", isDirectory: true)
        try FileManager.default.createDirectory(at: benchmarkRoot, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: workloadRoot, withIntermediateDirectories: false)
        let budget = AIOBudget(limits: .init(process: 4, system: 90))
        let benchmarkManager = try AIOPreservingFileManager(root: benchmarkRoot)
        let workloadManager = try AIOPreservingFileManager(root: workloadRoot)
        let benchmark = AsyncQueueBenchmarkRunner(
            fileManager: benchmarkManager, operationIntervalSeconds: 0, passIntervalSeconds: 0,
            temporaryRunLeaseDirectoryURL: benchmarkRoot.appendingPathComponent("leases"),
            aioTransfer: AIOTransfer(budget: budget)
        )
        let workload = NativeDiskActivityWorkloadRunner(
            fileManager: workloadManager, temporaryRunLeaseDirectoryURL: workloadRoot.appendingPathComponent("leases"),
            transfer: AIOTransfer(budget: budget)
        )
        let bytes: Int64 = externalRoot == nil ? 1024 * 1024 : 128 * 1024 * 1024
        let test = BenchmarkTest(
            id: "acceptance", label: "SEQ Q4T4", accessPattern: .sequential, operation: .write,
            blockSizeBytes: 1024 * 1024, queueDepth: 4, threads: 4,
            durationSeconds: 0.001, testSizeBytes: bytes, dataPattern: .zeroFill, writePercentForMixed: 100
        )
        let profile = BenchmarkProfile(id: "acceptance", name: "AIO acceptance", testFileSizeBytes: bytes, runs: 1, engine: .asyncQueue, tests: [test])
        async let result = benchmark.run(profile: profile, drive: CapricornTests.fixtureDrive(mountedAt: benchmarkRoot.path), volumePath: benchmarkRoot.path, progress: { _ in }, result: { _ in })
        async let activity: Void = workload.run(configuration: configuration(workloadRoot, operation: .mixed, bytes: bytes), drive: CapricornTests.fixtureDrive(mountedAt: workloadRoot.path), progress: { _ in })
        let (measurements, _) = try await (result, activity)
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements.first?.bytesTransferred, bytes)
        XCTAssertEqual(budget.occupancy, 0)
    }

    func testMixedFailureKeepsActualPhaseAndCanRunAgain() async throws {
        let root = try folder("failure")
        let manager = try AIOPreservingFileManager(root: root)
        let budget = AIOBudget(limits: .init(process: 4, system: 90))
        let system = CancelOnSubmitAIO()
        let failWrites = LockedState(false)
        system.rejectWrite = { failWrites.snapshot() }
        let runner = NativeDiskActivityWorkloadRunner(
            fileManager: manager, temporaryRunLeaseDirectoryURL: root.appendingPathComponent("leases"),
            transfer: AIOTransfer(budget: budget, system: system)
        )
        let updates = LockedState<[DiskActivityWorkloadProgress]>([])
        do {
            try await runner.run(
                configuration: configuration(root, operation: .mixed, bytes: 1024 * 1024),
                drive: CapricornTests.fixtureDrive(mountedAt: root.path)
            ) { update in
                if update.phase == .mixed { failWrites.withLock { $0 = true } }
                updates.withLock { $0.append(update) }
            }
            XCTFail("Injected write failure must propagate")
        } catch {
            XCTAssertEqual((error as? AIOTransferFailure)?.code, EIO)
        }
        let values = updates.snapshot()
        XCTAssertEqual(values.last?.phase, .failed)
        XCTAssertEqual(values.last?.failedPhaseMessage, "Running mixed workload")
        XCTAssertFalse(values.contains { $0.phase == .flushing })
        XCTAssertEqual(budget.occupancy, 0)
        system.rejectWrite = nil
        try await runner.run(
            configuration: configuration(root, operation: .mixed, bytes: 1024 * 1024),
            drive: CapricornTests.fixtureDrive(mountedAt: root.path), progress: { _ in }
        )
        XCTAssertEqual(budget.occupancy, 0)
    }

    private func configuration(_ root: URL, operation: DiskActivityWorkloadOperation, bytes: Int64) -> DiskActivityWorkloadConfiguration {
        .init(targetFolderURL: root, operation: operation, fileSizeOption: .gib32, fileSizeBytes: bytes, loopEnabled: false)
    }

    func testQuickProfileCompletesBothEnginesWithoutArtificialPauses() async throws {
        for engine in BenchmarkEngine.allCases {
            let root = try folder("quick-\(engine.rawValue)")
            let manager = try AIOPreservingFileManager(root: root)
            let updates = LockedState<[BenchmarkProgress]>([])
            let runner: any BenchmarkRunning
            if engine == .asyncQueue {
                runner = AsyncQueueBenchmarkRunner(
                    fileManager: manager, operationSleeper: { _, _ in XCTFail("Quick must skip artificial pauses") },
                    temporaryRunLeaseDirectoryURL: root.appendingPathComponent("leases")
                )
            } else {
                runner = NativeBenchmarkRunner(
                    fileManager: manager, operationSleeper: { _, _ in XCTFail("Quick must skip artificial pauses") },
                    temporaryRunLeaseDirectoryURL: root.appendingPathComponent("leases")
                )
            }
            let profile = BenchmarkProfile.quick.applying(engine: engine).configured(
                runs: 9, fileSizeBytes: 64 * 1_024 * 1_024 * 1_024, dataPattern: .random,
                usesTrimmedAverage: true, usesSmallBlockEfficiency: true
            )
            let measurements = try await runner.run(
                profile: profile, drive: CapricornTests.fixtureDrive(mountedAt: root.path),
                volumePath: root.path, progress: { update in updates.withLock { $0.append(update) } },
                result: { _ in }
            )
            XCTAssertEqual(measurements.count, 4)
            XCTAssertEqual(measurements.map(\.bytesTransferred).sorted(), [
                BenchmarkProfile.quickRandomTestSize, BenchmarkProfile.quickRandomTestSize,
                BenchmarkProfile.quickTestSize, BenchmarkProfile.quickTestSize
            ])
            XCTAssertFalse(updates.snapshot().contains { $0.message.hasPrefix("Waiting between") })
        }
    }
}

private final class AIOPreservingFileManager: FileManager, @unchecked Sendable {
    let root: URL
    let retained: URL
    init(root: URL) throws {
        self.root = root
        retained = root.appendingPathComponent("retained", isDirectory: true)
        super.init()
        try createDirectory(at: retained, withIntermediateDirectories: false)
    }
    override func removeItem(at url: URL) throws {
        guard url.path.hasPrefix(root.path + "/"), !url.path.hasPrefix(retained.path + "/") else {
            throw BenchmarkError.ioFailed("Acceptance test refused cleanup outside owned directory")
        }
        try moveItem(at: url, to: retained.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent))
    }
}

private final class CancelOnSubmitAIO: AIOSystemCalling, @unchecked Sendable {
    var onSubmit: (@Sendable () -> Void)?
    var rejectWrite: (@Sendable () -> Bool)?
    private let native = DarwinAIOSystem()
    func submit(_ control: UnsafeMutablePointer<aiocb>, write: Bool) -> AIOCallResult {
        if write && rejectWrite?() == true { return .init(value: -1, error: EIO) }
        let result = native.submit(control, write: write)
        if result.value == 0 { onSubmit?() }
        return result
    }
    func status(_ control: UnsafeMutablePointer<aiocb>) -> Int32 { native.status(control) }
    func result(_ control: UnsafeMutablePointer<aiocb>) -> AIOCallResult { native.result(control) }
    func wait(_ controls: [UnsafeMutablePointer<aiocb>]) -> AIOCallResult { native.wait(controls) }
    func cancel(_ descriptor: Int32) -> AIOCallResult { native.cancel(descriptor) }
}
