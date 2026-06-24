import Foundation

protocol DiskInventoryProviding {
    func loadDrives(showVirtual: Bool) async throws -> [DriveDevice]
}

struct DiskutilListModel {
    var wholeDiskIDs: [String]
    var volumesByPhysicalDisk: [String: [DriveDevice.Volume]]
}

struct NetworkMountEntry: Equatable {
    var source: String
    var mountPoint: String
    var fileSystemType: String
    var options: [String]
}

protocol NetworkVolumeInventoryProviding {
    func loadNetworkDrives() async throws -> [DriveDevice]
}

enum DiskutilParserError: Error, LocalizedError {
    case invalidPlist

    var errorDescription: String? {
        "diskutil returned an unexpected plist shape."
    }
}

enum DiskutilPlistParser {
    static func parseList(_ data: Data) throws -> DiskutilListModel {
        guard
            let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { throw DiskutilParserError.invalidPlist }

        let wholeDisks = root["WholeDisks"] as? [String] ?? root["AllDisks"] as? [String] ?? []
        let entries = root["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        var partitionToWholeDisk: [String: String] = [:]

        for entry in entries {
            guard let wholeDiskID = entry.string("DeviceIdentifier") else { continue }
            for partition in entry.arrayOfDictionaries("Partitions") {
                if let partitionID = partition.string("DeviceIdentifier") {
                    partitionToWholeDisk[partitionID] = wholeDiskID
                }
            }
        }

        var volumesByDisk: [String: [DriveDevice.Volume]] = [:]
        for entry in entries {
            let stores = entry.arrayOfDictionaries("APFSPhysicalStores")
            let volumes = entry.arrayOfDictionaries("APFSVolumes")
            guard !stores.isEmpty, !volumes.isEmpty else { continue }

            let physicalDisks = stores.compactMap { store -> String? in
                guard let storeID = store.string("DeviceIdentifier") else { return nil }
                return partitionToWholeDisk[storeID] ?? wholeDiskName(from: storeID)
            }

            let parsedVolumes = volumes.compactMap { volume -> DriveDevice.Volume? in
                guard let id = volume.string("DeviceIdentifier") else { return nil }
                return DriveDevice.Volume(
                    deviceIdentifier: id,
                    name: volume.string("VolumeName") ?? id,
                    mountPoint: normalizedMountPoint(volume.string("MountPoint")),
                    sizeBytes: volume.int64("Size") ?? 0,
                    isWritable: !(volume.bool("ReadOnly") ?? false),
                    isSystem: volume.bool("OSInternal") ?? false || normalizedMountPoint(volume.string("MountPoint")) == "/"
                )
            }

            for disk in physicalDisks {
                volumesByDisk[disk, default: []].append(contentsOf: parsedVolumes)
            }
        }

        return DiskutilListModel(wholeDiskIDs: wholeDisks, volumesByPhysicalDisk: volumesByDisk)
    }

    static func parseDevice(infoData: Data, volumes: [DriveDevice.Volume], showVirtual: Bool) throws -> DriveDevice? {
        guard
            let info = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any]
        else { throw DiskutilParserError.invalidPlist }

        let bsdName = info.string("DeviceIdentifier") ?? ""
        guard !bsdName.isEmpty else { return nil }
        guard info.bool("WholeDisk") ?? false else { return nil }

        let content = info.string("Content") ?? ""
        let protocolName = info.string("BusProtocol") ?? "Unknown"
        let virtualOrPhysical = info.string("VirtualOrPhysical") ?? ""
        let isVirtual = virtualOrPhysical == "Virtual" || protocolName == "Disk Image" || (info.string("MediaName") ?? "").contains("Disk Image")

        if content == "Apple_APFS_Container" || content == "Apple_CoreStorage" {
            return nil
        }
        if !showVirtual && isVirtual {
            return nil
        }
        if !showVirtual && volumes.contains(where: { ($0.mountPoint ?? "").contains("/Library/Developer/CoreSimulator/") }) {
            return nil
        }

        let mediaName = cleanName(info.string("MediaName"))
        let registryName = cleanName(info.string("IORegistryEntryName"))
        let displayName = mediaName ?? registryName ?? bsdName
        let nativeSmartKeys = parseSmartKeys(info.dictionary("SMARTDeviceSpecificKeysMayVaryNotGuaranteed"))

        return DriveDevice(
            bsdName: bsdName,
            deviceNode: info.string("DeviceNode") ?? "/dev/\(bsdName)",
            displayName: displayName,
            mediaName: mediaName ?? displayName,
            protocolName: protocolName,
            sizeBytes: info.int64("TotalSize") ?? info.int64("Size") ?? info.int64("IOKitSize") ?? 0,
            blockSize: info.int("DeviceBlockSize") ?? 512,
            isInternal: info.bool("Internal") ?? false,
            isRemovable: info.bool("RemovableMediaOrExternalDevice") ?? info.bool("Removable") ?? false,
            isSolidState: info.bool("SolidState") ?? false,
            isWritable: info.bool("WritableMedia") ?? info.bool("Writable") ?? false,
            isVirtual: isVirtual,
            isSystemDisk: volumes.contains(where: { $0.mountPoint == "/" }),
            smartStatusRaw: cleanName(info.string("SMARTStatus")),
            nativeSmartKeys: nativeSmartKeys,
            volumes: deduplicatedVolumes(volumes),
            model: registryName,
            serialNumber: cleanName(info.string("DeviceSerial"))
        )
    }

