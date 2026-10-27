// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit

struct StorageHostPort: Equatable, Hashable, Sendable {
    let number: Int

    static func parse(type: String?, number: Int?, builtIn: Bool) -> StorageHostPort? {
        guard builtIn, type == "USB-C", let number, number > 0 else { return nil }
        return .init(number: number)
    }
}

enum StorageHostPortPosition: String, Sendable {
    case leftRear, leftFront, right

    var titleKey: String {
        switch self {
        case .leftRear: "Left rear"
        case .leftFront: "Left front"
        case .right: "Right side"
        }
    }
}

struct StorageHostModel: Equatable, Sendable {
    let identifier: String
    let board: String

    var hasVerifiedPortLayout: Bool {
        // Asahi's board descriptions explicitly label typec0/1/2 as left back,
        // left front and right. Restrict the map to these board families.
        // M1: AsahiLinux/linux, arch/arm64/boot/dts/apple/t600x-j314-j316.dtsi
        // M2: AsahiLinux/linux, arch/arm64/boot/dts/apple/t602x-j414-j416.dtsi
        ["j314s", "j314c", "j316s", "j316c", "j414s", "j414c", "j416s", "j416c"]
            .contains(board.lowercased())
    }

    func position(for port: StorageHostPort) -> StorageHostPortPosition? {
        guard hasVerifiedPortLayout else { return nil }
        switch port.number {
        case 1: return .leftRear
        case 2: return .leftFront
        case 3: return .right
        default: return nil
        }
    }
}

struct IOKitStorageHostReader: Sendable {
    func readModel() -> StorageHostModel? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let identifier = string(property(entry, "model")),
              let board = string(property(entry, "target-type")) else { return nil }
        return .init(identifier: identifier, board: board)
    }

    func readPort(for entry: io_registry_entry_t) -> StorageHostPort? {
        if let port = directPort(entry) { return port }
        if let path = property(entry, "UsbIOPort") as? String {
            let connector = path.withCString { IORegistryEntryFromPath(kIOMainPortDefault, $0) }
            if connector != 0 {
                defer { IOObjectRelease(connector) }
                if let port = directPort(connector) { return port }
            }
        }
        // A Thunderbolt adapter's TRM ID is the registry identity of its
        // IOPortTransportStateCIO service, whose built-in parent is the socket.
        if let transportID = (property(entry, "TRM Transport ID") as? NSNumber)?.uint64Value,
           let matching = IORegistryEntryIDMatching(transportID) {
            let transport = IOServiceGetMatchingService(kIOMainPortDefault, matching)
            guard transport != 0 else { return nil }
            defer { IOObjectRelease(transport) }
            return StorageHostPort.parse(
                type: property(transport, "ParentBuiltInPortTypeDescription") as? String,
                number: (property(transport, "ParentBuiltInPortNumber") as? NSNumber)?.intValue,
                builtIn: (property(transport, "ParentPortBuiltIn") as? NSNumber)?.boolValue == true
            )
        }
        return nil
    }

    private func directPort(_ entry: io_registry_entry_t) -> StorageHostPort? {
        StorageHostPort.parse(
            type: property(entry, "PortTypeDescription") as? String,
            number: (property(entry, "PortNumber") as? NSNumber)?.intValue,
            builtIn: (property(entry, "BuiltIn") as? NSNumber)?.boolValue == true
        )
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        guard let data = value as? Data else { return nil }
        return String(data: data.prefix(while: { $0 != 0 }), encoding: .utf8)
    }

    private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
