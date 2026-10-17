// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import Vision
import XCTest
@testable import Capricorn

final class SmartErrorLogPresentationTests: XCTestCase {
    @MainActor
    func testTitleRowButtonCollapsesAndExpandsDiagnosticsWithoutSummary() async throws {
        var drive = CapricornTests.fixtureDrive()
        drive.isSystemDisk = false
        for language in AppLanguage.allCases {
            let hostingView = NSHostingView(rootView: panel(model: AppModel(), drive: drive, language: language))
            let window = makeWindow(hostingView)
            defer { window.orderOut(nil) }

            for expanded in [true, false, true] {
                try await Task.sleep(for: .milliseconds(250))
                hostingView.layoutSubtreeIfNeeded()
                let image = try capturedImage(
                    in: hostingView, name: "title-row-\(language.rawValue)-\(expanded)"
                )
                let observations = try textObservations(in: image)
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let title = try XCTUnwrap(observations.first {
                    normalized($0.topCandidates(1).first?.string ?? "")
                        .contains(normalized(language.t("SMART Diagnostics")))
                })
                let text = normalized(lines.joined())
                XCTAssertEqual(text.contains(normalized(language.t("Retry Self-Test Check"))), expanded)
                XCTAssertEqual(text.contains(normalized(language.t("SMART Error Entries"))), expanded)
                XCTAssertFalse(text.contains(normalized(language.t("Self-tests and saved reports."))))
                XCTAssertFalse(text.contains(normalized(language.t("Self-tests, saved reports, and controller error entries."))))

                // Click at the title's height to verify the button shares that row.
                let point = NSPoint(
                    x: hostingView.bounds.width - 40,
                    y: (hostingView.isFlipped ? 1 - title.boundingBox.midY : title.boundingBox.midY)
                        * hostingView.bounds.height
                )
                try click(in: hostingView, window: window, at: point)
            }
        }
    }

    @MainActor
    func testSettingsRevealErrorEntryReaderBelowEnabledDiagnosticsInBothLanguages() async throws {
        let suiteName = "CapricornTests.errorReaderSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)

        for language in AppLanguage.allCases {
            preferences.languageRawValue = language.rawValue
            let root = Form {
                SmartDiagnosticsSettingsControls(preferences: preferences)
            }
            .formStyle(.grouped)
            .padding(20)
            .frame(width: 620, height: 260)
            let hostingView = NSHostingView(rootView: root)
            let window = makeWindow(hostingView)
            defer { window.orderOut(nil) }

            for enabled in [false, true, false] {
                preferences.showsSmartSelfTestInterface = enabled
                try await Task.sleep(for: .milliseconds(250))
                hostingView.layoutSubtreeIfNeeded()
                let image = try capturedImage(
                    in: hostingView, name: "settings-\(language.rawValue)-\(enabled)"
                )
                let observations = try textObservations(in: image)
                let main = try XCTUnwrap(observations.first {
                    $0.topCandidates(1).first?.string.contains(language.t("Show SMART diagnostics")) == true
                })
                let child = observations.first {
                    $0.topCandidates(1).first?.string.contains(language.t("Show error entry reader")) == true
                }
                XCTAssertEqual(child != nil, enabled)
                if let child {
                    XCTAssertLessThan(child.boundingBox.midY, main.boundingBox.midY)
                    XCTAssertEqual(child.boundingBox.minX, main.boundingBox.minX, accuracy: 0.01)
                }
                let text = normalized(observations.compactMap { $0.topCandidates(1).first?.string }.joined())
                XCTAssertTrue(text.contains(normalized(language.t(
                    "When disabled, the SMART page hides self-test controls, saved reports, and error-log tools."
                ))))
                XCTAssertEqual(text.contains(normalized(language.t(
                    "Off by default. When enabled, the SMART page shows tools to read, view, and export controller error reports."
                ))), enabled)
                XCTAssertFalse(text.contains(normalized(language.t("Overview"))))
                XCTAssertFalse(preferences.showsSmartErrorLogInterface)
            }
        }
    }

