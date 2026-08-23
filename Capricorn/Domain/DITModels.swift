// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI

enum HealthStatus: String, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case good
    case warning
    case preFail
    case failed
    case unavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .good: "Good"
        case .warning: "Warning"
        case .preFail: "Pre-Fail"
        case .failed: "Failed"
        case .unavailable: "Unavailable"
        }
    }

    var symbolName: String {
        switch self {
        case .good: "checkmark.seal.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .preFail: "exclamationmark.octagon.fill"
        case .failed: "xmark.octagon.fill"
        case .unavailable: "questionmark.circle.fill"
        }
    }

    var severity: Int {
        switch self {
        case .good: 0
        case .warning: 1
        case .preFail: 2
        case .failed: 3
        case .unavailable: -1
        }
    }

    static func < (lhs: HealthStatus, rhs: HealthStatus) -> Bool {
        lhs.severity < rhs.severity
    }
}

enum ProviderState: String, Codable, CaseIterable, Sendable {
    case available
    case limited
    case unavailable
    case failed
}

struct ProviderStatus: Identifiable, Codable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var state: ProviderState
    var message: String
}

struct DriveDevice: Identifiable, Codable, Hashable, Sendable {
    struct Volume: Identifiable, Codable, Hashable, Sendable {
        var id: String { deviceIdentifier }
        var deviceIdentifier: String
        var name: String
        var mountPoint: String?
        var sizeBytes: Int64
        var isWritable: Bool
        var isSystem: Bool
        var fileSystemType: String? = nil
        var capacityGroupIdentifier: String? = nil
        var totalCapacityBytes: Int64? = nil
        var availableCapacityBytes: Int64? = nil
    }

    var id: String { bsdName }
    var bsdName: String
    var deviceNode: String
    var displayName: String
    var mediaName: String
    var protocolName: String
    var sizeBytes: Int64
    var blockSize: Int
    var isInternal: Bool
    var isRemovable: Bool
    var isSolidState: Bool
    var isWritable: Bool
    var isVirtual: Bool
    var isSystemDisk: Bool
    var isNetwork: Bool = false
    var isMemoryCard: Bool = false
    var smartStatusRaw: String?
    var nativeSmartKeys: [String: Int64]
    var volumes: [Volume]
    var model: String?
    var serialNumber: String?

    var capacityUsage: DriveCapacityUsage? {
        DriveCapacityUsage.resolve(volumes: volumes)
    }

    var benchmarkMountPoint: String? {
        volumes.first(where: { $0.isWritable && !$0.isSystem && $0.mountPoint != nil })?.mountPoint
            ?? volumes.first(where: { $0.isWritable && $0.mountPoint != nil })?.mountPoint
    }

    var primaryMountPoint: String? {
        volumes.first(where: { $0.mountPoint == "/" })?.mountPoint
            ?? volumes.first(where: { $0.mountPoint != nil })?.mountPoint
    }

    var actionTargetVolume: Volume? {
        volumes.first(where: { !$0.isSystem && $0.mountPoint != nil })
            ?? volumes.first(where: { $0.mountPoint != nil })
            ?? volumes.first
    }

    var fileSystemSummary: String? {
        if isNetwork {
            return protocolName.isEmpty ? nil : protocolName
        }

        let formats = volumes
            .compactMap { FileSystemFormatResolver.normalized($0.fileSystemType) }
            .reduce(into: [String]()) { result, format in
                if !result.contains(format) {
                    result.append(format)
                }
            }

        if formats.isEmpty {
            return nil
        }
        if formats.count == 1 {
            return formats[0]
        }
        return formats.joined(separator: " + ")
    }
}

struct DriveCapacityUsage: Equatable, Sendable {
    var totalBytes: Int64
    var usedBytes: Int64
    var availableBytes: Int64

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    static func resolve(volumes: [DriveDevice.Volume]) -> DriveCapacityUsage? {
        var capacitiesByGroup: [String: (total: Int64, available: Int64)] = [:]

        for volume in volumes {
            guard let total = volume.totalCapacityBytes,
                  let available = volume.availableCapacityBytes,
                  total > 0,
                  available >= 0 else {
                continue
            }

            let group = volume.capacityGroupIdentifier ?? volume.deviceIdentifier
            let clampedAvailable = min(available, total)
            if let current = capacitiesByGroup[group] {
                capacitiesByGroup[group] = (
                    total: max(current.total, total),
                    available: max(current.available, clampedAvailable)
                )
            } else {
                capacitiesByGroup[group] = (total: total, available: clampedAvailable)
            }
        }

        guard !capacitiesByGroup.isEmpty else { return nil }
        let total = capacitiesByGroup.values.reduce(Int64(0)) { $0 + $1.total }
        let available = min(
            capacitiesByGroup.values.reduce(Int64(0)) { $0 + $1.available },
            total
        )
        return DriveCapacityUsage(
            totalBytes: total,
            usedBytes: total - available,
            availableBytes: available
        )
    }
}

enum FileSystemFormatResolver {
    static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let lower = value.lowercased()
        if lower.contains("apfs") {
            return "APFS"
        }
        if lower.contains("exfat") || lower.contains("ex-fat") {
            return "ExFAT"
        }
        if lower.contains("ntfs") {
            return "NTFS"
        }
        if lower.contains("hfs") || lower.contains("mac os extended") {
            return "HFS+"
        }
        if lower.contains("ms-dos") || lower.contains("msdos") {
            return "MS-DOS"
        }
        if lower.contains("fat32") || lower.contains("fat 32") {
            return "FAT32"
        }
        if lower == "microsoft basic data" {
            return nil
        }

        return value
    }

    static func fileSystemType(atMountPoint mountPoint: String) -> String? {
        let url = URL(fileURLWithPath: mountPoint, isDirectory: true)
        guard let values = try? url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey]),
              let description = values.volumeLocalizedFormatDescription else {
            return nil
        }
        return normalized(description)
    }
}

enum DiskSidebarAction: String, CaseIterable, Identifiable, Equatable {
    case mount
    case unmount
    case forceUnmount
    case eject
    case inspectOpenFiles
    case checkLog
    case detailedCheck
    case firstAid
    case rename
    case revealInFinder
    case refresh
    case disconnect

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .mount: "Mount"
        case .unmount: "Unmount"
        case .forceUnmount: "Force Unmount"
        case .eject: "Eject"
        case .inspectOpenFiles: "View Open Files"
        case .checkLog: "Check Log"
        case .detailedCheck: "Detailed Check"
        case .firstAid: "First Aid…"
        case .rename: "Rename Volume"
        case .revealInFinder: "Reveal in Finder"
        case .refresh: "Refresh"
        case .disconnect: "Disconnect"
        }
    }

    var systemImage: String {
        switch self {
        case .mount: "externaldrive.badge.plus"
        case .unmount: "externaldrive.badge.minus"
        case .forceUnmount: "externaldrive.badge.xmark"
        case .eject: "eject"
        case .inspectOpenFiles: "person.crop.circle.badge.exclamationmark"
        case .checkLog: "doc.text.magnifyingglass"
        case .detailedCheck: "stethoscope"
        case .firstAid: "cross.case.fill"
        case .rename: "pencil"
        case .revealInFinder: "folder"
        case .refresh: "arrow.clockwise"
        case .disconnect: "network.slash"
        }
    }
}

