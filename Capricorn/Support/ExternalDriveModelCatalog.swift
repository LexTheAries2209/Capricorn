// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import OSLog

struct ExternalDriveModelCatalog: @unchecked Sendable {
    struct Document: Decodable {
        var schemaVersion: Int
        var records: [Record]
    }

    struct Record: Decodable, Equatable, Sendable {
        struct Example: Decodable, Equatable, Sendable {
            var reportedModel: String
            var canonicalModel: String
            var capacityToken: String
        }

        var id: String
        var manufacturer: String
        var family: String
        var mediaKind: String
        var interfaces: [String]
        var introduced: Int
        var modelPatterns: [String]
        var capacityLabels: [String: String]
        var prefersMarketingNameOnly: Bool?
        var sourceURL: String
        var examples: [Example]

        func marketingName(capacityToken: String) -> String? {
            guard let capacity = capacityLabels[capacityToken.uppercased()] else { return nil }
            return "\(manufacturer) \(family) \(capacity)"
        }
    }

    struct Match: Equatable, Sendable {
        var recordID: String
        var family: String
        var capacityLabel: String
        var canonicalModel: String
        var marketingName: String
        var reportedModel: String
        var prefersMarketingNameOnly: Bool

        var displayName: String {
            "\(canonicalModel) · \(marketingName)"
        }

        /// Product-facing names such as "ARES 4T" or "Gold P31 1TB" are
        /// already more useful than the catalog's part-number presentation.
        /// Requiring both the family and capacity, plus a word boundary in the
        /// reported value, prevents opaque codes such as KXG80ZNV1T02 from
        /// being mistaken for an intentional marketing name.
        func preservesReportedName(_ name: String) -> Bool {
            guard name.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
                return false
            }

            let nameTokens = Self.wordTokens(name)
            let familyTokens = Self.wordTokens(family)
            let capacityKey = Self.capacityKey(capacityLabel)
            return !familyTokens.isEmpty
                && !capacityKey.isEmpty
                && Self.containsSequence(familyTokens, in: nameTokens)
                && Self.comparisonKey(name).contains(capacityKey)
        }

        private static func wordTokens(_ value: String) -> [String] {
            value.uppercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }

        private static func containsSequence(_ needle: [String], in haystack: [String]) -> Bool {
            guard !needle.isEmpty, needle.count <= haystack.count else { return false }
            return haystack.indices.contains { start in
                guard start + needle.count <= haystack.count else { return false }
                return Array(haystack[start..<(start + needle.count)]) == needle
            }
        }

        private static func comparisonKey(_ value: String) -> String {
            String(value.uppercased().filter { $0.isLetter || $0.isNumber })
        }

