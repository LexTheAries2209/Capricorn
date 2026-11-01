// SPDX-License-Identifier: GPL-3.0-only
import ServiceManagement
import XCTest
@testable import Capricorn

@MainActor
final class DeviceHelperServiceLifecycleTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "CapricornTests.helperLifecycle." + UUID().uuidString))
    }

    private func manager(_ service: TestHelperRegistration, _ defaults: UserDefaults,
                         stop: @escaping () async throws -> Void = {},
                         cancelStop: @escaping () async throws -> Void = {},
                         check: @escaping () async throws -> Void = {},
                         team: String = "TEAM") -> DeviceHelperServiceManager {
        DeviceHelperServiceManager(registration: service, defaults: defaults, validateInstallation: { team },
                                   stop: stop, cancelStop: cancelStop, checkConnection: check)
    }

    func testEnabledServiceIsStoppedAndRestoredByNextAppInstance() async throws {
        let service = TestHelperRegistration(.enabled)
        let defaults = try defaults()
        var stopped = false
        var checked = false
        let old = manager(service, defaults, stop: { stopped = true })
        try await old.prepareForUpdate()
        XCTAssertTrue(stopped)
        XCTAssertEqual(service.unregisters, 1)
        XCTAssertTrue(old.requiresRestoration)
        XCTAssertEqual(service.status, .notRegistered)
        let new = manager(service, defaults, check: { checked = true })
        await new.restoreAfterUpdate()
        XCTAssertEqual(service.registers, 1)
        XCTAssertTrue(checked)
        XCTAssertEqual(new.status, .enabled)
        XCTAssertFalse(new.requiresRestoration)
        await new.restoreAfterUpdate()
        XCTAssertEqual(service.registers, 1, "A completed update must not reregister on every launch.")
    }

    func testDisabledAndAwaitingApprovalServicesAreNotAutoEnabled() async throws {
        for status in [SMAppService.Status.notRegistered, .notFound, .requiresApproval] {
            let service = TestHelperRegistration(status)
            let manager = manager(service, try defaults())
            try await manager.prepareForUpdate()
            await manager.restoreAfterUpdate()
            XCTAssertFalse(manager.requiresRestoration)
            XCTAssertEqual(service.registers, 0)
            XCTAssertEqual(service.unregisters, 0)
        }
    }

    func testBusyWorkerBlocksUnregisterAndClearsUpdateIntent() async throws {
        let service = TestHelperRegistration(.enabled)
        let manager = manager(service, try defaults(), stop: {
            throw DeviceHelperError.rejected("busy")
        })
        do { try await manager.prepareForUpdate(); XCTFail() } catch {}
        XCTAssertEqual(service.unregisters, 0)
        XCTAssertEqual(service.status, .enabled)
        XCTAssertFalse(manager.requiresRestoration)
    }

    func testUnregisterFailureReleasesIdleStopReservation() async throws {
        let service = TestHelperRegistration(.enabled)
        service.unregisterError = CocoaError(.fileWriteUnknown)
        var resumed = false
        let manager = manager(service, try defaults(), cancelStop: { resumed = true })
        do { try await manager.prepareForUpdate(); XCTFail() } catch {}
        XCTAssertTrue(resumed)
        XCTAssertEqual(service.status, .enabled)
        XCTAssertFalse(manager.requiresRestoration)
    }

    func testCrashBetweenStopAndUnregisterCanReleaseReservationOnNextLaunch() async throws {
        let service = TestHelperRegistration(.enabled)
        let defaults = try defaults()
        var resumed = false
        let next = manager(service, defaults, cancelStop: { resumed = true })
        let old = manager(service, defaults, stop: {
            // The durable receipt must exist before the first async boundary.
            XCTAssertNotNil(defaults.data(forKey: DeviceHelperServiceManager.updateReceiptKey))
            await next.restoreAfterUpdate()
        })
        try await old.prepareForUpdate()
        XCTAssertTrue(resumed)
        XCTAssertTrue(old.requiresRestoration)
        await next.restoreAfterUpdate()
        XCTAssertFalse(next.requiresRestoration)
    }

    func testSystemRevocationDuringUpdateIsRespected() async throws {
        let service = TestHelperRegistration(.enabled)
        let manager = manager(service, try defaults())
        try await manager.prepareForUpdate()
        service.status = .requiresApproval
        await manager.restoreAfterUpdate()
        XCTAssertEqual(service.registers, 0)
        XCTAssertEqual(manager.error, DeviceHelperServiceManager.approvalMessage)
        XCTAssertFalse(manager.requiresRestoration, "Do not retry over the user's revocation at each launch.")
    }

    func testRegistrationRequiringApprovalDoesNotOpenPromptsOrRetryForever() async throws {
        let service = TestHelperRegistration(.enabled)
        let manager = manager(service, try defaults())
        try await manager.prepareForUpdate()
        service.registrationResult = .requiresApproval
        service.registerError = CocoaError(.fileWriteNoPermission)
        await manager.restoreAfterUpdate()
        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertEqual(manager.error, DeviceHelperServiceManager.approvalMessage)
        XCTAssertFalse(manager.requiresRestoration)
        await manager.restoreAfterUpdate()
        XCTAssertEqual(service.registers, 1)
    }

    func testSigningTeamChangeCannotReuseUpdateIntent() async throws {
        let service = TestHelperRegistration(.enabled)
        let defaults = try defaults()
        let old = manager(service, defaults)
        try await old.prepareForUpdate()
        let new = manager(service, defaults, team: "OTHER")
        await new.restoreAfterUpdate()
        XCTAssertEqual(service.registers, 0)
        XCTAssertNotNil(new.error)
    }

    func testFailedStopCancellationKeepsRecoveryJournal() async throws {
        let service = TestHelperRegistration(.enabled)
        service.unregisterError = CocoaError(.fileWriteUnknown)
        let defaults = try defaults()
        let old = manager(service, defaults, cancelStop: { throw DeviceHelperError.rejected("unavailable") })
        do { try await old.prepareForUpdate(); XCTFail() } catch {}
        XCTAssertTrue(old.requiresRestoration)
        var resumed = false
        let next = manager(service, defaults, cancelStop: { resumed = true })
        await next.restoreAfterUpdate()
        XCTAssertTrue(resumed)
        XCTAssertFalse(next.requiresRestoration)
    }

    func testManualDisableInProgressRequiresInstallationPreparation() async throws {
        let service = TestHelperRegistration(.enabled)
        var continuation: CheckedContinuation<Void, Never>?
        let manager = manager(service, try defaults(), stop: {
            await withCheckedContinuation { continuation = $0 }
        })
        let task = Task { await manager.disable() }
        let started = await AsyncTestWaiter.wait { continuation != nil }
        XCTAssertTrue(started)
        service.status = .notRegistered
        XCTAssertTrue(manager.requiresPreparation)
        do { try await manager.prepareForUpdate(); XCTFail() } catch {}
        continuation?.resume()
        await task.value
        XCTAssertFalse(manager.requiresPreparation)
    }

    func testConnectionFailureKeepsIntentForRetryAndSuccessfulManualDisableCancelsIt() async throws {
        let service = TestHelperRegistration(.enabled)
        let manager = manager(service, try defaults(), check: { throw DeviceHelperError.rejected("mismatch") })
        try await manager.prepareForUpdate()
        await manager.restoreAfterUpdate()
        XCTAssertEqual(manager.error, "mismatch")
        XCTAssertTrue(manager.requiresRestoration)
        await manager.disable()
        XCTAssertFalse(manager.requiresRestoration)
        await manager.restoreAfterUpdate()
        XCTAssertEqual(service.registers, 1)
    }
}

@MainActor
private final class TestHelperRegistration: DeviceHelperRegistering {
    var status: SMAppService.Status
    var registers = 0
    var unregisters = 0
    var registerError: Error?
    var unregisterError: Error?
    var registrationResult = SMAppService.Status.enabled
    init(_ status: SMAppService.Status) { self.status = status }
    func register() throws {
        registers += 1
        status = registrationResult
        if let registerError { throw registerError }
    }
    func unregister() async throws {
        unregisters += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }
}