enum DiskSidebarActionPolicy {
    static func actions(for drive: DriveDevice) -> [DiskSidebarAction] {
        if drive.isNetwork {
            return [.mount, .unmount, .disconnect, .inspectOpenFiles]
        }
        return [.checkLog, .detailedCheck, .firstAid, .mount, .unmount, .forceUnmount, .eject, .inspectOpenFiles, .rename, .revealInFinder, .refresh]
    }

    static func isEnabled(_ action: DiskSidebarAction, for drive: DriveDevice) -> Bool {
        if isProtectedSystemControlAction(action, for: drive) {
            return false
        }

        switch action {
        case .mount:
            return drive.isNetwork ? networkMountURL(for: drive) != nil : true
        case .unmount, .forceUnmount:
            return drive.primaryMountPoint != nil || !drive.isNetwork
        case .disconnect:
            return drive.isNetwork && drive.primaryMountPoint != nil
        case .eject:
            return !drive.isNetwork && (!drive.isInternal || drive.isRemovable || drive.isMemoryCard)
        case .inspectOpenFiles:
            return drive.primaryMountPoint != nil
        case .checkLog, .detailedCheck:
            return !isProtectedInternalSystemDisk(drive) && !drive.isNetwork && (!drive.bsdName.isEmpty || !drive.volumes.isEmpty)
        case .firstAid:
            return !drive.isNetwork && (!drive.bsdName.isEmpty || !drive.volumes.isEmpty)
        case .rename:
            return !drive.isNetwork && !drive.isSystemDisk && drive.actionTargetVolume != nil
        case .revealInFinder:
            return drive.primaryMountPoint != nil
        case .refresh:
            return true
        }
    }

    static func isProtectedSystemControlAction(_ action: DiskSidebarAction, for drive: DriveDevice) -> Bool {
        guard isProtectedInternalSystemDisk(drive) else { return false }
        switch action {
        case .mount, .unmount, .forceUnmount, .eject:
            return true
        case .inspectOpenFiles, .checkLog, .detailedCheck, .firstAid, .rename, .revealInFinder, .refresh, .disconnect:
            return false
        }
    }

    static func isProtectedInternalSystemDisk(_ drive: DriveDevice) -> Bool {
        guard !drive.isNetwork, drive.isInternal else { return false }
        if drive.isSystemDisk { return true }
        return drive.volumes.contains { volume in
            if volume.isSystem { return true }
            guard let mountPoint = volume.mountPoint else { return false }
            return mountPoint == "/" || mountPoint.hasPrefix("/System/Volumes")
        }
    }

    static func networkMountURL(for drive: DriveDevice) -> URL? {
        guard drive.isNetwork else { return nil }
        let source = drive.deviceNode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }

        if source.contains("://") {
            return URL(string: source)
        }

        let protocolName = drive.protocolName.lowercased()
        if source.hasPrefix("//") {
            let hostPath = String(source.dropFirst(2))
            let scheme: String
            switch protocolName {
            case "afp":
                scheme = "afp"
            case "webdav":
                scheme = "http"
            case "sshfs":
                scheme = "ssh"
            default:
                scheme = "smb"
            }
            return URL(string: "\(scheme)://\(hostPath)")
        }

        if protocolName == "nfs", let separator = source.range(of: ":/") {
            let host = String(source[..<separator.lowerBound])
            let path = String(source[separator.upperBound...])
            return URL(string: "nfs://\(host)/\(path)")
        }

        return nil
    }
}

struct DiskOpenFileProcess: Identifiable, Hashable, Sendable {
    var id: String { "\(pid)-\(path)" }
    var command: String
    var pid: Int
    var user: String
    var path: String
}

struct DiskOpenFileInspection: Identifiable, Hashable, Sendable {
    var id = UUID()
    var driveID: String
    var driveName: String
    var mountPoint: String
    var capturedAt: Date = Date()
    var processes: [DiskOpenFileProcess]
}

struct DiskActionFailure: Identifiable, Hashable, Sendable {
    var id = UUID()
    var action: DiskSidebarAction
    var drive: DriveDevice
    var message: String
    var openFiles: DiskOpenFileInspection

    var canForceUnmount: Bool {
        action != .forceUnmount && DiskSidebarActionPolicy.isEnabled(.forceUnmount, for: drive)
    }
}

enum DiskCheckMode: String, CaseIterable, Codable, Hashable, Sendable {
    case ordinary
    case detailed

    var titleKey: String {
        switch self {
        case .ordinary: "Check Log"
        case .detailed: "Detailed Check"
        }
    }

    var descriptionKey: String {
        switch self {
        case .ordinary: "Runs diskutil verification and shows the complete system log."
        case .detailed: "Runs read-only filesystem-specific fsck checks where macOS provides a checker."
        }
    }
}

extension DiskCheckMode {
    var sidebarAction: DiskSidebarAction {
        switch self {
        case .ordinary: .checkLog
        case .detailed: .detailedCheck
        }
    }
}

struct DiskCheckEntry: Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var executable: String?
    var arguments: [String]
    var terminationStatus: Int32?
    var stdout: String
    var stderr: String
    var isRunning: Bool = false

    var commandLine: String {
        ([executable].compactMap { $0 } + arguments).joined(separator: " ")
    }

    var hasIssue: Bool {
        guard !isRunning else { return false }
        if terminationStatus == nil { return true }
        return terminationStatus != 0
    }

    var combinedOutput: String {
        let parts = [stdout, stderr].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return parts.isEmpty ? "No output." : parts.joined(separator: "\n")
    }
}

struct DiskCheckReport: Identifiable, Hashable, Sendable {
    var id = UUID()
    var mode: DiskCheckMode
    var driveID: String
    var driveName: String
    var capturedAt: Date = Date()
    var entries: [DiskCheckEntry]

    var hasIssues: Bool {
        entries.contains(where: \.hasIssue)
    }

    var completedEntryCount: Int {
        entries.filter { !$0.isRunning }.count
    }

