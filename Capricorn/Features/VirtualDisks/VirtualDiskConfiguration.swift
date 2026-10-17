// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum VirtualDiskCapacityUnit: String, CaseIterable, Identifiable, Sendable {
    case mb = "MB"
    case gb = "GB"
    case tb = "TB"

    var id: Self { self }
    var bytes: Double {
        switch self {
        case .mb: 1_000_000
        case .gb: 1_000_000_000
        case .tb: 1_000_000_000_000
        }
    }

    func byteCount(_ text: String, allowsZero: Bool = false) -> Int64? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, value >= (allowsZero ? 0 : Double.leastNonzeroMagnitude) else { return nil }
        let bytes = value * self.bytes
        guard bytes.isFinite, bytes < Double(Int64.max), bytes >= (allowsZero ? 0 : 1) else { return nil }
        return Int64(bytes.rounded(.down))
    }
}

enum VirtualDiskMediaType: String, CaseIterable, Identifiable, Sendable {
    case ssd = "SSD"
    case hdd = "HDD"
    var id: Self { self }
}

enum VirtualDiskInterface: String, CaseIterable, Identifiable, Sendable {
    case nvme = "NVMe"
    case sata = "SATA"
    case usb = "USB"
    case thunderbolt = "Thunderbolt"
    var id: Self { self }
}

enum VirtualDiskFormat: String, CaseIterable, Identifiable, Sendable {
    case apfs = "APFS"
    case exfat = "ExFAT"
    case ntfs = "NTFS"
    case hfs = "HFS+"
    case unformatted = "Unformatted"
    var id: Self { self }
}

struct VirtualDiskPartition: Identifiable, Sendable {
    let id = UUID()
    var name = "Data"
    var capacity = "1"
    var unit: VirtualDiskCapacityUnit = .tb
    var usedCapacity = "0"
    var format: VirtualDiskFormat = .apfs
}

struct VirtualDiskConfiguration: Sendable {
    var name = "Virtual Disk"
    var model = ""
    var serialNumber = ""
    var capacity = "1"
    var unit: VirtualDiskCapacityUnit = .tb
    var mediaType: VirtualDiskMediaType = .ssd
    var interface: VirtualDiskInterface = .nvme
    var blockSize = 512
    var partitions = [VirtualDiskPartition()]
    // A nil override uses the same health evaluation as physical disks.
    var health: HealthStatus?
    var temperature = "35"
    var lifeRemaining = "100"
    var powerOnHours = "0"
    var powerCycleCount = "0"
    var mediaErrors = "0"
    var unsafeShutdowns = "0"

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a virtual disk name."
        }
        guard let capacityBytes = unit.byteCount(capacity) else {
            return "Enter a valid disk capacity."
        }
        guard [512, 4096].contains(blockSize) else { return "Choose a valid sector size." }
        var remaining = capacityBytes
        for partition in partitions {
            guard !partition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let size = partition.unit.byteCount(partition.capacity),
                  let used = partition.unit.byteCount(partition.usedCapacity, allowsZero: true),
                  used <= size else {
                return "Each partition needs a name, a positive capacity, and used space within its capacity."
            }
            guard size <= remaining else { return "Partition capacities exceed the disk capacity." }
            remaining -= size
        }
        if !temperature.isEmpty {
            guard let value = Double(temperature), value.isFinite, (-273.15...200).contains(value) else {
                return "Temperature must be between -273.15 and 200 C, or empty."
            }
        }
        if !lifeRemaining.isEmpty {
            guard let value = Int(lifeRemaining), (0...100).contains(value) else {
                return "Life remaining must be between 0 and 100, or empty."
            }
        }
        for field in [powerOnHours, powerCycleCount, mediaErrors, unsafeShutdowns] where !field.isEmpty {
            guard let value = Int64(field), value >= 0, value <= Int64(Int.max) else {
                return "Counters must be nonnegative whole numbers, or empty."
            }
        }
        return nil
    }

    var unallocatedBytes: Int64? {
        guard validationMessage == nil, let size = unit.byteCount(capacity) else { return nil }
        return size - partitions.reduce(Int64(0)) { $0 + ($1.unit.byteCount($1.capacity) ?? 0) }
    }

    func makeDisk(id: UUID = UUID()) throws -> (drive: DriveDevice, snapshot: SmartSnapshot) {
        if let validationMessage { throw VirtualDiskConfigurationError.invalid(validationMessage) }
        let identifier = "virtual-\(id.uuidString.lowercased())"
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // No /dev node, mount path, or filesystem UUID may point at real storage.
        let volumes = partitions.enumerated().map { index, partition in
            let size = partition.unit.byteCount(partition.capacity)!
            return DriveDevice.Volume(
                deviceIdentifier: "\(identifier)-p\(index + 1)",
                name: partition.name.trimmingCharacters(in: .whitespacesAndNewlines),
                mountPoint: nil,
                sizeBytes: size,
                isWritable: false,
                isSystem: false,
                fileSystemType: partition.format == .unformatted ? nil : partition.format.rawValue,
                totalCapacityBytes: size,
                availableCapacityBytes: size - partition.unit.byteCount(partition.usedCapacity, allowsZero: true)!,
                topologyKind: .logicalVolume
            )
        }
        let drive = DriveDevice(
            bsdName: identifier, deviceNode: "", displayName: name, mediaName: name,
            protocolName: interface.rawValue, sizeBytes: unit.byteCount(capacity)!, blockSize: blockSize,
            isInternal: false, isRemovable: true, isSolidState: mediaType == .ssd,
            isWritable: false, isVirtual: true, isSystemDisk: false,
            smartStatusRaw: nil, nativeSmartKeys: [:], volumes: volumes,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            serialNumber: serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        var snapshot = SmartSnapshot(
            driveID: drive.id, capturedAt: Date(), health: health ?? .unavailable,
            summary: "User-defined simulated disk",
            providerStatuses: [ProviderStatus(name: "Simulation", state: .available, message: "User-defined overview values")],
            attributes: [], temperatureCelsius: Double(temperature), lifeRemainingPercent: Int(lifeRemaining),
            powerOnHours: Int(powerOnHours), powerCycleCount: Int(powerCycleCount),
            mediaErrors: Int64(mediaErrors), unsafeShutdowns: Int64(unsafeShutdowns),
            smartStatusRaw: nil, selfTestStatus: nil, selectedProvider: "Simulation"
        )
        if health == nil {
            snapshot.health = DriveHealthEvaluator().evaluate(drive: drive, snapshot: snapshot)
        }
        return (drive, snapshot)
    }
}

enum VirtualDiskConfigurationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
