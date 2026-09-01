// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit
import IOKit.storage
import OSLog

protocol DiskInventoryProviding: Sendable {
    func loadDrives(showVirtual: Bool) async throws -> [DriveDevice]
}

struct DiskutilListModel: Sendable {
    var wholeDiskIDs: [String]
    var wholeDiskSizes: [String: Int64]
    var volumesByPhysicalDisk: [String: [DriveDevice.Volume]]
}

struct NetworkMountEntry: Equatable {
    var source: String
    var mountPoint: String
    var fileSystemType: String
    var options: [String]
}

struct MountedVolumeCapacity: Equatable, Sendable {
    var totalBytes: Int64
    var availableBytes: Int64
}

enum MountedVolumeCapacityReader {
    static func read(at mountPoint: String) -> MountedVolumeCapacity? {
        let url = URL(fileURLWithPath: mountPoint, isDirectory: true)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let totalValue = values.volumeTotalCapacity else {
            return nil
        }

        return resolve(
            totalBytes: Int64(totalValue),
            availableBytes: values.volumeAvailableCapacity.map(Int64.init),
            importantUsageAvailableBytes: values.volumeAvailableCapacityForImportantUsage.map { Int64(truncating: $0 as NSNumber) }
        )
    }

    static func resolve(
        totalBytes: Int64?,
        availableBytes: Int64?,
        importantUsageAvailableBytes: Int64?
    ) -> MountedVolumeCapacity? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        // The important-usage value can be zero on removable media even while
        // the ordinary volume free-space value is accurate. Use the normal
        // volume capacity first because this is the user-visible free space.
        let availableBytes = availableBytes ?? importantUsageAvailableBytes
        guard let availableBytes, availableBytes >= 0 else { return nil }
        return MountedVolumeCapacity(
            totalBytes: totalBytes,
            availableBytes: min(availableBytes, totalBytes)
        )
    }
}

enum MountedVolumeUUIDReader {
    static func read(at mountPoint: String) -> String? {
        let url = URL(fileURLWithPath: mountPoint, isDirectory: true)
        guard let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]) else {
            return nil
        }
        return VolumeUUIDNormalizer.normalize(values.volumeUUIDString)
    }
}

protocol NetworkVolumeInventoryProviding: Sendable {
    func loadNetworkDrives() async throws -> [DriveDevice]
}

protocol DriveSerialNumberProviding: Sendable {
    func serialNumbers(for drives: [DriveDevice]) async -> [String: String]
}

protocol DriveUSBDeviceIdentityProviding: Sendable {
    func deviceIdentities(for drives: [DriveDevice]) async -> [String: DriveUSBDeviceIdentity]
}

