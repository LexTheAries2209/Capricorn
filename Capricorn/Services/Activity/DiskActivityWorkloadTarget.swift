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
        drive.volumes.sorted {
            $0.deviceIdentifier.localizedStandardCompare($1.deviceIdentifier) == .orderedAscending
        }
    }

    static func isUsable(_ volume: DriveDevice.Volume, fileManager: FileManager = .default) -> Bool {
        guard volume.isWritable, let mountPoint = volume.mountPoint else { return false }
        return isUsableFolder(mountPoint, fileManager: fileManager)
    }

    static func defaultVolume(for drive: DriveDevice, fileManager: FileManager = .default) -> DriveDevice.Volume? {
        orderedVolumes(for: drive).first { isUsable($0, fileManager: fileManager) }
    }

    static func resolve(
        _ selection: DiskActivityWorkloadTargetSelection,
        for drive: DriveDevice,
        fileManager: FileManager = .default
    ) -> DiskActivityWorkloadResolvedTarget {
        switch selection {
        case .automatic:
            return automaticTarget(for: drive, fileManager: fileManager, didFallBack: false)
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

        return automaticTarget(for: drive, fileManager: fileManager, didFallBack: true)
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
        fileManager: FileManager,
        didFallBack: Bool
    ) -> DiskActivityWorkloadResolvedTarget {
        let volume = defaultVolume(for: drive, fileManager: fileManager)
        let folderURL = volume?.mountPoint.map { URL(fileURLWithPath: $0, isDirectory: true) }
        return DiskActivityWorkloadResolvedTarget(
            selection: .automatic,
            volume: volume,
            folderURL: folderURL,
            didFallBackToAutomatic: didFallBack
        )
    }
}
