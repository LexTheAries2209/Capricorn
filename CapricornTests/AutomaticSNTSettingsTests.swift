// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ServiceManagement
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
    func testRenderAutomaticSettingsAndStatusesInBothLanguages() async throws {
        let suite = "AutomaticSNTSettingsTests.render.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        for language in AppLanguage.allCases {
            preferences.languageRawValue = language.rawValue
            let service = SNTSettingsRegistration(status: .notRegistered)
            let manager = DeviceHelperServiceManager(
                registration: service, defaults: defaults, validateInstallation: { "TEAM" }, checkConnection: {})
            manager.refresh()
            let root = Form {
                Section(language.t("Disk Actions")) {
                    AutomaticSNTSettingsControls(preferences: preferences, serviceManager: manager)
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

    @MainActor
    func testRenderWarningsAcrossServiceHealthChangesInBothLanguages() async throws {
        let suite = "AutomaticSNTSettingsTests.serviceHealth.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for language in AppLanguage.allCases {
            let preferences = AppPreferences(defaults: defaults)
            preferences.languageRawValue = language.rawValue
            preferences.automaticSNT = false
            let service = SNTSettingsRegistration(status: .notRegistered)
            var connectionFails = true
            let manager = DeviceHelperServiceManager(
                registration: service, defaults: defaults, validateInstallation: { "TEAM" },
                checkConnection: {
                    if connectionFails { throw DeviceHelperError.rejected("version mismatch") }
                })
            manager.refresh()
            let root = Form {
                AutomaticSNTSettingsControls(preferences: preferences, serviceManager: manager)
            }
            .formStyle(.grouped)
            .frame(width: 660, height: 120)
            let view = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 120),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            view.layoutSubtreeIfNeeded()

            for expected in [DeviceHelperAvailability.notEnabled, .unhealthy, .available] {
                if expected != .notEnabled {
                    service.status = .enabled
                    connectionFails = expected == .unhealthy
                    manager.refresh()
                }
                let settled = await AsyncTestWaiter.wait {
                    view.layoutSubtreeIfNeeded()
                    return manager.availability == expected
                }
                XCTAssertTrue(settled, "\(language): \(expected)")
                try await Task.sleep(for: .milliseconds(100))
                view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let url = URL(fileURLWithPath: "/tmp/capricorn-snt-service-\(language.rawValue)-\(expected).png")
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
                add(XCTAttachment(contentsOfFile: url))
            }
            preferences.automaticSNT = true
            service.status = .notRegistered
            manager.refresh()
            XCTAssertEqual(manager.availability, .notEnabled)
            XCTAssertTrue(preferences.automaticSNT, "Unavailable service pauses the saved choice without clearing it.")
        }
        XCTAssertEqual(AppLanguage.simplifiedChinese.t(
            "Enable the device service in Settings before using automatic SNT reads."),
                       "请先在设置启用设备服务，否则无法自动读取SNT")
        XCTAssertEqual(AppLanguage.simplifiedChinese.t(
            "The privileged device service is not working. Disable and re-enable it."),
                       "特权设备服务状态不正常，请关闭再重新启用设备服务")
    }
}

@MainActor
private final class SNTSettingsRegistration: DeviceHelperRegistering {
    var status: SMAppService.Status
    init(status: SMAppService.Status) { self.status = status }
    func register() throws { status = .enabled }
    func unregister() async throws { status = .notRegistered }
}
