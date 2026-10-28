// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import OSLog

struct DeviceChipIdentifier: Hashable, Sendable {
    enum Bus: String, Sendable {
        case pci = "PCI"
        case usb = "USB"
    }

    let bus: Bus
    let vendorID: UInt16
    let deviceID: UInt16

    init?(description: String) {
        let parts = description.split(separator: " ", maxSplits: 1)
        guard parts.count == 2,
              let bus = Bus(rawValue: parts[0].uppercased()) else {
            return nil
        }
        let identifiers = parts[1].split(separator: ":", omittingEmptySubsequences: false)
        guard identifiers.count == 2,
              identifiers.allSatisfy({ $0.count == 4 }),
              let vendorID = UInt16(identifiers[0], radix: 16),
              let deviceID = UInt16(identifiers[1], radix: 16) else {
            return nil
        }
        self.bus = bus
        self.vendorID = vendorID
        self.deviceID = deviceID
    }

    var displayValue: String {
        "\(bus.rawValue) \(String(format: "%04X:%04X", vendorID, deviceID))"
    }

    var deviceHuntURL: URL {
        let type = bus == .pci ? "pci" : "usb"
        return URL(string: "https://devicehunt.com/view/type/\(type)/vendor/\(String(format: "%04X", vendorID))/device/\(String(format: "%04X", deviceID))")!
    }
}

/// Curated offline ID mappings; a vendor/product ID can identify a device family rather than one exact silicon revision.
struct DeviceHuntChipCatalog: Sendable {
    struct Document: Decodable {
        let schemaVersion: Int
        let source: String
        let snapshotDate: String
        let records: [Record]
    }

    struct Record: Decodable, Equatable, Sendable {
        let id: String
        let manufacturer: String
        let category: String
        let name: String
        let shortName: String?
        let sourceURL: String

        var topologyName: String {
            shortName ?? name
        }

        var identifier: DeviceChipIdentifier? {
            DeviceChipIdentifier(description: id)
        }
    }

    enum CatalogError: Error, LocalizedError {
        case unsupportedSchema(Int)
        case invalidIdentifier(String)
        case duplicateIdentifier(String)
        case invalidRecord(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version):
                "Unsupported DeviceHunt chip catalog schema version \(version)."
            case .invalidIdentifier(let id):
                "Invalid hardware identifier in DeviceHunt chip catalog: \(id)."
            case .duplicateIdentifier(let id):
                "Duplicate hardware identifier in DeviceHunt chip catalog: \(id)."
            case .invalidRecord(let id):
                "Incomplete DeviceHunt chip catalog record: \(id)."
            }
        }
    }

    static let bundled: DeviceHuntChipCatalog = {
        let bundle = Bundle.main
        let url = bundle.url(forResource: "DeviceHuntChipCatalog", withExtension: "json")
            ?? bundle.url(forResource: "DeviceHuntChipCatalog", withExtension: "json", subdirectory: "Resources")
        guard let url else {
            CapricornLog.inventory.error("DeviceHunt chip catalog resource is missing.")
            return DeviceHuntChipCatalog(records: [])
        }
        do {
            return try DeviceHuntChipCatalog(data: Data(contentsOf: url))
        } catch {
            CapricornLog.inventory.error("DeviceHunt chip catalog could not be loaded: \(String(describing: error), privacy: .public)")
            return DeviceHuntChipCatalog(records: [])
        }
    }()

    let source: String
    let snapshotDate: String
    let records: [Record]
    private let recordsByIdentifier: [DeviceChipIdentifier: Record]

    init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1 else {
            throw CatalogError.unsupportedSchema(document.schemaVersion)
        }
        guard document.source == "DeviceHunt", !document.snapshotDate.isEmpty else {
            throw CatalogError.invalidRecord("catalog metadata")
        }

        var index: [DeviceChipIdentifier: Record] = [:]
        for record in document.records {
            guard let identifier = record.identifier else {
                throw CatalogError.invalidIdentifier(record.id)
            }
            guard !record.manufacturer.isEmpty, !record.category.isEmpty, !record.name.isEmpty,
                  record.shortName?.isEmpty != true,
                  let sourceURL = URLComponents(string: record.sourceURL),
                  sourceURL.scheme == "https", sourceURL.host == "devicehunt.com" else {
                throw CatalogError.invalidRecord(record.id)
            }
            guard URL(string: record.sourceURL) == identifier.deviceHuntURL else {
                throw CatalogError.invalidRecord(record.id)
            }
            guard index[identifier] == nil else {
                throw CatalogError.duplicateIdentifier(identifier.displayValue)
            }
            index[identifier] = record
        }
        source = document.source
        snapshotDate = document.snapshotDate
        records = document.records
        recordsByIdentifier = index
    }

    private init(records: [Record]) {
        source = "DeviceHunt"
        snapshotDate = ""
        self.records = records
        recordsByIdentifier = [:]
    }

    func resolve(chipDescriptions: [String]) -> [String: Record] {
        var matches: [String: Record] = [:]
        for description in chipDescriptions {
            guard let identifier = DeviceChipIdentifier(description: description),
                  let record = recordsByIdentifier[identifier] else {
                continue
            }
            matches[identifier.displayValue] = record
        }
        return matches
    }
}
