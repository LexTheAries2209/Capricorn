// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class AutomaticSNTTests: XCTestCase {
    private let suite = "AutomaticSNTTests.\(UUID())"

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    @MainActor
    private func model(service: AutomaticSNTTestService, refresh: AutomaticSNTTestRefresh) -> AppModel {
        let model = AppModel(refreshService: refresh, usbRawSmartService: service,
                             automaticSNTCache: AutomaticSNTCache(defaults: UserDefaults(suiteName: suite)!))
        let drive = AutomaticSNTCacheTests.drive()
        model.drives = [drive]
        model.snapshots[drive.id] = .unavailable(for: drive, reason: "Fixture")
        model.smartSelfTestCapabilities[drive.id] = .unavailable("Fixture")
        model.automaticSNTEnabled = true
        return model
    }

    @MainActor
    func testStartupReadsOnceAndReconnectUsesFreshCacheWithoutScheduledExpiryRead() async {
        let drive = AutomaticSNTCacheTests.drive()
        let service = AutomaticSNTTestService()
        let refresh = AutomaticSNTTestRefresh(drives: [drive])
        let model = model(service: service, refresh: refresh)
        model.selectedFeatureTab = .overview
        let now = Date()
        model.synchronizeAutomaticSNTConnections(now: now)
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(3))
        XCTAssertEqual(model.snapshots[drive.id]?.temperatureCelsius, 37)
        XCTAssertEqual(model.selectedFeatureTab, .overview)
        XCTAssertNil(model.usbRawSmartSession)
        XCTAssertFalse(model.isUSBRawSmartPresented)
        XCTAssertEqual(model.automaticSNTStatus(for: drive), .updated)
        await model.refresh()
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(100))
        var count = await service.readCount
        XCTAssertEqual(count, 1)

        await refresh.setDrives([])
        await model.refresh()
        await refresh.setDrives([drive])
        await model.refresh()
        await model.processAutomaticSNTQueue(now: Date().addingTimeInterval(5))
        count = await service.readCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.automaticSNTStatus(for: drive), .cached)
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(49 * 60 * 60))
        model.synchronizeAutomaticSNTConnections(now: now.addingTimeInterval(49 * 60 * 60))
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(49 * 60 * 60 + 3))
        count = await service.readCount
        XCTAssertEqual(count, 1, "Expiry alone must not start a read during the same connection.")
    }

    @MainActor
    func testBusyAndAuthorizationDeferralsDoNotConsumeFailuresOrBlacklist() async {
        let drive = AutomaticSNTCacheTests.drive()
        let service = AutomaticSNTTestService()
        let model = model(service: service, refresh: AutomaticSNTTestRefresh(drives: [drive]))
        let now = Date()
        model.synchronizeAutomaticSNTConnections(now: now)
        for (index, deferral) in [AutomaticSNTDeferral.busy, .occupancyUnknown, .needsAuthorization, .busy].enumerated() {
            await service.setDeferral(deferral)
            await model.processAutomaticSNTQueue(now: now.addingTimeInterval(Double(index * 60 + 3)))
        }
        let connection = model.automaticSNTConnections.values.first!
        XCTAssertFalse(connection.completed)
        let deferred = model.automaticSNTCache.record(for: drive, connectionKey: connection.id.uuidString)
        XCTAssertEqual(deferred?.consecutiveFailures, 0)
        XCTAssertEqual(deferred?.status, .retryable)
        await service.setDeferral(nil)
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(300))
        XCTAssertEqual(model.automaticSNTStatus(for: drive), .updated)
    }

    @MainActor
    func testThreeFailuresStopAcrossRestartAndManualSuccessOverrides() async {
        let drive = AutomaticSNTCacheTests.drive()
        let service = AutomaticSNTTestService()
        var failure = USBRawSmartTests.result(restored: true)
        failure.snapshot = nil
        await service.setResult(failure)
        let refresh = AutomaticSNTTestRefresh(drives: [drive])
        let model = model(service: service, refresh: refresh)
        let now = Date()
        model.synchronizeAutomaticSNTConnections(now: now)
        for seconds in [3.0, 40, 170, 400] {
            await model.processAutomaticSNTQueue(now: now.addingTimeInterval(seconds))
        }
        let count = await service.readCount
        XCTAssertEqual(count, 3)
        XCTAssertEqual(model.automaticSNTStatus(for: drive), .stopped)
        let restarted = self.model(service: service, refresh: refresh)
        restarted.synchronizeAutomaticSNTConnections(now: now)
        await restarted.processAutomaticSNTQueue(now: now.addingTimeInterval(500))
        let restartedCount = await service.readCount
        XCTAssertEqual(restartedCount, 3)
        await service.setResult(USBRawSmartTests.result(restored: true))
        restarted.requestUSBRawSmart(for: drive)
        await restarted.beginUSBRawSmart()
        XCTAssertEqual(restarted.automaticSNTStatus(for: drive), .updated)
        let record = restarted.automaticSNTCache.record(for: drive, connectionKey: "")
        XCTAssertEqual(record?.status, .available)
        XCTAssertEqual(record?.consecutiveFailures, 0)
        XCTAssertEqual(record?.preferredBridge, .realtek)
        let nextLaunch = self.model(service: service, refresh: refresh)
        nextLaunch.synchronizeAutomaticSNTConnections(now: now)
        await nextLaunch.processAutomaticSNTQueue(now: now.addingTimeInterval(600))
        let finalCount = await service.readCount
        XCTAssertEqual(finalCount, 4, "Manual success supplies a fresh cache for the next launch.")
        XCTAssertEqual(nextLaunch.automaticSNTStatus(for: drive), .cached)
        let expiredLaunch = self.model(service: service, refresh: refresh)
        expiredLaunch.synchronizeAutomaticSNTConnections(now: now.addingTimeInterval(49 * 60 * 60))
        await expiredLaunch.processAutomaticSNTQueue(now: now.addingTimeInterval(49 * 60 * 60 + 3))
        let expiredCount = await service.readCount
        XCTAssertEqual(expiredCount, 5, "Manual success must also clear the persistent stop.")
    }

    @MainActor
    func testReenumerationKeepsConnectionAndRestorationFailureStopsRetries() async {
        let original = AutomaticSNTCacheTests.drive()
        var renamed = original
        renamed.bsdName = "disk101"
        let refresh = AutomaticSNTTestRefresh(drives: [renamed])
        let service = AutomaticSNTTestService()
        let model = model(service: service, refresh: refresh)
        let now = Date()
        model.synchronizeAutomaticSNTConnections(now: now)
        let token = model.automaticSNTConnections.keys.first
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(3))
        await model.refresh()
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(100))
        XCTAssertEqual(model.automaticSNTConnections.keys.first, token)
        XCTAssertEqual(model.snapshots[renamed.id]?.temperatureCelsius, 37)
        let count = await service.readCount
        XCTAssertEqual(count, 1)

        let failureModel = self.model(service: service, refresh: AutomaticSNTTestRefresh(drives: [original]))
        await service.setResult(USBRawSmartTests.result(restored: false))
        let expired = now.addingTimeInterval(49 * 60 * 60)
        failureModel.synchronizeAutomaticSNTConnections(now: expired)
        await failureModel.processAutomaticSNTQueue(now: expired.addingTimeInterval(3))
        await failureModel.processAutomaticSNTQueue(now: expired.addingTimeInterval(300))
        XCTAssertEqual(failureModel.automaticSNTStatus(for: original), .recovery)
        let afterFailure = await service.readCount
        XCTAssertEqual(afterFailure, 2)
    }

    @MainActor
    func testDisabledAndConflictingWorkDoNotReadAndOldCacheKeepsItsTimestamp() async {
        let drive = AutomaticSNTCacheTests.drive()
        let service = AutomaticSNTTestService()
        let model = model(service: service, refresh: AutomaticSNTTestRefresh(drives: [drive]))
        let now = Date()
        var cached = AutomaticSNTRecord()
        cached.apply(USBRawSmartTests.result(restored: true), now: now)
        model.automaticSNTCache.store(cached, for: drive, connectionKey: "")
        model.synchronizeAutomaticSNTConnections(now: now)
        XCTAssertEqual(model.snapshots[drive.id]!.capturedAt.timeIntervalSince1970,
                       cached.lastSnapshot!.capturedAt.timeIntervalSince1970, accuracy: 0.001)
        model.automaticSNTEnabled = false
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(5))
        model.automaticSNTEnabled = true
        model.isBenchmarking = true
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(5))
        let count = await service.readCount
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testFreshCacheSkipsStartupAndManualReadStillUpdatesIt() async {
        let drive = AutomaticSNTCacheTests.drive()
        let service = AutomaticSNTTestService()
        let model = model(service: service, refresh: AutomaticSNTTestRefresh(drives: [drive]))
        let now = Date()
        var result = USBRawSmartTests.result(restored: true)
        result.snapshot?.capturedAt = now.addingTimeInterval(-47 * 60 * 60)
        var record = AutomaticSNTRecord()
        record.apply(result, now: now)
        model.automaticSNTCache.store(record, for: drive, connectionKey: "")
        model.synchronizeAutomaticSNTConnections(now: now)
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(3))
        let count = await service.readCount
        XCTAssertEqual(count, 0)
        XCTAssertEqual(model.automaticSNTStatus(for: drive), .cached)
        XCTAssertEqual(model.snapshots[drive.id]?.capturedAt, result.snapshot?.capturedAt)

        model.requestUSBRawSmart(for: drive)
        await model.beginUSBRawSmart()
        let manualCount = await service.readCount
        XCTAssertEqual(manualCount, 1)
        XCTAssertEqual(model.automaticSNTStatus(for: drive), .updated)
        let updated = model.automaticSNTCache.record(for: drive, connectionKey: "")
        XCTAssertGreaterThan(updated!.lastSnapshot!.capturedAt, result.snapshot!.capturedAt)
        XCTAssertTrue(updated!.hasFreshSnapshot(now: Date()))
    }

    @MainActor
    func testExpiredCacheAttemptsReadAndRetainsPreviousDataAfterFailure() async {
        let drive = AutomaticSNTCacheTests.drive()
        let service = AutomaticSNTTestService()
        let model = model(service: service, refresh: AutomaticSNTTestRefresh(drives: [drive]))
        let now = Date()
        var result = USBRawSmartTests.result(restored: true)
        result.snapshot?.capturedAt = now.addingTimeInterval(-48 * 60 * 60)
        var record = AutomaticSNTRecord()
        record.apply(result, now: now)
        model.automaticSNTCache.store(record, for: drive, connectionKey: "")
        var failure = result
        failure.snapshot = nil
        await service.setResult(failure)

        model.synchronizeAutomaticSNTConnections(now: now)
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(3))

        let count = await service.readCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.automaticSNTStatus(for: drive), .retrying)
        XCTAssertEqual(model.snapshots[drive.id]?.capturedAt, result.snapshot?.capturedAt)
        XCTAssertEqual(model.snapshots[drive.id]?.temperatureCelsius, 37)
        let failed = model.automaticSNTCache.record(for: drive, connectionKey: "")
        XCTAssertEqual(failed?.lastSnapshot?.capturedAt, result.snapshot?.capturedAt)
        XCTAssertFalse(failed!.hasFreshSnapshot(now: now))
    }

    @MainActor
    func testOrdinarySMARTSkipsSNTButUnsupportedStatusStringDoesNot() {
        var drive = AutomaticSNTCacheTests.drive()
        let service = AutomaticSNTTestService()
        let model = model(service: service, refresh: AutomaticSNTTestRefresh(drives: [drive]))
        model.snapshots[drive.id] = CapricornTests.fixtureSnapshot(for: drive)
        model.synchronizeAutomaticSNTConnections()
        XCTAssertTrue(model.automaticSNTConnections.isEmpty)
        drive.smartStatusRaw = "Not Supported"
        model.drives = [drive]
        model.snapshots[drive.id] = .unavailable(for: drive, reason: "Unavailable")
        model.synchronizeAutomaticSNTConnections()
        XCTAssertEqual(model.automaticSNTConnections.count, 1)
    }

    @MainActor
    func testReplacementMediaInSameEnclosureNeverReceivesPriorReading() async {
        let original = AutomaticSNTCacheTests.drive()
        var replacement = original
        replacement.volumes[0].volumeUUID = "REPLACEMENT-MEDIA"
        let service = AutomaticSNTTestService()
        let model = model(service: service, refresh: AutomaticSNTTestRefresh(drives: [replacement]))
        let now = Date()
        model.synchronizeAutomaticSNTConnections(now: now)
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(3))
        XCTAssertNil(model.snapshots[replacement.id]?.temperatureCelsius)
        XCTAssertEqual(model.automaticSNTStatus(for: replacement), .recovery)
    }

    @MainActor
    func testDisappearingTargetDoesNotBlockAnotherQueuedDisk() async {
        let drive = AutomaticSNTCacheTests.drive()
        var second = drive
        second.bsdName = "disk102"
        second.serialNumber = "SECOND"
        second.volumes[0].volumeUUID = "SECOND-MEDIA"
        let service = AutomaticSNTTestService()
        let model = model(service: service, refresh: AutomaticSNTTestRefresh(drives: [drive, second]))
        model.drives = [drive, second]
        model.snapshots[second.id] = .unavailable(for: second, reason: "Fixture")
        model.smartSelfTestCapabilities[second.id] = .unavailable("Fixture")
        let now = Date()
        model.synchronizeAutomaticSNTConnections(now: now)
        let token = model.automaticSNTConnections.values.first { $0.drive.id == drive.id }!.id
        model.automaticSNTConnections[token]?.target = .init(registryID: 1)
        model.automaticSNTConnections[token]?.nextAttempt = now
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(3))
        await model.processAutomaticSNTQueue(now: now.addingTimeInterval(3))
        let count = await service.readCount
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.automaticSNTStatus(for: second), .updated)
    }
}

