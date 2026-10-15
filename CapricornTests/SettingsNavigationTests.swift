// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Capricorn

final class SettingsNavigationTests: XCTestCase {
    @MainActor
    func testUpdatesDestinationReturnsOpenSettingsToTopOnRepeatedRequests() async throws {
        let suiteName = "CapricornTests.settingsNavigation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.requestedSettingsDestination = .updates
        let checker = AppUpdateChecker(fetchLatest: { throw URLError(.notConnectedToInternet) })
        let root = CapricornSettingsView(preferences: preferences, updateChecker: checker)
            .modelContainer(try ModelContainerFactory.makeInMemory())
        let hostingView = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        let appeared = await AsyncTestWaiter.wait { preferences.requestedSettingsDestination == nil }
        XCTAssertTrue(appeared)
        try await Task.sleep(for: .milliseconds(350))
        hostingView.layoutSubtreeIfNeeded()
        let scrollView = try XCTUnwrap(findScrollView(in: hostingView))
        let topOffset = scrollView.contentView.bounds.minY

        // Route away and back twice without recreating the settings window.
        for _ in 0..<2 {
            preferences.requestedSettingsDestination = .satSMARTDriver
            let scrolledDown = await AsyncTestWaiter.wait {
                preferences.requestedSettingsDestination == nil
                    && scrollView.contentView.bounds.minY > topOffset + 100
            }
            XCTAssertTrue(scrolledDown, "Expected lower section; offset \(scrollView.contentView.bounds.minY), top \(topOffset)")

            preferences.requestedSettingsDestination = .updates
            let returnedToTop = await AsyncTestWaiter.wait {
                preferences.requestedSettingsDestination == nil
                    && abs(scrollView.contentView.bounds.minY - topOffset) < 2
            }
            XCTAssertTrue(returnedToTop, "Expected updates at top; offset \(scrollView.contentView.bounds.minY), top \(topOffset)")
        }
    }

    @MainActor
    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }
}