    private static func parseSmartKeys(_ dict: [String: Any]) -> [String: Int64] {
        var result: [String: Int64] = [:]
        for (key, value) in dict {
            if let number = value as? NSNumber {
                result[key] = number.int64Value
            } else if let int = value as? Int64 {
                result[key] = int
            } else if let string = value as? String, let int = Int64(string) {
                result[key] = int
            }
        }
        return result
    }

    private static func wholeDiskName(from identifier: String) -> String {
        guard let range = identifier.range(of: #"^disk\d+"#, options: .regularExpression) else {
            return identifier
        }
        return String(identifier[range])
    }

    private static func normalizedMountPoint(_ mountPoint: String?) -> String? {
        guard let mountPoint, !mountPoint.isEmpty else { return nil }
        return mountPoint
    }

    private static func cleanName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func deduplicatedVolumes(_ volumes: [DriveDevice.Volume]) -> [DriveDevice.Volume] {
        var seen: Set<String> = []
        var result: [DriveDevice.Volume] = []
        for volume in volumes where seen.insert(volume.deviceIdentifier).inserted {
            result.append(volume)
        }
        return result
    }
}

enum NetworkVolumeMountParser {
    private static let networkFileSystemTypes: Set<String> = [
        "afpfs",
        "davfs",
        "fuse.sshfs",
        "fusefs.sshfs",
        "nfs",
        "smbfs",
        "sshfs",
        "webdav"
    ]

    static func parse(_ output: String) -> [NetworkMountEntry] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseLine(String($0)) }
    }

    static func protocolDisplayName(for fileSystemType: String) -> String {
        switch fileSystemType.lowercased() {
        case "smbfs":
            return "SMB"
        case "afpfs":
            return "AFP"
        case "nfs":
            return "NFS"
        case "webdav", "davfs":
            return "WebDAV"
        case "sshfs", "fuse.sshfs", "fusefs.sshfs":
            return "SSHFS"
        default:
            return fileSystemType.uppercased()
        }
    }

    private static func parseLine(_ line: String) -> NetworkMountEntry? {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let optionsStart = line.lastIndex(of: "("),
              line.hasSuffix(")") else {
            return nil
        }

        let sourceAndMount = String(line[..<optionsStart]).trimmingCharacters(in: .whitespaces)
        guard let separator = sourceAndMount.range(of: " on ", options: .backwards) else {
            return nil
        }

        let source = unescapeMountPath(String(sourceAndMount[..<separator.lowerBound]))
        let mountPoint = unescapeMountPath(String(sourceAndMount[separator.upperBound...]))
        let rawOptions = String(line[line.index(after: optionsStart)..<line.index(before: line.endIndex)])
        let options = rawOptions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let fileSystemType = options.first?.lowercased(),
              networkFileSystemTypes.contains(fileSystemType) else {
            return nil
        }

        return NetworkMountEntry(
            source: source,
            mountPoint: mountPoint,
            fileSystemType: fileSystemType,
            options: options
        )
    }

    private static func unescapeMountPath(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\040", with: " ")
            .replacingOccurrences(of: "\\011", with: "\t")
            .replacingOccurrences(of: "\\012", with: "\n")
            .replacingOccurrences(of: "\\134", with: "\\")
    }
}

final class NetworkMountInventoryProvider: NetworkVolumeInventoryProviding {
    private let runner: CommandRunning
    private let mountPath: String
    private let fileManager: FileManager

    init(runner: CommandRunning = ShellCommandRunner(), mountPath: String = "/sbin/mount", fileManager: FileManager = .default) {
        self.runner = runner
        self.mountPath = mountPath
        self.fileManager = fileManager
    }

    func loadNetworkDrives() async throws -> [DriveDevice] {
        let result = try await runner.run(mountPath, arguments: [])
        if result.terminationStatus != 0 {
            throw CommandError.nonZeroExit(executable: mountPath, status: result.terminationStatus, stderr: result.stderrString)
        }

        return NetworkVolumeMountParser.parse(result.stdoutString).map(makeDrive)
    }

