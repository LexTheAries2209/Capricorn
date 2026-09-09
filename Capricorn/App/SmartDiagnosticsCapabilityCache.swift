// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum SmartDiagnosticsFeature: String, Codable, Sendable {
    case selfTest
    case errorLog
}

enum SmartDiagnosticsCachedStatus: String, Codable, Sendable {
    case supported
    case unavailable
}

struct SmartDiagnosticsFeatureCacheRecord: Codable, Sendable {
    var status: SmartDiagnosticsCachedStatus
    var message: String
    var selfTestCapability: SmartSelfTestCapability?
    var checkedAt: Date
}

struct SmartDiagnosticsCapabilityCacheEntry: Codable, Sendable {
    var transportSignature: String
    var smartctlVersion: String?
    var selfTest: SmartDiagnosticsFeatureCacheRecord?
    var errorLog: SmartDiagnosticsFeatureCacheRecord?
}

protocol SmartDiagnosticsCapabilityCaching: AnyObject {
    func cachedEntry(
        for drive: DriveDevice,
        smartctlVersion: String?
    ) -> SmartDiagnosticsCapabilityCacheEntry?
    func store(
        _ record: SmartDiagnosticsFeatureCacheRecord,
        feature: SmartDiagnosticsFeature,
        for drive: DriveDevice,
        smartctlVersion: String?
    )

    func remove(for drive: DriveDevice)
}

/// Persists capability probes independently from SwiftData history. Capability
/// checks happen frequently enough that a small Codable UserDefaults payload is
/// a better fit than emitting a historical record every time a disk appears.
final class SmartDiagnosticsCapabilityCache: SmartDiagnosticsCapabilityCaching {
    private static let defaultsKey = "smartDiagnosticsCapabilityCache.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func cachedEntry(
        for drive: DriveDevice,
        smartctlVersion: String?
    ) -> SmartDiagnosticsCapabilityCacheEntry? {
        guard let identity = identityKey(for: drive),
              let entry = entries()[identity],
              entry.transportSignature == transportSignature(for: drive),
              versionsMatch(cached: entry.smartctlVersion, current: smartctlVersion) else {
            return nil
        }
        return entry
    }

    func store(
        _ record: SmartDiagnosticsFeatureCacheRecord,
        feature: SmartDiagnosticsFeature,
        for drive: DriveDevice,
        smartctlVersion: String?
    ) {
        guard let identity = identityKey(for: drive) else { return }
        var allEntries = entries()
        var entry = allEntries[identity] ?? SmartDiagnosticsCapabilityCacheEntry(
            transportSignature: transportSignature(for: drive),
            smartctlVersion: smartctlVersion,
            selfTest: nil,
            errorLog: nil
        )
        entry.transportSignature = transportSignature(for: drive)
        entry.smartctlVersion = smartctlVersion ?? entry.smartctlVersion
        switch feature {
        case .selfTest:
            entry.selfTest = record
        case .errorLog:
            entry.errorLog = record
        }
        allEntries[identity] = entry
        guard let data = try? JSONEncoder.dit.encode(allEntries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func remove(for drive: DriveDevice) {
        guard let identity = identityKey(for: drive) else { return }
        var allEntries = entries()
        guard allEntries.removeValue(forKey: identity) != nil else { return }
        guard let data = try? JSONEncoder.dit.encode(allEntries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private func entries() -> [String: SmartDiagnosticsCapabilityCacheEntry] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let entries = try? JSONDecoder.dit.decode(
                  [String: SmartDiagnosticsCapabilityCacheEntry].self,
                  from: data
              ) else {
            return [:]
        }
        return entries
    }

    private func identityKey(for drive: DriveDevice) -> String? {
        if let serial = HistoryDriveMatcher.normalize(drive.serialNumber) {
            return "serial:\(serial)"
        }
        let volumes = VolumeUUIDNormalizer.normalized(drive.volumeUUIDs)
        guard !volumes.isEmpty else { return nil }
        return "volumes:\(volumes.sorted().joined(separator: ","))"
    }

    private func transportSignature(for drive: DriveDevice) -> String {
        [
            drive.protocolName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            drive.isSolidState ? "ssd" : "hdd",
            (drive.model ?? drive.mediaName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        ].joined(separator: "|")
    }

    private func versionsMatch(cached: String?, current: String?) -> Bool {
        guard let cached, let current else { return true }
        return cached == current
    }
}