    var totalEntryCount: Int {
        entries.count
    }

    var progressFraction: Double {
        guard totalEntryCount > 0 else { return 0 }
        return Double(completedEntryCount) / Double(totalEntryCount)
    }
}

enum DiskFirstAidTargetSupport: String, Hashable, Sendable {
    case eligible
    case unsupportedFormat
    case ntfsRequiresWindows
    case systemVolume
    case internalDisk
    case networkVolume
    case virtualDisk
    case readOnly
    case locked
    case missingDevice
    case preflightFailed

    var isEligible: Bool {
        self == .eligible
    }

    var messageKey: String {
        switch self {
        case .eligible:
            return "Ready for First Aid"
        case .unsupportedFormat:
            return "This filesystem is not supported for native First Aid on macOS."
        case .ntfsRequiresWindows:
            return "macOS cannot natively repair NTFS. Use Windows CHKDSK or the filesystem vendor's tool."
        case .systemVolume:
            return "Startup and system volumes must be repaired from macOS Recovery."
        case .internalDisk:
            return "Direct First Aid is limited to external or removable disks."
        case .networkVolume:
            return "Network volumes do not expose a local repair target."
        case .virtualDisk:
            return "Virtual disks are not eligible for direct First Aid."
        case .readOnly:
            return "The volume or media is read-only and cannot be repaired."
        case .locked:
            return "Unlock the volume before running First Aid."
        case .missingDevice:
            return "The volume has no stable local device identifier."
        case .preflightFailed:
            return "The current disk information could not be verified. Refresh and try again."
        }
    }
}

enum DiskFirstAidBlockReason: String, Hashable, Sendable {
    case networkVolume
    case virtualDisk
    case internalDisk
    case systemDisk
    case unhealthyMedia
    case noEligibleVolumes

    var messageKey: String {
        switch self {
        case .networkVolume:
            return "Network volumes cannot run local First Aid."
        case .virtualDisk:
            return "Virtual disks are not eligible for direct First Aid."
        case .internalDisk:
            return "Direct First Aid is limited to external or removable disks."
        case .systemDisk:
            return "System disks must be repaired from macOS Recovery."
        case .unhealthyMedia:
            return "SMART reports a failing device. Back up data and replace the disk instead of repairing it here."
        case .noEligibleVolumes:
            return "No external APFS or ExFAT volume is eligible for direct First Aid."
        }
    }
}

struct DiskFirstAidTarget: Identifiable, Hashable, Sendable {
    var id: String { deviceIdentifier }
    var deviceIdentifier: String
    var volumeUUID: String?
    var parentWholeDisk: String?
    var volumeName: String
    var fileSystemType: String?
    var mountPoint: String?
    var sizeBytes: Int64
    var isMounted: Bool
    var isWritable: Bool
    var isLocked: Bool
    var isSystem: Bool
    var support: DiskFirstAidTargetSupport

    var isEligible: Bool {
        support.isEligible
    }
}

struct DiskFirstAidPlan: Identifiable, Hashable, Sendable {
    var id = UUID()
    var driveID: String
    var driveName: String
    var physicalDiskIdentifier: String
    var health: HealthStatus
    var targets: [DiskFirstAidTarget]
    var blockedReason: DiskFirstAidBlockReason?
    var requiresHealthWarningConfirmation: Bool
    var selectedTargetIDs: Set<String> = []

    var selectedTargets: [DiskFirstAidTarget] {
        targets.filter { selectedTargetIDs.contains($0.id) && $0.isEligible }
    }

    var eligibleTargets: [DiskFirstAidTarget] {
        targets.filter { $0.isEligible }
    }
}

enum DiskFirstAidSessionState: String, Hashable, Sendable {
    case idle
    case preflighting
    case awaitingConfirmation
    case running
    case stoppingAfterCurrent
    case refreshing
    case completed

    var isActive: Bool {
        switch self {
        case .idle, .completed, .awaitingConfirmation:
            return false
        case .preflighting, .running, .stoppingAfterCurrent, .refreshing:
            return true
        }
    }

    var isRepairing: Bool {
        switch self {
        case .running, .stoppingAfterCurrent:
            return true
        case .idle, .preflighting, .awaitingConfirmation, .refreshing, .completed:
            return false
        }
    }
}

enum DiskFirstAidOutputStream: String, Hashable, Sendable {
    case stdout
    case stderr
}

enum DiskFirstAidTargetOutcome: String, Hashable, Sendable {
    case succeeded
    case failed
    case skipped
}

struct DiskFirstAidTargetResult: Identifiable, Hashable, Sendable {
    var id: String
    var target: DiskFirstAidTarget
    var outcome: DiskFirstAidTargetOutcome
    var terminationStatus: Int32?
    var stdout: String
    var stderr: String
}

struct DiskFirstAidReport: Identifiable, Hashable, Sendable {
    var id: UUID
    var driveID: String
    var driveName: String
    var capturedAt: Date
    var results: [DiskFirstAidTargetResult]

    var completedTargetCount: Int {
        results.count
    }

    var totalTargetCount: Int {
        results.count
    }

    var hasFailures: Bool {
        results.contains { $0.outcome == .failed }
    }

    var succeededTargetCount: Int {
        results.filter { $0.outcome == .succeeded }.count
    }
}

enum DiskFirstAidEvent: Sendable {
    case targetStarted(runID: UUID, target: DiskFirstAidTarget, index: Int, total: Int)
    case output(runID: UUID, targetID: String, stream: DiskFirstAidOutputStream, text: String)
    case targetFinished(runID: UUID, result: DiskFirstAidTargetResult, index: Int, total: Int)
    case completed(runID: UUID, report: DiskFirstAidReport)
}

enum DiskOpenFileTableLayout {
    static let columnWidths: [CGFloat] = [150, 80, 110, 900]
    static let spacing: CGFloat = 12
    static var contentWidth: CGFloat {
        columnWidths.reduce(0, +) + spacing * CGFloat(max(0, columnWidths.count - 1))
    }
}

enum AppCommandShortcut {
    static let refreshDisks = (key: "r", modifiers: EventModifiers.command)
    static let refreshDisksKeyEquivalent = KeyEquivalent("r")
    static let settings = (key: "p", modifiers: EventModifiers.command)
    static let settingsKeyEquivalent = KeyEquivalent("p")
    static let nextFeatureTab = (key: "tab", modifiers: EventModifiers.control)
    static let previousFeatureTab = (key: "tab", modifiers: EventModifiers.control.union(.shift))
    static let featureTabCharacter: Character = "\t"
    static let featureTabKeyEquivalent = KeyEquivalent(featureTabCharacter)
}