enum DriveSerialNumberNormalizer {
    static func normalize(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let invalidValues = ["unknown", "not available", "not specified", "n/a", "none", "nil"]
        guard !invalidValues.contains(trimmed.lowercased()) else { return nil }
        return trimmed
    }
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
        let wholeDiskSizes = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, Int64)? in
            guard let identifier = entry.string("DeviceIdentifier"),
                  wholeDisks.contains(identifier),
                  let size = entry.int64("Size") else { return nil }
            return (identifier, size)
        })
        var partitionToWholeDisk: [String: String] = [:]
        let apfsPhysicalStoreIDs = Set(entries.flatMap { entry in
            entry.arrayOfDictionaries("APFSPhysicalStores").compactMap {
                $0.string("DeviceIdentifier")
            }
        })

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
            let capacityGroupIdentifier = entry.string("DeviceIdentifier").map { "apfs:\($0)" }

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
                    isSystem: volume.bool("OSInternal") ?? false || normalizedMountPoint(volume.string("MountPoint")) == "/",
                    fileSystemType: parsedFileSystemType(from: volume, fallback: "APFS"),
                    capacityGroupIdentifier: capacityGroupIdentifier,
                    volumeUUID: parsedVolumeUUID(from: volume),
                    apfsRole: volume.stringList("APFSVolumeRole") ?? volume.stringList("Role"),
                    topologyKind: .logicalVolume
                )
            }

            for disk in physicalDisks {
                volumesByDisk[disk, default: []].append(contentsOf: parsedVolumes)
            }
        }

        for entry in entries {
            guard let wholeDiskID = entry.string("DeviceIdentifier") else { continue }
            let mountedPartitions = entry
                .arrayOfDictionaries("Partitions")
                .compactMap { partition in
                    parsePartitionVolume(
                        partition,
                        apfsPhysicalStoreIDs: apfsPhysicalStoreIDs
                    )
                }
            if !mountedPartitions.isEmpty {
                volumesByDisk[wholeDiskID, default: []].append(contentsOf: mountedPartitions)
            }
        }

        return DiskutilListModel(
            wholeDiskIDs: wholeDisks,
            wholeDiskSizes: wholeDiskSizes,
            volumesByPhysicalDisk: volumesByDisk
        )
    }

    private static func parsePartitionVolume(
        _ partition: [String: Any],
        apfsPhysicalStoreIDs: Set<String>
    ) -> DriveDevice.Volume? {
        guard let id = partition.string("DeviceIdentifier") else {
            return nil
        }
        let mountPoint = normalizedMountPoint(partition.string("MountPoint"))
        let partitionContent = cleanName(partition.string("Content"))
        let isContainerBackingStore = apfsPhysicalStoreIDs.contains(id)
            || isStructuralPartitionContent(partitionContent)

        let isReadOnly = partition.bool("ReadOnly") ?? false
        let isWritable = partition.bool("Writable") ?? !isReadOnly
        return DriveDevice.Volume(
            deviceIdentifier: id,
            name: cleanName(partition.string("VolumeName")) ?? cleanName(partition.string("Name")) ?? id,
            mountPoint: mountPoint,
            sizeBytes: partition.int64("Size") ?? 0,
            isWritable: isWritable,
            isSystem: partition.bool("OSInternal") ?? false || mountPoint == "/",
            fileSystemType: parsedFileSystemType(from: partition, fallback: nil),
            capacityGroupIdentifier: "volume:\(id)",
            volumeUUID: parsedVolumeUUID(from: partition),
            apfsRole: partition.stringList("APFSVolumeRole") ?? partition.stringList("Role"),
            topologyKind: isContainerBackingStore ? .containerBackingStore : .physicalPartition,
            partitionContent: partitionContent
        )
    }

    /// These are diskutil partition-content identifiers, not volume names.
    /// They describe storage metadata or a container's physical backing store
    /// and therefore cannot be mounted, benchmarked, or renamed as volumes.
    private static func isStructuralPartitionContent(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value
            .lowercased()
            .filter(\.isLetter)
        return [
            "efi",
            "appleapfs",
            "appleapfsisc",
            "appleapfsrecovery",
            "appleapfsvm",
            "applecorestorage",
            "appleboot",
            "microsoftreserved",
        ].contains(normalized)
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

        // Some filesystems (notably UDF media from camera/recording devices)
        // are omitted from `diskutil list -plist` even while `diskutil info`
        // reports a mounted volume. Recover that user-facing volume here so
        // the sidebar and volume-aware actions do not fall back to the model.
        var deviceVolumes = volumes
        if let infoVolume = volumeFromDeviceInfo(info, deviceIdentifier: bsdName) {
            if let index = deviceVolumes.firstIndex(where: { $0.deviceIdentifier == bsdName }) {
                deviceVolumes[index] = infoVolume
            } else if !deviceVolumes.contains(where: { $0.mountPoint == infoVolume.mountPoint }) {
                deviceVolumes.append(infoVolume)
            }
        }
        deviceVolumes = deduplicatedVolumes(deviceVolumes)

        let mediaName = cleanName(info.string("MediaName"))
        let registryName = cleanName(info.string("IORegistryEntryName"))
        let displayName = mediaName ?? registryName ?? bsdName
        let isMemoryCard = isMemoryCardDevice(
            protocolName: protocolName,
            mediaName: mediaName,
            registryName: registryName,
            content: content
        )
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
            isSystemDisk: deviceVolumes.contains(where: { $0.mountPoint == "/" }),
            isMemoryCard: isMemoryCard,
            // Native SMART is intentionally collected by NativeSmartProbe after
            // inventory has been published. Keeping it out of DriveDevice avoids
            // treating a transient first diskutil response as permanent state.
            smartStatusRaw: nil,
            nativeSmartKeys: [:],
            volumes: deviceVolumes,
            model: registryName,
            serialNumber: cleanName(info.string("DeviceSerial"))
        )
    }

    private static func volumeFromDeviceInfo(
        _ info: [String: Any],
        deviceIdentifier: String
    ) -> DriveDevice.Volume? {
        let mountPoint = normalizedMountPoint(info.string("MountPoint"))
        guard let mountPoint else { return nil }

        let name = cleanName(info.string("VolumeName"))
            ?? cleanName(info.string("Name"))
            ?? URL(fileURLWithPath: mountPoint).lastPathComponent
        guard !name.isEmpty else { return nil }

        let isReadOnly = info.bool("ReadOnly") ?? !(info.bool("Writable") ?? true)
        let isWritable = info.bool("WritableMedia") ?? !isReadOnly
        return DriveDevice.Volume(
            deviceIdentifier: deviceIdentifier,
            name: name,
            mountPoint: mountPoint,
            sizeBytes: info.int64("VolumeSize")
                ?? info.int64("TotalSize")
                ?? info.int64("Size")
                ?? info.int64("IOKitSize")
                ?? 0,
            isWritable: isWritable && !isReadOnly,
            isSystem: mountPoint == "/" || info.bool("OSInternal") == true,
            fileSystemType: parsedFileSystemType(from: info, fallback: nil),
            capacityGroupIdentifier: "volume:\(deviceIdentifier)",
            volumeUUID: parsedVolumeUUID(from: info),
            topologyKind: .physicalPartition
        )
    }

    private static func isMemoryCardDevice(protocolName: String, mediaName: String?, registryName: String?, content: String) -> Bool {
        if protocolName.caseInsensitiveCompare("Secure Digital") == .orderedSame {
            return true
        }

        let searchable = [protocolName, mediaName, registryName, content]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return searchable.contains("sdxc")
            || searchable.contains("sdhc")
            || searchable.contains("sd card")
            || searchable.contains("secure digital")
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

    private static func parsedFileSystemType(from dictionary: [String: Any], fallback: String?) -> String? {
        var candidates = [
            dictionary.string("FilesystemName"),
            dictionary.string("FileSystemName"),
            dictionary.string("FilesystemType"),
            dictionary.string("FileSystemType"),
            dictionary.string("VolumeKind"),
        ]
        // `Content` is a partition-map type, not necessarily the mounted
        // filesystem. For example, an ExFAT card commonly reports
        // `Windows_NTFS` here. Only use it as a fallback for unmounted media.
        if normalizedMountPoint(dictionary.string("MountPoint")) == nil {
            candidates.append(dictionary.string("Content"))
        }
        candidates.append(fallback)

        for candidate in candidates {
            if let normalized = FileSystemFormatResolver.normalized(candidate) {
                return normalized
            }
        }
        return nil
    }

    private static func parsedVolumeUUID(from dictionary: [String: Any]) -> String? {
        VolumeUUIDNormalizer.normalize(
            dictionary.string("VolumeUUID") ?? dictionary.string("APFSVolumeUUID")
        )
    }
}