private actor AutomaticSNTTestService: USBRawSmartRunning {
    private(set) var readCount = 0
    private var result = USBRawSmartTests.result(restored: true)
    private var deferral: AutomaticSNTDeferral?
    nonisolated func target(for drive: DriveDevice) throws -> USBRawSmartTarget {
        .init(registryID: drive.bsdName == "disk101" ? 101 : USBRawSmartTests.target.registryID)
    }
    func setResult(_ result: USBRawSmartResult) { self.result = result }
    func setDeferral(_ deferral: AutomaticSNTDeferral?) { self.deferral = deferral }
    func read(drive: DriveDevice, target: USBRawSmartTarget) async throws -> USBRawSmartResult {
        readCount += 1
        return result
    }
    func readAutomatically(
        drive: DriveDevice, target: USBRawSmartTarget, preferredBridge: SNTBridge?
    ) async throws -> USBRawSmartResult {
        if let deferral { throw deferral }
        return try await read(drive: drive, target: target)
    }
}

private actor AutomaticSNTTestRefresh: DriveRefreshing {
    var drives: [DriveDevice]
    init(drives: [DriveDevice]) { self.drives = drives }
    func setDrives(_ drives: [DriveDevice]) { self.drives = drives }
    func discover() async throws -> DriveRefreshSnapshot { .init(drives: drives, snapshots: [:]) }
    func snapshotUpdates(for drives: [DriveDevice]) async -> AsyncStream<DriveSnapshotUpdate> {
        AsyncStream { continuation in
            for drive in drives {
                continuation.yield(.init(driveID: drive.id, snapshot: .unavailable(for: drive, reason: "Fixture"),
                                         phase: .complete))
            }
            continuation.finish()
        }
    }
}
