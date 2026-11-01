// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit
import IOKit.storage

enum DeviceHelperDeviceResolver {
    static func resolve(bsdName: String) throws -> DeviceHelperDisk {
        guard bsdName.range(of: #"^disk[0-9]+\z"#, options: .regularExpression) != nil,
              let match = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else {
            throw DeviceHelperError.rejected("A whole physical disk is required.")
        }
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, match)
        guard entry != 0 else { throw DeviceHelperError.rejected("The selected disk is no longer connected.") }
        let original = entry
        defer { IOObjectRelease(original) }
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(original, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        guard property(kIOMediaWholeKey) as? Bool == true,
              let size = property(kIOMediaSizeKey) as? NSNumber, size.int64Value > 0 else {
            throw DeviceHelperError.rejected("A whole physical disk is required.")
        }
        var mediaID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(original, &mediaID) == KERN_SUCCESS else {
            throw DeviceHelperError.rejected("The disk Registry ID is unavailable.")
        }
        var usbID: UInt64?
        var isInternal = false
        var physical = false
        IOObjectRetain(entry)
        while entry != 0 {
            if IOObjectConformsTo(entry, "IOBlockStorageDevice") != 0 { physical = true }
            if let properties = IORegistryEntryCreateCFProperty(
                entry, "Protocol Characteristics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any],
               properties["Physical Interconnect Location"] as? String == "Internal" {
                isInternal = true
            }
            if IOObjectConformsTo(entry, "IOUSBHostDevice") != 0 {
                var identifier: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(entry, &identifier) == KERN_SUCCESS { usbID = identifier }
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            entry = status == KERN_SUCCESS ? parent : 0
        }
        guard physical else { throw DeviceHelperError.rejected("Virtual and synthesized disks are not allowed.") }
        return DeviceHelperDisk(bsdName: bsdName, mediaRegistryID: mediaID,
                                sizeBytes: size.int64Value, usbRegistryID: usbID, isInternal: isInternal)
    }

    static func transportID(path: String, disk: DeviceHelperDisk) throws -> UInt64? {
        if path == "/dev/\(disk.bsdName)" || path == disk.bsdName { return nil }
        guard path.hasPrefix("IOService:") else {
            throw DeviceHelperError.rejected("The SMART target is not a permitted device node.")
        }
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { throw DeviceHelperError.rejected("The SMART target is unavailable.") }
        defer { IOObjectRelease(entry) }
        var identifier: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(entry, &identifier) == KERN_SUCCESS else {
            throw DeviceHelperError.rejected("The SMART target identity is unavailable.")
        }
        _ = try targetPath(transportID: identifier, disk: disk)
        return identifier
    }

    static func targetPath(transportID: UInt64?, disk: DeviceHelperDisk) throws -> String {
        guard let transportID else { return "/dev/\(disk.bsdName)" }
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(disk.mediaRegistryID))
        guard entry != 0 else { throw DeviceHelperError.rejected("The disk is no longer connected.") }
        while entry != 0 {
            var identifier: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(entry, &identifier)
            // Only an actual storage driver's ancestor is a valid IOService target.
            if identifier == transportID,
               (IOObjectConformsTo(entry, "IOBlockStorageDevice") != 0
                || IOObjectConformsTo(entry, "IONVMeController") != 0) {
                var path = [CChar](repeating: 0, count: 4096)
                let status = IORegistryEntryGetPath(entry, kIOServicePlane, &path)
                IOObjectRelease(entry)
                guard status == KERN_SUCCESS else { break }
                return String(cString: path)
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            entry = status == KERN_SUCCESS ? parent : 0
        }
        throw DeviceHelperError.rejected("The SMART target is not an ancestor of this physical disk.")
    }

    static func disk(forTarget target: String) throws -> DeviceHelperDisk {
        if target.hasPrefix("/dev/disk") || target.hasPrefix("disk") {
            return try resolve(bsdName: URL(fileURLWithPath: target).lastPathComponent)
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOMediaClass), &iterator) == KERN_SUCCESS else {
            throw DeviceHelperError.rejected("Unable to enumerate physical disks.")
        }
        defer { IOObjectRelease(iterator) }
        var matches: [DeviceHelperDisk] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            let name = IORegistryEntryCreateCFProperty(
                entry, kIOBSDNameKey as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String
            IOObjectRelease(entry)
            if let name, let disk = try? resolve(bsdName: name) {
                let matchesTarget: Bool
                if target.hasPrefix("usbraw:"), let id = UInt64(target.dropFirst(7)) {
                    matchesTarget = disk.usbRegistryID == id
                } else {
                    matchesTarget = (try? transportID(path: target, disk: disk)) != nil
                }
                if matchesTarget { matches.append(disk) }
            }
        }
        guard matches.count == 1, let disk = matches.first else {
            throw DeviceHelperError.rejected("The SMART target does not identify exactly one physical disk.")
        }
        return disk
    }
}
