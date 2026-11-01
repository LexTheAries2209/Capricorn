// SPDX-License-Identifier: GPL-3.0-only
import Sparkle
import XCTest
@testable import Capricorn

@MainActor
final class DeviceServiceUpdateTests: XCTestCase {
    func testRestorationRunsOnLaunchEvenWithAutomaticUpdateChecksDisabled() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CapricornTests.restoreLaunch." + UUID().uuidString))
        let service = SuspendedDeviceServiceUpdate()
        service.requiresPreparation = false
        service.requiresRestoration = true
        defaults.set(false, forKey: AppUpdater.PreferenceKey.checksOnLaunch)
        let updater = AppUpdater(safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
                                 allowsStartup: true, defaults: defaults, deviceService: service)
        updater.applicationDidLaunch()
        updater.applicationDidLaunch()
        let restored = await AsyncTestWaiter.wait { service.restorations == 1 }
        XCTAssertTrue(restored)
        XCTAssertFalse(updater.isStarted, "Restoring a service must not opt the user into update checks.")
    }

    func testInstallerReplyWaitsForSafeStopAndOnlyStopsAtInstallTime() async throws {
        let service = SuspendedDeviceServiceUpdate()
        let gate = AppUpdateSafetyGate(conflicts: { [] })
        let updater = AppUpdater(safety: gate, language: { .english }, allowsStartup: false,
                                 presentAlert: { _, _ in }, deviceService: service)
        let standard = RecordingUpdateUserDriver()
        let driver = GuardedUpdateUserDriver(standard: standard, owner: updater)
        XCTAssertTrue(updater.authorizeUpdate(), "Downloading with an enabled service must be allowed.")
        XCTAssertEqual(service.preparations, 0)
        updater.markPendingInstallation(true)
        var choices: [SPUUserUpdateChoice] = []
        driver.showReady { choices.append($0) }
        standard.readyReply?(.install)
        XCTAssertTrue(gate.isReserved)
        XCTAssertTrue(updater.isPreparingDeviceService)
        XCTAssertTrue(choices.isEmpty)
        let started = await AsyncTestWaiter.wait { service.preparations == 1 }
        XCTAssertTrue(started)
        service.finish()
        let finished = await AsyncTestWaiter.wait { !choices.isEmpty }
        XCTAssertTrue(finished)
        XCTAssertEqual(choices, [.install])
        XCTAssertFalse(updater.isPreparingDeviceService)
        XCTAssertTrue(updater.applicationMayTerminate())
        XCTAssertEqual(service.restorations, 0, "Do not restart the old helper after committing installation.")
    }

    func testCancellationDuringPreparationRepliesOnceAndRestoresOldService() async {
        let service = SuspendedDeviceServiceUpdate()
        let updater = AppUpdater(safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
                                 allowsStartup: false, presentAlert: { _, _ in }, deviceService: service)
        let standard = RecordingUpdateUserDriver()
        let driver = GuardedUpdateUserDriver(standard: standard, owner: updater)
        updater.markPendingInstallation(true)
        var choices: [SPUUserUpdateChoice] = []
        driver.showReady { choices.append($0) }
        standard.readyReply?(.install)
        let started = await AsyncTestWaiter.wait { service.preparations == 1 }
        XCTAssertTrue(started)
        XCTAssertFalse(updater.applicationMayTerminate())
        XCTAssertEqual(choices, [.skip])
        service.finish()
        let restored = await AsyncTestWaiter.wait { service.restorations == 1 }
        XCTAssertTrue(restored)
        XCTAssertEqual(choices, [.skip])
        XCTAssertFalse(updater.safety.isReserved)
        XCTAssertFalse(updater.hasPendingInstallation)
    }

    func testWorkerFailureBlocksInstallAndReleasesReservation() async {
        let service = SuspendedDeviceServiceUpdate()
        let updater = AppUpdater(safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
                                 allowsStartup: false, presentAlert: { _, _ in }, deviceService: service)
        var ready: Bool?
        updater.prepareInstallation { ready = $0 }
        let started = await AsyncTestWaiter.wait { service.preparations == 1 }
        XCTAssertTrue(started)
        service.finish(error: DeviceHelperError.rejected("busy"))
        let finished = await AsyncTestWaiter.wait { ready != nil }
        XCTAssertTrue(finished)
        XCTAssertEqual(ready, false)
        XCTAssertEqual(updater.state, .failed(.deviceService))
        XCTAssertFalse(updater.safety.isReserved)
        XCTAssertEqual(service.restorations, 1)
    }

    func testNewConflictAfterUnregisterRestoresServiceAndBlocksInstallation() async {
        let service = SuspendedDeviceServiceUpdate()
        var conflicts: [AppUpdateConflict] = []
        let updater = AppUpdater(safety: AppUpdateSafetyGate(conflicts: { conflicts }), language: { .english },
                                 allowsStartup: false, presentAlert: { _, _ in }, deviceService: service)
        var ready: Bool?
        updater.prepareInstallation { ready = $0 }
        let started = await AsyncTestWaiter.wait { service.preparations == 1 }
        XCTAssertTrue(started)
        conflicts = [.firstAid]
        service.finish()
        let finished = await AsyncTestWaiter.wait { ready != nil }
        XCTAssertTrue(finished)
        XCTAssertEqual(ready, false)
        XCTAssertEqual(updater.state, .blocked([.firstAid]))
        XCTAssertEqual(service.restorations, 1)
    }

    func testInstallFailureRestoresServiceButNormalCheckNeverRestoresOrRegisters() async {
        let service = SuspendedDeviceServiceUpdate()
        let updater = AppUpdater(safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
                                 allowsStartup: false, presentAlert: { _, _ in }, deviceService: service)
        XCTAssertTrue(updater.canBeginAutomaticUpdate())
        XCTAssertEqual(service.restorations, 0)
        var ready = false
        updater.prepareInstallation { ready = $0 }
        let started = await AsyncTestWaiter.wait { service.preparations == 1 }
        XCTAssertTrue(started)
        service.finish()
        let prepared = await AsyncTestWaiter.wait { ready }
        XCTAssertTrue(prepared)
        updater.handleError(CocoaError(.fileWriteNoPermission), showingAlert: false)
        let restored = await AsyncTestWaiter.wait { service.restorations == 1 }
        XCTAssertTrue(restored)
        XCTAssertFalse(updater.safety.isReserved)
    }
}

@MainActor
private final class SuspendedDeviceServiceUpdate: DeviceServiceUpdateCoordinating {
    var requiresPreparation = true
    var requiresRestoration = false
    var preparations = 0
    var restorations = 0
    private var continuation: CheckedContinuation<Void, Error>?
    func prepareForUpdate() async throws {
        preparations += 1
        requiresRestoration = true
        try await withCheckedThrowingContinuation { continuation = $0 }
        requiresPreparation = false
    }
    func finish(error: Error? = nil) {
        let current = continuation
        continuation = nil
        if let error { current?.resume(throwing: error) }
        else { current?.resume() }
    }
    func restoreAfterUpdate() async {
        restorations += 1
        requiresRestoration = false
        requiresPreparation = true
    }
}
