// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI
import Vision
import XCTest
@testable import Capricorn

final class DeveloperSettingsTests: XCTestCase {
    @MainActor
    func testSidebarAddVirtualDiskRequiresBothDeveloperSwitchesInBothLanguages() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Sidebar screenshots require Screen Recording permission.")
        }
        let suiteName = "CapricornTests.virtualDiskEntry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: AppPreferences.Key.legacyShowVirtualDisks)
        let preferences = AppPreferences(defaults: defaults)
        let model = AppModel()
        let drive = CapricornTests.fixtureDrive()
        model.drives = [drive]
        model.selectedDriveID = drive.id
        model.snapshots = [drive.id: CapricornTests.fixtureSnapshot(for: drive)]
        let root = ContentView(viewModel: model, preferences: preferences)
            .modelContainer(try ModelContainerFactory.makeInMemory())
        let hostingView = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_433, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.contentView = hostingView
        window.appearance = NSAppearance(named: .aqua)
        window.center()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        for language in AppLanguage.allCases {
            preferences.languageRawValue = language.rawValue
            for (developer, virtualDisks) in [(false, false), (false, true), (true, false), (true, true), (false, true)] {
                preferences.enablesDeveloperOptions = developer
                preferences.enablesVirtualDisks = virtualDisks
                try await Task.sleep(nanoseconds: 300_000_000)
                hostingView.layoutSubtreeIfNeeded()
                let url = URL(fileURLWithPath: "/tmp/Capricorn-virtual-disk-entry-\(language.rawValue)-\(developer)-\(virtualDisks).png")
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", url.path]
                try capture.run()
                capture.waitUntilExit()
                XCTAssertEqual(capture.terminationStatus, 0)
                let image = try XCTUnwrap(NSImage(contentsOf: url)?.cgImage(
                    forProposedRect: nil, context: nil, hints: nil
                ))
                let attachment = XCTAttachment(contentsOfFile: url)
                attachment.lifetime = .keepAlways
                add(attachment)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                try VNImageRequestHandler(cgImage: image).perform([request])
                // Vision can recognize the small Simplified Chinese glyph as its traditional form.
                let lines = (request.results ?? []).compactMap {
                    $0.topCandidates(1).first?.string.replacingOccurrences(of: "虛", with: "虚")
                }
                XCTAssertEqual(
                    lines.contains { $0.contains(language.t("Add virtual disk")) },
                    developer && virtualDisks,
                    "\(language): \(lines)"
                )
                XCTAssertFalse(lines.contains { $0.contains("Show virtual disks") || $0.contains("显示虚拟硬盘") })
                XCTAssertEqual(model.drives.map(\.id), [drive.id])
                XCTAssertFalse(model.isRefreshing)
            }
        }
    }

    @MainActor
    func testDeveloperSettingsRevealChildSwitchesInBothLanguages() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Developer settings screenshots require Screen Recording permission.")
        }
        let suiteName = "CapricornTests.developerSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let root = Form {
            DeveloperSettingsSection(preferences: preferences)
        }
        .formStyle(.grouped)
        .padding(20)
        let hostingView = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hostingView
        window.appearance = NSAppearance(named: .aqua)
        window.center()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        for language in AppLanguage.allCases {
            preferences.languageRawValue = language.rawValue
            for enabled in [false, true] {
                preferences.enablesDeveloperOptions = enabled
                try await Task.sleep(nanoseconds: 300_000_000)
                hostingView.layoutSubtreeIfNeeded()
                let captureURL = URL(fileURLWithPath: "/tmp/Capricorn-developer-settings-\(language.rawValue)-\(enabled).png")
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", captureURL.path]
                try capture.run()
                capture.waitUntilExit()
                XCTAssertEqual(capture.terminationStatus, 0)
                let image = try XCTUnwrap(NSImage(contentsOf: captureURL)?.cgImage(
                    forProposedRect: nil, context: nil, hints: nil
                ))
                let attachment = XCTAttachment(contentsOfFile: captureURL)
                attachment.lifetime = .keepAlways
                add(attachment)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                try VNImageRequestHandler(cgImage: image).perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                XCTAssertTrue(lines.contains { $0.contains(language.t("Enable developer options")) }, "\(lines)")
                for title in ["Enable custom benchmark configuration", "Allow adding virtual disks", "Show build number"] {
                    XCTAssertEqual(lines.contains { $0.contains(language.t(title)) }, enabled, "\(lines)")
                }
                XCTAssertFalse(preferences.enablesCustomBenchmarkConfiguration)
                XCTAssertFalse(preferences.enablesVirtualDisks)
                XCTAssertFalse(preferences.showsBuildNumber)
            }
        }
    }
}
