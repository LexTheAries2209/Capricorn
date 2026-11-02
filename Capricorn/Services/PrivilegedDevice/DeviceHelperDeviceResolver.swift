// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit
import IOKit.storage

/// The resolver uses the same registry traversal for live devices and fixture
/// trees, so APFS layers can be tested without mounting or capturing a disk.
struct DeviceHelperRegistry {
    var matchingBSDName: (String) -> io_registry_entry_t
    var parent: (io_registry_entry_t) -> io_registry_entry_t
    var property: (io_registry_entry_t, String) -> Any?
    var conforms: (io_registry_entry_t, String) -> Bool
    var identifier: (io_registry_entry_t) -> UInt64?
    var retain: (io_registry_entry_t) -> Void
    var release: (io_registry_entry_t) -> Void
    var mediaNames: () throws -> [String]

    static var system: Self {
        Self(
            matchingBSDName: { name in
                guard let match = IOBSDNameMatching(kIOMainPortDefault, 0, name) else { return 0 }
                return IOServiceGetMatchingService(kIOMainPortDefault, match)
            },
            parent: { entry in
                var parent: io_registry_entry_t = 0
                return IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS ? parent : 0
            },
            property: { entry, key in
                IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            },
            conforms: { IOObjectConformsTo($0, $1) != 0 },
            identifier: { entry in
                var identifier: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(entry, &identifier) == KERN_SUCCESS,
                      identifier > 0 else { return nil }
                return identifier
            },
            retain: { _ = IOObjectRetain($0) },
            release: { _ = IOObjectRelease($0) },
            mediaNames: {
                var iterator: io_iterator_t = 0
                guard IOServiceGetMatchingServices(
                    kIOMainPortDefault, IOServiceMatching(kIOMediaClass), &iterator
                ) == KERN_SUCCESS else {
                    throw DeviceHelperError.rejected("Unable to enumerate physical disks.")
                }
                defer { IOObjectRelease(iterator) }
                var names: [String] = []
                while case let entry = IOIteratorNext(iterator), entry != 0 {
                    if let name = IORegistryEntryCreateCFProperty(
                        entry, kIOBSDNameKey as CFString, kCFAllocatorDefault, 0
                    )?.takeRetainedValue() as? String {
                        names.append(name)
                    }
                    IOObjectRelease(entry)
                }
                return names
            })
    }
}

enum DeviceHelperDeviceResolver {
    static func resolve(
        bsdName: String, registry: DeviceHelperRegistry = .system
    ) throws -> DeviceHelperDisk {
        guard bsdName.range(of: #"^disk[0-9]+\z"#, options: .regularExpression) != nil else {
            throw DeviceHelperError.rejected("A whole physical disk is required.")
        }
        var entry = registry.matchingBSDName(bsdName)
        guard entry != 0 else { throw DeviceHelperError.rejected("The selected disk is no longer connected.") }
        let original = entry
        defer { registry.release(original) }
        func property(_ key: String) -> Any? {
            registry.property(original, key)
        }
        guard registry.conforms(original, kIOMediaClass),
              property(kIOMediaWholeKey) as? Bool == true,
              let size = property(kIOMediaSizeKey) as? NSNumber, size.int64Value > 0 else {
            throw DeviceHelperError.rejected("A whole physical disk is required.")
        }
        // APFS containers also set Whole=true and eventually reach a physical
        // storage device. Only media provided directly by a block-storage
        // driver represent that device; never count its synthesized children.
        let provider = registry.parent(original)
        guard provider != 0 else {
            throw DeviceHelperError.rejected("Virtual and synthesized disks are not allowed.")
        }
        let physicalProvider = registry.conforms(provider, "IOBlockStorageDriver")
        registry.release(provider)
        guard physicalProvider else {
            throw DeviceHelperError.rejected("Virtual and synthesized disks are not allowed.")
        }
        guard let mediaID = registry.identifier(original) else {
            throw DeviceHelperError.rejected("The disk Registry ID is unavailable.")
        }
        var usbID: UInt64?
        var isInternal = false
        var physical = false
        var virtual = false
        registry.retain(entry)
        while entry != 0 {
            if registry.conforms(entry, "IOBlockStorageDevice") { physical = true }
            if let properties = registry.property(entry, "Protocol Characteristics") as? [String: Any] {
                let location = properties["Physical Interconnect Location"] as? String
                if location == "Internal" { isInternal = true }
                if location == "File" || properties["Physical Interconnect"] as? String == "Virtual Interface" {
                    virtual = true
                }
            }
            // Keep the nearest USB device; higher ancestors may be upstream hubs.
            if usbID == nil, registry.conforms(entry, "IOUSBHostDevice") {
                usbID = registry.identifier(entry)
            }
            let parent = registry.parent(entry)
            registry.release(entry)
            entry = parent
        }
        guard physical, !virtual else { throw DeviceHelperError.rejected("Virtual and synthesized disks are not allowed.") }
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

    static func disk(
        forTarget target: String, registry: DeviceHelperRegistry = .system
    ) throws -> DeviceHelperDisk {
        if target.hasPrefix("/dev/disk") || target.hasPrefix("disk") {
            return try resolve(bsdName: URL(fileURLWithPath: target).lastPathComponent, registry: registry)
        }
        var matches: [DeviceHelperDisk] = []
        for name in try registry.mediaNames() {
            if let disk = try? resolve(bsdName: name, registry: registry) {
                let matchesTarget: Bool
                if target.hasPrefix("usbraw:"), let id = UInt64(target.dropFirst(7)) {
                    matchesTarget = disk.usbRegistryID == id
                } else {
                    matchesTarget = (try? transportID(path: target, disk: disk)) != nil
                }
                if matchesTarget { matches.append(disk) }
            }
        }
        guard !matches.isEmpty else {
            throw DeviceHelperError.rejected("No connected physical disk matches this SMART target. Refresh disks and try again.")
        }
        guard matches.count == 1, let disk = matches.first else {
            throw DeviceHelperError.rejected("This SMART target matches multiple physical disks. The operation was stopped.")
        }
        return disk
    }
}
