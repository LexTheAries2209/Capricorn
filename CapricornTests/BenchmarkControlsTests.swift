// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import Vision
import XCTest
@testable import Capricorn

final class BenchmarkControlsTests: XCTestCase {
    @MainActor
    func testChineseControlGroupsAndDisabledEfficiencyAtNarrowWidth() async throws {
        // Include the added Stop button; smaller panels intentionally scroll this row.
        try await verifyControls(language: .simplifiedChinese, width: 860, efficiencyEnabled: false)
    }

    @MainActor
    func testEnglishControlGroupsAndSavedEfficiencyRatio() async throws {
        try await verifyControls(language: .english, width: 1_180, efficiencyEnabled: true)
    }

    @MainActor
    func testCustomProfileTracksDeveloperSettingsAndRetainsLinkedQueueControls() async throws {
        let suiteName = "CapricornTests.benchmarkDeveloperOptions.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let savedRows = BenchmarkCustomRow.encodeList([
            BenchmarkCustomRow(id: "saved-custom", accessPattern: .random, blockSizeBytes: 65_536, queueDepth: 8, threads: 2, includeMixed: false)
        ])
        defaults.set(savedRows, forKey: "benchmarkCustomRowsJSON")
        defaults.set(BenchmarkExecutionMode.loopUntilCancelled.rawValue, forKey: "benchmarkCustomExecutionMode")
        let preferences = AppPreferences(defaults: defaults)
        let model = AppModel()
        let hostingView = NSHostingView(rootView: DeveloperBenchmarkTestView(
            preferences: preferences,
            model: model
        ).defaultAppStorage(defaults))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 680),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        try await assertProfileChoices(in: hostingView, includesCustom: false)
        preferences.enablesDeveloperOptions = true
        try await assertProfileChoices(in: hostingView, includesCustom: false)
        preferences.enablesCustomBenchmarkConfiguration = true
        try await assertProfileChoices(in: hostingView, includesCustom: true)

        let picker = try XCTUnwrap(profilePicker(in: hostingView))
        picker.selectItem(withTitle: "Custom")
        picker.menu?.performActionForItem(at: picker.indexOfSelectedItem)
        picker.sendAction(picker.action, to: picker.target)
        let customSelected = await AsyncTestWaiter.wait {
            self.profilePicker(in: hostingView)?.titleOfSelectedItem == "Custom"
        }
        XCTAssertTrue(customSelected)

        preferences.enablesCustomBenchmarkConfiguration = false
        try await assertProfileChoices(in: hostingView, includesCustom: false)
        XCTAssertEqual(profilePicker(in: hostingView)?.titleOfSelectedItem, "Default")
        XCTAssertEqual(defaults.string(forKey: "benchmarkCustomRowsJSON"), savedRows)

        preferences.enablesCustomBenchmarkConfiguration = true
        try await assertProfileChoices(in: hostingView, includesCustom: true)
        let restoredPicker = try XCTUnwrap(profilePicker(in: hostingView))
        restoredPicker.selectItem(withTitle: "Custom")
        restoredPicker.menu?.performActionForItem(at: restoredPicker.indexOfSelectedItem)
        restoredPicker.sendAction(restoredPicker.action, to: restoredPicker.target)
        model.isBenchmarking = true
        preferences.enablesDeveloperOptions = false
        try await assertProfileChoices(in: hostingView, includesCustom: false)
        XCTAssertEqual(profilePicker(in: hostingView)?.titleOfSelectedItem, "Default")
        XCTAssertTrue(model.isBenchmarking, "Changing developer settings must not stop the active run.")
        XCTAssertEqual(defaults.string(forKey: "benchmarkCustomRowsJSON"), savedRows)
        XCTAssertEqual(
            defaults.string(forKey: "benchmarkCustomExecutionMode"),
            BenchmarkExecutionMode.loopUntilCancelled.rawValue
        )
        model.isBenchmarking = false
        preferences.enablesDeveloperOptions = true
        try await assertProfileChoices(in: hostingView, includesCustom: true)
        XCTAssertEqual(profilePicker(in: hostingView)?.titleOfSelectedItem, "Default")
        let customPicker = try XCTUnwrap(profilePicker(in: hostingView))
        customPicker.selectItem(withTitle: "Custom")
        customPicker.menu?.performActionForItem(at: customPicker.indexOfSelectedItem)

        let fullOptions = ["1", "2", "4", "8", "16"]
        let controlsReady = await AsyncTestWaiter.wait {
            self.popUpButtons(in: hostingView).contains { $0.itemTitles == fullOptions }
        }
        XCTAssertTrue(controlsReady, "Menus: \(popUpButtons(in: hostingView).map(\.itemTitles))")
        let queuePicker = try XCTUnwrap(popUpButtons(in: hostingView).first { $0.itemTitles == fullOptions })
        queuePicker.selectItem(withTitle: "16")
        queuePicker.menu?.performActionForItem(at: queuePicker.indexOfSelectedItem)
        queuePicker.sendAction(queuePicker.action, to: queuePicker.target)
        let clampedToOne = await AsyncTestWaiter.wait {
            let row = BenchmarkCustomRow.decodeList(from: defaults.string(forKey: "benchmarkCustomRowsJSON") ?? "")[0]
            return row.queueDepth == 16 && row.threads == 1
                && self.popUpButtons(in: hostingView).contains { $0.itemTitles == ["1"] }
        }
        XCTAssertTrue(clampedToOne)
        queuePicker.selectItem(withTitle: "1")
        queuePicker.menu?.performActionForItem(at: queuePicker.indexOfSelectedItem)
        queuePicker.sendAction(queuePicker.action, to: queuePicker.target)
        let expanded = await AsyncTestWaiter.wait {
            self.popUpButtons(in: hostingView).filter { $0.itemTitles == fullOptions }.count == 2
        }
        XCTAssertTrue(expanded)
        let threadPicker = try XCTUnwrap(popUpButtons(in: hostingView).last { $0.itemTitles == fullOptions })
        threadPicker.selectItem(withTitle: "16")
        threadPicker.menu?.performActionForItem(at: threadPicker.indexOfSelectedItem)
        threadPicker.sendAction(threadPicker.action, to: threadPicker.target)
        let selectedSixteen = await AsyncTestWaiter.wait {
            BenchmarkCustomRow.decodeList(from: defaults.string(forKey: "benchmarkCustomRowsJSON") ?? "")[0].threads == 16
        }
        XCTAssertTrue(selectedSixteen)
        queuePicker.selectItem(withTitle: "8")
        queuePicker.menu?.performActionForItem(at: queuePicker.indexOfSelectedItem)
        queuePicker.sendAction(queuePicker.action, to: queuePicker.target)
        let clampedToTwo = await AsyncTestWaiter.wait {
            let row = BenchmarkCustomRow.decodeList(from: defaults.string(forKey: "benchmarkCustomRowsJSON") ?? "")[0]
            return row.queueDepth == 8 && row.threads == 2
                && self.popUpButtons(in: hostingView).contains { $0.itemTitles == ["1", "2"] && $0.titleOfSelectedItem == "2" }
        }
        XCTAssertTrue(clampedToTwo)
    }

    @MainActor
    private func assertProfileChoices(in view: NSView, includesCustom: Bool) async throws {
        let expected = ["Default", "Quick", "SSD", "HDD"] + (includesCustom ? ["Custom"] : [])
        let updated = await AsyncTestWaiter.wait {
            self.profilePicker(in: view)?.itemTitles == expected
        }
        XCTAssertTrue(updated, "Profile choices: \(profilePicker(in: view)?.itemTitles ?? [])")
    }

    @MainActor
    private func profilePicker(in view: NSView) -> NSPopUpButton? {
        if let picker = view as? NSPopUpButton, picker.itemTitles.contains("Default") {
            return picker
        }
        return view.subviews.lazy.compactMap { self.profilePicker(in: $0) }.first
    }

    @MainActor
    private func popUpButtons(in view: NSView) -> [NSPopUpButton] {
        if let picker = view as? NSPopUpButton { return [picker] }
        return view.subviews.flatMap { popUpButtons(in: $0) }
    }

    @MainActor
    func testQuickControlsShowEffectiveValuesAndKeepSavedSettingsInBothLanguages() async throws {
        for language in AppLanguage.allCases {
            let suiteName = "CapricornTests.quickControls.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(7, forKey: "benchmarkRunCount")
            defaults.set(4 * 1_024 * 1_024 * 1_024, forKey: "benchmarkFileSizeBytes")
            defaults.set(true, forKey: "benchmarkUsesTrimmedAverage")
            defaults.set(true, forKey: "benchmarkUsesSmallBlockEfficiency")
            let root = BenchmarkView(
                drive: CapricornTests.fixtureDrive(mountedAt: "/"), viewModel: AppModel(),
                allowsCustomBenchmarkConfiguration: false, saveResults: { _, _ in }
            )
            .defaultAppStorage(defaults)
            .environment(\.appLanguage, language)
            .padding(12)
            let hostingView = NSHostingView(rootView: root)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_280, height: 820),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.contentView = hostingView
            window.appearance = NSAppearance(named: .aqua)
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            let ready = await AsyncTestWaiter.wait {
                self.popUpButtons(in: hostingView).contains { $0.itemTitles.contains(language.profileName(.quick)) }
            }
            XCTAssertTrue(ready)
            let picker = try XCTUnwrap(popUpButtons(in: hostingView).first { $0.itemTitles.contains(language.profileName(.quick)) })
            picker.selectItem(withTitle: language.profileName(.quick))
            picker.menu?.performActionForItem(at: picker.indexOfSelectedItem)
            let quickShown = await AsyncTestWaiter.wait {
                self.popUpButtons(in: hostingView).contains { $0.itemTitles == ["128 MiB"] && !$0.isEnabled }
                    && self.popUpButtons(in: hostingView).contains {
                        $0.itemTitles == (1...9).map(String.init) && $0.titleOfSelectedItem == "1" && !$0.isEnabled
                    }
            }
            XCTAssertTrue(quickShown)
            hostingView.layoutSubtreeIfNeeded()
            if let image = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
                hostingView.cacheDisplay(in: hostingView.bounds, to: image)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Capricorn-Quick-\(language.rawValue)-\(UUID().uuidString).png")
                try image.representation(using: .png, properties: [:])?.write(to: url, options: .withoutOverwriting)
                let attachment = XCTAttachment(contentsOfFile: url)
                attachment.lifetime = .keepAlways
                add(attachment)
                print("Quick profile screenshot: \(url.path)")
            }
            picker.selectItem(withTitle: language.profileName(.default))
            picker.menu?.performActionForItem(at: picker.indexOfSelectedItem)
            let restored = await AsyncTestWaiter.wait {
                self.popUpButtons(in: hostingView).contains { $0.titleOfSelectedItem == "4 GiB" }
                    && self.popUpButtons(in: hostingView).contains { $0.titleOfSelectedItem == "7" }
            }
            XCTAssertTrue(restored)
            XCTAssertEqual(defaults.integer(forKey: "benchmarkRunCount"), 7)
            XCTAssertEqual(defaults.integer(forKey: "benchmarkFileSizeBytes"), 4 * 1_024 * 1_024 * 1_024)
            XCTAssertTrue(defaults.bool(forKey: "benchmarkUsesTrimmedAverage"))
            XCTAssertTrue(defaults.bool(forKey: "benchmarkUsesSmallBlockEfficiency"))
        }
    }

    @MainActor
    private func verifyControls(language: AppLanguage, width: CGFloat, efficiencyEnabled: Bool) async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Benchmark control screenshots require Screen Recording permission.")
        }
        let suiteName = "CapricornTests.benchmarkControls.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(efficiencyEnabled, forKey: "benchmarkUsesSmallBlockEfficiency")
        defaults.set(20, forKey: "benchmarkSmallBlockFileSizePercent")
        let model = AppModel()
        let root = BenchmarkView(
            drive: CapricornTests.fixtureDrive(mountedAt: "/"),
            viewModel: model,
            allowsCustomBenchmarkConfiguration: false,
            saveResults: { _, _ in }
        )
        .defaultAppStorage(defaults)
        .environment(\.appLanguage, language)
        .environment(\.locale, Locale(identifier: language.localeIdentifier))
        .padding(12)
        let hostingView = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 680),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hostingView
        window.appearance = NSAppearance(named: .aqua)
        window.center()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(nanoseconds: 300_000_000)
        hostingView.layoutSubtreeIfNeeded()

        // Capture native controls through the window server, as in sidebar tests.
        let captureURL = URL(fileURLWithPath: "/tmp/Capricorn-benchmark-controls-\(language.rawValue).png")
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
        let titles = ["Benchmark Controls", "Target Location", "Improve Small-Block Test Efficiency"]
        request.customWords = titles.map { language.t($0) }
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let headings = try titles.map { title in
            try XCTUnwrap(observations.first {
                $0.topCandidates(1).first?.string.contains(language.t(title)) == true
            }, "Missing \(title): \(lines)")
        }
        XCTAssertLessThan(headings[0].boundingBox.midX, headings[1].boundingBox.midX)
        XCTAssertLessThan(headings[1].boundingBox.midX, headings[2].boundingBox.midX)
        for heading in headings.dropFirst() {
            XCTAssertEqual(heading.boundingBox.midY, headings[0].boundingBox.midY, accuracy: 0.02)
        }
        XCTAssertEqual(lines.filter { $0.contains(language.t("Target Location")) }.count, 1)
        let efficiencyTitle = headings[2].boundingBox
        XCTAssertTrue(observations.contains {
            $0.topCandidates(1).first?.string.contains(efficiencyEnabled ? "20%" : language.t("Off")) == true
                && $0.boundingBox.midY < efficiencyTitle.midY
                && $0.boundingBox.minX >= efficiencyTitle.minX - 0.01
                && $0.boundingBox.midY > efficiencyTitle.midY - 0.08
        }, "Efficiency selection must appear below its title: \(lines)")
        XCTAssertTrue(lines.contains { $0.contains(language.t("Target folder is writable")) }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains(language.t("Stop")) }, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains(language.t("Cancel")) }, "\(lines)")
        XCTAssertFalse(lines.contains { $0.hasPrefix("/") }, "The detailed target path must not occupy a row: \(lines)")
        XCTAssertFalse(model.isBenchmarking)
    }
}

private struct DeveloperBenchmarkTestView: View {
    let preferences: AppPreferences
    let model: AppModel

    var body: some View {
        BenchmarkView(
            drive: CapricornTests.fixtureDrive(mountedAt: "/"),
            viewModel: model,
            allowsCustomBenchmarkConfiguration: preferences.allowsCustomBenchmarkConfiguration,
            saveResults: { _, _ in }
        )
        .environment(\.appLanguage, AppLanguage.english)
        .padding(12)
    }
}
