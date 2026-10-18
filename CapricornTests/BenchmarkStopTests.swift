// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class BenchmarkStopTests: XCTestCase {
    @MainActor
    func testModelKeepsSessionLockedUntilStoppedPassResultArrives() async throws {
        for policy in [BenchmarkResultUpdatePolicy.replaceProfile, .mergeTests] {
            let runner = PassBoundaryBenchmarkRunner()
            defer { runner.finishPass() }
            let model = AppModel(benchmarkRunner: runner)
            let drive = CapricornTests.fixtureDrive(mountedAt: "/Volumes/Unit")
            model.drives = [drive]
            model.selectedDriveID = drive.id
            let profile = profile(engine: .synchronous)
            var previous = CapricornTests.fixtureBenchmarkResult(for: drive)
            previous.profileID = profile.id
            previous.testID = "untouched"
            model.benchmarkResults = [previous]
            XCTAssertTrue(model.startBenchmark(profile: profile, volumePath: "/Volumes/Unit", resultUpdatePolicy: policy))
            let started = await AsyncTestWaiter.wait { model.benchmarkProgress?.message == "Read run 3/5" }
            XCTAssertTrue(started)

            model.stopBenchmarkAfterCurrentPass()
            model.stopBenchmarkAfterCurrentPass()
            XCTAssertTrue(model.isBenchmarking)
            XCTAssertTrue(model.isBenchmarkStopRequested)
            XCTAssertTrue(model.isDriveSelectionLocked)
            XCTAssertFalse(model.canStopBenchmark)
            XCTAssertTrue(model.appUpdateConflicts.contains(.benchmark))
            XCTAssertFalse(model.startBenchmark(profile: profile, volumePath: "/Volumes/Unit"))
            XCTAssertEqual(runner.cancelCount.snapshot(), 0)
            XCTAssertTrue(runner.request.snapshot()?.isRequested == true)
            XCTAssertFalse(model.benchmarkSession.didStopAfterCurrentPass)

            runner.finishPass()
            let finished = await AsyncTestWaiter.wait { !model.appUpdateConflicts.contains(.benchmark) }
            XCTAssertTrue(finished)
            XCTAssertFalse(model.isBenchmarking)
            XCTAssertTrue(model.benchmarkSession.didStopAfterCurrentPass)
            XCTAssertNil(model.benchmarkError)
            XCTAssertEqual(model.benchmarkProgress?.message, BenchmarkStopRequest.completedMessage)
            XCTAssertTrue(model.benchmarkResults.contains { $0.testID == "first" })
            XCTAssertEqual(model.benchmarkResults.contains { $0.testID == "untouched" }, policy == .mergeTests)
            XCTAssertEqual(runner.cancelCount.snapshot(), 0)
        }
    }

    @MainActor
    func testImmediateCancelOverridesPendingStopAndRejectsLateResult() async throws {
        let runner = PassBoundaryBenchmarkRunner()
        defer { runner.finishPass() }
        let model = AppModel(benchmarkRunner: runner)
        let drive = CapricornTests.fixtureDrive(mountedAt: "/Volumes/Unit")
        model.drives = [drive]
        model.selectedDriveID = drive.id
        XCTAssertTrue(model.startBenchmark(profile: profile(engine: .synchronous), volumePath: "/Volumes/Unit"))
        let started = await AsyncTestWaiter.wait { model.canStopBenchmark }
        XCTAssertTrue(started)
        model.stopBenchmarkAfterCurrentPass()
        model.cancelBenchmark()
        let finished = await AsyncTestWaiter.wait { !model.appUpdateConflicts.contains(.benchmark) }
        XCTAssertTrue(finished)
        XCTAssertEqual(runner.cancelCount.snapshot(), 1)
        XCTAssertFalse(model.benchmarkSession.didStopAfterCurrentPass)
        XCTAssertEqual(model.benchmarkError, BenchmarkError.cancelled.localizedDescription)
        XCTAssertTrue(model.benchmarkResults.isEmpty)
    }

    func testStopMessagesKeepCurrentPhaseAndDescribeCompletedResultsInBothLanguages() {
        for language in AppLanguage.allCases {
            let phase = "Read run 3/5"
            let pending = language.benchmarkProgressMessage(phase, stoppingAfterCurrentPass: true)
            XCTAssertTrue(pending.contains(language.t(BenchmarkStopRequest.waitingMessage)))
            XCTAssertTrue(pending.contains(language.statusMessage(phase)))
            XCTAssertEqual(language.benchmarkProgressMessage(phase, stoppingAfterCurrentPass: false), language.statusMessage(phase))
            XCTAssertEqual(
                language.benchmarkProgressMessage(BenchmarkStopRequest.completedMessage, stoppingAfterCurrentPass: true),
                language.t(BenchmarkStopRequest.completedMessage)
            )
        }
        XCTAssertEqual(AppLanguage.simplifiedChinese.t("Stop"), "停止")
        XCTAssertTrue(AppLanguage.simplifiedChinese.t(BenchmarkStopRequest.completedMessage).contains("后续测试已跳过"))
    }

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

private final class PassBoundaryBenchmarkRunner: BenchmarkRunning, Sendable {
    let request = LockedState<BenchmarkStopRequest?>(nil)
    let cancelCount = LockedState(0)
    private let pass = AsyncStream<Void>.makeStream()

    func run(
        profile: BenchmarkProfile, drive: DriveDevice, volumePath: String,
        stopRequest: BenchmarkStopRequest,
        progress: @escaping @Sendable (BenchmarkProgress) -> Void,
        result: @escaping @Sendable (BenchmarkResult) -> Void
    ) async throws -> [BenchmarkResult] {
        request.withLock { $0 = stopRequest }
        progress(BenchmarkProgress(currentTestLabel: "SEQ1M Q1T1", completed: 3, total: 12, message: "Read run 3/5"))
        for await _ in pass.stream { break }
        var completed = CapricornTests.fixtureBenchmarkResult(for: drive)
        completed.profileID = profile.id
        completed.testID = "first"
        result(completed)
        progress(BenchmarkProgress(currentTestLabel: "Complete", completed: 4, total: 12, message: "Benchmark complete"))
        return [completed]
    }

    func finishPass() {
        pass.continuation.yield()
        pass.continuation.finish()
    }

    func cancel() {
        cancelCount.withLock { $0 += 1 }
        finishPass()
    }
}
