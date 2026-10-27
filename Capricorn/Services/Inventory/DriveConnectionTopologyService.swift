// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit
import IOKit.storage

struct DrivePCIeLink: Equatable, Sendable {
    let generation: Int
    let gigatransfersPerSecond: Double
    let laneCount: Int

    var detailLabel: String {
        "\(String(format: "%.1f", gigatransfersPerSecond)) GT/s · x\(laneCount)"
    }
}

struct DriveConnectionTopologyNode: Equatable, Sendable {
    enum Kind: String, Sendable {
        case computer
        case thunderboltTransport
        case pcieTunnel
        case usbHostController
        case usbHub
        case usbDevice
        case pcieBridge
        case pcieDevice
        case nvmeController
        case sataController
        case storageController
        case storageBridge
        case disk
    }

    let kind: Kind
    let hardwareName: String?
    let pcieLink: DrivePCIeLink?
}

struct DriveConnectionTopology: Equatable, Sendable {
    let nodes: [DriveConnectionTopologyNode]
    let hasResolvedController: Bool
}

struct DriveConnectionRegistryEntry: Equatable, Sendable {
    let className: String
    let entryName: String
    let bsdName: String?
    let pcieLinkStatus: UInt64?
    let isPCIeTunnelled: Bool
    var hardwareDescription: String? = nil
}

enum DriveConnectionTopologyResolver {
    static func resolve(
        drive: DriveDevice,
        registryEntriesFromDiskToHost entries: [DriveConnectionRegistryEntry]
    ) -> DriveConnectionTopology? {
        guard entries.contains(where: { $0.bsdName == drive.bsdName }) else { return nil }

        var nodes = entries.reversed().compactMap { entry -> DriveConnectionTopologyNode? in
            guard let kind = kind(for: entry, drive: drive) else { return nil }
            let hardwareName = name(for: entry, kind: kind)
            return DriveConnectionTopologyNode(
                kind: kind,
                hardwareName: hardwareName,
                pcieLink: entry.pcieLinkStatus.flatMap(DrivePCIeLinkParser.parse)
            )
        }

        var uniqueNodes: [DriveConnectionTopologyNode] = []
        for node in nodes {
            guard !uniqueNodes.contains(where: {
                $0.kind == node.kind && $0.hardwareName == node.hardwareName
            }) else {
                continue
            }
            uniqueNodes.append(node)
        }
        nodes = uniqueNodes

        let hasResolvedController = nodes.contains { $0.kind != .disk }
        guard hasResolvedController else {
            return DriveConnectionTopology(nodes: nodes, hasResolvedController: false)
        }

        if nodes.first?.kind != .computer {
            nodes.insert(
                DriveConnectionTopologyNode(kind: .computer, hardwareName: nil, pcieLink: nil),
                at: 0
            )
        }
        if nodes.last?.kind != .disk {
            nodes.append(
                DriveConnectionTopologyNode(kind: .disk, hardwareName: drive.displayName, pcieLink: nil)
            )
        }

        if !nodes.contains(where: { $0.kind == .thunderboltTransport }),
           !nodes.contains(where: { $0.kind == .pcieTunnel }),
           entries.contains(where: \.isPCIeTunnelled) {
            // IORegistry may expose a tunneled endpoint without a Thunderbolt ancestor node.
            let pcieIndex = nodes.firstIndex(where: {
                $0.kind == .pcieBridge || $0.kind == .pcieDevice
            }) ?? nodes.endIndex
            nodes.insert(
                DriveConnectionTopologyNode(
                    kind: .pcieTunnel,
                    hardwareName: nil,
                    pcieLink: nil
                ),
                at: pcieIndex
            )
        }

        return DriveConnectionTopology(nodes: nodes, hasResolvedController: true)
    }

    private static func kind(
        for entry: DriveConnectionRegistryEntry,
        drive: DriveDevice
    ) -> DriveConnectionTopologyNode.Kind? {
        let className = entry.className.lowercased()
        let text = "\(entry.className) \(entry.entryName)".lowercased()

        if className == "iomedia", entry.bsdName == drive.bsdName {
            return .disk
        }
        if text.contains("thunderbolt") {
            return .thunderboltTransport
        }
        if className.contains("pci2pcibridge")
            || (className == "iopcidevice" && entry.entryName.localizedCaseInsensitiveContains("bridge")) {
            return .pcieBridge
        }
        if className == "iopcidevice" {
            return .pcieDevice
        }
        if className.contains("nvmecontroller") {
            return .nvmeController
        }
        if text.contains("usb") {
            if text.contains("xhci") || text.contains("hostcontroller") {
                return .usbHostController
            }
            if text.contains("hub") {
                return .usbHub
            }
            if className.contains("usbhostdevice") {
                return .usbDevice
            }
            if text.contains("massstorage") || text.contains("uas") {
                return .storageBridge
            }
        }
        if text.contains("sata") || text.contains("ahci") {
            return .sataController
        }
        if text.contains("ans"), drive.protocolName.localizedCaseInsensitiveContains("fabric") {
            return .storageController
        }
        return nil
    }