enum AppFeatureTabKeyAction: Equatable {
    case next
    case previous
}

enum AppFeatureTabKeyRouter {
    static let tabKeyCode: UInt16 = 48

    static func action(
        keyCode: UInt16? = nil,
        charactersIgnoringModifiers: String?,
        hasShift: Bool,
        hasDisqualifyingModifiers: Bool
    ) -> AppFeatureTabKeyAction? {
        let isTabKey = charactersIgnoringModifiers == String(AppCommandShortcut.featureTabCharacter)
            || keyCode == tabKeyCode
        guard isTabKey, !hasDisqualifyingModifiers else { return nil }
        return hasShift ? .previous : .next
    }
}

enum DrivePageHeaderText {
    static func serialNumber(for drive: DriveDevice) -> String {
        drive.serialNumber ?? "nil"
    }

    static func mediaKind(for drive: DriveDevice, language: AppLanguage) -> String {
        if drive.isNetwork {
            return language.t("Network Drive")
        }
        if drive.isMemoryCard {
            return language.t("SD Card")
        }
        return drive.isSolidState ? language.t("SSD") : language.t("HDD/Media")
    }

    static func subtitle(for drive: DriveDevice, language: AppLanguage) -> String {
        "\(drive.bsdName) · \(drive.protocolName) · \(mediaKind(for: drive, language: language))"
    }
}

enum DriveFeatureTab: String, CaseIterable, Identifiable {
    case overview
    case smart
    case benchmark
    case liveActivity
    case history

    var id: String { rawValue }

    static func next(after tab: DriveFeatureTab) -> DriveFeatureTab {
        tab.offset(by: 1)
    }

    static func previous(before tab: DriveFeatureTab) -> DriveFeatureTab {
        tab.offset(by: -1)
    }

    private func offset(by distance: Int) -> DriveFeatureTab {
        let tabs = Self.allCases
        guard let index = tabs.firstIndex(of: self) else { return .overview }
        let nextIndex = (index + distance + tabs.count) % tabs.count
        return tabs[nextIndex]
    }
}

extension DriveDevice {
    private enum CodingKeys: String, CodingKey {
        case bsdName
        case deviceNode
        case displayName
        case mediaName
        case protocolName
        case sizeBytes
        case blockSize
        case isInternal
        case isRemovable
        case isSolidState
        case isWritable
        case isVirtual
        case isSystemDisk
        case isNetwork
        case isMemoryCard
        case smartStatusRaw
        case nativeSmartKeys
        case volumes
        case model
        case serialNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bsdName = try container.decode(String.self, forKey: .bsdName)
        deviceNode = try container.decode(String.self, forKey: .deviceNode)
        displayName = try container.decode(String.self, forKey: .displayName)
        mediaName = try container.decode(String.self, forKey: .mediaName)
        protocolName = try container.decode(String.self, forKey: .protocolName)
        sizeBytes = try container.decode(Int64.self, forKey: .sizeBytes)
        blockSize = try container.decode(Int.self, forKey: .blockSize)
        isInternal = try container.decode(Bool.self, forKey: .isInternal)
        isRemovable = try container.decode(Bool.self, forKey: .isRemovable)
        isSolidState = try container.decode(Bool.self, forKey: .isSolidState)
        isWritable = try container.decode(Bool.self, forKey: .isWritable)
        isVirtual = try container.decode(Bool.self, forKey: .isVirtual)
        isSystemDisk = try container.decode(Bool.self, forKey: .isSystemDisk)
        isNetwork = try container.decodeIfPresent(Bool.self, forKey: .isNetwork) ?? false
        isMemoryCard = try container.decodeIfPresent(Bool.self, forKey: .isMemoryCard) ?? false
        smartStatusRaw = try container.decodeIfPresent(String.self, forKey: .smartStatusRaw)
        nativeSmartKeys = try container.decode([String: Int64].self, forKey: .nativeSmartKeys)
        volumes = try container.decode([Volume].self, forKey: .volumes)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bsdName, forKey: .bsdName)
        try container.encode(deviceNode, forKey: .deviceNode)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(mediaName, forKey: .mediaName)
        try container.encode(protocolName, forKey: .protocolName)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encode(blockSize, forKey: .blockSize)
        try container.encode(isInternal, forKey: .isInternal)
        try container.encode(isRemovable, forKey: .isRemovable)
        try container.encode(isSolidState, forKey: .isSolidState)
        try container.encode(isWritable, forKey: .isWritable)
        try container.encode(isVirtual, forKey: .isVirtual)
        try container.encode(isSystemDisk, forKey: .isSystemDisk)
        try container.encode(isNetwork, forKey: .isNetwork)
        try container.encode(isMemoryCard, forKey: .isMemoryCard)
        try container.encodeIfPresent(smartStatusRaw, forKey: .smartStatusRaw)
        try container.encode(nativeSmartKeys, forKey: .nativeSmartKeys)
        try container.encode(volumes, forKey: .volumes)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(serialNumber, forKey: .serialNumber)
    }
}

enum BenchmarkTargetFolderMatcher {
    static func targetFolderBelongsToDrive(_ folderPath: String, drive: DriveDevice) -> Bool {
        matchingVolume(for: folderPath, drive: drive) != nil
    }

    static func matchingVolume(for folderPath: String, drive: DriveDevice) -> DriveDevice.Volume? {
        guard !folderPath.isEmpty else { return nil }
        let folderPath = normalizedPath(folderPath)
        let folderVolumeRoot = volumeRootPath(for: folderPath)
        let mountedVolumes = drive.volumes
            .compactMap { volume -> (DriveDevice.Volume, String)? in
                guard let mountPoint = volume.mountPoint else { return nil }
                return (volume, normalizedPath(mountPoint))
            }
            .sorted { $0.1.count > $1.1.count }

        for (volume, mountPath) in mountedVolumes {
            if let folderVolumeRoot,
               let mountVolumeRoot = volumeRootPath(for: mountPath),
               mountPath == mountVolumeRoot,
               folderVolumeRoot == mountVolumeRoot {
                return volume
            }
            if path(folderPath, isInsideOrEqualTo: mountPath) {
                return volume
            }
        }

        return nil
    }

    private static func normalizedPath(_ path: String) -> String {
        let resolved = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return trimmingTrailingSlash(resolved)
    }