    @MainActor
    func testSmartPageHidesErrorReaderByDefaultAndTracksBothSettings() async throws {
        let suiteName = "CapricornTests.errorReaderVisibility.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        var drive = CapricornTests.fixtureDrive()
        drive.isSystemDisk = false
        var snapshot = CapricornTests.fixtureSnapshot(for: drive)
        snapshot.attributes = [SmartAttribute(
            id: "nvme.num_err_log_entries", name: "Error Log Entries",
            rawValue: "2", current: nil, worst: nil, threshold: nil,
            status: .good, source: "smartctl"
        )]
        let model = AppModel()
        for language in AppLanguage.allCases {
            let root = SmartAttributesView(
                drive: drive, snapshot: snapshot, viewModel: model, selfTestHistory: [],
                saveSnapshot: { _ in "" }, exportSelfTestHistory: { _, _, _ in "" },
                exportErrorLog: { _, _, _ in "" }, satDriverGuidance: nil,
                openSATDriverSettings: {}
            )
            .defaultAppStorage(defaults)
            .environment(\.appLanguage, language)
            .environment(\.locale, Locale(identifier: language.localeIdentifier))
            .frame(width: 1_000, height: 650)
            let hostingView = NSHostingView(rootView: root)
            let window = makeWindow(hostingView)
            defer { window.orderOut(nil) }

            for (diagnostics, errorReader) in [(true, false), (true, true), (false, true), (true, true), (true, false)] {
                preferences.showsSmartSelfTestInterface = diagnostics
                preferences.showsSmartErrorLogInterface = errorReader
                try await Task.sleep(for: .milliseconds(250))
                hostingView.layoutSubtreeIfNeeded()
                let image = try capturedImage(
                    in: hostingView,
                    name: "visibility-\(language.rawValue)-\(diagnostics)-\(errorReader)"
                )
                let text = normalized(try textObservations(in: image).compactMap {
                    $0.topCandidates(1).first?.string
                }.joined())
                XCTAssertEqual(text.contains(normalized(language.t("SMART Diagnostics"))), diagnostics)
                XCTAssertEqual(
                    text.contains(normalized(language.t("SMART Error Entries"))),
                    diagnostics && errorReader
                )
                XCTAssertFalse(text.contains(normalized(language.t("Self-tests and saved reports."))))
                XCTAssertFalse(text.contains(normalized(language.t("Self-tests, saved reports, and controller error entries."))))
                XCTAssertTrue(model.smartErrorLogReports.isEmpty, "Changing visibility must not read a drive.")
            }
        }
    }

    @MainActor
    func testOneClickReadsAndOpensDetailsWithCachedSupport() async throws {
        let suiteName = "CapricornTests.errorLogClick.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var drive = CapricornTests.fixtureDrive()
        drive.isSystemDisk = false
        let runner = ErrorLogUICommandRunner()
        let model = AppModel(
            smartErrorLogService: SmartErrorLogService(
                smartctlProvider: CapricornTests.testSmartctlProvider(),
                runner: runner,
                administratorRunner: runner,
                commandCoordinator: SmartctlCommandCoordinator()
            ),
            smartDiagnosticsCapabilityCache: SmartDiagnosticsCapabilityCache(defaults: defaults)
        )
        // A cached capability must not require a second click to load the report.
        model.smartErrorLogCapabilities[drive.id] = .supported
        let hostingView = NSHostingView(rootView: panel(model: model, drive: drive, language: .english))
        let window = makeWindow(hostingView)
        defer {
            if let sheet = window.sheets.first { window.endSheet(sheet) }
            window.orderOut(nil)
        }

        try await Task.sleep(for: .milliseconds(250))
        hostingView.layoutSubtreeIfNeeded()
        let image = try capturedImage(in: hostingView, name: "before-click")
        let label = try XCTUnwrap(textObservations(in: image).first {
            $0.topCandidates(1).first?.string.contains("Read Error Entries") == true
        })
        let point = NSPoint(
            x: label.boundingBox.midX * hostingView.bounds.width,
            y: (hostingView.isFlipped ? 1 - label.boundingBox.midY : label.boundingBox.midY)
                * hostingView.bounds.height
        )
        try click(in: hostingView, window: window, at: point)
        let opened = await AsyncTestWaiter.wait(timeout: 3) { !window.sheets.isEmpty }

        XCTAssertTrue(opened, "The first read should open its details without a View action.")
        XCTAssertEqual(runner.readCount, 1)
        XCTAssertEqual(model.smartErrorLogReports[drive.id]?.entries.first?.status, "Invalid Field")
    }