    private static func name(
        for entry: DriveConnectionRegistryEntry,
        kind: DriveConnectionTopologyNode.Kind
    ) -> String? {
        switch kind {
        case .computer, .disk, .pcieTunnel:
            return nil
        case .nvmeController, .sataController, .storageController, .storageBridge,
             .usbHostController, .usbHub, .usbDevice, .thunderboltTransport:
            return hardwareName(for: entry)
        case .pcieBridge, .pcieDevice:
            return hardwareName(for: entry)
        }
    }

    private static func hardwareName(for entry: DriveConnectionRegistryEntry) -> String? {
        let candidate = nonempty(entry.hardwareDescription) ?? nonempty(entry.entryName)
        guard let candidate else { return nil }
        let genericRegistryNames = [
            "iopp",
            "ionvmecontroller",
            "ionvmeblockstoragedevice",
            "ioblockstoragedriver"
        ]
        return genericRegistryNames.contains(candidate.lowercased()) ? nil : candidate
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

enum DrivePCIeLinkParser {
    static func parse(linkStatus: UInt64) -> DrivePCIeLink? {
        // PCIe Link Status stores negotiated speed in bits 3:0 and width in bits 9:4.
        let rateCode = Int(linkStatus & 0x0f)
        let laneCount = Int((linkStatus >> 4) & 0x3f)
        let rates: [Int: (generation: Int, gigatransfersPerSecond: Double)] = [
            1: (1, 2.5),
            2: (2, 5.0),
            3: (3, 8.0),
            4: (4, 16.0),
            5: (5, 32.0),
            6: (6, 64.0)
        ]
        guard let rate = rates[rateCode], laneCount > 0 else { return nil }
        return DrivePCIeLink(
            generation: rate.generation,
            gigatransfersPerSecond: rate.gigatransfersPerSecond,
            laneCount: laneCount
        )
    }
}

struct IOKitDriveConnectionTopologyReader: Sendable {
    func read(for drive: DriveDevice) -> DriveConnectionTopology? {
        guard !drive.isNetwork, !drive.isVirtual,
              let media = copyWholeMedia(bsdName: drive.bsdName) else {
            return nil
        }
        defer { IOObjectRelease(media) }

        var entries: [DriveConnectionRegistryEntry] = []
        var current = media
        var ownsCurrent = false
        defer {
            if ownsCurrent {
                IOObjectRelease(current)
            }
        }

        while true {
            entries.append(registryEntry(from: current))

            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                break
            }
            if ownsCurrent {
                IOObjectRelease(current)
            }
            current = parent
            ownsCurrent = true
        }

        return DriveConnectionTopologyResolver.resolve(
            drive: drive,
            registryEntriesFromDiskToHost: entries
        )
    }

    private func registryEntry(from entry: io_registry_entry_t) -> DriveConnectionRegistryEntry {
        var classBuffer = [CChar](repeating: 0, count: 128)
        _ = IOObjectGetClass(entry, &classBuffer)
        var nameBuffer = [CChar](repeating: 0, count: 128)
        _ = IORegistryEntryGetName(entry, &nameBuffer)

        let pcieStatus = copyProperty(entry, key: "IOPCIExpressLinkStatus")
            .map { ($0 as? NSNumber)?.uint64Value }
            ?? nil
        let tunnelled = (copyProperty(entry, key: "IOPCITunnelled") as? NSNumber)?.boolValue ?? false
        let modelName = copyProperty(entry, key: "Model Number") as? String
        let chipsetName = copyProperty(entry, key: "Chipset Name") as? String
        let productName = copyProperty(entry, key: "USB Product Name") as? String
        let hardwareDescription = [
            productName,
            chipsetName,
            modelName
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
            .joined(separator: " · ")

        return DriveConnectionRegistryEntry(
            className: String(cString: classBuffer),
            entryName: String(cString: nameBuffer),
            bsdName: copyProperty(entry, key: kIOBSDNameKey) as? String,
            pcieLinkStatus: pcieStatus,
            isPCIeTunnelled: tunnelled,
            hardwareDescription: hardwareDescription.isEmpty ? nil : hardwareDescription
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

    private func copyProperty(_ entry: io_registry_entry_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
