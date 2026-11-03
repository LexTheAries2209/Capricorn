// SPDX-License-Identifier: GPL-3.0-only
import Foundation

extension SNTBridge: Codable {}

struct AutomaticSNTRecord: Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case available, retryable, stopped, needsRecovery
    }

    var status: Status = .retryable
    var consecutiveFailures = 0
    var preferredBridge: SNTBridge?
    var checkedAt = Date()
    var retryAfter: Date?
    var lastSnapshot: SmartSnapshot?
    var diagnostic: String?

    func hasFreshSnapshot(now: Date) -> Bool {
        guard let snapshot = lastSnapshot,
              snapshot.selectedProvider == USBRawSmartService.providerName,
              snapshot.hasSMARTPayload else { return false }
        let age = now.timeIntervalSince(snapshot.capturedAt)
        return age >= 0 && age < 48 * 60 * 60
    }

    mutating func apply(_ result: USBRawSmartResult, now: Date) {
        checkedAt = now
        diagnostic = result.transcript
        retryAfter = nil
        // An unfinished capture must never be repeated automatically, even
        // when SMART data arrived before cleanup failed.
        guard result.restorationConfirmed else {
            status = .needsRecovery
            return
        }
        if let snapshot = result.snapshot, snapshot.hasSMARTPayload {
            status = .available
            consecutiveFailures = 0
            preferredBridge = snapshot.selectedTransport.flatMap(SNTBridge.init(rawValue:))
            lastSnapshot = snapshot
            return
        }
        // Busy and pre-capture failures say nothing about bridge compatibility.
        guard !result.unmountBusy, result.phases.contains(.capturing) else { return }
        consecutiveFailures += 1
        let exhaustedProtocols = Set(result.attemptedBridges) == Set(SNTBridge.allCases)
            && result.probeInterruption == nil
        status = exhaustedProtocols || consecutiveFailures >= 3 ? .stopped : .retryable
        if status == .retryable {
            retryAfter = now.addingTimeInterval(consecutiveFailures == 1 ? 30 : 120)
        }
    }
}

/// One replaceable record per bridge/media combination, separate from history.
/// Media UUIDs prevent an enclosure serial from blacklisting replacement disks.
final class AutomaticSNTCache {
    static let defaultsKey = "automaticSNTCache.v1"
    private let defaults: UserDefaults
    private var transient: [String: AutomaticSNTRecord] = [:]

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static func identityKey(for drive: DriveDevice) -> String? {
        let volumes = VolumeUUIDNormalizer.normalized(drive.displayableVolumes.filter {
            $0.partitionContent?.caseInsensitiveCompare("EFI") != .orderedSame
        }.compactMap(\.volumeUUID))
        let media: [String]
        if !volumes.isEmpty {
            media = volumes
        } else if let name = CodexCompactDriveNameIdentity.volumeName(for: drive) {
            media = ["codex", name]
        } else {
            return nil
        }
        let components = [
            drive.protocolName.lowercased(),
            String(drive.usbDevice?.vendorID ?? 0),
            String(drive.usbDevice?.productID ?? 0),
            DriveSerialNumberNormalizer.normalize(drive.serialNumber ?? "") ?? "",
            drive.mediaName, String(drive.sizeBytes), String(drive.blockSize)
        ] + media
        guard let data = try? JSONEncoder().encode(components) else { return nil }
        return data.base64EncodedString()
    }

    func record(for drive: DriveDevice, connectionKey: String) -> AutomaticSNTRecord? {
        if let key = Self.identityKey(for: drive) { return entries()[key] }
        return transient[connectionKey]
    }

    func store(_ record: AutomaticSNTRecord, for drive: DriveDevice, connectionKey: String) {
        guard let key = Self.identityKey(for: drive) else {
            transient[connectionKey] = record
            return
        }
        var values = entries()
        values[key] = record
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    func retainConnections(_ keys: Set<String>) {
        transient = transient.filter { keys.contains($0.key) }
    }

    private func entries() -> [String: AutomaticSNTRecord] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let values = try? JSONDecoder().decode([String: AutomaticSNTRecord].self, from: data)
        else { return [:] }
        return values
    }
}