    private static func volumeRootPath(for path: String) -> String? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let values = try? url.resourceValues(forKeys: [.volumeURLKey]),
              let volumeURL = values.allValues[.volumeURLKey] as? URL else {
            return nil
        }
        return trimmingTrailingSlash(volumeURL.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    private static func path(_ path: String, isInsideOrEqualTo parentPath: String) -> Bool {
        if parentPath == "/" {
            return path == "/" || path.hasPrefix("/")
        }
        return path == parentPath || path.hasPrefix(parentPath + "/")
    }

    private static func trimmingTrailingSlash(_ path: String) -> String {
        guard path.count > 1 else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

struct SmartAttribute: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var rawValue: String
    var current: Int?
    var worst: Int?
    var threshold: Int?
    var status: HealthStatus
    var source: String
}

enum SmartSelfTestKind: String, Codable, Hashable, Sendable {
    case short
    case long
    case vendor
    case unknown

    var displayName: String {
        switch self {
        case .short: "Short"
        case .long: "Extended"
        case .vendor: "Vendor"
        case .unknown: "Unknown"
        }
    }
}

enum SmartSelfTestState: String, Codable, Hashable, Sendable {
    case noLog
    case running
    case passed
    case failed
    case aborted
    case unknown

    var isTerminal: Bool {
        self != .running
    }
}

enum SmartSelfTestSessionState: Equatable, Sendable {
    case idle
    case starting(SmartSelfTestKind)
    case running(SmartSelfTestKind, remainingPercent: Int?)
    case stopping
    case failed(String)

    var isActive: Bool {
        switch self {
        case .idle, .failed: false
        case .starting, .running, .stopping: true
        }
    }
}

struct SmartSelfTestCapability: Equatable, Sendable {
    var shortSupported: Bool
    var longSupported: Bool
    var message: String

    func supports(_ kind: SmartSelfTestKind) -> Bool {
        switch kind {
        case .short: shortSupported
        case .long: longSupported
        case .vendor, .unknown: false
        }
    }
}

enum SmartSelfTestCapabilityState: Equatable, Sendable {
    case unknown
    case checking
    case supported(SmartSelfTestCapability)
    case unavailable(String)
}

struct SmartSelfTestEntry: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var kind: SmartSelfTestKind
    var state: SmartSelfTestState
    var status: String
    var remainingPercent: Int?
    var lifetimeHours: Int?
    var failingLBA: UInt64?
    var rawStatus: String?
}

struct SmartSelfTestReport: Codable, Hashable, Sendable {
    var state: SmartSelfTestState
    var currentKind: SmartSelfTestKind?
    var currentRemainingPercent: Int?
    var entries: [SmartSelfTestEntry]
    var shortSupported: Bool?
    var longSupported: Bool?
    var rawOutput: String?
    var capturedAt: Date

    var latestEntry: SmartSelfTestEntry? {
        entries.max { lhs, rhs in
            (lhs.lifetimeHours ?? -1) < (rhs.lifetimeHours ?? -1)
        } ?? entries.first
    }
}

struct SmartctlDiagnostics: Codable, Hashable, Sendable {
    var version: String?
    var driveDatabaseVersion: String?
    var targetPath: String?
    var deviceType: String?
    var protocolName: String?
    var powerMode: String?
    var readSkippedToAvoidWake: Bool?
    var openError: String?
}

struct SmartSnapshot: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var driveID: String
    var capturedAt: Date
    var health: HealthStatus
    var summary: String
    var providerStatuses: [ProviderStatus]
    var attributes: [SmartAttribute]
    var temperatureCelsius: Double?
    var lifeRemainingPercent: Int?
    var powerOnHours: Int?
    var powerCycleCount: Int?
    var mediaErrors: Int64?
    var unsafeShutdowns: Int64?
    var smartStatusRaw: String?
    var selfTestStatus: String?
    var selfTestReport: SmartSelfTestReport? = nil
    var enduranceUsedPercent: Int? = nil
    var spareAvailablePercent: Int? = nil
    var spareAvailableThresholdPercent: Int? = nil
    var smartctlDiagnostics: SmartctlDiagnostics? = nil

    static func unavailable(for drive: DriveDevice, reason: String) -> SmartSnapshot {
        SmartSnapshot(
            driveID: drive.id,
            capturedAt: Date(),
            health: .unavailable,
            summary: reason,
            providerStatuses: [ProviderStatus(name: "SMART", state: .unavailable, message: reason)],
            attributes: [],
            temperatureCelsius: nil,
            lifeRemainingPercent: nil,
            powerOnHours: nil,
            powerCycleCount: nil,
            mediaErrors: nil,
            unsafeShutdowns: nil,
            smartStatusRaw: drive.smartStatusRaw,
            selfTestStatus: nil,
            selfTestReport: nil
        )
    }

    var smartReadSkippedToAvoidWake: Bool {
        smartctlDiagnostics?.readSkippedToAvoidWake == true
    }

    func retainingSMARTData(from previous: SmartSnapshot) -> SmartSnapshot {
        guard smartReadSkippedToAvoidWake else { return self }
        var retained = previous
        retained.summary = summary
        retained.providerStatuses = providerStatuses
        retained.smartctlDiagnostics = smartctlDiagnostics
        return retained
    }
}

enum BenchmarkAccessPattern: String, Codable, CaseIterable, Identifiable, Sendable {
    case sequential
    case random

    var id: String { rawValue }
    var title: String { self == .sequential ? "SEQ" : "RND" }
}

enum BenchmarkOperation: String, Codable, CaseIterable, Identifiable, Sendable {
    case read
    case write
    case mixed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .read: "Read"
        case .write: "Write"
        case .mixed: "Mixed"
        }
    }
}

enum BenchmarkDataPattern: String, Codable, CaseIterable, Identifiable, Sendable {
    case random
    case zeroFill

    var id: String { rawValue }
    var title: String { self == .random ? "Random" : "0 Fill" }
}

enum BenchmarkExecutionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case finite
    case loopUntilCancelled

    var id: String { rawValue }
}

enum BenchmarkEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case synchronous
    case asyncQueue

    var id: String { rawValue }
}

struct BenchmarkTest: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var label: String
    var accessPattern: BenchmarkAccessPattern
    var operation: BenchmarkOperation
    var blockSizeBytes: Int
    var queueDepth: Int
    var threads: Int
    var durationSeconds: TimeInterval
    var testSizeBytes: Int64
    var dataPattern: BenchmarkDataPattern
    var writePercentForMixed: Int

    var operationsDescription: String {
        "\(accessPattern.title) \(formatBytes(blockSizeBytes)) Q\(queueDepth)T\(threads)"
    }

    var rowLabel: String {
        Self.rowLabel(for: label)
    }

    static func rowLabel(for label: String) -> String {
        label.hasSuffix(" Mix") ? String(label.dropLast(4)) : label
    }
}