enum SystemProfilerDriveSerialParser {
    static func parse(_ data: Data) -> [String: String] {
        guard let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return [:]
        }

        var serialNumbers: [String: String] = [:]
        visit(propertyList, serialNumbers: &serialNumbers)
        return serialNumbers
    }

    private static func visit(_ value: Any, serialNumbers: inout [String: String]) {
        if let dictionary = value as? [String: Any] {
            if let bsdName = string(in: dictionary, keys: ["bsd_name", "BSD Name"]),
               let serialNumber = string(in: dictionary, keys: ["device_serial", "serial_number", "serial_num"]),
               let normalizedSerial = DriveSerialNumberNormalizer.normalize(serialNumber),
               serialNumbers[bsdName] == nil {
                serialNumbers[bsdName] = normalizedSerial
            }

            for child in dictionary.values {
                visit(child, serialNumbers: &serialNumbers)
            }
            return
        }

        if let array = value as? [Any] {
            for child in array {
                visit(child, serialNumbers: &serialNumbers)
            }
        }
    }

    private static func string(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }
        return nil
    }
}

final class SystemProfilerDriveSerialProvider: DriveSerialNumberProviding, @unchecked Sendable {
    private let runner: CommandRunning
    private let executablePath: String

    init(runner: CommandRunning = ShellCommandRunner(), executablePath: String = "/usr/sbin/system_profiler") {
        self.runner = runner
        self.executablePath = executablePath
    }

