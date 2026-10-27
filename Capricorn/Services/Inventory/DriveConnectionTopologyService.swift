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

struct DriveConnectionTopologyNode: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case computer
        case thunderboltController
        case thunderboltSwitch
        case thunderboltPort
        case thunderboltAdapter
        case thunderboltTransport
        case pcieTunnel
        case usbPort
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

    let id: String
    let kind: Kind
    let hardwareName: String?
    let portDescription: String?
    let linkRateDescription: String?
    let bsdName: String?
    let pcieLink: DrivePCIeLink?
    let isPCIeTunnelled: Bool
    var chipDescription: String? = nil
    var hostPort: StorageHostPort? = nil
    var isUSBTunnelled: Bool = false
}

struct DriveConnectionTopologyPath: Equatable, Sendable {
    let nodes: [DriveConnectionTopologyNode]
    let hasResolvedController: Bool
}

struct DriveConnectionTopologyEdge: Equatable, Sendable, Identifiable {
    let fromID: String
    let toID: String
    var driveBSDNames: Set<String>

    var id: String { "\(fromID)->\(toID)" }
}

struct DriveConnectionTopologyGraph: Equatable, Sendable {
    let nodes: [DriveConnectionTopologyNode]
    let edges: [DriveConnectionTopologyEdge]
    var hostModel: StorageHostModel? = nil

    static func assemble(paths: [String: DriveConnectionTopologyPath]) -> DriveConnectionTopologyGraph {
        var nodesByID: [String: DriveConnectionTopologyNode] = [:]
        var orderedNodeIDs: [String] = []
        var driveNamesByEdge: [String: Set<String>] = [:]
        var edgeEndpoints: [String: (from: String, to: String)] = [:]

        for driveName in paths.keys.sorted(by: {
            $0.localizedStandardCompare($1) == .orderedAscending
        }) {
            guard let path = paths[driveName] else { continue }
            for node in path.nodes where nodesByID[node.id] == nil {
                nodesByID[node.id] = node
                orderedNodeIDs.append(node.id)
            }
            for pair in zip(path.nodes, path.nodes.dropFirst()) {
                let key = "\(pair.0.id)->\(pair.1.id)"
                edgeEndpoints[key] = (pair.0.id, pair.1.id)
                driveNamesByEdge[key, default: []].insert(driveName)
            }
        }

        return DriveConnectionTopologyGraph(
            nodes: orderedNodeIDs.compactMap { nodesByID[$0] },
            edges: edgeEndpoints.keys.sorted().compactMap { key in
                guard let endpoints = edgeEndpoints[key],
                      let driveNames = driveNamesByEdge[key] else {
                    return nil
                }
                return DriveConnectionTopologyEdge(
                    fromID: endpoints.from,
                    toID: endpoints.to,
                    driveBSDNames: driveNames
                )
            }
        )
    }

    func pathNodeIDs(to driveBSDName: String) -> Set<String> {
        let selectedEdges = edges.filter { $0.driveBSDNames.contains(driveBSDName) }
        return Set(selectedEdges.flatMap { [$0.fromID, $0.toID] })
    }

    func pathEdges(for driveBSDName: String) -> Set<String> {
        Set(edges.filter { $0.driveBSDNames.contains(driveBSDName) }.map(\.id))
    }

    func path(for driveBSDName: String) -> [DriveConnectionTopologyNode] {
        let selectedEdges = edges.filter { $0.driveBSDNames.contains(driveBSDName) }
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var result: [DriveConnectionTopologyNode] = []
        var nextID: String? = "computer"
        var visited: Set<String> = []
        while let id = nextID, visited.insert(id).inserted, let node = nodesByID[id] {
            result.append(node)
            nextID = selectedEdges.first { $0.fromID == id }?.toID
        }
        return result.last?.bsdName == driveBSDName ? result : []
    }
}

