// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum DiskActivityWorkloadTargetSelection: Codable, Equatable, Sendable {
    case automatic
    case volume(deviceIdentifier: String)
    case folder(path: String)
}

struct DiskActivityWorkloadTargetPreferences: Codable, Equatable, Sendable {
    private(set) var selectionsByDrive: [String: DiskActivityWorkloadTargetSelection] = [:]

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

    func selection(for drive: DriveDevice) -> DiskActivityWorkloadTargetSelection {
        selectionsByDrive[DiskActivityWorkloadTargetResolver.preferenceKey(for: drive)] ?? .automatic
    }

    mutating func setSelection(_ selection: DiskActivityWorkloadTargetSelection, for drive: DriveDevice) {
        let key = DiskActivityWorkloadTargetResolver.preferenceKey(for: drive)
        if selection == .automatic {
            selectionsByDrive.removeValue(forKey: key)
        } else {
            selectionsByDrive[key] = selection
        }
    }

    mutating func migrateLegacyFolder(
        _ path: String,
        to drive: DriveDevice,
        fileManager: FileManager = .default
    ) -> Bool {
        guard selection(for: drive) == .automatic,
              DiskActivityWorkloadTargetResolver.isUsableFolder(path, fileManager: fileManager),
              let volume = BenchmarkTargetFolderMatcher.matchingVolume(for: path, drive: drive),
              volume.isWritable else {
            return false
        }
        setSelection(.folder(path: path), for: drive)
        return true
    }
}

struct DiskActivityWorkloadResolvedTarget: Equatable, Sendable {
    var selection: DiskActivityWorkloadTargetSelection
    var volume: DriveDevice.Volume?
    var folderURL: URL?
    var didFallBackToAutomatic: Bool
}

enum DiskActivityWorkloadTargetResolver {
    static func preferenceKey(for drive: DriveDevice) -> String {
        if drive.isNetwork {
            return "network:\(drive.id)"
        }
        if let serial = drive.serialNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !serial.isEmpty {
            return "serial:\(serial.lowercased())"
        }
        return "drive:\(drive.id)"
    }

    static func orderedVolumes(for drive: DriveDevice) -> [DriveDevice.Volume] {
        RepresentativeVolumeResolver.orderedVolumes(for: drive)
    }

    static func isUsable(_ volume: DriveDevice.Volume, fileManager: FileManager = .default) -> Bool {
        guard RepresentativeVolumeResolver.isSelectable(volume), let mountPoint = volume.mountPoint else { return false }
        return isUsableFolder(mountPoint, fileManager: fileManager)
    }

    /// Automatic workload targets use the current representative volume when
    /// it is usable. If it disappears, falls read-only, or is a protected
    /// backup/system volume, fall back to the largest safe mounted volume.
    static func defaultVolume(
        for drive: DriveDevice,
        preferredVolumeID: String? = nil,
        fileManager: FileManager = .default
    ) -> DriveDevice.Volume? {
        let usableVolumes = orderedVolumes(for: drive).filter { isUsable($0, fileManager: fileManager) }
        if let preferredVolumeID,
           let preferred = usableVolumes.first(where: { $0.deviceIdentifier == preferredVolumeID }) {
            return preferred
        }
        return usableVolumes.first
    }

    static func resolve(
        _ selection: DiskActivityWorkloadTargetSelection,
        for drive: DriveDevice,
        preferredVolumeID: String? = nil,
        fileManager: FileManager = .default
    ) -> DiskActivityWorkloadResolvedTarget {
        switch selection {
        case .automatic:
            return automaticTarget(for: drive, preferredVolumeID: preferredVolumeID, fileManager: fileManager, didFallBack: false)
        case let .volume(deviceIdentifier):
            if let volume = orderedVolumes(for: drive).first(where: {
                $0.deviceIdentifier == deviceIdentifier && isUsable($0, fileManager: fileManager)
            }), let mountPoint = volume.mountPoint {
                return DiskActivityWorkloadResolvedTarget(
                    selection: selection,
                    volume: volume,
                    folderURL: URL(fileURLWithPath: mountPoint, isDirectory: true),
                    didFallBackToAutomatic: false
                )
            }
        case let .folder(path):
            if isUsableFolder(path, fileManager: fileManager),
               let volume = BenchmarkTargetFolderMatcher.matchingVolume(for: path, drive: drive),
               volume.isWritable {
                return DiskActivityWorkloadResolvedTarget(
                    selection: selection,
                    volume: volume,
                    folderURL: URL(fileURLWithPath: path, isDirectory: true),
                    didFallBackToAutomatic: false
                )
            }
        }

        return automaticTarget(for: drive, preferredVolumeID: preferredVolumeID, fileManager: fileManager, didFallBack: true)
    }

    static func isUsableFolder(_ path: String, fileManager: FileManager = .default) -> Bool {
        guard !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.isWritableFile(atPath: path)
    }

    private static func automaticTarget(
        for drive: DriveDevice,
        preferredVolumeID: String?,
        fileManager: FileManager,
        didFallBack: Bool
    ) -> DiskActivityWorkloadResolvedTarget {
        let volume = defaultVolume(for: drive, preferredVolumeID: preferredVolumeID, fileManager: fileManager)
        let folderURL = volume?.mountPoint.map { URL(fileURLWithPath: $0, isDirectory: true) }
        return DiskActivityWorkloadResolvedTarget(
            selection: .automatic,
            volume: volume,
            folderURL: folderURL,
            didFallBackToAutomatic: didFallBack
        )
    }
}

/// Resolves benchmark destinations without changing the live activity
/// workload policy. System-disk benchmarks are safer and more useful when
/// their automatic destination is the user's Desktop instead of the volume
/// root, while explicit volume and folder selections retain the shared rules.
enum DiskBenchmarkTargetResolver {
    static func resolve(
        _ selection: DiskActivityWorkloadTargetSelection,
        for drive: DriveDevice,
        preferredVolumeID: String? = nil,
        fileManager: FileManager = .default,
        desktopURL: URL? = nil
    ) -> DiskActivityWorkloadResolvedTarget {
        let fallback = {
            DiskActivityWorkloadTargetResolver.resolve(
                selection,
                for: drive,
                preferredVolumeID: preferredVolumeID,
                fileManager: fileManager
            )
        }

        guard drive.isSystemDisk, selection == .automatic else {
            return fallback()
        }

        let candidate = (desktopURL ?? fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first)?
            .standardizedFileURL
        guard let candidate,
              DiskActivityWorkloadTargetResolver.isUsableFolder(candidate.path, fileManager: fileManager),
              let volume = BenchmarkTargetFolderMatcher.matchingVolume(for: candidate.path, drive: drive),
              volume.isWritable else {
            return fallback()
        }

        return DiskActivityWorkloadResolvedTarget(
            selection: .folder(path: candidate.path),
            volume: volume,
            folderURL: candidate,
            didFallBackToAutomatic: false
        )
    }
}
