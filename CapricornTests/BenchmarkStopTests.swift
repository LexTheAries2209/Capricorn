// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class BenchmarkStopTests: XCTestCase {
    func testStopCompletesThirdPassAndSkipsLaterPassesAndTestsInBothEngines() async throws {
        for engine in [BenchmarkEngine.synchronous, .asyncQueue] {
            for operation in [BenchmarkOperation.read, .write, .mixed] {
                for trimsOutliers in [false, true] {
                    let root = try makeFolder()
                    defer { try? FileManager.default.removeItem(at: root) }
                    let request = BenchmarkStopRequest()
                    let profile = profile(engine: engine, operation: operation, trimsOutliers: trimsOutliers)
                    let measuredRuns = BenchmarkMeasurementReducer.measuredRunCount(
                        for: profile.runs, usesTrimmedAverage: trimsOutliers
                    )
                    let updates = LockedState<[BenchmarkProgress]>([])
                    let published = LockedState<[BenchmarkResult]>([])
                    let runner = runner(engine: engine)
                    let results = try await runner.run(
                        profile: profile, drive: CapricornTests.fixtureDrive(), volumePath: root.path,
                        stopRequest: request,
                        progress: { progress in
                            updates.withLock { $0.append(progress) }
                            if progress.message == "\(operation.title) run 3/\(measuredRuns)",
                               progress.phaseTotalBytes > 0, progress.phaseCompletedBytes == 0 {
                                request.request()
                            }
                        },
                        result: { result in published.withLock { $0.append(result) } }
                    )

                    XCTAssertTrue(request.isRequested)
                    XCTAssertEqual(results.map(\.testID), ["first"])
                    XCTAssertEqual(results, published.snapshot())
                    XCTAssertEqual(results.first?.bytesTransferred, 32_768)
                    XCTAssertGreaterThan(results.first?.bestMegabytesPerSecond ?? 0, 0)
                    XCTAssertEqual(updates.snapshot().last?.completed, 4, "Warm-up plus three measured passes")
                    XCTAssertEqual(updates.snapshot().last?.message, BenchmarkStopRequest.completedMessage)
                    XCTAssertFalse(updates.snapshot().contains { $0.message == "\(operation.title) run 4/\(measuredRuns)" })
                    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
                }
            }
        }
    }

    func testStopDuringWarmupDoesNotPublishAnUnmeasuredResult() async throws {
        for engine in [BenchmarkEngine.synchronous, .asyncQueue] {
            let root = try makeFolder()
            defer { try? FileManager.default.removeItem(at: root) }
            let request = BenchmarkStopRequest()
            let results = try await runner(engine: engine).run(
                profile: profile(engine: engine), drive: CapricornTests.fixtureDrive(), volumePath: root.path,
                stopRequest: request,
                progress: { progress in
                    if progress.message == "Read warm-up", progress.phaseTotalBytes > 0 {
                        request.request()
                    }
                },
                result: { _ in XCTFail("A warm-up must not become a scored result.") }
            )
            XCTAssertTrue(request.isRequested)
            XCTAssertTrue(results.isEmpty)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }

    func testLoopStopKeepsCurrentPassAndLatestResultsWithoutStartingNextItem() async throws {
        for engine in [BenchmarkEngine.synchronous, .asyncQueue] {
            let root = try makeFolder()
            defer { try? FileManager.default.removeItem(at: root) }
            let request = BenchmarkStopRequest()
            var profile = profile(engine: engine)
            profile.executionMode = .loopUntilCancelled
            let published = LockedState<[BenchmarkResult]>([])
            let results = try await runner(engine: engine).run(
                profile: profile, drive: CapricornTests.fixtureDrive(), volumePath: root.path,
                stopRequest: request,
                progress: { progress in
                    if progress.currentTestLabel == "Loop 2 - SEQ1M Q1T1 Read",
                       progress.phaseTotalBytes > 0, progress.phaseCompletedBytes == 0 {
                        request.request()
                    }
                },
                result: { result in published.withLock { $0.append(result) } }
            )
            XCTAssertTrue(request.isRequested)
            XCTAssertEqual(published.snapshot().map(\.testID), ["first", "later", "first"])
            XCTAssertEqual(results.map(\.testID), ["first", "later"])
            XCTAssertEqual(results.first, published.snapshot().last)
            XCTAssertTrue(results.allSatisfy { $0.bytesTransferred == 32_768 })
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }

    func testEarlyStopIsNotClearedAndDoesNotLeakIntoNextRun() async throws {
        for engine in [BenchmarkEngine.synchronous, .asyncQueue] {
            let root = try makeFolder()
            defer { try? FileManager.default.removeItem(at: root) }
            let request = BenchmarkStopRequest()
            request.request()
            let runner = runner(engine: engine)
            let profile = profile(engine: engine)
            let stopped = try await runner.run(
                profile: profile, drive: CapricornTests.fixtureDrive(), volumePath: root.path,
                stopRequest: request, progress: { _ in }, result: { _ in }
            )
            XCTAssertTrue(stopped.isEmpty)
            let restarted = try await runner.run(
                profile: profile, drive: CapricornTests.fixtureDrive(), volumePath: root.path,
                progress: { _ in }, result: { _ in }
            )
            XCTAssertEqual(restarted.map(\.testID), ["first", "later"])
        }
    }

    func testStopDuringIntervalKeepsCompletedMeasurements() async throws {
        for engine in [BenchmarkEngine.synchronous, .asyncQueue] {
            let root = try makeFolder()
            defer { try? FileManager.default.removeItem(at: root) }
            let request = BenchmarkStopRequest()
            let waits = LockedState(0)
            let sleeper: NativeBenchmarkRunner.OperationSleeper = { _, interrupted in
                let count = waits.withLock { $0 += 1; return $0 }
                if count == 2 {
                    request.request()
                    XCTAssertTrue(interrupted())
                    throw BenchmarkError.cancelled
                }
            }
            let runner: any BenchmarkRunning = engine == .synchronous
                ? NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 1, operationSleeper: sleeper)
                : AsyncQueueBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 1, operationSleeper: sleeper)
            let results = try await runner.run(
                profile: profile(engine: engine), drive: CapricornTests.fixtureDrive(), volumePath: root.path,
                stopRequest: request, progress: { _ in }, result: { _ in }
            )
            XCTAssertEqual(results.map(\.testID), ["first"])
            XCTAssertEqual(results.first?.bytesTransferred, 32_768)
            XCTAssertEqual(waits.snapshot(), 2, "Stop in the interval after the first scored pass.")
        }
    }

    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func runner(engine: BenchmarkEngine) -> any BenchmarkRunning {
        BenchmarkRunnerRouter(
            synchronousRunner: NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0),
            asyncRunner: AsyncQueueBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0)
        )
    }

    private func profile(
        engine: BenchmarkEngine, operation: BenchmarkOperation = .read, trimsOutliers: Bool = false
    ) -> BenchmarkProfile {
        let first = BenchmarkTest(
            id: "first", label: "SEQ1M Q1T1", accessPattern: .sequential, operation: operation,
            blockSizeBytes: 4_096, queueDepth: 1, threads: 1, durationSeconds: 0.001,
            testSizeBytes: 32_768, dataPattern: .zeroFill, writePercentForMixed: 30
        )
        var later = first
        later.id = "later"
        later.operation = .write
        return BenchmarkProfile(
            id: "stop-test", name: "Stop Test", testFileSizeBytes: 32_768, runs: 5,
            usesTrimmedAverage: trimsOutliers, engine: engine, tests: [first, later]
        )
    }
}
