// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class AutomaticSNTCacheTests: XCTestCase {
    static func drive() -> DriveDevice {
        var drive = USBRawSmartTests.drive()
        drive.volumes = [.init(deviceIdentifier: "disk99s1", name: "Data", mountPoint: "/Volumes/Data",
                               sizeBytes: drive.sizeBytes, isWritable: true, isSystem: false,
                               volumeUUID: "TEST-MEDIA-UUID")]
        return drive
    }

    func testThreeFailuresPersistAndManualSuccessReplacesStopAndRetainsOnlyLatestSnapshot() throws {
        let suite = "AutomaticSNTCacheTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = AutomaticSNTCache(defaults: defaults)
        let drive = Self.drive()
        XCTAssertNotNil(AutomaticSNTCache.identityKey(for: drive))
        var record = AutomaticSNTRecord()
        var failed = USBRawSmartTests.result(restored: true)
        failed.snapshot = nil
        for count in 1...3 {
            record.apply(failed, now: Date())
            XCTAssertEqual(record.consecutiveFailures, count)
        }
        cache.store(record, for: drive, connectionKey: "connection")
        let reopened = AutomaticSNTCache(defaults: defaults)
        XCTAssertEqual(reopened.record(for: drive, connectionKey: "new")?.status, .stopped)
        record.apply(USBRawSmartTests.result(restored: true), now: Date())
        cache.store(record, for: drive, connectionKey: "connection")
        XCTAssertEqual(reopened.record(for: drive, connectionKey: "new")?.status, .available)
        XCTAssertEqual(reopened.record(for: drive, connectionKey: "new")?.consecutiveFailures, 0)
        XCTAssertEqual(reopened.record(for: drive, connectionKey: "new")?.preferredBridge, .realtek)
        XCTAssertEqual(reopened.record(for: drive, connectionKey: "new")?.lastSnapshot?.temperatureCelsius, 37)
    }

    func testExhaustedProtocolsStopImmediatelyButBusyNeverConsumesBudget() {
        var record = AutomaticSNTRecord()
        var failed = USBRawSmartTests.result(restored: true)
        failed.snapshot = nil
        failed.attemptedBridges = SNTBridge.allCases
        failed.unmountBusy = true
        record.apply(failed, now: Date())
        XCTAssertEqual(record.consecutiveFailures, 0)
        XCTAssertEqual(record.status, .retryable)
        failed.unmountBusy = false
        record.apply(failed, now: Date())
        XCTAssertEqual(record.status, .stopped)
        XCTAssertEqual(record.consecutiveFailures, 1)
    }

    func testIncompleteRestorationPausesEvenWithValidSMARTAndKeepsOldSnapshot() {
        var record = AutomaticSNTRecord()
        record.apply(USBRawSmartTests.result(restored: true), now: Date())
        let previous = record.lastSnapshot?.id
        record.apply(USBRawSmartTests.result(restored: false), now: Date())
        XCTAssertEqual(record.status, .needsRecovery)
        XCTAssertEqual(record.consecutiveFailures, 0)
        XCTAssertEqual(record.lastSnapshot?.id, previous)
    }

    func testIdentityIncludesMediaAndBridgeButIgnoresBSDNumber() {
        let drive = Self.drive()
        let key = AutomaticSNTCache.identityKey(for: drive)
        var changed = drive
        changed.bsdName = "disk101"
        XCTAssertEqual(key, AutomaticSNTCache.identityKey(for: changed))
        changed.volumes[0].volumeUUID = "NEW-MEDIA"
        XCTAssertNotEqual(key, AutomaticSNTCache.identityKey(for: changed))
        changed = drive
        changed.usbDevice = .init(vendorName: nil, productName: nil, vendorID: 123, productID: 456)
        XCTAssertNotEqual(key, AutomaticSNTCache.identityKey(for: changed))
        changed = drive
        for index in changed.volumes.indices { changed.volumes[index].volumeUUID = nil }
        XCTAssertNil(AutomaticSNTCache.identityKey(for: changed), "An enclosure serial alone cannot identify inserted media.")
    }
}