struct BenchmarkCustomRow: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var accessPattern: BenchmarkAccessPattern
    var blockSizeBytes: Int
    var queueDepth: Int
    var threads: Int
    var includeMixed: Bool

    static let maxRows = 4
    static let blockSizeOptions = [
        4_096,
        16_384,
        65_536,
        131_072,
        1_048_576,
        4_194_304,
        16_777_216,
        134_217_728
    ]
    static let queueDepthOptions = [1, 2, 4, 8, 16, 32]
    static let threadOptions = [1, 2, 4, 8, 16]

    static let defaultRows = [
        BenchmarkCustomRow(id: "custom-default-seq", accessPattern: .sequential, blockSizeBytes: 1_048_576, queueDepth: 1, threads: 1, includeMixed: true),
        BenchmarkCustomRow(id: "custom-default-rnd", accessPattern: .random, blockSizeBytes: 4_096, queueDepth: 4, threads: 1, includeMixed: true)
    ]

    var label: String {
        "\(accessPattern.title)\(formatBytes(blockSizeBytes).replacingOccurrences(of: " ", with: "")) Q\(queueDepth)T\(threads)"
    }

    var fingerprint: String {
        "\(accessPattern.rawValue)-b\(blockSizeBytes)-q\(queueDepth)-t\(threads)-\(includeMixed ? "mix" : "plain")"
    }

    static func newRow(index: Int) -> BenchmarkCustomRow {
        var row = defaultRows[min(max(0, index), defaultRows.count - 1)]
        row.id = UUID().uuidString
        return row
    }

    static func sanitized(_ rows: [BenchmarkCustomRow]) -> [BenchmarkCustomRow] {
        let candidates = rows.isEmpty ? defaultRows : rows
        return Array(candidates.prefix(maxRows)).enumerated().map { index, row in
            BenchmarkCustomRow(
                id: row.id.isEmpty ? "custom-row-\(index)" : row.id,
                accessPattern: row.accessPattern,
                blockSizeBytes: blockSizeOptions.contains(row.blockSizeBytes) ? row.blockSizeBytes : 1_048_576,
                queueDepth: queueDepthOptions.contains(row.queueDepth) ? row.queueDepth : 1,
                threads: threadOptions.contains(row.threads) ? row.threads : 1,
                includeMixed: row.includeMixed
            )
        }
    }

    static func decodeList(from json: String) -> [BenchmarkCustomRow] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([BenchmarkCustomRow].self, from: data) else {
            return defaultRows
        }
        return sanitized(decoded)
    }

    static func encodeList(_ rows: [BenchmarkCustomRow]) -> String {
        let sanitizedRows = sanitized(rows)
        guard let data = try? JSONEncoder().encode(sanitizedRows),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }
}

