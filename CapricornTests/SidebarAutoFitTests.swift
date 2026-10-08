// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import Vision
import XCTest
@testable import Capricorn

final class SidebarAutoFitTests: XCTestCase {
    func testPreferredWidthUsesWidestRowInsteadOfMaximum() {
        XCTAssertEqual(SidebarAutoFitWidth.preferred(rowWidths: []), 260)
        XCTAssertEqual(SidebarAutoFitWidth.preferred(rowWidths: [180, 220]), 260)
        XCTAssertEqual(SidebarAutoFitWidth.preferred(rowWidths: [310.2, 280, 340.1]), 341)
        XCTAssertEqual(SidebarAutoFitWidth.preferred(rowWidths: [500]), 500)
        XCTAssertEqual(SidebarAutoFitWidth.preferred(rowWidths: [.nan, .infinity, -1, 310]), 310)
        XCTAssertEqual(SidebarAutoFitWidth.preferred(rowWidths: [310], rowInset: 14), 338)
    }

    @MainActor
    func testDoubleClickFitsDividerFromEitherDirectionAndIsRepeatable() throws {
        let (window, splitView, anchor) = makeSplitView()
        defer { window.orderOut(nil) }
        let coordinator = SidebarDividerAutoFit.Coordinator(preferredWidth: 310)
        coordinator.anchor = anchor
        defer { coordinator.invalidate() }

        for startingWidth: CGFloat in [420, 260, 310] {
            splitView.setPosition(startingWidth, ofDividerAt: 0)
            let event = try mouseEvent(window: window, splitView: splitView, clickCount: 2)
            XCTAssertNil(coordinator.handle(event))
            XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, 310, accuracy: 1)
        }
    }

    @MainActor
    func testMonitorConsumesDoubleClickBeforeNativeDividerHandling() throws {
        let (window, splitView, anchor) = makeSplitView()
        defer { window.orderOut(nil) }
        let coordinator = SidebarDividerAutoFit.Coordinator(preferredWidth: 310)
        coordinator.anchor = anchor
        defer { coordinator.invalidate() }

        splitView.setPosition(420, ofDividerAt: 0)
        let event = try mouseEvent(window: window, splitView: splitView, clickCount: 2)
        NSApp.sendEvent(event)
        XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, 310, accuracy: 1)
    }

    @MainActor
    func testOtherMouseEventsAndWindowsKeepNativeBehavior() throws {
        let (window, splitView, anchor) = makeSplitView()
        defer { window.orderOut(nil) }
        let coordinator = SidebarDividerAutoFit.Coordinator(preferredWidth: 310)
        coordinator.anchor = anchor
        defer { coordinator.invalidate() }

        let singleClick = try mouseEvent(window: window, splitView: splitView, clickCount: 1)
        XCTAssertTrue(coordinator.handle(singleClick) === singleClick)
        let elsewhere = try mouseEvent(window: window, splitView: splitView, clickCount: 2, x: 100)
        XCTAssertTrue(coordinator.handle(elsewhere) === elsewhere)
        let dragged = try mouseEvent(window: window, splitView: splitView, clickCount: 2, type: .leftMouseDragged)
        XCTAssertTrue(coordinator.handle(dragged) === dragged)

        let (otherWindow, otherSplitView, _) = makeSplitView()
        defer { otherWindow.orderOut(nil) }
        let otherEvent = try mouseEvent(window: otherWindow, splitView: otherSplitView, clickCount: 2)
        XCTAssertTrue(coordinator.handle(otherEvent) === otherEvent)
        XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, 420, accuracy: 1)
    }

    @MainActor
    func testActualContentViewFitsNativeSidebarDivider() async throws {
        let suiteName = "CapricornTests.sidebarAutoFit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.languageRawValue = AppLanguage.simplifiedChinese.rawValue
        let model = AppModel()
        var drive = CapricornTests.fixtureDrive(mountedAt: "/")
        drive.protocolName = "Apple Fabric"
        drive.serialNumber = "0ba01ee32464d219"
        drive.volumes[0].name = "Macintosh HD"
        drive.volumes[0].fileSystemType = "APFS"
        drive.volumes[0].totalCapacityBytes = 994_660_000_000
        drive.volumes[0].availableCapacityBytes = 91_550_000_000
        model.drives = [drive]
        model.selectedDriveID = drive.id
        model.snapshots = [drive.id: CapricornTests.fixtureSnapshot(for: drive)]
        let container = try ModelContainerFactory.makeInMemory()
        let availableRowWidth = LockedState<CGFloat>(0)
        let root = ContentView(viewModel: model, preferences: preferences)
            .modelContainer(container)
            .onPreferenceChange(DriveSidebarAvailableWidthPreferenceKey.self) { width in
                availableRowWidth.withLock { $0 = width }
            }
        let hostingView = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()
        let ready = await AsyncTestWaiter.wait {
            self.descendants(of: hostingView).contains {
                ($0 as? SidebarDividerAutoFitView)?.coordinator?.preferredWidth ?? 0 > 260
            }
        }
        XCTAssertTrue(ready)
        let anchor = try XCTUnwrap(descendants(of: hostingView).compactMap { $0 as? SidebarDividerAutoFitView }.first)
        let coordinator = try XCTUnwrap(anchor.coordinator)
        let splitView = try XCTUnwrap(descendants(of: hostingView).compactMap { $0 as? NSSplitView }.first {
            $0.isVertical && $0.arrangedSubviews.count >= 2 && anchor.isDescendant(of: $0.arrangedSubviews[0])
        })
        let preferredWidth = coordinator.preferredWidth
        XCTAssertLessThan(preferredWidth, 420)
        // The native sidebar may impose a slightly larger minimum thickness.
        let fittedWidth = coordinator.fittedWidth(sidebarWidth: splitView.arrangedSubviews[0].frame.width)
        let chromeWidth = fittedWidth - preferredWidth
        splitView.setPosition(fittedWidth, ofDividerAt: 0)
        splitView.layoutSubtreeIfNeeded()
        let allowedWidth = splitView.arrangedSubviews[0].frame.width
        XCTAssertGreaterThanOrEqual(allowedWidth, preferredWidth)
        XCTAssertLessThan(allowedWidth, 420)
        splitView.setPosition(420, ofDividerAt: 0)
        let layoutSettled = await AsyncTestWaiter.wait {
            abs((coordinator.viewportWidth ?? 0) - splitView.arrangedSubviews[0].frame.width + chromeWidth) < 1
        }
        XCTAssertTrue(layoutSettled)
        XCTAssertNil(coordinator.handle(try mouseEvent(window: window, splitView: splitView, clickCount: 2)))
        XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, allowedWidth, accuracy: 1)
        try await Task.sleep(nanoseconds: 100_000_000)
        hostingView.layoutSubtreeIfNeeded()
        let intrinsicRowWidth = await measuredWidth(drive: drive, volume: drive.volumes[0], language: .simplifiedChinese)
        let actualRowWidth = availableRowWidth.snapshot()
        XCTAssertGreaterThanOrEqual(actualRowWidth + 1, intrinsicRowWidth,
                                    "The visible list row must fit its complete content, not just the requested divider position.")

        let renderedRow = DriveSidebarRow(
            drive: drive,
            representativeVolume: drive.volumes[0],
            snapshot: CapricornTests.fixtureSnapshot(for: drive)
        )
        .environment(\.appLanguage, AppLanguage.simplifiedChinese)
        .frame(width: actualRowWidth)
        .padding(14)
        .background(Color.blue)
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: renderedRow)
        renderer.scale = 2
        let renderedImage = try XCTUnwrap(renderer.cgImage)
        let captureURL = URL(fileURLWithPath: "/tmp/Capricorn-sidebar-autofit.png")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: renderedImage).representation(using: .png, properties: [:]))
        try png.write(to: captureURL)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: renderedImage).perform([request])
        let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        XCTAssertTrue(lines.contains {
            $0.contains("Apple Fabric") && $0.replacingOccurrences(of: " ", with: "").contains("1TB")
        },
                      "Rendered sidebar must show the full capacity line: \(lines)")

        var drives = (1...30).map { index in
            var entry = drive
            entry.bsdName = "disk\(index)"
            return entry
        }
        drives[29].serialNumber = String(repeating: "1234567890", count: 8)
        model.drives = drives
        let includesOffscreenDrive = await AsyncTestWaiter.wait {
            coordinator.preferredWidth > 420
        }
        XCTAssertTrue(includesOffscreenDrive, "Auto-fit must include drives below the visible portion of the list.")
        model.drives = [drive]
        let shrinksAfterRemoval = await AsyncTestWaiter.wait {
            abs(coordinator.preferredWidth - preferredWidth) <= 1
        }
        XCTAssertTrue(shrinksAfterRemoval)
    }

    @MainActor
    func testDriveRowMeasuresFullContentIncludingLongRepresentativeVolumeName() async {
        let drive = CapricornTests.fixtureDrive(mountedAt: "/Volumes/Unit")
        var volume = drive.volumes[0]
        let shortWidth = await measuredWidth(drive: drive, volume: volume, language: .english)
        volume.name = "Projects and Media Archive on the External Production Drive"
        let longWidth = await measuredWidth(drive: drive, volume: volume, language: .english)

        XCTAssertGreaterThan(shortWidth, 0)
        XCTAssertGreaterThan(longWidth, shortWidth + 100)
        XCTAssertGreaterThan(longWidth, SidebarAutoFitWidth.defaultMaximum)
    }

    @MainActor
    func testDriveRowWidthTracksLocalizedHealthAndSerialNumberContent() async {
        var drive = CapricornTests.fixtureDrive()
        let shortEnglish = await measuredWidth(drive: drive, volume: nil, language: .english)
        let shortChinese = await measuredWidth(drive: drive, volume: nil, language: .simplifiedChinese)
        XCTAssertGreaterThan(shortEnglish, 0)
        XCTAssertGreaterThan(shortChinese, 0)

        drive.serialNumber = String(repeating: "1234567890", count: 8)
        let longEnglish = await measuredWidth(drive: drive, volume: nil, language: .english)
        XCTAssertGreaterThan(longEnglish, shortEnglish + 100)
    }

    @MainActor
    func testAutoFitIncludesCompleteAppleFabricCapacityLine() async throws {
        var drive = CapricornTests.fixtureDrive(mountedAt: "/")
        drive.protocolName = "Apple Fabric"
        drive.serialNumber = "0ba01ee32464d219"
        drive.volumes[0].name = "Macintosh HD"
        drive.volumes[0].fileSystemType = "APFS"
        drive.volumes[0].totalCapacityBytes = 994_660_000_000
        drive.volumes[0].availableCapacityBytes = 91_550_000_000
        let language = AppLanguage.simplifiedChinese
        let measured = await measuredWidth(drive: drive, volume: drive.volumes[0], language: language)
        let summary = Text("disk0 · APFS · Apple Fabric · \(formatByteCount(drive.sizeBytes))")
            .font(.caption)
            .fixedSize()
        let summaryWidth = NSHostingView(rootView: summary).fittingSize.width
        let badgeWidth = NSHostingView(
            rootView: HealthBadge(status: .good, compact: true)
                .environment(\.appLanguage, language)
                .fixedSize()
        ).fittingSize.width
        XCTAssertGreaterThanOrEqual(measured, ceil(summaryWidth + 24 + 20 + badgeWidth) - 1,
                                    "Full device summary, icon, both gaps and uncompressed health badge must fit.")
    }

    @MainActor
    func testFittedWidthIncludesMeasuredNativeNavigationChrome() {
        let coordinator = SidebarDividerAutoFit.Coordinator(preferredWidth: 310, viewportWidth: 412)
        defer { coordinator.invalidate() }
        XCTAssertEqual(coordinator.fittedWidth(sidebarWidth: 420), 318)
        coordinator.viewportWidth = 302
        XCTAssertEqual(coordinator.fittedWidth(sidebarWidth: 310), 318)
        coordinator.viewportWidth = nil
        XCTAssertEqual(coordinator.fittedWidth(sidebarWidth: 420), 310)
    }

    @MainActor
    private func measuredWidth(
        drive: DriveDevice,
        volume: DriveDevice.Volume?,
        language: AppLanguage
    ) async -> CGFloat {
        let widths = LockedState<[String: CGFloat]>([:])
        let root = DriveSidebarRow(
            drive: drive,
            representativeVolume: volume,
            snapshot: CapricornTests.fixtureSnapshot(for: drive),
            measuresIntrinsicWidth: true
        )
        .environment(\.appLanguage, language)
        .fixedSize(horizontal: true, vertical: true)
        .onPreferenceChange(DriveSidebarWidthPreferenceKey.self) { value in
            widths.withLock { $0 = value }
        }
        let hostingView = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 268, height: 180),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        _ = await AsyncTestWaiter.wait { widths.snapshot()[drive.id] != nil }
        window.orderOut(nil)
        return widths.snapshot()[drive.id] ?? 0
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor
    private func makeSplitView() -> (NSWindow, NSSplitView, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let splitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 600))
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        let sidebar = NSView()
        let anchor = NSView()
        sidebar.addSubview(anchor)
        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(NSView())
        window.contentView = splitView
        splitView.adjustSubviews()
        splitView.setPosition(420, ofDividerAt: 0)
        return (window, splitView, anchor)
    }

    @MainActor
    private func mouseEvent(
        window: NSWindow,
        splitView: NSSplitView,
        clickCount: Int,
        x: CGFloat? = nil,
        type: NSEvent.EventType = .leftMouseDown
    ) throws -> NSEvent {
        let location = splitView.convert(
            NSPoint(x: x ?? splitView.arrangedSubviews[0].frame.maxX + splitView.dividerThickness / 2, y: 200),
            to: nil
        )
        return try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        ))
    }
}