    func serialNumbers(for drives: [DriveDevice]) async -> [String: String] {
        let physicalBSDNames = Set(drives.filter { !$0.isNetwork }.map(\.bsdName))
        guard !physicalBSDNames.isEmpty,
              let result = try? await runner.run(
                  executablePath,
                  arguments: ["SPNVMeDataType", "SPSerialATADataType", "SPUSBDataType", "-xml"]
              ),
              result.terminationStatus == 0 else {
            return [:]
        }

        return SystemProfilerDriveSerialParser.parse(result.stdout).filter { physicalBSDNames.contains($0.key) }
    }
}

struct IOKitDriveSerialProvider: DriveSerialNumberProviding {
    func serialNumbers(for drives: [DriveDevice]) async -> [String: String] {
        var serialNumbers: [String: String] = [:]
        for drive in drives where !drive.isNetwork {
            if let serialNumber = serialNumber(forBSDName: drive.bsdName) {
                serialNumbers[drive.bsdName] = serialNumber
            }
        }
        return serialNumbers
    }

    private func serialNumber(forBSDName bsdName: String) -> String? {
        guard let media = copyWholeMedia(bsdName: bsdName) else { return nil }
        defer { IOObjectRelease(media) }

        // Walk from the whole-disk IOMedia node toward its hardware provider. SAT SMART
        // Driver publishes the ATA serial on this path even when diskutil and
        // system_profiler omit the USB disk entirely. Registry reads do not issue a
        // SMART command and therefore do not wake a sleeping mechanical disk.
        var current = media
        var ownsCurrent = false
        defer {
            if ownsCurrent {
                IOObjectRelease(current)
            }
        }

        while true {
            if let serialNumber = serialNumberProperty(from: current) {
                return serialNumber
            }

            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                return nil
            }
            if ownsCurrent {
                IOObjectRelease(current)
            }
            current = parent
            ownsCurrent = true
        }
    }

    private func copyWholeMedia(bsdName: String) -> io_registry_entry_t? {
        guard let matching = IOServiceMatching(kIOMediaClass) else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let media = IOIteratorNext(iterator)
            guard media != 0 else { return nil }
            let name = copyProperty(media, key: kIOBSDNameKey) as? String
            let whole = copyProperty(media, key: kIOMediaWholeKey) as? Bool
            if name == bsdName, whole == true {
                return media
            }
            IOObjectRelease(media)
        }
    }

    private func serialNumberProperty(from entry: io_registry_entry_t) -> String? {
        if let serialNumber = copyProperty(entry, key: "Serial Number") as? String,
           let normalized = DriveSerialNumberNormalizer.normalize(serialNumber) {
            return normalized
        }

        if let characteristics = copyProperty(entry, key: "Device Characteristics") as? [String: Any],
           let serialNumber = characteristics["Serial Number"] as? String {
            return DriveSerialNumberNormalizer.normalize(serialNumber)
        }
        return nil
    }

    private func copyProperty(_ entry: io_registry_entry_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}