struct BenchmarkProfile: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var testFileSizeBytes: Int64
    var runs: Int
    var usesTrimmedAverage: Bool = false
    var executionMode: BenchmarkExecutionMode = .finite
    var engine: BenchmarkEngine = .synchronous
    var tests: [BenchmarkTest]

    static let defaultTestSize: Int64 = 1_073_741_824
    static let defaultRuns = 3
    static let defaultDataPattern = BenchmarkDataPattern.random
    static let defaultUsesTrimmedAverage = false
    static let defaultSmallBlockFileSizePercent = 20
    static let smallBlockFileSizePercentOptions = [5, 10, 20, 30, 50]
    static let smallBlockEfficiencyBlockSizes: Set<Int> = [4_096, 16_384, 65_536]
    static let runCountOptions = Array(1...9)
    static let fileSizeOptions: [Int64] = [
        1_024 * 1_024 * 1_024,
        2 * 1_024 * 1_024 * 1_024,
        4 * 1_024 * 1_024 * 1_024,
        8 * 1_024 * 1_024 * 1_024,
        16 * 1_024 * 1_024 * 1_024,
        32 * 1_024 * 1_024 * 1_024,
        64 * 1_024 * 1_024 * 1_024
    ]

    var baseProfileID: String {
        id.components(separatedBy: "@").first ?? id
    }

    static var presets: [BenchmarkProfile] {
        [.default, .peakNVMe, .realWorld, .demoLight, .custom]
    }

    static var `default`: BenchmarkProfile {
        makeProfile(
            id: "default",
            name: "Default",
            testSize: defaultTestSize,
            runs: defaultRuns,
            duration: 5,
            rows: [
                (.sequential, 1_048_576, 8, 1),
                (.sequential, 1_048_576, 1, 1),
                (.random, 4_096, 32, 1),
                (.random, 4_096, 1, 1)
            ],
            engine: .asyncQueue
        )
    }

    static var peakNVMe: BenchmarkProfile {
        makeProfile(
            id: "peak-nvme",
            name: "Peak / NVMe",
            testSize: 2_147_483_648,
            runs: 3,
            duration: 5,
            rows: [
                (.sequential, 1_048_576, 8, 1),
                (.sequential, 131_072, 32, 1),
                (.random, 4_096, 32, 16),
                (.random, 4_096, 1, 1)
            ],
            engine: .asyncQueue
        )
    }

    static var realWorld: BenchmarkProfile {
        makeProfile(
            id: "real-world",
            name: "RealWorld",
            testSize: defaultTestSize,
            runs: 2,
            duration: 3,
            rows: [
                (.sequential, 1_048_576, 1, 1),
                (.random, 65_536, 4, 2),
                (.random, 4_096, 4, 1),
                (.random, 4_096, 1, 1)
            ],
            includeMixed: true
        )
    }

    static var demoLight: BenchmarkProfile {
        makeProfile(
            id: "demo",
            name: "Demo / Light",
            testSize: defaultTestSize,
            runs: 1,
            duration: 1,
            rows: [
                (.sequential, 1_048_576, 1, 1),
                (.random, 4_096, 1, 1)
            ]
        )
    }

    static var custom: BenchmarkProfile {
        makeProfile(
            id: "custom",
            name: "Custom",
            testSize: defaultTestSize,
            runs: 2,
            duration: 2,
            rows: [
                (.sequential, 1_048_576, 1, 1),
                (.random, 4_096, 4, 1)
            ],
            includeMixed: true
        )
    }

    static func custom(
        rows: [BenchmarkCustomRow],
        engine: BenchmarkEngine = .synchronous,
        executionMode: BenchmarkExecutionMode = .finite
    ) -> BenchmarkProfile {
        makeCustomProfile(
            id: "custom",
            name: "Custom",
            testSize: defaultTestSize,
            runs: 2,
            duration: 2,
            rows: rows,
            executionMode: executionMode,
            engine: engine
        )
    }

    static var asyncTest: BenchmarkProfile {
        makeProfile(
            id: "test",
            name: "Test",
            testSize: defaultTestSize,
            runs: defaultRuns,
            duration: 5,
            rows: [
                (.sequential, 1_048_576, 1, 1),
                (.sequential, 1_048_576, 1, 2),
                (.sequential, 1_048_576, 1, 4),
                (.sequential, 1_048_576, 8, 1),
                (.sequential, 1_048_576, 8, 2),
                (.sequential, 1_048_576, 8, 4)
            ],
            engine: .asyncQueue
        )
    }

    static var loop: BenchmarkProfile {
        makeProfile(
            id: "loop",
            name: "Loop",
            testSize: defaultTestSize,
            runs: 1,
            duration: 5,
            rows: [
                (.sequential, 1_048_576, 1, 1),
                (.sequential, 1_048_576, 8, 1)
            ],
            executionMode: .loopUntilCancelled
        )
    }

    static var extremeLoop: BenchmarkProfile {
        makeProfile(
            id: "loop-extreme",
            name: "Extreme Loop",
            testSize: defaultTestSize,
            runs: 1,
            duration: 5,
            rows: [
                (.sequential, 1_048_576, 8, 1),
                (.sequential, 4_194_304, 8, 4),
                (.sequential, 1_048_576, 32, 4)
            ],
            executionMode: .loopUntilCancelled
        )
    }

    static func makeCustomProfile(
        id: String,
        name: String,
        testSize: Int64,
        runs: Int,
        duration: TimeInterval,
        rows requestedRows: [BenchmarkCustomRow],
        executionMode: BenchmarkExecutionMode = .finite,
        engine: BenchmarkEngine = .synchronous
    ) -> BenchmarkProfile {
        let rows = BenchmarkCustomRow.sanitized(requestedRows)
        let rowFingerprint = rows.map(\.fingerprint).joined(separator: "_")
        var tests: [BenchmarkTest] = []
        for (index, row) in rows.enumerated() {
            let base = row.label
            let testIDPrefix = "\(id)-row\(index)-\(row.fingerprint)"
            tests.append(BenchmarkTest(
                id: "\(testIDPrefix)-read",
                label: base,
                accessPattern: row.accessPattern,
                operation: .read,
                blockSizeBytes: row.blockSizeBytes,
                queueDepth: row.queueDepth,
                threads: row.threads,
                durationSeconds: duration,
                testSizeBytes: testSize,
                dataPattern: .random,
                writePercentForMixed: 0
            ))
            tests.append(BenchmarkTest(
                id: "\(testIDPrefix)-write",
                label: base,
                accessPattern: row.accessPattern,
                operation: .write,
                blockSizeBytes: row.blockSizeBytes,
                queueDepth: row.queueDepth,
                threads: row.threads,
                durationSeconds: duration,
                testSizeBytes: testSize,
                dataPattern: .random,
                writePercentForMixed: 100
            ))
            if row.includeMixed {
                tests.append(BenchmarkTest(
                    id: "\(testIDPrefix)-mixed",
                    label: "\(base) Mix",
                    accessPattern: row.accessPattern,
                    operation: .mixed,
                    blockSizeBytes: row.blockSizeBytes,
                    queueDepth: row.queueDepth,
                    threads: row.threads,
                    durationSeconds: duration,
                    testSizeBytes: testSize,
                    dataPattern: .random,
                    writePercentForMixed: 30
                ))
            }
        }
        return BenchmarkProfile(
            id: "\(id)@rows-\(rowFingerprint)",
            name: name,
            testFileSizeBytes: testSize,
            runs: runs,
            usesTrimmedAverage: defaultUsesTrimmedAverage,
            executionMode: executionMode,
            engine: engine,
            tests: tests
        )
    }

    static func makeProfile(
        id: String,
        name: String,
        testSize: Int64,
        runs: Int,
        duration: TimeInterval,
        rows: [(BenchmarkAccessPattern, Int, Int, Int)],
        includeMixed: Bool = false,
        executionMode: BenchmarkExecutionMode = .finite,
        engine: BenchmarkEngine = .synchronous
    ) -> BenchmarkProfile {
        var tests: [BenchmarkTest] = []
        for (index, row) in rows.enumerated() {
            let base = "\(row.0.title)\(formatBytes(row.1).replacingOccurrences(of: " ", with: "")) Q\(row.2)T\(row.3)"
            tests.append(BenchmarkTest(
                id: "\(id)-read-\(index)",
                label: base,
                accessPattern: row.0,
                operation: .read,
                blockSizeBytes: row.1,
                queueDepth: row.2,
                threads: row.3,
                durationSeconds: duration,
                testSizeBytes: testSize,
                dataPattern: .random,
                writePercentForMixed: 0
            ))
            tests.append(BenchmarkTest(
                id: "\(id)-write-\(index)",
                label: base,
                accessPattern: row.0,
                operation: .write,
                blockSizeBytes: row.1,
                queueDepth: row.2,
                threads: row.3,
                durationSeconds: duration,
                testSizeBytes: testSize,
                dataPattern: .random,
                writePercentForMixed: 100
            ))
            if includeMixed {
                tests.append(BenchmarkTest(
                    id: "\(id)-mixed-\(index)",
                    label: "\(base) Mix",
                    accessPattern: row.0,
                    operation: .mixed,
                    blockSizeBytes: row.1,
                    queueDepth: row.2,
                    threads: row.3,
                    durationSeconds: duration,
                    testSizeBytes: testSize,
                    dataPattern: .random,
                    writePercentForMixed: 30
                ))
            }
        }
        return BenchmarkProfile(
            id: id,
            name: name,
            testFileSizeBytes: testSize,
            runs: runs,
            usesTrimmedAverage: defaultUsesTrimmedAverage,
            executionMode: executionMode,
            engine: engine,
            tests: tests
        )
    }

    func applying(engine nextEngine: BenchmarkEngine) -> BenchmarkProfile {
        var profile = self
        profile.engine = nextEngine
        return profile
    }

    func configured(
        runs requestedRuns: Int,
        fileSizeBytes requestedFileSizeBytes: Int64,
        dataPattern: BenchmarkDataPattern,
        usesTrimmedAverage: Bool = defaultUsesTrimmedAverage,
        usesSmallBlockEfficiency: Bool = false,
        smallBlockFileSizePercent requestedSmallBlockFileSizePercent: Int = defaultSmallBlockFileSizePercent
    ) -> BenchmarkProfile {
        let isLooping = executionMode == .loopUntilCancelled
        let safeRuns = isLooping ? 1 : min(max(requestedRuns, Self.runCountOptions.first ?? 1), Self.runCountOptions.last ?? 9)
        let safeFileSizeBytes = max(Self.fileSizeOptions.first ?? Self.defaultTestSize, requestedFileSizeBytes)
        let safeUsesTrimmedAverage = isLooping ? false : usesTrimmedAverage
        let safeSmallBlockFileSizePercent = Self.smallBlockFileSizePercentOptions.contains(requestedSmallBlockFileSizePercent)
            ? requestedSmallBlockFileSizePercent
            : Self.defaultSmallBlockFileSizePercent
        let appliesSmallBlockEfficiency = usesSmallBlockEfficiency
            && tests.contains { Self.smallBlockEfficiencyBlockSizes.contains($0.blockSizeBytes) }
        let fingerprint: String
        let rowFingerprint = id
            .components(separatedBy: "@")
            .dropFirst()
            .first { $0.hasPrefix("rows-") }
        let engineFingerprint = engine == .synchronous ? nil : "engine-\(engine.rawValue)"
        let smallBlockFingerprint = appliesSmallBlockEfficiency ? "small-\(safeSmallBlockFileSizePercent)" : nil
        if isLooping {
            let loopFingerprint = "loop-s\(safeFileSizeBytes)-\(dataPattern.rawValue)"
            fingerprint = [rowFingerprint, loopFingerprint, engineFingerprint, smallBlockFingerprint].compactMap { $0 }.joined(separator: "-")
        } else {
            let averageMode = safeUsesTrimmedAverage ? "trim" : "plain"
            let runFingerprint = "r\(safeRuns)-s\(safeFileSizeBytes)-\(dataPattern.rawValue)-\(averageMode)"
            fingerprint = [rowFingerprint, runFingerprint, engineFingerprint, smallBlockFingerprint].compactMap { $0 }.joined(separator: "-")
        }
        let configuredTests = tests.map { test in
            var configuredTest = test
            let baseTestID = test.id.components(separatedBy: "@").first ?? test.id
            configuredTest.id = "\(baseTestID)@\(fingerprint)"
            configuredTest.testSizeBytes = Self.effectiveTestSize(
                fileSizeBytes: safeFileSizeBytes,
                blockSizeBytes: test.blockSizeBytes,
                usesSmallBlockEfficiency: appliesSmallBlockEfficiency,
                smallBlockFileSizePercent: safeSmallBlockFileSizePercent
            )
            configuredTest.dataPattern = dataPattern
            return configuredTest
        }
        return BenchmarkProfile(
            id: "\(baseProfileID)@\(fingerprint)",
            name: name,
            testFileSizeBytes: safeFileSizeBytes,
            runs: safeRuns,
            usesTrimmedAverage: safeUsesTrimmedAverage,
            executionMode: executionMode,
            engine: engine,
            tests: configuredTests
        )
    }

    static func effectiveTestSize(
        fileSizeBytes: Int64,
        blockSizeBytes: Int,
        usesSmallBlockEfficiency: Bool,
        smallBlockFileSizePercent: Int
    ) -> Int64 {
        guard usesSmallBlockEfficiency, smallBlockEfficiencyBlockSizes.contains(blockSizeBytes) else {
            return fileSizeBytes
        }
        let safePercent = smallBlockFileSizePercentOptions.contains(smallBlockFileSizePercent)
            ? smallBlockFileSizePercent
            : defaultSmallBlockFileSizePercent
        return max(Int64(blockSizeBytes), fileSizeBytes * Int64(safePercent) / 100)
    }

    func singleRunProfile(forRowLabel rowLabel: String) -> BenchmarkProfile? {
        let normalizedRowLabel = BenchmarkTest.rowLabel(for: rowLabel)
        let rowTests = tests.filter { $0.rowLabel == normalizedRowLabel }
        guard !rowTests.isEmpty else { return nil }

        var profile = self
        profile.runs = 1
        profile.usesTrimmedAverage = false
        profile.executionMode = .finite
        profile.tests = rowTests
        return profile
    }
}

