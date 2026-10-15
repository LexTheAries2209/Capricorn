// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftData
import SwiftUI
import Vision
import XCTest
@testable import Capricorn

final class VirtualDiskPresentationTests: XCTestCase {
    @MainActor
    func testCommandTOpensConfigurationOnlyWhenAddVirtualDiskIsAvailable() async throws {
        XCTAssertEqual(AppCommandShortcut.addVirtualDisk.key, "t")
        XCTAssertEqual(AppCommandShortcut.addVirtualDisk.modifiers, .command)
        let suite = "CapricornTests.virtualShortcut.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let model = AppModel()
        let physical = CapricornTests.fixtureDrive()
        model.drives = [physical]
        model.selectedDriveID = physical.id
        let window = makeWindow(
            root: ContentView(viewModel: model, preferences: preferences)
                .modelContainer(try ModelContainerFactory.makeInMemory()),
            size: NSSize(width: 1_433, height: 800)
        )
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "t", charactersIgnoringModifiers: "t",
            isARepeat: false, keyCode: 17
        ))
        for (developer, virtualDisks, locked) in [
            (false, false, false), (false, true, false), (true, false, false),
            (true, true, true), (true, true, false)
        ] {
            preferences.enablesDeveloperOptions = developer
            preferences.enablesVirtualDisks = virtualDisks
            model.isLiveActivityMonitoring = locked
            try await Task.sleep(for: .milliseconds(150))
            _ = window.contentView?.performKeyEquivalent(with: event)
            if developer && virtualDisks && !locked {
                let opened = await AsyncTestWaiter.wait { window.attachedSheet != nil }
                XCTAssertTrue(opened, "Command+T should open the configuration sheet.")
                preferences.enablesVirtualDisks = false
                let dismissed = await AsyncTestWaiter.wait { window.attachedSheet == nil }
                XCTAssertTrue(dismissed)
            } else {
                try await Task.sleep(for: .milliseconds(150))
                XCTAssertNil(window.attachedSheet)
            }
        }
    }

    @MainActor
    func testDisablingEitherVirtualDiskSwitchEjectsAllCreatedDisks() async throws {
        for disablesMaster in [false, true] {
            let suite = "CapricornTests.disableVirtualDisks.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let preferences = AppPreferences(defaults: defaults)
            preferences.enablesDeveloperOptions = true
            preferences.enablesVirtualDisks = true
            var physical = CapricornTests.fixtureDrive()
            physical.isSystemDisk = true
            let refresh = StagedDriveRefreshService(
                discovery: DriveRefreshSnapshot(drives: [physical], snapshots: [:]),
                updateDelayNanoseconds: 0, updates: []
            )
            let model = AppModel(refreshService: refresh)
            await model.refresh()
            var configuration = VirtualDiskConfiguration()
            let first = try model.addSimulatedDisk(configuration)
            configuration.serialNumber = physical.serialNumber ?? "SN"
            let second = try model.addSimulatedDisk(configuration)
            let window = makeWindow(
                root: ContentView(viewModel: model, preferences: preferences)
                    .modelContainer(try ModelContainerFactory.makeInMemory()),
                size: NSSize(width: 1_433, height: 800)
            )
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(150))

            if disablesMaster {
                preferences.enablesDeveloperOptions = false
            } else {
                preferences.enablesVirtualDisks = false
            }
            let ejected = await AsyncTestWaiter.wait {
                model.drives.map(\.id) == [physical.id]
            }
            XCTAssertTrue(ejected)
            XCTAssertNil(model.snapshots[first.id])
            XCTAssertNil(model.snapshots[second.id])
            XCTAssertEqual(model.selectedDriveID, physical.id)
            preferences.enablesDeveloperOptions = true
            preferences.enablesVirtualDisks = true
            await model.refresh()
            XCTAssertEqual(model.drives.map(\.id), [physical.id])
        }
    }

    @MainActor
    func testConfigurationAndOverviewRenderInBothLanguages() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Virtual disk presentation screenshots require Screen Recording permission.")
        }
        for language in AppLanguage.allCases {
            let model = AppModel()
            var createdFromForm: DriveDevice?
            let formWindow = makeWindow(
                root: VirtualDiskConfigurationSheet(
                    language: language,
                    create: { createdFromForm = try model.addSimulatedDisk($0) },
                    cancel: {}
                ),
                size: NSSize(width: 700, height: 760)
            )
            formWindow.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(350))
            let formLines = try capture(window: formWindow, name: "configuration-\(language.rawValue)")
            XCTAssertTrue(formLines.contains { $0.contains(language.t("Add virtual disk")) }, "\(formLines)")
            XCTAssertTrue(formLines.contains { $0.contains(language.t("Serial Number")) }, "\(formLines)")
            XCTAssertTrue(formLines.contains { $0.contains(language.t("Partitions")) }, "\(formLines)")
            try clickButton(window: formWindow, title: language.t("Add"), name: "configuration-\(language.rawValue)")
            let created = await AsyncTestWaiter.wait { createdFromForm != nil }
            XCTAssertTrue(created)
            if let createdFromForm { await model.performDiskAction(.eject, on: createdFromForm) }
            XCTAssertTrue(model.drives.isEmpty)
            formWindow.orderOut(nil)

            let suite = "CapricornTests.virtualPresentation.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let preferences = AppPreferences(defaults: defaults)
            preferences.languageRawValue = language.rawValue
            preferences.enablesDeveloperOptions = true
            preferences.enablesVirtualDisks = true
            var config = VirtualDiskConfiguration()
            config.name = "Preview"
            config.serialNumber = "DEMO-SERIAL-1234"
            let drive = try model.addSimulatedDisk(config)
            XCTAssertEqual(drive.displayNameWithVirtualMarker(language: language),
                           language == .simplifiedChinese ? "Preview（虚拟硬盘）" : "Preview (Virtual Disk)")
            let window = makeWindow(
                root: ContentView(viewModel: model, preferences: preferences)
                    .modelContainer(try ModelContainerFactory.makeInMemory()),
                size: NSSize(width: 1_433, height: 900)
            )
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(350))
            let overviewLines = try capture(window: window, name: "overview-\(language.rawValue)")
            XCTAssertTrue(overviewLines.contains { $0.contains("Preview") && $0.contains(language.t("Virtual Disk")) }, "\(overviewLines)")
            XCTAssertTrue(overviewLines.contains { $0.contains(language.t("Eject")) }, "\(overviewLines)")
            XCTAssertTrue(overviewLines.contains { $0.contains(language.t("Unallocated")) }, "\(overviewLines)")
            XCTAssertFalse(overviewLines.contains { $0 == language.t("Benchmark") })
            try clickButton(window: window, title: language.t("Eject"), name: "overview-\(language.rawValue)")
            let ejected = await AsyncTestWaiter.wait { model.drives.isEmpty }
            XCTAssertTrue(ejected)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(model.drives.isEmpty)
            let emptyLines = try capture(window: window, name: "ejected-\(language.rawValue)")
            XCTAssertFalse(emptyLines.contains { $0.contains("Preview") })
            window.orderOut(nil)
        }
    }

    @MainActor
    private func clickButton(window: NSWindow, title: String, name: String) throws {
        let url = URL(fileURLWithPath: "/tmp/Capricorn-virtual-\(name).png")
        let image = try XCTUnwrap(NSImage(contentsOf: url)?.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let button = try XCTUnwrap(request.results?.first {
            let text = $0.topCandidates(1).first?.string ?? ""
            return text.hasSuffix(title) && (title == "Add" || title == "添加" ? $0.boundingBox.midY < 0.2 : true)
        })
        let point = NSPoint(
            x: button.boundingBox.midX * window.frame.width,
            y: button.boundingBox.midY * window.frame.height
        )
        let events = try [NSEvent.EventType.leftMouseDown, .leftMouseUp].map { type in
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
        }
        // Native buttons track mouse-down synchronously until mouse-up is queued.
        NSApp.postEvent(events[1], atStart: true)
        window.sendEvent(events[0])
    }

    @MainActor
    private func makeWindow<V: View>(root: V, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.contentView = NSHostingView(rootView: root)
        window.appearance = NSAppearance(named: .aqua)
        window.center()
        return window
    }

    @MainActor
    private func capture(window: NSWindow, name: String) throws -> [String] {
        window.contentView?.layoutSubtreeIfNeeded()
        let url = URL(fileURLWithPath: "/tmp/Capricorn-virtual-\(name).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", url.path]
        try capture.run()
        capture.waitUntilExit()
        XCTAssertEqual(capture.terminationStatus, 0)
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(NSImage(contentsOf: url)?.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap {
            $0.topCandidates(1).first?.string.replacingOccurrences(of: "虛", with: "虚")
        }
    }
}
