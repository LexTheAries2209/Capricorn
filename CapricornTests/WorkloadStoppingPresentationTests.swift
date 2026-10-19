import XCTest
@testable import Capricorn

final class WorkloadStoppingPresentationTests: XCTestCase {
    func testStopKeepsBlockingPhaseAndTimestampWithoutBytePercentage() {
        let started = Date(timeIntervalSince1970: 100)
        let stopped = progress(.sizingFile).requestingStop(at: started)
        XCTAssertEqual(stopped.phase, .stopping)
        XCTAssertEqual(stopped.stopPhase, .sizingFile)
        XCTAssertEqual(stopped.stopRequestedAt, started)
        XCTAssertEqual(stopped.requestingStop(at: started.addingTimeInterval(10)).stopRequestedAt, started)
        XCTAssertFalse(stopped.hasMeasurableByteProgress)
        XCTAssertFalse(AppLanguage.simplifiedChinese.activityWorkloadProgressText(stopped).contains(" / "))
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.activityWorkloadStopElapsed(stopped, now: started.addingTimeInterval(12)),
            "正在等待停止 · 已等待 12 秒"
        )
        XCTAssertTrue(AppLanguage.simplifiedChinese.activityWorkloadStopExplanation(stopped).contains("文件准备"))
        XCTAssertTrue(AppLanguage.simplifiedChinese.activityWorkloadStopExplanation(stopped).contains("无法提供百分比"))
        XCTAssertTrue(AppLanguage.english.activityWorkloadStopElapsed(stopped, now: started.addingTimeInterval(12)).contains("12 s"))
    }

    func testFlushWaitExplainsDurationWithoutInventingPendingCount() {
        let stopped = progress(.flushing).requestingStop(at: .now)
        XCTAssertTrue(AppLanguage.simplifiedChinese.activityWorkloadStopExplanation(stopped).contains("刷盘"))
        XCTAssertTrue(AppLanguage.simplifiedChinese.activityWorkloadStopExplanation(stopped).contains("无法估算"))
        XCTAssertNil(AppLanguage.simplifiedChinese.activityWorkloadPendingIO(stopped))
    }

    func testMixedDrainCountsBothPathsAndTracksDecreasingPendingRequests() {
        var summary = DiskActivityWorkloadQueueSummary()
        _ = summary.update(status(active: 3), writing: false)
        _ = summary.update(status(active: 4), writing: true)
        var drain = progress(.cleaningUp)
        drain.queueStatus = summary.update(status(active: 2, draining: true), writing: false)
        XCTAssertEqual(drain.queueStatus?.active, 6)
        XCTAssertEqual(AppLanguage.simplifiedChinese.activityWorkloadPendingIO(drain), "仍有 6 个已提交的 I/O 等待结束")
        drain.queueStatus = summary.update(status(active: 1), writing: true)
        XCTAssertEqual(drain.queueStatus?.active, 3)
        XCTAssertEqual(drain.queueStatus?.draining, true)
        drain.queueStatus = summary.update(status(active: 0, draining: true, finished: true), writing: false)
        drain.queueStatus = summary.update(status(active: 0, finished: true), writing: true)
        XCTAssertEqual(drain.queueStatus?.active, 0)
        XCTAssertEqual(drain.queueStatus?.finished, true)
        XCTAssertEqual(AppLanguage.simplifiedChinese.activityWorkloadPendingIO(drain), "已提交的 I/O 已结束，正在完成清理。")
        XCTAssertTrue(AppLanguage.english.activityWorkloadPendingIO(drain)?.contains("finished") == true)
    }

    func testDrainUpdatesPreserveOriginalWaitContext() {
        let stopped = progress(.writing).requestingStop(at: Date(timeIntervalSince1970: 100))
        var drain = progress(.cleaningUp)
        drain.queueStatus = status(active: 2, draining: true)
        let updated = drain.preservingStopContext(from: stopped)
        XCTAssertEqual(updated.stopRequestedAt, stopped.stopRequestedAt)
        XCTAssertEqual(updated.stopPhase, .writing)
        XCTAssertEqual(updated.queueStatus?.active, 2)
        XCTAssertTrue(AppLanguage.simplifiedChinese.activityWorkloadStopExplanation(updated).contains("安全关闭"))
    }

    @MainActor
    func testModelWaitsForDrainThenRemovesWaitingTimer() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Capricorn-Stop-Presentation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("Capricorn workload stopping presentation test; retain until reviewed.".utf8)
            .write(to: root.appendingPathComponent("CAPRICORN_TEST_ARTIFACTS.txt"), options: .withoutOverwriting)
        let runner = HoldingStopRunner()
        let model = AppModel(
            liveActivityWorkloadRunner: runner,
            diskOperationLockCoordinator: DiskOperationLockCoordinator(lockDirectoryURL: root.appendingPathComponent("locks"))
        )
        let drive = CapricornTests.fixtureDrive(mountedAt: root.path)
        model.drives = [drive]
        model.startLiveActivityWorkload(
            configuration: .init(targetFolderURL: root, operation: .mixed, fileSizeOption: .gib128, fileSizeBytes: 65536, loopEnabled: false),
            drive: drive, interval: .tenth
        )
        let started = await AsyncTestWaiter.wait { runner.isRunning }
        XCTAssertTrue(started, "Test runner did not start: \(String(describing: model.diskOperationLockNotice))")
        guard started else { return }
        let receivedSizing = await AsyncTestWaiter.wait { model.liveActivityWorkloadProgress?.phase == .sizingFile }
        XCTAssertTrue(receivedSizing)
        model.stopLiveActivityWorkload()
        let timestamp = model.liveActivityWorkloadProgress?.stopRequestedAt
        XCTAssertNotNil(timestamp)
        XCTAssertEqual(model.liveActivityWorkloadProgress?.stopPhase, .sizingFile)
        XCTAssertTrue(model.isLiveActivityWorkloadRunning)
        model.stopLiveActivityWorkload()
        XCTAssertEqual(model.liveActivityWorkloadProgress?.stopRequestedAt, timestamp)
        var drain = progress(.cleaningUp)
        drain.queueStatus = status(active: 3, draining: true)
        runner.emit(drain)
        let receivedDrain = await AsyncTestWaiter.wait { model.liveActivityWorkloadProgress?.phase == .cleaningUp }
        XCTAssertTrue(receivedDrain)
        XCTAssertEqual(model.liveActivityWorkloadProgress?.stopRequestedAt, timestamp)
        XCTAssertEqual(model.liveActivityWorkloadProgress?.queueStatus?.active, 3)
        runner.finish()
        let finished = await AsyncTestWaiter.wait { !model.isLiveActivityWorkloadRunning }
        XCTAssertTrue(finished)
        XCTAssertEqual(model.liveActivityWorkloadProgress?.phase, .stopped)
        XCTAssertNil(model.liveActivityWorkloadProgress?.stopRequestedAt)
        let stoppedProgress = try XCTUnwrap(model.liveActivityWorkloadProgress)
        XCTAssertEqual(AppLanguage.simplifiedChinese.activityWorkloadProgressText(stoppedProgress), "负载已停止")
        XCTAssertEqual(AppLanguage.english.activityWorkloadProgressText(stoppedProgress), "Workload stopped")
        model.stopLiveActivityMonitoring()
    }

    private func progress(_ phase: DiskActivityWorkloadPhase) -> DiskActivityWorkloadProgress {
        .init(operation: .mixed, phase: phase, loopIndex: 1, completedBytes: 0, totalBytes: 128 * 1024 * 1024 * 1024, message: "Stopping workload")
    }

    private func status(active: Int, draining: Bool = false, finished: Bool = false) -> AIOTransferStatus {
        .init(targetDepth: 16, active: active, peakActive: 16, processUsed: active, processLimit: 16, systemLimit: 90, retries: 0, waitMilliseconds: 0, draining: draining, finished: finished)
    }
}

private final class HoldingStopRunner: DiskActivityWorkloadRunning, @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<Void, Error>?
        var progress: (@Sendable (DiskActivityWorkloadProgress) -> Void)?
    }
    private let state = LockedState(State())
    var isRunning: Bool { state.withLock { $0.continuation != nil } }
    func run(configuration: DiskActivityWorkloadConfiguration, drive: DriveDevice, progress: @escaping @Sendable (DiskActivityWorkloadProgress) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            state.withLock {
                $0.continuation = continuation
                $0.progress = progress
            }
            progress(.init(operation: .mixed, phase: .sizingFile, loopIndex: 1, completedBytes: 0, totalBytes: configuration.fileSizeBytes, message: "Sizing workload file"))
        }
    }
    func cancel() {}
    func emit(_ progress: DiskActivityWorkloadProgress) { state.snapshot().progress?(progress) }
    func finish() {
        let continuation = state.withLock { state in
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.resume(throwing: BenchmarkError.cancelled)
    }
}