    @MainActor
    func testUnreadUnavailableAndEmptyReportsRenderInBothLanguages() async throws {
        var drive = CapricornTests.fixtureDrive()
        drive.isSystemDisk = false
        let report = SmartErrorLogReport(
            isSupported: true,
            message: "No SMART error log entries were reported.",
            entries: [],
            totalEntryCount: 0,
            capturedAt: Date()
        )
        for language in AppLanguage.allCases {
            for state in ["unread", "unavailable", "empty"] {
                let model = AppModel()
                model.smartErrorLogCapabilities[drive.id] = .supported
                if state != "unread" { model.smartErrorLogReports[drive.id] = report }
                let count = state == "empty" ? 0 : 2
                let hostingView = NSHostingView(rootView: panel(
                    model: model, drive: drive, language: language, historicalCount: count
                ))
                let window = makeWindow(hostingView)
                defer { window.orderOut(nil) }
                try await Task.sleep(for: .milliseconds(250))
                hostingView.layoutSubtreeIfNeeded()
                let image = try capturedImage(in: hostingView, name: "\(language.rawValue)-\(state)")
                let lines = try textObservations(in: image).compactMap { $0.topCandidates(1).first?.string }

                let expected = state == "unread"
                    ? language.smartErrorLogPendingReadMessage(count: 2)
                    : language.t(state == "empty" ? "No Error Entries" : "Error Report Unavailable")
                XCTAssertTrue(
                    lines.contains { normalized($0).contains(normalized(expected)) },
                    "\(state): \(lines)"
                )
                XCTAssertFalse(lines.contains { $0.contains(language.t("Retry Error Log Check")) })
                if state != "empty" {
                    XCTAssertFalse(lines.contains { $0.contains(language.t("No Error Entries")) })
                    XCTAssertFalse(lines.contains { $0.contains(language.t("View Error Entries")) })
                }
            }
        }
    }

