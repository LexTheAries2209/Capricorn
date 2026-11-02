// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import XCTest
@testable import Capricorn

final class AutomaticSNTSettingsTests: XCTestCase {
    @MainActor
    func testPreferenceDefaultsOffPersistsAndResetPreservesSNTCache() throws {
        let suite = "AutomaticSNTSettingsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.automaticSNT)
        preferences.automaticSNT = true
        XCTAssertTrue(AppPreferences(defaults: defaults).automaticSNT)
        let cache = AutomaticSNTCache(defaults: defaults)
        cache.store(.init(status: .stopped, consecutiveFailures: 3),
                    for: AutomaticSNTCacheTests.drive(), connectionKey: "")
        preferences.resetAllSettings()
        XCTAssertFalse(preferences.automaticSNT)
        XCTAssertFalse(AppPreferences(defaults: defaults).automaticSNT)
        XCTAssertEqual(cache.record(for: AutomaticSNTCacheTests.drive(), connectionKey: "")?.status, .stopped)
    }

    @MainActor
    func testRenderAutomaticSettingsAndStatusesInBothLanguages() throws {
        let suite = "AutomaticSNTSettingsTests.render.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        for language in AppLanguage.allCases {
            preferences.languageRawValue = language.rawValue
            let root = Form {
                Section(language.t("Disk Actions")) {
                    AutomaticSNTSettingsControls(preferences: preferences)
                }
                Section("SNT") {
                    ForEach([
                        AutomaticSNTStatus.waiting, .reading, .updated, .busy, .occupancyUnknown,
                        .authorization, .retrying, .stopped, .recovery
                    ], id: \.rawValue) { status in
                        Text(language.t(status.rawValue)).font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 660, height: 650)
            let view = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 650),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            window.appearance = NSAppearance(named: .aqua)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = URL(fileURLWithPath: "/tmp/capricorn-automatic-snt-\(language.rawValue).png")
            try data.write(to: url)
            add(XCTAttachment(contentsOfFile: url))
            window.orderOut(nil)
        }
    }
}