    private func makeDrive(from entry: NetworkMountEntry) -> DriveDevice {
        let protocolName = NetworkVolumeMountParser.protocolDisplayName(for: entry.fileSystemType)
        let displayName = displayName(for: entry)
        let sizeBytes = volumeCapacity(at: entry.mountPoint)
        let isWritable = !entry.options.contains { option in
            ["read-only", "rdonly", "ro"].contains(option.lowercased())
        } && fileManager.isWritableFile(atPath: entry.mountPoint)
        let bsdName = stableNetworkIdentifier(for: entry, protocolName: protocolName)

        return DriveDevice(
            bsdName: bsdName,
            deviceNode: entry.source,
            displayName: displayName,
            mediaName: displayName,
            protocolName: protocolName,
            sizeBytes: sizeBytes,
            blockSize: 4096,
            isInternal: false,
            isRemovable: false,
            isSolidState: false,
            isWritable: isWritable,
            isVirtual: false,
            isSystemDisk: false,
            isNetwork: true,
            smartStatusRaw: nil,
            nativeSmartKeys: [:],
            volumes: [
                DriveDevice.Volume(
                    deviceIdentifier: bsdName,
                    name: displayName,
                    mountPoint: entry.mountPoint,
                    sizeBytes: sizeBytes,
                    isWritable: isWritable,
                    isSystem: false
                )
            ],
            model: entry.source,
            serialNumber: nil
        )
    }

    private func displayName(for entry: NetworkMountEntry) -> String {
        let folderName = URL(fileURLWithPath: entry.mountPoint, isDirectory: true).lastPathComponent
        if !folderName.isEmpty {
            return folderName
        }

        let sourceName = entry.source.split(separator: "/").last.map(String.init)
        return sourceName?.isEmpty == false ? sourceName! : entry.source
    }

    private func volumeCapacity(at mountPoint: String) -> Int64 {
        let url = URL(fileURLWithPath: mountPoint, isDirectory: true)
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey]),
              let capacity = values.volumeTotalCapacity else {
            return 0
        }
        return Int64(capacity)
    }

    private func stableNetworkIdentifier(for entry: NetworkMountEntry, protocolName: String) -> String {
        let raw = "\(entry.fileSystemType)-\(entry.source)-\(entry.mountPoint)"
        let sanitized = raw
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
        let prefix = String(sanitized.prefix(36)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "network-\(protocolName.lowercased())-\(prefix)-\(stableHash(raw))"
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}

final class DiskutilInventoryProvider: DiskInventoryProviding {
    private let runner: CommandRunning
    private let diskutilPath: String
    private let networkProvider: NetworkVolumeInventoryProviding?

    init(
        runner: CommandRunning = ShellCommandRunner(),
        diskutilPath: String = "/usr/sbin/diskutil",
        networkProvider: NetworkVolumeInventoryProviding? = NetworkMountInventoryProvider()
    ) {
        self.runner = runner
        self.diskutilPath = diskutilPath
        self.networkProvider = networkProvider
    }

    func loadDrives(showVirtual: Bool) async throws -> [DriveDevice] {
        let listResult = try await runner.run(diskutilPath, arguments: ["list", "-plist"])
        if listResult.terminationStatus != 0 {
            throw CommandError.nonZeroExit(executable: diskutilPath, status: listResult.terminationStatus, stderr: listResult.stderrString)
        }

        let list = try DiskutilPlistParser.parseList(listResult.stdout)
        var devices: [DriveDevice] = []

        for diskID in list.wholeDiskIDs {
            let infoResult = try await runner.run(diskutilPath, arguments: ["info", "-plist", diskID])
            guard infoResult.terminationStatus == 0 else { continue }
            let volumes = list.volumesByPhysicalDisk[diskID] ?? []
            if let device = try DiskutilPlistParser.parseDevice(infoData: infoResult.stdout, volumes: volumes, showVirtual: showVirtual) {
                devices.append(device)
            }
        }

        if let networkProvider {
            do {
                devices.append(contentsOf: try await networkProvider.loadNetworkDrives())
            } catch {
                // Network mounts are an optional inventory source; physical disk discovery should still succeed.
            }
        }

        return devices.sorted { lhs, rhs in
            let lhsGroup = lhs.isNetwork ? 2 : (lhs.isInternal ? 0 : 1)
            let rhsGroup = rhs.isNetwork ? 2 : (rhs.isInternal ? 0 : 1)
            if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }
            return lhs.bsdName.localizedStandardCompare(rhs.bsdName) == .orderedAscending
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func int(_ key: String) -> Int? {
        if let int = self[key] as? Int { return int }
        if let number = self[key] as? NSNumber { return number.intValue }
        if let string = self[key] as? String { return Int(string) }
        return nil
    }

    func int64(_ key: String) -> Int64? {
        if let int = self[key] as? Int64 { return int }
        if let int = self[key] as? Int { return Int64(int) }
        if let number = self[key] as? NSNumber { return number.int64Value }
        if let string = self[key] as? String { return Int64(string) }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let bool = self[key] as? Bool { return bool }
        if let number = self[key] as? NSNumber { return number.boolValue }
        return nil
    }

    func dictionary(_ key: String) -> [String: Any] {
        self[key] as? [String: Any] ?? [:]
    }

    func arrayOfDictionaries(_ key: String) -> [[String: Any]] {
        self[key] as? [[String: Any]] ?? []
    }
}
