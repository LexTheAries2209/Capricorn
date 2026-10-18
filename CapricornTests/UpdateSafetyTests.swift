// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

@MainActor
final class UpdateSafetyTests: XCTestCase {
    func testEveryActiveSessionBlocksUpdatesIncludingStoppingAndConfirmation() {
        let model = AppModel()
        XCTAssertTrue(model.appUpdateConflicts.isEmpty)
        model.benchmarkSession.state = .finishingPass
        XCTAssertEqual(model.appUpdateConflicts, [.benchmark])
        model.benchmarkSession.state = .stopping
        model.liveActivitySession.workloadState = .stopping
        model.isLiveActivityMonitoring = true
        model.isDiskChecking = true
        model.firstAidState = .awaitingConfirmation
        model.smartSelfTestSession = .stopping
        model.isRefreshing = true
        XCTAssertEqual(
            Set(model.appUpdateConflicts),
            Set([.benchmark, .workload, .monitoring, .diskCheck, .firstAid, .selfTest, .refresh])
        )
    }

    func testBlockedInstallationNeverReservesOrSavesAndDoesNotResumeItself() throws {
        var conflicts: [AppUpdateConflict] = [.benchmark]
        var saved = false
        let gate = AppUpdateSafetyGate(conflicts: { conflicts }, save: { saved = true })
        XCTAssertThrowsError(try gate.beginInstallation()) {
            XCTAssertEqual($0 as? AppUpdateBlockedError, AppUpdateBlockedError(conflicts: [.benchmark]))
        }
        XCTAssertFalse(gate.isReserved)
        XCTAssertFalse(saved)
        conflicts = []
        XCTAssertFalse(gate.isReserved)
        XCTAssertFalse(saved)
        try gate.beginInstallation()
        XCTAssertTrue(gate.isReserved)
        XCTAssertTrue(saved)
    }

    func testSaveFailureReleasesInstallationReservation() {
        let model = AppModel()
        let gate = AppUpdateSafetyGate(
            conflicts: { model.appUpdateConflicts },
            reserve: { model.reserveAppUpdateInstallation() },
            release: { model.releaseAppUpdateInstallation() },
            save: { throw CocoaError(.fileWriteNoPermission) }
        )
        XCTAssertThrowsError(try gate.beginInstallation())
        XCTAssertFalse(gate.isReserved)
        XCTAssertFalse(model.isInstallingAppUpdate)
    }

    func testReservationPreventsNewBenchmarkAndRefreshAndCanBeReleased() async throws {
        let model = AppModel()
        let gate = AppUpdateSafetyGate(
            conflicts: { model.appUpdateConflicts },
            reserve: { model.reserveAppUpdateInstallation() },
            release: { model.releaseAppUpdateInstallation() }
        )
        try gate.beginInstallation()
        XCTAssertTrue(model.isInstallingAppUpdate)
        await model.refresh()
        XCTAssertFalse(model.isRefreshing)
        XCTAssertFalse(model.startBenchmark(profile: .default))
        try gate.check()
        gate.endInstallation()
        XCTAssertTrue(model.appUpdateConflicts.isEmpty)
    }
}
