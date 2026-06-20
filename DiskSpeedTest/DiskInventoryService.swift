import Foundation

protocol DiskInventoryProviding {
    func loadDrives(showVirtual: Bool) async throws -> [DriveDevice]
}

struct DiskutilListModel {
    var wholeDiskIDs: [String]
    var volumesByPhysicalDisk: [String: [DriveDevice.Volume]]
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

final class DiskutilInventoryProvider: DiskInventoryProviding {
    private let runner: CommandRunning
    private let diskutilPath: String

    init(runner: CommandRunning = ShellCommandRunner(), diskutilPath: String = "/usr/sbin/diskutil") {
        self.runner = runner
        self.diskutilPath = diskutilPath
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

        return devices.sorted { lhs, rhs in
            if lhs.isInternal != rhs.isInternal { return lhs.isInternal && !rhs.isInternal }
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
