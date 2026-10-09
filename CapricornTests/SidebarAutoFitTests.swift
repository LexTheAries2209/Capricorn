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
        XCTAssertEqual(SidebarAutoFitWidth.preferred(rowWidths: [310.2, 280, 340.1]), 343)
        XCTAssertEqual(SidebarAutoFitWidth.preferred(rowWidths: [500]), 502)
        XCTAssertEqual(SidebarAutoFitWidth.preferred(rowWidths: [.nan, .infinity, -1, 310]), 312)
        XCTAssertEqual(SidebarAutoFitWidth.preferred(rowWidths: [310], rowInset: 14), 340)
    }

    func testAvailableRowWidthUsesNarrowestVisibleRow() {
        var width = DriveSidebarAvailableWidthPreferenceKey.defaultValue
        for next: CGFloat in [0, 320, 300, 315, .nan] {
            DriveSidebarAvailableWidthPreferenceKey.reduce(value: &width) { next }
        }
        XCTAssertEqual(width, 300)
    }

    @MainActor
    func testAutoFitTracksEnrichedContentUntilManualDividerDrag() async throws {
        let (window, splitView, anchor) = makeSplitView()
        defer { window.orderOut(nil) }
        let coordinator = SidebarDividerAutoFit.Coordinator(preferredWidth: 310)
        coordinator.anchor = anchor
        defer { coordinator.invalidate() }
        XCTAssertNil(coordinator.handle(try mouseEvent(window: window, splitView: splitView, clickCount: 2)))
        coordinator.update(preferredWidth: 390, viewportWidth: nil)
        let expanded = await AsyncTestWaiter.wait { splitView.arrangedSubviews[0].frame.width == 390 }
        XCTAssertTrue(expanded)
        coordinator.update(preferredWidth: 330, viewportWidth: nil)
        let shrunk = await AsyncTestWaiter.wait { splitView.arrangedSubviews[0].frame.width == 330 }
        XCTAssertTrue(shrunk)
        let press = try mouseEvent(window: window, splitView: splitView, clickCount: 1)
        XCTAssertTrue(coordinator.handle(press) === press)
        XCTAssertFalse(coordinator.followsContentWidth)
        splitView.setPosition(350, ofDividerAt: 0)
        coordinator.update(preferredWidth: 400, viewportWidth: nil)
        await Task.yield()
        XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, 350, accuracy: 1)
        XCTAssertNil(coordinator.handle(try mouseEvent(window: window, splitView: splitView, clickCount: 2)))
        XCTAssertTrue(coordinator.followsContentWidth)
        XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, 400, accuracy: 1)
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
            .font(DriveSidebarTypography.metadata)
            .fixedSize()
        let summaryWidth = NSHostingView(rootView: summary).fittingSize.width
        let badgeWidth = NSHostingView(
            rootView: HealthBadge(status: .good, compact: true, labelFont: DriveSidebarTypography.metadata.bold())
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
    func testIntrinsicWidthIncludesEveryLineAcrossDriveKindsAndHealthStates() async {
        let kinds = ["internal", "USB3", "USB4", "Thunderbolt", "card", "virtual", "network"]
        for language in AppLanguage.allCases {
            for kind in kinds {
                for field in 0..<6 {
                    var drive = CapricornTests.fixtureDrive(mountedAt: "/Volumes/Storage")
                    drive.isInternal = kind == "internal"
                    drive.isSystemDisk = drive.isInternal
                    drive.isMemoryCard = kind == "card"
                    drive.isVirtual = kind == "virtual"
                    drive.isNetwork = kind == "network"
                    drive.protocolName = drive.isNetwork ? "SMB" : "PCI-Express"
                    if drive.isNetwork {
                        drive.deviceNode = "//user@production-storage-server.example/Archive"
                    } else if ["USB3", "USB4", "Thunderbolt"].contains(kind) {
                        drive.connectionInfo = DriveConnectionInfo(
                            transport: kind == "Thunderbolt" ? .thunderbolt : .usb,
                            generation: kind == "USB3" ? "USB3.2 Gen 2" : kind,
                            negotiatedBitsPerSecond: 40_000_000_000,
                            pathDescription: nil
                        )
                    }
                    drive.volumes[0].name = "Archive"
                    drive.volumes[0].fileSystemType = "NTFS"
                    drive.volumes[0].totalCapacityBytes = 9_999_999_000_000_000
                    drive.volumes[0].availableCapacityBytes = 6_789_123_000_000
                    let longText = String(repeating: "Archive-0123456789-资料备份-Été-", count: 4)
                    switch field {
                    case 0: drive.volumes[0].name = longText
                    case 1: drive.displayName = longText
                    case 2: drive.serialNumber = longText
                    case 3: drive.protocolName = longText
                    case 4:
                        drive.volumes.append(DriveDevice.Volume(
                            deviceIdentifier: "disk0s2", name: "Photos", mountPoint: "/Volumes/Photos",
                            sizeBytes: 1_000_000, isWritable: true, isSystem: false,
                            fileSystemType: "APFS"
                        ))
                        drive.sizeBytes = 9_999_999_000_000_000
                    default:
                        drive.volumes = []
                        drive.serialNumber = nil
                        drive.sizeBytes = 0
                    }
                    let health = HealthStatus.allCases[field % HealthStatus.allCases.count]
                    let width = await measuredWidth(
                        drive: drive, volume: drive.volumes.first, language: language, health: health
                    )
                    let badge = NSHostingView(rootView: HealthBadge(
                        status: health, compact: true, labelFont: DriveSidebarTypography.metadata.bold()
                    )
                        .environment(\.appLanguage, language).fixedSize()).fittingSize.width
                    let lines = metadataLines(drive: drive, language: language)
                    for (text, font) in lines {
                        let textWidth = NSHostingView(rootView: Text(text).font(font).fixedSize()).fittingSize.width
                        XCTAssertGreaterThanOrEqual(SidebarAutoFitWidth.preferred(rowWidths: [width]), textWidth + 24 + 20 + badge,
                                                    "\(language) \(kind) field \(field) \(health): \(text)")
                    }
                }
            }
        }
    }

    @MainActor
    func testConstrainedAutoFitWrapsMetadataWithoutHidingLineEndings() throws {
        var drive = CapricornTests.fixtureDrive(mountedAt: "/Volumes/Archive")
        drive.volumes[0].name = "Production media archive for the external storage array VolumeEnd"
        drive.displayName = "High capacity external storage device connected through a dock ModelEnd"
        drive.serialNumber = "0123456789-0123456789-0123456789-SerialEnd"
        drive.protocolName = "PCI-Express"
        drive.connectionInfo = DriveConnectionInfo(
            transport: .usb4, generation: "USB4",
            negotiatedBitsPerSecond: 40_000_000_000, pathDescription: nil
        )
        drive.sizeBytes = 4_100_000_000_000
        drive.volumes[0].fileSystemType = "NTFS"
        for language in AppLanguage.allCases {
            let row = DriveSidebarRow(
                drive: drive, representativeVolume: drive.volumes[0],
                snapshot: CapricornTests.fixtureSnapshot(for: drive),
                allowsTextWrapping: true
            )
            .environment(\.appLanguage, language)
            .frame(width: 260)
            .padding(14)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: row)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/Capricorn-sidebar-wrapped-\(language.rawValue).png"))
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = (request.results?.compactMap { $0.topCandidates(1).first?.string } ?? [])
                .joined().replacingOccurrences(of: " ", with: "").lowercased()
            for ending in ["volumeend", "modelend", "serialend", "4.1tb"] {
                XCTAssertTrue(text.contains(ending), "Wrapped row must retain \(ending): \(text)")
            }
        }
    }

    @MainActor
    func testSerialRedactionMeasuresOnlyTheDisplayedSerialText() async throws {
        let suite = "CapricornTests.sidebarRedaction.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var drive = CapricornTests.fixtureDrive()
        drive.serialNumber = String(repeating: "0123456789", count: 15)
        for language in AppLanguage.allCases {
            defaults.set(false, forKey: AppPreferences.Key.redactSerialNumbers)
            let full = await measuredWidth(drive: drive, volume: nil, language: language, defaults: defaults)
            defaults.set(true, forKey: AppPreferences.Key.redactSerialNumbers)
            let redacted = await measuredWidth(drive: drive, volume: nil, language: language, defaults: defaults)
            XCTAssertGreaterThan(full, redacted + 100)
        }
    }

    private func metadataLines(drive: DriveDevice, language: AppLanguage) -> [(String, Font)] {
        var summary = [String]()
        if !drive.isNetwork, !drive.bsdName.isEmpty { summary.append(drive.bsdName) }
        if let format = drive.fileSystemSummary { summary.append(format) }
        if !drive.protocolName.isEmpty,
           !summary.contains(where: { $0.caseInsensitiveCompare(drive.protocolName) == .orderedSame }) {
            summary.append(drive.protocolName)
        }
        if let connection = drive.connectionInfo?.compactLabel { summary.append(connection) }
        if drive.sizeBytes > 0 { summary.append(formatByteCount(drive.sizeBytes)) }
        var lines: [(String, Font)] = [
            (drive.networkServerDisplayName ?? drive.volumes.first?.name ?? drive.sidebarVolumeName, DriveSidebarTypography.title),
            (drive.catalogSidebarDisplayName, DriveSidebarTypography.model),
            (DrivePageHeaderText.serialNumberLine(for: drive, language: language, redact: false), DriveSidebarTypography.metadata),
            (summary.isEmpty ? drive.bsdName : summary.joined(separator: " · "), DriveSidebarTypography.metadata)
        ]
        if let usage = drive.capacityUsage {
            lines.append(("\(language.t("Used")) \(formatByteCount(usage.usedBytes)) · \(language.t("Available")) \(formatByteCount(usage.availableBytes))", DriveSidebarTypography.metadata))
        }
        return lines
    }

    @MainActor
    func testTwoDriveSidebarShowsFullUSB4CapacityInBothLanguagesAndAppearances() async throws {
        for language in AppLanguage.allCases {
            for appearance in [ColorScheme.light, .dark] {
                try await verifyTwoDriveSidebar(language: language, appearance: appearance)
                try await verifyTwoDriveSidebar(language: language, appearance: appearance, usesLongIdentity: true)
                try await verifyTwoDriveSidebar(language: language, appearance: appearance, loadsExternalAfterFit: true)
                try await verifyTwoDriveSidebar(language: language, appearance: appearance, loadsEnrichmentAfterFit: true)
                try await verifyTwoDriveSidebar(language: language, appearance: appearance, exceedsWindowWidth: true)
            }
        }
    }

    @MainActor
    func testNativeSidebarScreenshotsRetainLongFieldsAcrossDriveKinds() async throws {
        let kinds = ["internal", "USB3", "USB4", "Thunderbolt", "card", "virtual", "network"]
        for language in AppLanguage.allCases {
            for (index, kind) in kinds.enumerated() {
                var drive = CapricornTests.fixtureDrive(mountedAt: "/Volumes/Storage")
                drive.isInternal = kind == "internal"
                drive.isSystemDisk = drive.isInternal
                drive.isMemoryCard = kind == "card"
                drive.isVirtual = kind == "virtual"
                drive.isNetwork = kind == "network"
                drive.volumes[0].name = String(repeating: "Production Archive ", count: 10) + "VolumeEnd"
                drive.displayName = String(repeating: "External Storage ", count: 10) + "ModelEnd"
                drive.serialNumber = String(repeating: "0123456789-", count: 10) + "SerialEnd"
                drive.protocolName = String(repeating: "Transport ", count: 10) + "ProtocolEnd"
                drive.sizeBytes = 4_100_000_000_000
                drive.volumes[0].fileSystemType = "NTFS"
                if drive.isNetwork {
                    drive.deviceNode = "//user@storage-server-HostEnd.example/Archive"
                } else if ["USB3", "USB4", "Thunderbolt"].contains(kind) {
                    drive.connectionInfo = DriveConnectionInfo(
                        transport: kind == "Thunderbolt" ? .thunderbolt : .usb,
                        generation: kind, negotiatedBitsPerSecond: 40_000_000_000,
                        pathDescription: nil
                    )
                }
                let suite = "CapricornTests.nativeKinds.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let preferences = AppPreferences(defaults: defaults)
                preferences.languageRawValue = language.rawValue
                let model = AppModel()
                model.showVirtualDisks = true
                model.drives = [drive]
                model.selectedDriveID = drive.id
                var snapshot = CapricornTests.fixtureSnapshot(for: drive)
                snapshot.health = HealthStatus.allCases[index % HealthStatus.allCases.count]
                model.snapshots = [drive.id: snapshot]
                let widths = LockedState<[String: CGFloat]>([:])
                let root = ContentView(viewModel: model, preferences: preferences)
                    .modelContainer(try ModelContainerFactory.makeInMemory())
                    .environment(\.colorScheme, .light)
                    .onPreferenceChange(DriveSidebarWidthPreferenceKey.self) { value in
                        widths.withLock { $0 = value }
                    }
                let hostingView = NSHostingView(rootView: root)
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 1_433, height: 850),
                    styleMask: [.titled, .resizable], backing: .buffered, defer: false
                )
                window.appearance = NSAppearance(named: .aqua)
                window.contentView = hostingView
                window.makeKeyAndOrderFront(nil)
                defer { window.orderOut(nil) }
                hostingView.layoutSubtreeIfNeeded()
                let ready = await AsyncTestWaiter.wait { widths.snapshot()[drive.id] != nil }
                XCTAssertTrue(ready)
                let anchor = try XCTUnwrap(descendants(of: hostingView).compactMap { $0 as? SidebarDividerAutoFitView }.first)
                let coordinator = try XCTUnwrap(anchor.coordinator)
                let splitView = try XCTUnwrap(descendants(of: hostingView).compactMap { $0 as? NSSplitView }.first {
                    $0.isVertical && $0.arrangedSubviews.count >= 2 && anchor.isDescendant(of: $0.arrangedSubviews[0])
                })
                XCTAssertNil(coordinator.handle(try mouseEvent(window: window, splitView: splitView, clickCount: 2)))
                try await Task.sleep(nanoseconds: 150_000_000)
                hostingView.layoutSubtreeIfNeeded()
                let image = try captureNativeSidebar(
                    window: window, splitView: splitView,
                    name: "\(language.rawValue)-\(kind)-long-fields"
                )
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "en-US"]
                try VNImageRequestHandler(cgImage: image).perform([request])
                let text = (request.results?.compactMap { $0.topCandidates(1).first?.string } ?? [])
                    .joined().replacingOccurrences(of: " ", with: "").lowercased()
                for ending in [drive.isNetwork ? "hostend" : "volumeend", "modelend", "serialend", "protocolend", "4.1tb"] {
                    XCTAssertTrue(text.contains(ending), "\(language) \(kind) native sidebar hid \(ending): \(text)")
                }
            }
        }
    }

    @MainActor
    private func verifyTwoDriveSidebar(
        language: AppLanguage,
        appearance: ColorScheme,
        usesLongIdentity: Bool = false,
        loadsExternalAfterFit: Bool = false,
        loadsEnrichmentAfterFit: Bool = false,
        exceedsWindowWidth: Bool = false
    ) async throws {
        var internalDrive = CapricornTests.fixtureDrive(mountedAt: "/")
        internalDrive.protocolName = "Apple Fabric"
        internalDrive.serialNumber = "0ba01ee32464d219"
        internalDrive.volumes[0].name = "Macintosh HD"
        internalDrive.volumes[0].fileSystemType = "APFS"
        var externalDrive = CapricornTests.fixtureDrive(mountedAt: "/Volumes/40G4T_NTFS_E")
        externalDrive.bsdName = "disk4"
        externalDrive.deviceNode = "/dev/disk4"
        externalDrive.isInternal = false
        externalDrive.isSystemDisk = false
        externalDrive.model = "GeIL P4S 4TB"
        externalDrive.displayName = "GeIL P4S 4TB"
        externalDrive.mediaName = "GeIL P4S 4TB"
        externalDrive.protocolName = "PCI-Express"
        externalDrive.serialNumber = "WKCI3602785"
        externalDrive.sizeBytes = 4_100_000_000_000
        externalDrive.connectionInfo = DriveConnectionInfo(
            transport: .usb4, generation: "USB4",
            negotiatedBitsPerSecond: 40_000_000_000, pathDescription: nil
        )
        externalDrive.volumes[0].name = "40G4T_NTFS_E"
        externalDrive.volumes[0].deviceIdentifier = "disk4s1"
        externalDrive.volumes[0].fileSystemType = "NTFS"
        externalDrive.volumes[0].sizeBytes = externalDrive.sizeBytes
        externalDrive.volumes[0].totalCapacityBytes = externalDrive.sizeBytes
        externalDrive.volumes[0].availableCapacityBytes = 65_000_000_000
        if usesLongIdentity {
            externalDrive.serialNumber = String(repeating: "0123456789", count: 6)
            externalDrive.volumes[0].name = "Production media and project archive for the external storage array"
        }
        if exceedsWindowWidth {
            externalDrive.volumes[0].name = String(repeating: "Storage-Archive-", count: 30)
        }
        let drives = [internalDrive, externalDrive]
        var discoveryDrive = externalDrive
        if loadsEnrichmentAfterFit {
            discoveryDrive.connectionInfo = nil
            discoveryDrive.protocolName = "USB"
            discoveryDrive.serialNumber = nil
        }
        let model = AppModel()
        model.drives = loadsExternalAfterFit ? [internalDrive] : [internalDrive, discoveryDrive]
        model.selectedDriveID = internalDrive.id
        model.snapshots = Dictionary(uniqueKeysWithValues: drives.map {
            ($0.id, CapricornTests.fixtureSnapshot(for: $0))
        })
        let suite = "CapricornTests.twoDriveAutoFit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.languageRawValue = language.rawValue
        let intrinsicWidths = LockedState<[String: CGFloat]>([:])
        let availableWidth = LockedState<CGFloat>(0)
        let container = try ModelContainerFactory.makeInMemory()
        let root = ContentView(viewModel: model, preferences: preferences)
            .modelContainer(container)
            .environment(\.colorScheme, appearance)
            .onPreferenceChange(DriveSidebarWidthPreferenceKey.self) { value in
                intrinsicWidths.withLock { $0 = value }
            }
            .onPreferenceChange(DriveSidebarAvailableWidthPreferenceKey.self) { value in
                availableWidth.withLock { $0 = value }
            }
        let hostingView = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_433, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.contentView = hostingView
        window.appearance = NSAppearance(named: appearance == .light ? .aqua : .darkAqua)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hostingView.layoutSubtreeIfNeeded()
        let ready = await AsyncTestWaiter.wait {
            intrinsicWidths.snapshot().count == model.drives.count && availableWidth.snapshot() > 0
        }
        XCTAssertTrue(ready)
        let anchor = try XCTUnwrap(descendants(of: hostingView).compactMap { $0 as? SidebarDividerAutoFitView }.first)
        let coordinator = try XCTUnwrap(anchor.coordinator)
        let splitView = try XCTUnwrap(descendants(of: hostingView).compactMap { $0 as? NSSplitView }.first {
            $0.isVertical && $0.arrangedSubviews.count >= 2 && anchor.isDescendant(of: $0.arrangedSubviews[0])
        })
        XCTAssertNil(coordinator.handle(try mouseEvent(window: window, splitView: splitView, clickCount: 2)))
        if loadsExternalAfterFit || loadsEnrichmentAfterFit {
            model.drives = drives
            let expected = await measuredWidth(drive: externalDrive, volume: externalDrive.volumes[0], language: language)
            let loaded = await AsyncTestWaiter.wait {
                abs((intrinsicWidths.snapshot()[externalDrive.id] ?? 0) - expected) <= 1
            }
            XCTAssertTrue(loaded)
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        hostingView.layoutSubtreeIfNeeded()
        let width = availableWidth.snapshot()
        let widths = intrinsicWidths.snapshot()
        if exceedsWindowWidth {
            XCTAssertLessThan(width, try XCTUnwrap(widths[externalDrive.id]))
            XCTAssertTrue(coordinator.followsContentWidth)
            XCTAssertLessThanOrEqual(
                splitView.arrangedSubviews[0].frame.width,
                window.contentLayoutRect.width - SidebarAutoFitWidth.minimumDetailWidth,
                "Auto-fit must preserve visible space for the selected drive."
            )
        } else {
            XCTAssertGreaterThanOrEqual(width + 1, try XCTUnwrap(widths[externalDrive.id]),
                                        "Actual external row must fit: divider \(splitView.arrangedSubviews[0].frame.width), viewport \(coordinator.viewportWidth ?? 0), target \(coordinator.preferredWidth), measured \(widths)")
        }
        let scenario = exceedsWindowWidth ? "window-limit" : usesLongIdentity ? "long-identity"
            : loadsExternalAfterFit ? "late-drive" : loadsEnrichmentAfterFit ? "late-metadata" : "normal"
        let recognitionImage = try captureNativeSidebar(
            window: window, splitView: splitView,
            name: "\(language.rawValue)-\(appearance == .light ? "light" : "dark")-\(scenario)"
        )
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: recognitionImage).perform([request])
        let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        XCTAssertTrue(lines.contains {
            $0.contains("USB4") && $0.replacingOccurrences(of: " ", with: "").contains("4.1TB")
        }, "Native sidebar USB4 capacity must be complete: \(lines)")
    }

    @MainActor
    private func captureNativeSidebar(window: NSWindow, splitView: NSSplitView, name: String) throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Native sidebar screenshot verification requires Screen Recording permission.")
        }
        let captureURL = URL(fileURLWithPath: "/tmp/Capricorn-native-sidebar-\(name).png")
        // Native List rows are separate drawing layers; cacheDisplay and
        // ImageRenderer do not capture what the window server actually shows.
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", captureURL.path]
        try capture.run()
        capture.waitUntilExit()
        XCTAssertEqual(capture.terminationStatus, 0)
        let image = try XCTUnwrap(NSImage(contentsOf: captureURL)?.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ))
        let scale = CGFloat(image.width) / window.frame.width
        // Inspect the actual native sidebar, not a separately rendered row.
        return try XCTUnwrap(image.cropping(to: CGRect(
            x: 0, y: 0,
            width: min(CGFloat(image.width), ceil(splitView.arrangedSubviews[0].frame.width * scale)),
            height: CGFloat(image.height)
        )))
    }

    @MainActor
    private func measuredWidth(
        drive: DriveDevice,
        volume: DriveDevice.Volume?,
        language: AppLanguage,
        health: HealthStatus = .good,
        defaults: UserDefaults = .standard
    ) async -> CGFloat {
        let widths = LockedState<[String: CGFloat]>([:])
        var snapshot = CapricornTests.fixtureSnapshot(for: drive)
        snapshot.health = health
        let root = DriveSidebarRow(
            drive: drive,
            representativeVolume: volume,
            snapshot: snapshot,
            measuresIntrinsicWidth: true
        )
        .defaultAppStorage(defaults)
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
