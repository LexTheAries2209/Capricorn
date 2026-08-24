// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Controls which volume is selected when Capricorn starts a new session.
/// A manual change always applies immediately; this preference only decides
/// what becomes active the next time the app starts.
enum RepresentativeVolumeStartupPreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case largestCapacity
    case lastSelected

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (language, self) {
        case (.english, .largestCapacity):
            "Largest volume"
        case (.simplifiedChinese, .largestCapacity):
            "容量最大的卷宗"
        case (.english, .lastSelected):
            "Previously selected volume"
        case (.simplifiedChinese, .lastSelected):
            "上次选择的卷宗"
        }
    }
}

/// Identifies a selected volume across a device reattachment. The BSD device
/// identifier is retained only as a fallback because macOS can reassign it;
/// a volume UUID takes precedence whenever the filesystem supplies one.
struct RepresentativeVolumeIdentity: Codable, Equatable, Sendable {
    var deviceIdentifier: String
    var volumeUUID: String?

    init(deviceIdentifier: String, volumeUUID: String?) {
        self.deviceIdentifier = deviceIdentifier
        self.volumeUUID = VolumeUUIDNormalizer.normalize(volumeUUID)
    }

    init(volume: DriveDevice.Volume) {
        deviceIdentifier = volume.deviceIdentifier
        volumeUUID = VolumeUUIDNormalizer.normalize(volume.volumeUUID)
    }

    func resolvedVolume(in drive: DriveDevice) -> DriveDevice.Volume? {
        if let volumeUUID,
           let matchedVolume = drive.volumes.first(where: {
               VolumeUUIDNormalizer.normalize($0.volumeUUID) == volumeUUID
           }) {
            return matchedVolume
        }
        return drive.volumes.first(where: { $0.deviceIdentifier == deviceIdentifier })
    }
}

/// Persists the last manual representative-volume choice per physical drive.
/// The mount path is deliberately not stored, because renaming a volume can
/// change it without changing the volume's identity.
struct RepresentativeVolumePreferences: Codable, Equatable, Sendable {
    private(set) var selectionsByDrive: [String: RepresentativeVolumeIdentity] = [:]

    private enum CodingKeys: String, CodingKey {
        case selectionsByDrive
        case volumeIDsByDrive
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectionsByDrive = try container.decodeIfPresent(
            [String: RepresentativeVolumeIdentity].self,
            forKey: .selectionsByDrive
        ) ?? [:]

        // Earlier development builds wrote only the BSD identifier. Preserve
        // it as a fallback rather than silently discarding the user's choice.
        if selectionsByDrive.isEmpty,
           let legacyVolumeIDs = try container.decodeIfPresent([String: String].self, forKey: .volumeIDsByDrive) {
            selectionsByDrive = legacyVolumeIDs.mapValues {
                RepresentativeVolumeIdentity(deviceIdentifier: $0, volumeUUID: nil)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectionsByDrive, forKey: .selectionsByDrive)
    }

    static func decode(_ encoded: String) -> Self {
        guard let data = encoded.data(using: .utf8),
              let preferences = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self()
        }
        return preferences
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let encoded = String(data: data, encoding: .utf8) else {
            return ""
        }
        return encoded
    }

    func selectedVolumeID(for drive: DriveDevice) -> String? {
        selectionsByDrive[RepresentativeVolumeResolver.preferenceKey(for: drive)]?
            .resolvedVolume(in: drive)?
            .deviceIdentifier
    }

    mutating func setSelectedVolumeID(_ volumeID: String, for drive: DriveDevice) {
        let volume = drive.volumes.first(where: { $0.deviceIdentifier == volumeID })
        selectionsByDrive[RepresentativeVolumeResolver.preferenceKey(for: drive)] = volume.map { RepresentativeVolumeIdentity(volume: $0) }
            ?? RepresentativeVolumeIdentity(deviceIdentifier: volumeID, volumeUUID: nil)
    }
}

/// Resolves the single volume that represents a physical disk for operations
/// such as renaming and automatic file-based benchmarks. The resolver does
/// not treat system or Time Machine backup volumes as safe operation targets.
enum RepresentativeVolumeResolver {
    static func preferenceKey(for drive: DriveDevice) -> String {
        if drive.isNetwork {
            return "network:\(drive.id)"
        }
        if let serial = normalizedIdentifier(drive.serialNumber) {
            return "serial:\(serial)"
        }
        let volumeUUIDs = drive.volumeUUIDs
        if !volumeUUIDs.isEmpty {
            return "volumes:\(volumeUUIDs.joined(separator: ",").lowercased())"
        }
        return "drive:\(drive.id)"
    }

    static func maySwitchVolume(for drive: DriveDevice) -> Bool {
        !drive.isNetwork && !drive.isSystemDisk
    }

    static func orderedVolumes(for drive: DriveDevice) -> [DriveDevice.Volume] {
        drive.volumes.sorted { lhs, rhs in
            let lhsCapacity = volumeCapacity(lhs)
            let rhsCapacity = volumeCapacity(rhs)
            if lhsCapacity != rhsCapacity {
                return lhsCapacity > rhsCapacity
            }
            return lhs.deviceIdentifier.localizedStandardCompare(rhs.deviceIdentifier) == .orderedAscending
        }
    }

    static func isSelectable(_ volume: DriveDevice.Volume) -> Bool {
        guard !volume.isSystem,
              !isTimeMachineVolume(volume),
              volume.isWritable,
              let mountPoint = volume.mountPoint else {
            return false
        }
        return !mountPoint.isEmpty
    }

    static func isTimeMachineVolume(_ volume: DriveDevice.Volume) -> Bool {
        let name = volume.name.lowercased()
        let mountPoint = volume.mountPoint?.lowercased() ?? ""
        let apfsRole = volume.apfsRole?.lowercased() ?? ""
        return apfsRole.contains("backup")
            || name.contains("time machine")
            || name.contains("time-machine")
            || mountPoint.contains("backups.backupdb")
            || mountPoint.contains("time machine")
    }

    static func fallbackVolume(for drive: DriveDevice) -> DriveDevice.Volume? {
        orderedVolumes(for: drive).first(where: isSelectable)
    }

    static func resolve(
        for drive: DriveDevice,
        preferredVolumeID: String? = nil
    ) -> DriveDevice.Volume? {
        guard maySwitchVolume(for: drive) else { return fallbackVolume(for: drive) }
        if let preferredVolumeID,
           let preferred = drive.volumes.first(where: { $0.deviceIdentifier == preferredVolumeID }),
           isSelectable(preferred) {
            return preferred
        }
        return fallbackVolume(for: drive)
    }

    static func volumeCapacity(_ volume: DriveDevice.Volume) -> Int64 {
        volume.totalCapacityBytes ?? volume.sizeBytes
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "nil" ? nil : normalized
    }
}
