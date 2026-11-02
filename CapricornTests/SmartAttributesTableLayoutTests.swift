// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import XCTest
@testable import Capricorn

final class SmartAttributesTableLayoutTests: XCTestCase {
    @MainActor
    func testNVMeColumnsRemainResizableAndReachableAfterWideningAndRestoringWindow() async throws {
        for language in AppLanguage.allCases {
            try await checkLayout(normalized: false, language: language)
        }
    }

    @MainActor
    func testATAColumnsRemainResizableAndReachableAfterWideningAndRestoringWindow() async throws {
        for language in AppLanguage.allCases {
            try await checkLayout(normalized: true, language: language)
        }
    }

    @MainActor
    private func checkLayout(normalized: Bool, language: AppLanguage) async throws {
        let drive = CapricornTests.fixtureDrive()
        var snapshot = CapricornTests.fixtureSnapshot(for: drive)
        snapshot.attributes = [SmartAttribute(
            id: "AVAILABLE_SPARE_THRESHOLD", name: "Available Spare Threshold", rawValue: "99%",
            current: normalized ? 100 : nil, worst: normalized ? 99 : nil,
            threshold: normalized ? 10 : nil, status: .good, source: "Native macOS"
        )]
        let page = SmartAttributesView(
            drive: drive, snapshot: snapshot, viewModel: AppModel(), selfTestHistory: [],
            saveSnapshot: { _ in "" }, exportSelfTestHistory: { _, _, _ in "" },
            exportErrorLog: { _, _, _ in "" }, satDriverGuidance: nil, openSATDriverSettings: {}
        )
        let hostingView = NSHostingView(rootView: page.environment(\.appLanguage, language))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_100, height: 500),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        hostingView.layoutSubtreeIfNeeded()

        let table = try XCTUnwrap(findTable(in: hostingView))
        let scroll = try XCTUnwrap(table.enclosingScrollView)
        XCTAssertEqual(table.tableColumns.count, normalized ? 8 : 5)
        XCTAssertTrue(scroll.hasHorizontalScroller)
        XCTAssertFalse(scroll.autohidesScrollers)
        XCTAssertEqual(table.columnAutoresizingStyle, .noColumnAutoresizing)
        for column in table.tableColumns {
            XCTAssertGreaterThan(column.minWidth, 0)
            XCTAssertLessThanOrEqual(column.maxWidth, 560)
            if column.title == language.t("Status") {
                XCTAssertEqual(column.width, 82, accuracy: 1)
                XCTAssertEqual(column.minWidth, 82, accuracy: 1)
                XCTAssertEqual(column.maxWidth, 82, accuracy: 1)
                XCTAssertFalse(column.resizingMask.contains(.userResizingMask))
            } else {
                XCTAssertGreaterThan(column.maxWidth, column.minWidth)
                XCTAssertTrue(column.resizingMask.contains(.userResizingMask), column.title)
            }
        }
        let source = try XCTUnwrap(table.tableColumns.last)
        XCTAssertGreaterThanOrEqual(source.width, source.minWidth)
        source.width = 220
        XCTAssertEqual(source.width, 220, accuracy: 1)

        // Reproduce an oversized leading column, then shrink and restore the window.
        for column in table.tableColumns {
            column.width = column.maxWidth
        }
        table.tile()
        let resizedWidths = table.tableColumns.map(\.width)
        for width: CGFloat in [650, 1_100] {
            window.setContentSize(NSSize(width: width, height: 500))
            try await Task.sleep(for: .milliseconds(150))
            hostingView.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(table.bounds.width, scroll.contentSize.width)
            table.scrollColumnToVisible(table.tableColumns.count - 1)
            let sourceRect = table.rect(ofColumn: table.tableColumns.count - 1)
            XCTAssertGreaterThan(scroll.contentView.bounds.minX, 0)
            XCTAssertLessThanOrEqual(sourceRect.maxX, table.visibleRect.maxX + 1)
            XCTAssertGreaterThanOrEqual(source.width, source.minWidth)
            XCTAssertEqual(table.tableColumns.map(\.width), resizedWidths)
        }
    }

    @MainActor
    private func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { self.findTable(in: $0) }.first
    }
}
