// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import XCTest
@testable import Capricorn

final class TopologyShortcutTests: XCTestCase {
    func testMShortcutMatchesPhysicalKeyAndCapsLockCharacters() {
        XCTAssertTrue(AppFeatureTabKeyRouter.matchesTopology(
            keyCode: 46, charactersIgnoringModifiers: nil, hasModifiers: false, isEditingText: false))
        XCTAssertTrue(AppFeatureTabKeyRouter.matchesTopology(
            charactersIgnoringModifiers: "m", hasModifiers: false, isEditingText: false))
        XCTAssertTrue(AppFeatureTabKeyRouter.matchesTopology(
            charactersIgnoringModifiers: "M", hasModifiers: false, isEditingText: false))
        XCTAssertFalse(AppFeatureTabKeyRouter.matchesTopology(
            charactersIgnoringModifiers: "n", hasModifiers: false, isEditingText: false))
    }

    func testMShortcutDoesNotConsumeTextOrModifiedKeys() {
        XCTAssertFalse(AppFeatureTabKeyRouter.matchesTopology(
            keyCode: 46, charactersIgnoringModifiers: "m", hasModifiers: false, isEditingText: true))
        XCTAssertFalse(AppFeatureTabKeyRouter.matchesTopology(
            keyCode: 46, charactersIgnoringModifiers: "m", hasModifiers: true, isEditingText: false))
    }

    @MainActor
    func testNativeMonitorConsumesMOnlyInItsWindowOutsideTextEditing() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var calls = 0
        let monitor = FeatureTabKeyMonitor.Coordinator(onOpenSettings: {}, onNext: {}, onOpenTopology: { calls += 1 })
        defer { monitor.invalidate() }
        monitor.window = window
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "m",
            charactersIgnoringModifiers: "m", isARepeat: false, keyCode: 46))
        XCTAssertNil(monitor.handle(event))
        XCTAssertEqual(calls, 1)

        let editor = NSTextView(frame: window.contentView!.bounds)
        window.contentView = editor
        XCTAssertTrue(window.makeFirstResponder(editor))
        XCTAssertNotNil(monitor.handle(event))
        XCTAssertEqual(calls, 1)

        editor.isEditable = false
        XCTAssertNil(monitor.handle(event))
        XCTAssertEqual(calls, 2)

        monitor.window = nil
        XCTAssertNotNil(monitor.handle(event))
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    func testTopologyShortcutKeepsSidebarSelectionAndIsIdempotent() {
        let model = AppModel()
        model.selectedDriveID = "disk8"
        model.selectedFeatureTab = .history
        model.selectTopologyFeatureTab()
        XCTAssertEqual(model.selectedFeatureTab, .topology)
        XCTAssertEqual(model.selectedDriveID, "disk8")
        model.selectTopologyFeatureTab()
        XCTAssertEqual(model.selectedFeatureTab, .topology)
        XCTAssertEqual(model.selectedDriveID, "disk8")
    }
}