        private static func capacityKey(_ value: String) -> String {
            let key = comparisonKey(value)
            if key.hasSuffix("TB") || key.hasSuffix("GB") {
                return String(key.dropLast())
            }
            return key
        }
    }

    enum CatalogError: Error, LocalizedError {
        case unsupportedSchema(Int)
        case duplicateRecordID(String)
        case emptyPattern(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version):
                return "Unsupported external-drive catalog schema version \(version)."
            case .duplicateRecordID(let id):
                return "Duplicate external-drive catalog record ID \(id)."
            case .emptyPattern(let id):
                return "External-drive catalog record \(id) has no model patterns."
            }
        }
    }

    private struct CompiledRecord {
        var record: Record
        var expressions: [NSRegularExpression]
    }

    static let bundled: ExternalDriveModelCatalog = {
        let bundle = Bundle.main
        let url = bundle.url(forResource: "ExternalDriveModels", withExtension: "json")
            ?? bundle.url(forResource: "ExternalDriveModels", withExtension: "json", subdirectory: "Resources")
        guard let url else {
            CapricornLog.inventory.error("External drive model catalog resource is missing.")
            return ExternalDriveModelCatalog(compiledRecords: [])
        }

        do {
            return try ExternalDriveModelCatalog(data: Data(contentsOf: url))
        } catch {
            CapricornLog.inventory.error("External drive model catalog could not be loaded: \(String(describing: error), privacy: .public)")
            return ExternalDriveModelCatalog(compiledRecords: [])
        }
    }()

    let records: [Record]
    private let compiledRecords: [CompiledRecord]

    init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1 else {
            throw CatalogError.unsupportedSchema(document.schemaVersion)
        }

        var seenIDs: Set<String> = []
        var compiled: [CompiledRecord] = []
        for record in document.records {
            guard seenIDs.insert(record.id).inserted else {
                throw CatalogError.duplicateRecordID(record.id)
            }
            guard !record.modelPatterns.isEmpty else {
                throw CatalogError.emptyPattern(record.id)
            }
            let expressions = try record.modelPatterns.map {
                try NSRegularExpression(pattern: $0, options: [.caseInsensitive])
            }
            compiled.append(CompiledRecord(record: record, expressions: expressions))
        }

        records = document.records
        compiledRecords = compiled
    }

    private init(compiledRecords: [CompiledRecord]) {
        self.compiledRecords = compiledRecords
        records = compiledRecords.map(\.record)
    }

    func match(for drive: DriveDevice) -> Match? {
        guard Self.isEligible(drive) else { return nil }

        let candidates = Self.uniqueCandidates([
            drive.displayName,
            drive.mediaName,
            drive.model
        ])
        for candidate in candidates {
            let normalized = Self.normalized(candidate)
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            for compiled in compiledRecords {
                guard Self.transportIsCompatible(drive: drive, record: compiled.record) else {
                    continue
                }
                for expression in compiled.expressions {
                    guard let result = expression.firstMatch(in: normalized, range: range),
                          let model = Self.capture(named: "model", from: result, in: normalized),
                          let capacityToken = Self.capture(named: "capacity", from: result, in: normalized),
                          let marketingName = compiled.record.marketingName(capacityToken: capacityToken) else {
                        continue
                    }
                    return Match(
                        recordID: compiled.record.id,
                        family: compiled.record.family,
                        capacityLabel: compiled.record.capacityLabels[capacityToken.uppercased()] ?? capacityToken,
                        canonicalModel: model.uppercased(),
                        marketingName: marketingName,
                        reportedModel: candidate,
                        prefersMarketingNameOnly: compiled.record.prefersMarketingNameOnly ?? false
                    )
                }
            }
        }
        return nil
    }

    private static func isEligible(_ drive: DriveDevice) -> Bool {
        guard !drive.isNetwork,
              !drive.isVirtual,
              !drive.isMemoryCard else {
            return false
        }

        return true
    }

    private static func transportIsCompatible(drive: DriveDevice, record: Record) -> Bool {
        let transport = drive.protocolName.lowercased()
        let isPCIeDevice = transport.contains("nvme")
            || transport.contains("pci-express")
            || transport.contains("apple fabric")
        guard isPCIeDevice else { return true }

        let declaredInterfaces = record.interfaces.joined(separator: " ").lowercased()
        return declaredInterfaces.contains("nvme")
            || declaredInterfaces.contains("pcie")
            || declaredInterfaces.contains("m.2")
    }

    private static func normalized(_ value: String) -> String {
        var result = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
        if result.range(of: #"\s+MEDIA$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            result = result.replacingOccurrences(
                of: #"\s+MEDIA$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .uppercased()
    }

    private static func uniqueCandidates(_ values: [String?]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) where !value.isEmpty {
            let key = normalized(value)
            if seen.insert(key).inserted {
                result.append(value)
            }
        }
        return result
    }

    private static func capture(named name: String, from result: NSTextCheckingResult, in value: String) -> String? {
        let range = result.range(withName: name)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: value) else {
            return nil
        }
        return String(value[swiftRange])
    }
}

extension DriveDevice {
    var catalogMatch: ExternalDriveModelCatalog.Match? {
        ExternalDriveModelCatalog.bundled.match(for: self)
    }

    var catalogDisplayName: String {
        guard let match = catalogMatch else { return displayName }
        if match.preservesReportedName(displayName) { return displayName }
        return match.prefersMarketingNameOnly ? match.marketingName : match.displayName
    }

    var catalogSidebarDisplayName: String {
        guard let match = catalogMatch else { return displayName }
        return match.preservesReportedName(displayName) ? displayName : match.marketingName
    }

    var catalogHeaderDisplayName: String {
        guard let match = catalogMatch else { return displayName }
        guard !match.preservesReportedName(displayName) else { return displayName }
        let groupedMarketingName = match.marketingName.replacingOccurrences(of: " ", with: "\u{00A0}")
        guard !match.prefersMarketingNameOnly else { return groupedMarketingName }
        return "\(match.canonicalModel) · \(groupedMarketingName)"
    }

    func catalogDisplayHelp(language: AppLanguage) -> String {
        let enhancedName = catalogDisplayName
        guard enhancedName != displayName else { return displayName }
        return "\(enhancedName)\n\(language.t("Original model")): \(displayName)"
    }
}