struct IOKitDriveUSBDeviceIdentityProvider: DriveUSBDeviceIdentityProviding {
    func deviceIdentities(for drives: [DriveDevice]) async -> [String: DriveUSBDeviceIdentity] {
        var identities: [String: DriveUSBDeviceIdentity] = [:]
        for drive in drives where !drive.isNetwork {
            if let identity = deviceIdentity(forBSDName: drive.bsdName) {
                identities[drive.bsdName] = identity
            }
        }
        return identities
    }

    private func deviceIdentity(forBSDName bsdName: String) -> DriveUSBDeviceIdentity? {
        guard let media = copyWholeMedia(bsdName: bsdName) else { return nil }
        defer { IOObjectRelease(media) }

        // Walk to the USB device ancestor so an enclosure identity remains
        // paired with the backing IOMedia even when the disk model is generic.
        var current = media
        var ownsCurrent = false
        var partialIdentity: DriveUSBDeviceIdentity?
        defer {
            if ownsCurrent {
                IOObjectRelease(current)
            }
        }

        while true {
            let identityAtNode = identity(from: current)
            // SAT/storage stacks can split USB identity across several ancestors:
            // the mass-storage node may expose product + VID/PID while the USB
            // host node exposes the vendor. Keep walking until the fields merge.
            if identityAtNode.hasAnyValue {
                partialIdentity = Self.merge(partialIdentity, with: identityAtNode)
                if partialIdentity?.isComplete == true {
                    return partialIdentity
                }
            }

            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                return partialIdentity
            }
            if ownsCurrent {
                IOObjectRelease(current)
            }
            current = parent
            ownsCurrent = true
        }
    }

    private static func merge(
        _ existing: DriveUSBDeviceIdentity?,
        with incoming: DriveUSBDeviceIdentity
    ) -> DriveUSBDeviceIdentity {
        DriveUSBDeviceIdentity(
            vendorName: existing?.vendorName ?? incoming.vendorName,
            productName: existing?.productName ?? incoming.productName,
            vendorID: existing?.vendorID ?? incoming.vendorID,
            productID: existing?.productID ?? incoming.productID
        )
    }

    private func identity(from entry: io_registry_entry_t) -> DriveUSBDeviceIdentity {
        let usbInfo = copyProperty(entry, key: "USB Device Info") as? [String: Any]
        let deviceCharacteristics = copyProperty(entry, key: "Device Characteristics") as? [String: Any]
        return DriveUSBDeviceIdentity(
            vendorName: stringProperty(from: entry, key: "USB Vendor Name")
                ?? stringProperty(in: usbInfo, keys: ["USB Vendor Name", "kUSBVendorString"]),
            productName: stringProperty(from: entry, key: "USB Product Name")
                ?? stringProperty(in: usbInfo, keys: ["USB Product Name", "kUSBProductString"])
                ?? stringProperty(in: deviceCharacteristics, keys: ["Product Name"]),
            vendorID: integerProperty(from: entry, key: "idVendor")
                ?? integerProperty(in: usbInfo, keys: ["idVendor", "USBVendorID"]),
            productID: integerProperty(from: entry, key: "idProduct")
                ?? integerProperty(in: usbInfo, keys: ["idProduct", "USBProductID"])
        )
    }

    private func copyWholeMedia(bsdName: String) -> io_registry_entry_t? {
        guard let matching = IOServiceMatching(kIOMediaClass) else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let media = IOIteratorNext(iterator)
            guard media != 0 else { return nil }
            let name = copyProperty(media, key: kIOBSDNameKey) as? String
            let whole = copyProperty(media, key: kIOMediaWholeKey) as? Bool
            if name == bsdName, whole == true {
                return media
            }
            IOObjectRelease(media)
        }
    }

    private func stringProperty(from entry: io_registry_entry_t, key: String) -> String? {
        guard let value = copyProperty(entry, key: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func integerProperty(from entry: io_registry_entry_t, key: String) -> Int? {
        (copyProperty(entry, key: key) as? NSNumber)?.intValue
    }

    private func stringProperty(in dictionary: [String: Any]?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func integerProperty(in dictionary: [String: Any]?, keys: [String]) -> Int? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = dictionary[key] as? NSNumber {
                return value.intValue
            }
        }
        return nil
    }

    private func copyProperty(_ entry: io_registry_entry_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}

private extension DriveUSBDeviceIdentity {
    var hasAnyValue: Bool {
        vendorName != nil || productName != nil || vendorID != nil || productID != nil
    }

    var isComplete: Bool {
        vendorName != nil && productName != nil && vendorID != nil && productID != nil
    }
}

final class FallbackDriveSerialProvider: DriveSerialNumberProviding, @unchecked Sendable {
    private let primary: DriveSerialNumberProviding
    private let fallback: DriveSerialNumberProviding

    init(primary: DriveSerialNumberProviding, fallback: DriveSerialNumberProviding) {
        self.primary = primary
        self.fallback = fallback
    }

    func serialNumbers(for drives: [DriveDevice]) async -> [String: String] {
        var serialNumbers = await primary.serialNumbers(for: drives)
        let unresolvedDrives = drives.filter { serialNumbers[$0.bsdName] == nil }
        guard !unresolvedDrives.isEmpty else { return serialNumbers }

        let fallbackSerialNumbers = await fallback.serialNumbers(for: unresolvedDrives)
        for (bsdName, serialNumber) in fallbackSerialNumbers where serialNumbers[bsdName] == nil {
            serialNumbers[bsdName] = serialNumber
        }
        return serialNumbers
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

final class NetworkMountInventoryProvider: NetworkVolumeInventoryProviding, @unchecked Sendable {
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
        let capacity = MountedVolumeCapacityReader.read(at: entry.mountPoint)
        let sizeBytes = capacity?.totalBytes ?? 0
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
                    isSystem: false,
                    fileSystemType: protocolName,
                    capacityGroupIdentifier: "network:\(bsdName)",
                    totalCapacityBytes: capacity?.totalBytes,
                    availableCapacityBytes: capacity?.availableBytes
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

final class DiskutilInventoryProvider: DiskInventoryProviding, @unchecked Sendable {
    private let runner: CommandRunning
    private let diskutilPath: String
    private let networkProvider: NetworkVolumeInventoryProviding?
    private let serialNumberProvider: DriveSerialNumberProviding
    private let usbDeviceIdentityProvider: DriveUSBDeviceIdentityProviding
    private let maximumConcurrentInfoCalls: Int
    private let infoTimeout: TimeInterval

    init(
        runner: CommandRunning = ShellCommandRunner(),
        diskutilPath: String = "/usr/sbin/diskutil",
        networkProvider: NetworkVolumeInventoryProviding? = NetworkMountInventoryProvider(),
        serialNumberProvider: DriveSerialNumberProviding? = nil,
        usbDeviceIdentityProvider: DriveUSBDeviceIdentityProviding? = nil,
        maximumConcurrentInfoCalls: Int = 2,
        infoTimeout: TimeInterval = 5
    ) {
        self.runner = runner
        self.diskutilPath = diskutilPath
        self.networkProvider = networkProvider
        self.serialNumberProvider = serialNumberProvider ?? FallbackDriveSerialProvider(
            primary: SystemProfilerDriveSerialProvider(runner: runner),
            fallback: IOKitDriveSerialProvider()
        )
        self.usbDeviceIdentityProvider = usbDeviceIdentityProvider ?? IOKitDriveUSBDeviceIdentityProvider()
        self.maximumConcurrentInfoCalls = max(1, maximumConcurrentInfoCalls)
        self.infoTimeout = infoTimeout
    }

    func loadDrives(showVirtual: Bool) async throws -> [DriveDevice] {
        let listResult = try await runner.run(diskutilPath, arguments: ["list", "-plist"])
        if listResult.terminationStatus != 0 {
            throw CommandError.nonZeroExit(executable: diskutilPath, status: listResult.terminationStatus, stderr: listResult.stderrString)
        }

        let list = try DiskutilPlistParser.parseList(listResult.stdout)
        let physicalDiskIDs = await loadPhysicalDiskIDs()
        var devices = await loadPhysicalDevices(
            list: list,
            physicalDiskIDs: physicalDiskIDs,
            showVirtual: showVirtual
        )
        let serialNumbers = await serialNumberProvider.serialNumbers(for: devices)
        if !serialNumbers.isEmpty {
            devices = devices.map { drive in
                guard let serialNumber = serialNumbers[drive.bsdName] else { return drive }
                var enriched = drive
                enriched.serialNumber = serialNumber
                return enriched
            }
        }
        let usbDeviceIdentities = await usbDeviceIdentityProvider.deviceIdentities(for: devices)
        if !usbDeviceIdentities.isEmpty {
            devices = devices.map { drive in
                guard let usbDevice = usbDeviceIdentities[drive.bsdName] else { return drive }
                var enriched = drive
                enriched.usbDevice = usbDevice
                return enriched
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

    private func loadPhysicalDiskIDs() async -> Set<String> {
        do {
            let result = try await runner.run(
                diskutilPath,
                arguments: ["list", "-plist", "physical"],
                timeout: infoTimeout
            )
            guard result.terminationStatus == 0 else { return [] }
            return Set(try DiskutilPlistParser.parseList(result.stdout).wholeDiskIDs)
        } catch {
            CapricornLog.inventory.notice(
                "Physical disk list fallback is unavailable: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    private func loadPhysicalDevices(
        list: DiskutilListModel,
        physicalDiskIDs: Set<String>,
        showVirtual: Bool
    ) async -> [DriveDevice] {
        let runner = runner
        let diskutilPath = diskutilPath
        let infoTimeout = infoTimeout
        let maximumConcurrentInfoCalls = maximumConcurrentInfoCalls
        let prioritizedDisks = Array(list.wholeDiskIDs.enumerated()).sorted { lhs, rhs in
            let lhsIsSystem = (list.volumesByPhysicalDisk[lhs.element] ?? []).contains { $0.mountPoint == "/" }
            let rhsIsSystem = (list.volumesByPhysicalDisk[rhs.element] ?? []).contains { $0.mountPoint == "/" }
            if lhsIsSystem != rhsIsSystem { return lhsIsSystem }
            return lhs.offset < rhs.offset
        }
        var iterator = prioritizedDisks.makeIterator()

        return await withTaskGroup(of: (Int, DriveDevice?).self) { group in
            for _ in 0..<min(maximumConcurrentInfoCalls, prioritizedDisks.count) {
                guard let (index, diskID) = iterator.next() else { break }
                let volumes = Self.enrichMountedVolumeMetadata(list.volumesByPhysicalDisk[diskID] ?? [])
                group.addTask {
                    do {
                        let result = try await runner.run(
                            diskutilPath,
                            arguments: ["info", "-plist", diskID],
                            timeout: infoTimeout
                        )
                        guard result.terminationStatus == 0 else {
                            return (
                                index,
                                Self.fallbackPhysicalDevice(
                                    diskID: diskID,
                                    list: list,
                                    physicalDiskIDs: physicalDiskIDs
                                )
                            )
                        }
                        return (
                            index,
                            try DiskutilPlistParser.parseDevice(
                                infoData: result.stdout,
                                volumes: volumes,
                                showVirtual: showVirtual
                            )
                        )
                    } catch {
                        CapricornLog.inventory.notice(
                            "Disk inventory info failed for \(diskID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                        return (
                            index,
                            Self.fallbackPhysicalDevice(
                                diskID: diskID,
                                list: list,
                                physicalDiskIDs: physicalDiskIDs
                            )
                        )
                    }
                }
            }

            var indexedDevices: [(Int, DriveDevice)] = []
            while let (index, device) = await group.next() {
                if let device {
                    indexedDevices.append((index, device))
                }
                if let (nextIndex, nextDiskID) = iterator.next() {
                    let volumes = Self.enrichMountedVolumeMetadata(list.volumesByPhysicalDisk[nextDiskID] ?? [])
                    group.addTask {
                        do {
                            let result = try await runner.run(
                                diskutilPath,
                                arguments: ["info", "-plist", nextDiskID],
                                timeout: infoTimeout
                            )
                            guard result.terminationStatus == 0 else {
                                return (
                                    nextIndex,
                                    Self.fallbackPhysicalDevice(
                                        diskID: nextDiskID,
                                        list: list,
                                        physicalDiskIDs: physicalDiskIDs
                                    )
                                )
                            }
                            return (
                                nextIndex,
                                try DiskutilPlistParser.parseDevice(
                                    infoData: result.stdout,
                                    volumes: volumes,
                                    showVirtual: showVirtual
                                )
                            )
                        } catch {
                            CapricornLog.inventory.notice(
                                "Disk inventory info failed for \(nextDiskID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                            )
                            return (
                                nextIndex,
                                Self.fallbackPhysicalDevice(
                                    diskID: nextDiskID,
                                    list: list,
                                    physicalDiskIDs: physicalDiskIDs
                                )
                            )
                        }
                    }
                }
            }
            return indexedDevices.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func fallbackPhysicalDevice(
        diskID: String,
        list: DiskutilListModel,
        physicalDiskIDs: Set<String>
    ) -> DriveDevice? {
        guard physicalDiskIDs.contains(diskID) else { return nil }
        let volumes = enrichMountedVolumeMetadata(list.volumesByPhysicalDisk[diskID] ?? [])
        let isSystemDisk = volumes.contains { $0.mountPoint == "/" }
        let representativeVolume = volumes.max { lhs, rhs in
            lhs.sizeBytes < rhs.sizeBytes
        }
        let displayName = representativeVolume?.name ?? diskID

        CapricornLog.inventory.notice(
            "Using physical-list fallback metadata for \(diskID, privacy: .public)"
        )
        return DriveDevice(
            bsdName: diskID,
            deviceNode: "/dev/\(diskID)",
            displayName: displayName,
            mediaName: displayName,
            protocolName: "Unknown",
            sizeBytes: list.wholeDiskSizes[diskID] ?? representativeVolume?.sizeBytes ?? 0,
            blockSize: 512,
            isInternal: isSystemDisk,
            isRemovable: !isSystemDisk,
            isSolidState: false,
            isWritable: volumes.contains(where: \.isWritable),
            isVirtual: false,
            isSystemDisk: isSystemDisk,
            smartStatusRaw: nil,
            nativeSmartKeys: [:],
            volumes: volumes,
            model: nil,
            serialNumber: nil
        )
    }

    private static func enrichMountedVolumeMetadata(_ volumes: [DriveDevice.Volume]) -> [DriveDevice.Volume] {
        volumes.map { volume in
            var enriched = volume
            guard let mountPoint = volume.mountPoint else { return enriched }
            if let fileSystemType = FileSystemFormatResolver.fileSystemType(atMountPoint: mountPoint) {
                // Mounted volume metadata is authoritative over the partition
                // map's `Content` value, which can describe the partition type
                // rather than the filesystem currently mounted on it.
                enriched.fileSystemType = fileSystemType
            }
            if let capacity = MountedVolumeCapacityReader.read(at: mountPoint) {
                enriched.totalCapacityBytes = capacity.totalBytes
                enriched.availableCapacityBytes = capacity.availableBytes
            }
            if enriched.volumeUUID == nil {
                enriched.volumeUUID = MountedVolumeUUIDReader.read(at: mountPoint)
            }
            return enriched
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        self[key] as? String
    }

    /// diskutil currently emits APFS roles as strings, while some plist
    /// producers represent the same role set as an array. Normalize both
    /// shapes so protected backup volumes cannot become write targets.
    func stringList(_ key: String) -> String? {
        if let value = string(key) { return value }
        guard let values = self[key] as? [String], !values.isEmpty else { return nil }
        return values.joined(separator: ",")
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
