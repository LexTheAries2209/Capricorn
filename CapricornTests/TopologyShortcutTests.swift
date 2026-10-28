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

    func testZShortcutMatchesPhysicalKeyAndProtectsTextAndUndo() {
        XCTAssertTrue(AppFeatureTabKeyRouter.matchesTopologyReset(
            keyCode: 6, charactersIgnoringModifiers: nil, hasModifiers: false, isEditingText: false))
        XCTAssertTrue(AppFeatureTabKeyRouter.matchesTopologyReset(
            charactersIgnoringModifiers: "Z", hasModifiers: false, isEditingText: false))
        XCTAssertFalse(AppFeatureTabKeyRouter.matchesTopologyReset(
            charactersIgnoringModifiers: "z", hasModifiers: false, isEditingText: true))
        XCTAssertFalse(AppFeatureTabKeyRouter.matchesTopologyReset(
            keyCode: 6, charactersIgnoringModifiers: "z", hasModifiers: true, isEditingText: false))
        XCTAssertFalse(AppFeatureTabKeyRouter.matchesTopologyReset(
            charactersIgnoringModifiers: "x", hasModifiers: false, isEditingText: false))
    }

    func testTopologyZoomShortcutsMatchMinusPlusAndKeypadKeys() {
        XCTAssertTrue(AppFeatureTabKeyRouter.matchesTopologyZoomOut(
            keyCode: 27, charactersIgnoringModifiers: "-", hasShift: false,
            hasDisqualifyingModifiers: false, isEditingText: false))
        XCTAssertTrue(AppFeatureTabKeyRouter.matchesTopologyZoomOut(
            keyCode: 78, charactersIgnoringModifiers: nil, hasShift: false,
            hasDisqualifyingModifiers: false, isEditingText: false))
        XCTAssertTrue(AppFeatureTabKeyRouter.matchesTopologyZoomIn(
            keyCode: 24, charactersIgnoringModifiers: "=", hasShift: true,
            hasDisqualifyingModifiers: false, isEditingText: false))
        XCTAssertTrue(AppFeatureTabKeyRouter.matchesTopologyZoomIn(
            keyCode: 69, charactersIgnoringModifiers: nil, hasShift: false,
            hasDisqualifyingModifiers: false, isEditingText: false))
    }

    func testTopologyZoomShortcutsDoNotStealTextOrModifiedShortcuts() {
        XCTAssertFalse(AppFeatureTabKeyRouter.matchesTopologyZoomOut(
            charactersIgnoringModifiers: "-", hasShift: false,
            hasDisqualifyingModifiers: false, isEditingText: true))
        XCTAssertFalse(AppFeatureTabKeyRouter.matchesTopologyZoomOut(
            charactersIgnoringModifiers: "-", hasShift: true,
            hasDisqualifyingModifiers: false, isEditingText: false))
        XCTAssertFalse(AppFeatureTabKeyRouter.matchesTopologyZoomIn(
            keyCode: 24, charactersIgnoringModifiers: "=", hasShift: true,
            hasDisqualifyingModifiers: true, isEditingText: false))
        XCTAssertFalse(AppFeatureTabKeyRouter.matchesTopologyZoomIn(
            keyCode: 24, charactersIgnoringModifiers: "=", hasShift: true,
            hasDisqualifyingModifiers: false, isEditingText: true))
    }

    @MainActor
    func testNativeZMonitorConsumesOnlyWhenTopologyHandlesReset() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var topologyIsActive = false
        var resets = 0
        let monitor = FeatureTabKeyMonitor.Coordinator(onOpenSettings: {}, onNext: {}, onOpenTopology: {},
                                                       onResetTopology: {
            guard topologyIsActive else { return false }
            resets += 1
            return true
        })
        defer { monitor.invalidate() }
        monitor.window = window
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "z",
            charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
        XCTAssertNotNil(monitor.handle(event))
        topologyIsActive = true
        XCTAssertNil(monitor.handle(event))
        XCTAssertEqual(resets, 1)

        let editor = NSTextView(frame: window.contentView!.bounds)
        window.contentView = editor
        XCTAssertTrue(window.makeFirstResponder(editor))
        XCTAssertNotNil(monitor.handle(event))
        XCTAssertEqual(resets, 1)
        monitor.window = nil
        XCTAssertNotNil(monitor.handle(event))
        XCTAssertEqual(resets, 1)
    }

    @MainActor
    func testNativeZoomMonitorConsumesPlusAndMinusOnlyOnTopologyPage() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var topologyIsActive = false
        var zoomIns = 0
        var zoomOuts = 0
        let monitor = FeatureTabKeyMonitor.Coordinator(
            onOpenSettings: {},
            onNext: {},
            onOpenTopology: {},
            onZoomInTopology: {
                guard topologyIsActive else { return false }
                zoomIns += 1
                return true
            },
            onZoomOutTopology: {
                guard topologyIsActive else { return false }
                zoomOuts += 1
                return true
            }
        )
        defer { monitor.invalidate() }
        monitor.window = window
        let minus = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "-",
            charactersIgnoringModifiers: "-", isARepeat: false, keyCode: 27))
        let plus = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "+",
            charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24))

        XCTAssertNotNil(monitor.handle(minus))
        XCTAssertNotNil(monitor.handle(plus))
        XCTAssertEqual(zoomIns, 0)
        XCTAssertEqual(zoomOuts, 0)

        topologyIsActive = true
        XCTAssertNil(monitor.handle(minus))
        XCTAssertNil(monitor.handle(plus))
        XCTAssertEqual(zoomIns, 1)
        XCTAssertEqual(zoomOuts, 1)

        let editor = NSTextView(frame: window.contentView!.bounds)
        window.contentView = editor
        XCTAssertTrue(window.makeFirstResponder(editor))
        XCTAssertNotNil(monitor.handle(minus))
        XCTAssertNotNil(monitor.handle(plus))
        XCTAssertEqual(zoomIns, 1)
        XCTAssertEqual(zoomOuts, 1)
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