struct DriveConnectionRegistryEntry: Equatable, Sendable {
    var registryID: String = ""
    let className: String
    let entryName: String
    let bsdName: String?
    let pcieLinkStatus: UInt64?
    let isPCIeTunnelled: Bool
    var hardwareDescription: String? = nil
    var portNumber: Int? = nil
    var portDescription: String? = nil
    var linkRateDescription: String? = nil
    var thunderboltPath: String? = nil
    var chipDescription: String? = nil
    var ignoresPCIeLinkStatus: Bool = false
    var hostPort: StorageHostPort? = nil
    var isUSBTunnelled: Bool = false
}

enum USBHubPresentation {
    static func isGeneric(_ hardwareName: String?) -> Bool {
        guard let hardwareName else { return false }
        let normalized = hardwareName.lowercased().filter { $0.isLetter }
        return ["hub", "hubdevice", "usbhub", "usb3hub", "usb30hub", "xhcihub", "usb集线器"].contains(normalized)
    }
}

enum DriveConnectionTopologyResolver {
    static func resolve(
        drive: DriveDevice,
        registryEntriesFromDiskToHost entries: [DriveConnectionRegistryEntry],
        thunderboltEntriesFromPortToHost: [DriveConnectionRegistryEntry] = []
    ) -> DriveConnectionTopologyPath? {
        guard entries.contains(where: { $0.bsdName == drive.bsdName }) else { return nil }

        let mainPath = entries.reversed().compactMap { entry -> DriveConnectionTopologyNode? in
            guard let kind = kind(for: entry, drive: drive) else { return nil }
            return node(for: entry, kind: kind, drive: drive)
        }

        var nodes = uniqueNodes(mainPath)

        let hasResolvedController = nodes.contains { $0.kind != .disk }
        if nodes.first?.kind != .computer {
            nodes.insert(
                DriveConnectionTopologyNode(
                    id: "computer",
                    kind: .computer,
                    hardwareName: nil,
                    portDescription: nil,
                    linkRateDescription: nil,
                    bsdName: nil,
                    pcieLink: nil,
                    isPCIeTunnelled: false
                ),
                at: 0
            )
        }
        if nodes.last?.kind != .disk {
            nodes.append(
                DriveConnectionTopologyNode(
                    id: "disk:\(drive.bsdName)",
                    kind: .disk,
                    hardwareName: drive.displayName,
                    portDescription: nil,
                    linkRateDescription: drive.connectionInfo?.detailLabel(effectiveLabel: "Effective"),
                    bsdName: drive.bsdName,
                    pcieLink: nil,
                    isPCIeTunnelled: false
                )
            )
        }

        if !thunderboltEntriesFromPortToHost.isEmpty {
            let thunderboltNodes = thunderboltEntriesFromPortToHost.reversed().compactMap { entry -> DriveConnectionTopologyNode? in
                guard let kind = kind(for: entry, drive: drive),
                      kind != .disk,
                      kind != .computer else {
                    return nil
                }
                return node(for: entry, kind: kind, drive: drive)
            }
            let tunnelIndex = nodes.firstIndex(where: \.isPCIeTunnelled)
                ?? nodes.firstIndex(where: { $0.kind == .pcieDevice || $0.kind == .pcieBridge })
            if let tunnelIndex, !thunderboltNodes.isEmpty {
                // Thunderbolt Path is an explicit cross-plane association, not a name match.
                nodes = uniqueNodes([nodes[0]] + thunderboltNodes + Array(nodes.suffix(from: tunnelIndex)))
            }
        }

        nodes = attachTransportRate(nodes, from: drive.connectionInfo)
        return DriveConnectionTopologyPath(nodes: nodes, hasResolvedController: hasResolvedController)
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
        if className.contains("iothunderboltport"),
           entry.portDescription?.localizedCaseInsensitiveContains("Thunderbolt Port") == true {
            return .thunderboltPort
        }
        if className.contains("iothunderboltswitch") {
            return .thunderboltSwitch
        }
        if className.contains("iothunderboltcontroller") {
            return .thunderboltController
        }
        if className.contains("thunderboltpcidownadapter") {
            return .thunderboltAdapter
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
            if (entry.hostPort != nil && entry.entryName.localizedCaseInsensitiveContains("port"))
                || className.contains("usbhostport") || className.contains("usbport")
                || className.contains("xhciport") || className.contains("hubport") {
                return .usbPort
            }
            if text.contains("xhci") || text.contains("hostcontroller") {
                return .usbHostController
            }
            if text.contains("hub") || isGenericUSBHubName(entry) {
                // Retain product-named hubs and OS-marked USB tunnel hubs only.
                return isNamedUSBDock(entry) || entry.isUSBTunnelled ? .usbHub : .usbPort
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
        return nil
    }

    private static func node(
        for entry: DriveConnectionRegistryEntry,
        kind: DriveConnectionTopologyNode.Kind,
        drive: DriveDevice
    ) -> DriveConnectionTopologyNode {
        let ignoresLink = entry.ignoresPCIeLinkStatus || (kind == .pcieBridge && entry.isPCIeTunnelled)
        let link = ignoresLink ? nil : entry.pcieLinkStatus.flatMap(DrivePCIeLinkParser.parse)
        let rate = link?.detailLabel ?? entry.linkRateDescription
        let hardwareName = kind == .disk
            ? drive.displayName
            : hardwareName(for: entry)
        let portDescription = entry.portNumber.map { number in
            [entry.portDescription, "Port \(number)"]
                .compactMap { $0 }
                .joined(separator: " ")
        } ?? entry.portDescription
        let id: String
        if kind == .disk {
            id = "disk:\(drive.bsdName)"
        } else if kind == .computer {
            id = "computer"
        } else if !entry.registryID.isEmpty {
            id = "registry:\(entry.registryID)"
        } else {
            id = "\(kind.rawValue):\(entry.className):\(entry.entryName)"
        }
        return DriveConnectionTopologyNode(
            id: id,
            kind: kind,
            hardwareName: hardwareName,
            portDescription: portDescription,
            linkRateDescription: rate,
            bsdName: kind == .disk ? drive.bsdName : nil,
            pcieLink: link,
            isPCIeTunnelled: entry.isPCIeTunnelled,
            chipDescription: entry.chipDescription,
            hostPort: entry.hostPort,
            isUSBTunnelled: entry.isUSBTunnelled
        )
    }

    private static func uniqueNodes(_ nodes: [DriveConnectionTopologyNode]) -> [DriveConnectionTopologyNode] {
        var seen: Set<String> = []
        return nodes.filter { seen.insert($0.id).inserted }
    }

    private static func attachTransportRate(
        _ nodes: [DriveConnectionTopologyNode],
        from connectionInfo: DriveConnectionInfo?
    ) -> [DriveConnectionTopologyNode] {
        guard let connectionInfo,
              let transportIndex = nodes.lastIndex(where: {
                  [.usbDevice, .usbHub, .usbPort, .usbHostController, .storageBridge].contains($0.kind)
              }),
              nodes[transportIndex].linkRateDescription == nil else {
            return nodes
        }
        var updatedNodes = nodes
        let node = updatedNodes[transportIndex]
        updatedNodes[transportIndex] = DriveConnectionTopologyNode(
            id: node.id,
            kind: node.kind,
            hardwareName: node.hardwareName,
            portDescription: node.portDescription,
            linkRateDescription: connectionInfo.detailLabel(effectiveLabel: "Effective"),
            bsdName: node.bsdName,
            pcieLink: node.pcieLink,
            isPCIeTunnelled: node.isPCIeTunnelled,
            chipDescription: node.chipDescription,
            hostPort: node.hostPort,
            isUSBTunnelled: node.isUSBTunnelled
        )
        return updatedNodes
    }

    private static func hardwareName(for entry: DriveConnectionRegistryEntry) -> String? {
        let candidate = nonempty(entry.hardwareDescription)
            ?? (entry.entryName == entry.className ? nil : nonempty(entry.entryName))
        guard let candidate else { return nil }
        let genericRegistryNames = [
            "iopp",
            "ionvmecontroller",
            "ionvmeblockstoragedevice",
            "ioblockstoragedriver"
        ]
        let registryStem = candidate.components(separatedBy: "@")[0]
        return genericRegistryNames.contains(candidate.lowercased()) || registryStem == entry.className ? nil : candidate
    }

    private static func isNamedUSBDock(_ entry: DriveConnectionRegistryEntry) -> Bool {
        guard let candidate = nonempty(entry.hardwareDescription)
                ?? (entry.entryName == entry.className ? nil : nonempty(entry.entryName)) else { return false }
        return !isGenericUSBHubName(entry)
    }

    private static func isGenericUSBHubName(_ entry: DriveConnectionRegistryEntry) -> Bool {
        let candidate = nonempty(entry.hardwareDescription)
            ?? (entry.entryName == entry.className ? nil : nonempty(entry.entryName))
        guard let candidate else { return false }
        let normalized = candidate.lowercased().filter { $0.isLetter }
        return USBHubPresentation.isGeneric(candidate)
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
    func readGraph(drives: [DriveDevice]) -> DriveConnectionTopologyGraph {
        var paths: [String: DriveConnectionTopologyPath] = [:]
        for drive in drives where !drive.isNetwork && !drive.isVirtual {
            paths[drive.bsdName] = read(for: drive) ?? DriveConnectionTopologyPath(
                nodes: [
                    .init(id: "computer", kind: .computer, hardwareName: nil, portDescription: nil,
                          linkRateDescription: nil, bsdName: nil, pcieLink: nil, isPCIeTunnelled: false),
                    .init(id: "disk:\(drive.bsdName)", kind: .disk, hardwareName: drive.displayName,
                          portDescription: nil, linkRateDescription: nil, bsdName: drive.bsdName,
                          pcieLink: nil, isPCIeTunnelled: false)
                ],
                hasResolvedController: false
            )
        }
        var graph = DriveConnectionTopologyGraph.assemble(paths: paths)
        graph.hostModel = IOKitStorageHostReader().readModel()
        return graph
    }

    func read(for drive: DriveDevice) -> DriveConnectionTopologyPath? {
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

        let thunderboltPath = entries.compactMap(\.thunderboltPath).first
        let thunderboltEntries = thunderboltPath.map(readRegistryPath) ?? []
        return DriveConnectionTopologyResolver.resolve(
            drive: drive,
            registryEntriesFromDiskToHost: entries,
            thunderboltEntriesFromPortToHost: thunderboltEntries
        )
    }

    private func registryEntry(from entry: io_registry_entry_t) -> DriveConnectionRegistryEntry {
        var classBuffer = [CChar](repeating: 0, count: 128)
        _ = IOObjectGetClass(entry, &classBuffer)
        var nameBuffer = [CChar](repeating: 0, count: 128)
        _ = IORegistryEntryGetName(entry, &nameBuffer)

        let pcieStatus = (copyProperty(entry, key: "IOPCIExpressLinkStatus") as? NSNumber)?.uint64Value
        let tunnelled = (copyProperty(entry, key: "IOPCITunnelled") as? NSNumber)?.boolValue ?? false
        let usbTunnelled = (copyProperty(entry, key: "UsbTunnel") as? NSNumber)?.boolValue ?? false
        let modelName = copyProperty(entry, key: "Model Number") as? String
        let chipsetName = copyProperty(entry, key: "Chipset Name") as? String
        let productName = copyProperty(entry, key: "USB Product Name") as? String
        let portNumber = (copyProperty(entry, key: "Port Number") as? NSNumber)?.intValue
        let description = copyProperty(entry, key: "Description") as? String
        let locationID = (copyProperty(entry, key: "locationID") as? NSNumber)?.uint32Value
        let portDescription = description ?? locationID.flatMap { $0 == 0 ? nil : String(format: "USB 0x%08X", $0) }
        let thunderboltPath = copyProperty(entry, key: "Thunderbolt Path") as? String
        let currentLinkSpeed = (copyProperty(entry, key: "Current Link Speed") as? NSNumber)?.intValue
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
        var registryIdentifier: UInt64 = 0
        let hasRegistryIdentifier = IORegistryEntryGetRegistryEntryID(entry, &registryIdentifier) == KERN_SUCCESS

        return DriveConnectionRegistryEntry(
            registryID: hasRegistryIdentifier ? String(registryIdentifier) : "",
            className: String(cString: classBuffer),
            entryName: String(cString: nameBuffer),
            bsdName: copyProperty(entry, key: kIOBSDNameKey) as? String,
            pcieLinkStatus: pcieStatus,
            isPCIeTunnelled: tunnelled,
            hardwareDescription: hardwareDescription.isEmpty ? nil : hardwareDescription,
            portNumber: portNumber,
            portDescription: portDescription,
            linkRateDescription: Self.linkRateDescription(
                currentLinkSpeed: currentLinkSpeed,
                usbSpeedCode: (copyProperty(entry, key: "USBSpeed") as? NSNumber)?.intValue
                    ?? (copyProperty(entry, key: "Device Speed") as? NSNumber)?.intValue,
                usbLinkSpeed: copyProperty(entry, key: "UsbLinkSpeed") as? NSNumber
            ),
            thunderboltPath: thunderboltPath,
            chipDescription: chipDescription(entry: entry, chipsetName: chipsetName),
            ignoresPCIeLinkStatus: copyProperty(entry, key: "pci-ignore-linkstatus") != nil,
            hostPort: IOKitStorageHostReader().readPort(for: entry),
            isUSBTunnelled: usbTunnelled
        )
    }

    private func readRegistryPath(_ path: String) -> [DriveConnectionRegistryEntry] {
        let pathEntry = path.withCString { IORegistryEntryFromPath(kIOMainPortDefault, $0) }
        guard pathEntry != 0 else { return [] }
        defer { IOObjectRelease(pathEntry) }

        var entries: [DriveConnectionRegistryEntry] = []
        var current = pathEntry
        var ownsCurrent = false
        defer {
            if ownsCurrent { IOObjectRelease(current) }
        }
        while true {
            entries.append(registryEntry(from: current))
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                break
            }
            if ownsCurrent { IOObjectRelease(current) }
            current = parent
            ownsCurrent = true
        }
        return entries
    }

    static func linkRateDescription(
        currentLinkSpeed: Int?,
        usbSpeedCode: Int?,
        usbLinkSpeed: NSNumber?
    ) -> String? {
        if let currentLinkSpeed, let rate = [1: 10, 2: 20, 4: 40, 8: 80][currentLinkSpeed] {
            return "\(rate) Gb/s"
        }
        let bitsPerSecond = (usbLinkSpeed?.int64Value).flatMap { $0 >= 100_000 ? $0 : nil }
            ?? usbSpeedCode.flatMap { [1: Int64(12_000_000), 2: 480_000_000, 3: 5_000_000_000,
                                      4: 10_000_000_000, 5: 20_000_000_000][$0] }
        guard let bitsPerSecond, bitsPerSecond > 0 else { return nil }
        return DriveConnectionInfo(transport: .usb, negotiatedBitsPerSecond: bitsPerSecond).detailLabel
    }

    private func chipDescription(entry: io_registry_entry_t, chipsetName: String?) -> String? {
        let vendor = propertyInteger(copyProperty(entry, key: "vendor-id"))
        let device = propertyInteger(copyProperty(entry, key: "device-id"))
        if let vendor, let device {
            return String(format: "PCI %04X:%04X", vendor, device)
        }
        if let vendor = propertyInteger(copyProperty(entry, key: "idVendor")),
           let product = propertyInteger(copyProperty(entry, key: "idProduct")) {
            return String(format: "USB %04X:%04X", vendor, product)
        }
        guard let chipsetName, !chipsetName.isEmpty,
              chipsetName != "SSD Controller" else { return nil }
        return chipsetName
    }

    private func propertyInteger(_ value: Any?) -> UInt32? {
        if let value = value as? NSNumber { return value.uint32Value }
        guard let data = value as? Data, data.count >= 2 else { return nil }
        return data.prefix(4).enumerated().reduce(UInt32(0)) { result, element in
            result | (UInt32(element.element) << (8 * element.offset))
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

    private func copyProperty(_ entry: io_registry_entry_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