struct BenchmarkResult: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var driveID: String
    var volumePath: String
    var profileID: String
    var profileName: String
    var testID: String
    var testLabel: String
    var operation: BenchmarkOperation
    var measuredAt: Date
    var bestMegabytesPerSecond: Double
    var iops: Double
    var latencyMicroseconds: Double
    var bytesTransferred: Int64
    var transferMegabytesPerSecond: Double? = nil
    var flushMilliseconds: Double? = nil
}

struct BenchmarkProgress: Equatable, Sendable {
    var currentTestLabel: String
    var completed: Int
    var total: Int
    var message: String
    var phaseCompletedBytes: Int64 = 0
    var phaseTotalBytes: Int64 = 0

    var fraction: Double {
        guard total > 0 else { return 0 }
        let phaseFraction: Double
        if phaseTotalBytes > 0 {
            phaseFraction = min(1, max(0, Double(phaseCompletedBytes) / Double(phaseTotalBytes)))
        } else {
            phaseFraction = 0
        }
        return min(1, max(0, (Double(completed) + phaseFraction) / Double(total)))
    }
}

enum BenchmarkProgressUpdateGate {
    static let defaultMinimumInterval: TimeInterval = 0.25

    static func shouldPublish(
        previous: BenchmarkProgress?,
        candidate: BenchmarkProgress,
        now: Date,
        lastPublishedAt: Date?,
        minimumInterval: TimeInterval = defaultMinimumInterval
    ) -> Bool {
        guard let previous, let lastPublishedAt else { return true }
        if candidate.currentTestLabel != previous.currentTestLabel { return true }
        if candidate.message != previous.message { return true }
        if candidate.completed != previous.completed { return true }
        if candidate.total != previous.total { return true }
        if candidate.total > 0, candidate.completed >= candidate.total { return true }
        if candidate.phaseTotalBytes > 0, candidate.phaseCompletedBytes >= candidate.phaseTotalBytes { return true }
        return now.timeIntervalSince(lastPublishedAt) >= minimumInterval
    }
}

func formatBytes(_ bytes: Int) -> String {
    if bytes >= 1_048_576 && bytes % 1_048_576 == 0 {
        return "\(bytes / 1_048_576) MiB"
    }
    if bytes >= 1_024 && bytes % 1_024 == 0 {
        return "\(bytes / 1_024) KiB"
    }
    return "\(bytes) B"
}

func formatByteCount(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func formatBenchmarkFileSize(_ bytes: Int64) -> String {
    let gib: Int64 = 1_024 * 1_024 * 1_024
    let mib: Int64 = 1_024 * 1_024
    if bytes >= gib, bytes % gib == 0 {
        return "\(bytes / gib) GiB"
    }
    if bytes >= mib, bytes % mib == 0 {
        return "\(bytes / mib) MiB"
    }
    return formatByteCount(bytes)
}
