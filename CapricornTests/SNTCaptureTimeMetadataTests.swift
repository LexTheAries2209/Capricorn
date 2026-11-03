// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import XCTest
@testable import Capricorn

final class SNTCaptureTimeMetadataTests: XCTestCase {
    func testCaptureTimeIsDisplayMetadataAndDoesNotChangeHealthOrPayload() throws {
        let snapshot = try XCTUnwrap(USBRawSmartTests.result(restored: true).snapshot)
        let rows = snapshot.attributesWithSNTCaptureTime
        let timestamp = try XCTUnwrap(rows.last)
        XCTAssertTrue(SNTCaptureTimeMetadata.isCaptureTime(timestamp))
        XCTAssertEqual(rows.count, snapshot.attributes.count + 1)
        XCTAssertEqual(Array(rows.dropLast()), snapshot.attributes)
        XCTAssertNil(timestamp.current)
        XCTAssertNil(timestamp.worst)
        XCTAssertNil(timestamp.threshold)
        XCTAssertEqual(timestamp.status, .unavailable)
        XCTAssertFalse(snapshot.attributes.contains(where: SNTCaptureTimeMetadata.isCaptureTime))
        for language in AppLanguage.allCases {
            XCTAssertEqual(language.smartAttributeDisplay(timestamp).title,
                           language == .english ? "Captured At" : "采集时间")
        }
        var ordinary = snapshot
        ordinary.selectedProvider = "smartctl"
        XCTAssertEqual(ordinary.attributesWithSNTCaptureTime, ordinary.attributes)
        var unavailable = SmartSnapshot.unavailable(for: USBRawSmartTests.drive(), reason: "Fixture")
        unavailable.selectedProvider = USBRawSmartService.providerName
        XCTAssertTrue(unavailable.attributesWithSNTCaptureTime.isEmpty)
        XCTAssertFalse(unavailable.hasSMARTPayload)
    }

    @MainActor
    func testHistoryAndCSVKeepOriginalCaptureTimeWithoutDuplicateExportRow() throws {
        let drive = USBRawSmartTests.drive()
        var snapshot = try XCTUnwrap(USBRawSmartTests.result(restored: true).snapshot)
        snapshot.capturedAt = Date(timeIntervalSince1970: 1_793_635_200)
        let saved = SmartHistoryRecord(drive: drive, snapshot: snapshot)
        let restored = try XCTUnwrap(saved.snapshot)
        XCTAssertEqual(saved.capturedAt, snapshot.capturedAt)
        XCTAssertEqual(restored.capturedAt, snapshot.capturedAt)
        XCTAssertEqual(restored.attributesWithSNTCaptureTime, snapshot.attributesWithSNTCaptureTime)
        let parsed = try XCTUnwrap(restored.attributesWithSNTCaptureTime.last?.rawValue)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        XCTAssertEqual(formatter.date(from: parsed), snapshot.capturedAt)
        for language in AppLanguage.allCases {
            let csv = ReportExporter.smartSnapshotCSVReport(drive: drive, snapshot: restored, language: language)
            XCTAssertEqual(csv.split(separator: "\n").filter { $0.hasPrefix("captured_at,") }.count, 1)
            XCTAssertTrue(csv.contains(ISO8601DateFormatter().string(from: snapshot.capturedAt)))
        }
    }

    @MainActor
    func testRenderCaptureTimeInBothLanguages() async throws {
        let drive = USBRawSmartTests.drive()
        var snapshot = try XCTUnwrap(USBRawSmartTests.result(restored: true).snapshot)
        snapshot.capturedAt = Date(timeIntervalSince1970: 1_793_635_200)
        for language in AppLanguage.allCases {
            let page = SmartAttributesView(
                drive: drive, snapshot: snapshot, viewModel: AppModel(), selfTestHistory: [],
                saveSnapshot: { _ in "" }, exportSelfTestHistory: { _, _, _ in "" },
                exportErrorLog: { _, _, _ in "" }, satDriverGuidance: nil, openSATDriverSettings: {}
            )
            let view = NSHostingView(rootView: page.environment(\.appLanguage, language).padding(20))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_300, height: 720),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.contentView = view
            window.appearance = NSAppearance(named: .aqua)
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(200))
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: "/tmp/capricorn-snt-capture-time-\(language.rawValue).png")
            try data.write(to: url)
            add(XCTAttachment(contentsOfFile: url))
        }
    }
}