    @MainActor
    func testFullSmartPageKeepsHistoricalErrorExplanationVisible() async throws {
        let suiteName = "CapricornTests.errorReportLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: AppPreferences.Key.showsSmartSelfTestInterface)
        defaults.set(true, forKey: AppPreferences.Key.showsSmartErrorLogInterface)
        var drive = CapricornTests.fixtureDrive()
        drive.isSystemDisk = false
        var snapshot = CapricornTests.fixtureSnapshot(for: drive)
        snapshot.attributes = [SmartAttribute(
            id: "nvme.num_err_log_entries", name: "Error Log Entries",
            rawValue: "2", current: nil, worst: nil, threshold: nil,
            status: .good, source: "smartctl"
        )]
        let model = AppModel()
        model.smartErrorLogCapabilities[drive.id] = .supported
        model.smartErrorLogReports[drive.id] = SmartErrorLogReport(
            isSupported: true, message: "No SMART error log entries were reported.",
            entries: [], totalEntryCount: 0, capturedAt: Date()
        )
        model.smartSelfTestCapabilities[drive.id] = .unavailable(
            SmartSelfTestService.macOSNativeNVMeUnavailableMessage
        )

        for language in AppLanguage.allCases {
            for height: CGFloat in [520, 650] {
                let root = SmartAttributesView(
                    drive: drive, snapshot: snapshot, viewModel: model, selfTestHistory: [],
                    saveSnapshot: { _ in "" }, exportSelfTestHistory: { _, _, _ in "" },
                    exportErrorLog: { _, _, _ in "" }, satDriverGuidance: nil,
                    openSATDriverSettings: {}
                )
                .defaultAppStorage(defaults)
                .environment(\.appLanguage, language)
                .environment(\.locale, Locale(identifier: language.localeIdentifier))
                .frame(width: 1_000, height: height)
                let hostingView = NSHostingView(rootView: root)
                let window = makeWindow(hostingView)
                defer { window.orderOut(nil) }
                try await Task.sleep(for: .milliseconds(250))
                hostingView.layoutSubtreeIfNeeded()
                let image = try capturedImage(
                    in: hostingView, name: "full-page-\(language.rawValue)-\(Int(height))"
                )
                let lines = try textObservations(in: image).compactMap { $0.topCandidates(1).first?.string }
                let text = normalized(lines.joined())
                let expected = normalized(language.smartErrorLogHistoryWithoutDetailsMessage(count: 2))
                XCTAssertTrue(text.contains(expected), "\(language), \(height): \(lines)")
                if language == .simplifiedChinese {
                    XCTAssertTrue(
                        lines.contains { normalized($0).contains(expected) },
                        "The Chinese explanation should fit on one line: \(lines)"
                    )
                }
                XCTAssertTrue(
                    text.contains(normalized(language.t("Retry Reading Error Entries"))),
                    "The retry control must remain visible."
                )
            }
        }
    }

    @MainActor
    private func panel(
        model: AppModel,
        drive: DriveDevice,
        language: AppLanguage,
        historicalCount: Int = 2
    ) -> some View {
        var snapshot = CapricornTests.fixtureSnapshot(for: drive)
        snapshot.attributes = [SmartAttribute(
            id: "nvme.num_err_log_entries", name: "Error Log Entries",
            rawValue: String(historicalCount), current: nil, worst: nil, threshold: nil,
            status: .good, source: "smartctl"
        )]
        return SmartDiagnosticsPanel(
            drive: drive, snapshot: snapshot, showsErrorLogInterface: true,
            viewModel: model, selfTestHistory: [],
            exportSelfTestHistory: { _, _, _ in "" }, exportErrorLog: { _, _, _ in "" },
            saveMessage: .constant(nil)
        )
        .environment(\.appLanguage, language)
        .environment(\.locale, Locale(identifier: language.localeIdentifier))
        .padding(16)
    }

    @MainActor
    private func click(in view: NSView, window: NSWindow, at point: NSPoint) throws {
        let location = view.convert(point, to: nil)
        let mouseUp = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 0
        ))
        let mouseDown = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        NSApp.postEvent(mouseUp, atStart: true)
        window.sendEvent(mouseDown)
    }

    @MainActor
    private func makeWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 370),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = view
        window.appearance = NSAppearance(named: .aqua)
        window.center()
        window.makeKeyAndOrderFront(nil)
        return window
    }

    @MainActor
    private func capturedImage(in view: NSView, name: String) throws -> CGImage {
        let url = URL(fileURLWithPath: "/tmp/Capricorn-smart-error-report-\(name).png")
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }

    private func textObservations(in image: CGImage) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results ?? []
    }

    private func normalized(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }
}

private final class ErrorLogUICommandRunner: CommandRunning, @unchecked Sendable {
    private let reads = LockedState(0)
    var readCount: Int { reads.snapshot() }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        reads.withLock { $0 += 1 }
        return CommandResult(
            stdout: Data("""
            {
              "smartctl": {"exit_status": 0},
              "nvme_error_information_log": {
                "entries": [{"error_count": 2, "status": "Invalid Field", "namespace_id": 1}]
              }
            }
            """.utf8),
            stderr: Data(), terminationStatus: 0
        )
    }
}
