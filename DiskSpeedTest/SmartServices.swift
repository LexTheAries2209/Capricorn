import Foundation
import UserNotifications

protocol SmartProviding {
    var providerName: String { get }
    func snapshot(for drive: DriveDevice) async -> SmartSnapshot?
}

final class NativeSmartProvider: SmartProviding {
    let providerName = "Native macOS"
    private let evaluator = DriveHealthEvaluator()

    func snapshot(for drive: DriveDevice) async -> SmartSnapshot? {
        guard drive.smartStatusRaw != nil || !drive.nativeSmartKeys.isEmpty else {
            return SmartSnapshot.unavailable(for: drive, reason: "Native SMART data is not exposed for this device.")
        }

        var attributes: [SmartAttribute] = []
        let keys = drive.nativeSmartKeys
        let temperatureC = nativeTemperature(from: keys["TEMPERATURE"])
        let percentageUsed = intValue(keys["PERCENTAGE_USED"])
        let lifeRemaining = percentageUsed.map { max(0, min(100, 100 - $0)) }
        let mediaErrors = combinedValue(prefix: "MEDIA_ERRORS", keys: keys)
        let unsafeShutdowns = combinedValue(prefix: "UNSAFE_SHUTDOWNS", keys: keys)
        let powerOnHours = intValue(combinedValue(prefix: "POWER_ON_HOURS", keys: keys))
        let powerCycles = intValue(combinedValue(prefix: "POWER_CYCLES", keys: keys))

        appendNative("AVAILABLE_SPARE", "Available Spare", keys, to: &attributes, suffix: "%")
        appendNative("AVAILABLE_SPARE_THRESHOLD", "Available Spare Threshold", keys, to: &attributes, suffix: "%")
        appendNative("PERCENTAGE_USED", "Percentage Used", keys, to: &attributes, suffix: "%")
        appendNative("TEMPERATURE", "Temperature", keys, to: &attributes, suffix: " K")
        appendCombined("DATA_UNITS_READ", "Data Units Read", keys, to: &attributes, multiplier: 512_000)
        appendCombined("DATA_UNITS_WRITTEN", "Data Units Written", keys, to: &attributes, multiplier: 512_000)
        appendCombined("MEDIA_ERRORS", "Media Errors", keys, to: &attributes)
        appendCombined("NUM_ERROR_INFO_LOG_ENTRIES", "Error Log Entries", keys, to: &attributes)
        appendCombined("POWER_ON_HOURS", "Power-On Hours", keys, to: &attributes)
        appendCombined("POWER_CYCLES", "Power Cycles", keys, to: &attributes)
        appendCombined("UNSAFE_SHUTDOWNS", "Unsafe Shutdowns", keys, to: &attributes)

        var snapshot = SmartSnapshot(
            driveID: drive.id,
            capturedAt: Date(),
            health: .unavailable,
            summary: drive.smartStatusRaw ?? "Native SMART keys parsed.",
            providerStatuses: [
                ProviderStatus(
                    name: providerName,
                    state: drive.nativeSmartKeys.isEmpty ? .limited : .available,
                    message: drive.smartStatusRaw ?? "SMART status not reported, device-specific keys available."
                )
            ],
            attributes: attributes,
            temperatureCelsius: temperatureC,
            lifeRemainingPercent: lifeRemaining,
            powerOnHours: powerOnHours,
            powerCycleCount: powerCycles,
            mediaErrors: mediaErrors,
            unsafeShutdowns: unsafeShutdowns,
            smartStatusRaw: drive.smartStatusRaw,
            selfTestStatus: nil
        )
        snapshot.health = evaluator.evaluate(drive: drive, snapshot: snapshot)
        snapshot.summary = evaluator.summary(for: drive, snapshot: snapshot)
        return snapshot
    }

    private func nativeTemperature(from kelvin: Int64?) -> Double? {
        guard let kelvin else { return nil }
        if kelvin > 200 {
            return Double(kelvin - 273)
        }
        return Double(kelvin)
    }

    private func appendNative(
        _ key: String,
        _ name: String,
        _ keys: [String: Int64],
        to attributes: inout [SmartAttribute],
        suffix: String = ""
    ) {
        guard let value = keys[key] else { return }
        attributes.append(SmartAttribute(
            id: key,
            name: name,
            rawValue: "\(value)\(suffix)",
            current: nil,
            worst: nil,
            threshold: nil,
            status: .good,
            source: providerName
        ))
    }

    private func appendCombined(
        _ prefix: String,
        _ name: String,
        _ keys: [String: Int64],
        to attributes: inout [SmartAttribute],
        multiplier: Int64 = 1
    ) {
        guard let value = combinedValue(prefix: prefix, keys: keys) else { return }
        let scaled = value * multiplier
        let raw = multiplier == 1 ? "\(value)" : "\(formatByteCount(scaled)) (\(value) units)"
        attributes.append(SmartAttribute(
            id: prefix,
            name: name,
            rawValue: raw,
            current: nil,
            worst: nil,
            threshold: nil,
            status: value == 0 || !prefix.contains("ERROR") ? .good : .warning,
            source: providerName
        ))
    }
}

final class SmartctlSmartProvider: SmartProviding {
    let providerName = "smartctl"
    private let runner: CommandRunning
    private let fileManager: FileManager
    private let configuredPath: String?

    init(runner: CommandRunning = ShellCommandRunner(), fileManager: FileManager = .default, configuredPath: String? = nil) {
        self.runner = runner
        self.fileManager = fileManager
        self.configuredPath = configuredPath
    }

    func snapshot(for drive: DriveDevice) async -> SmartSnapshot? {
        guard let executable = findExecutable() else {
            return SmartSnapshot(
                driveID: drive.id,
                capturedAt: Date(),
                health: .unavailable,
                summary: "smartctl was not found. Install smartmontools to enable deep SMART details.",
                providerStatuses: [ProviderStatus(name: providerName, state: .unavailable, message: "smartctl not installed.")],
                attributes: [],
                temperatureCelsius: nil,
                lifeRemainingPercent: nil,
                powerOnHours: nil,
                powerCycleCount: nil,
                mediaErrors: nil,
                unsafeShutdowns: nil,
                smartStatusRaw: nil,
                selfTestStatus: nil
            )
        }

        let target = await smartctlTarget(for: drive, executable: executable) ?? drive.deviceNode
        do {
            let result = try await runner.run(executable, arguments: ["-a", "--json", target])
            return SmartctlParser.parseSnapshot(result.stdout, drive: drive, providerName: providerName, exitStatus: result.terminationStatus)
        } catch {
            return SmartSnapshot(
                driveID: drive.id,
                capturedAt: Date(),
                health: .unavailable,
                summary: error.localizedDescription,
                providerStatuses: [ProviderStatus(name: providerName, state: .failed, message: error.localizedDescription)],
                attributes: [],
                temperatureCelsius: nil,
                lifeRemainingPercent: nil,
                powerOnHours: nil,
                powerCycleCount: nil,
                mediaErrors: nil,
                unsafeShutdowns: nil,
                smartStatusRaw: nil,
                selfTestStatus: nil
            )
        }
    }

    func findExecutable() -> String? {
        let candidates = [
            configuredPath,
            UserDefaults.standard.string(forKey: "smartctlPath"),
            "/opt/homebrew/bin/smartctl",
            "/usr/local/bin/smartctl",
            "/usr/sbin/smartctl"
        ].compactMap { $0 }.filter { !$0.isEmpty }

        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    private func smartctlTarget(for drive: DriveDevice, executable: String) async -> String? {
        guard let result = try? await runner.run(executable, arguments: ["--scan-open", "--json"]),
              let devices = SmartctlParser.parseScan(result.stdout) else {
            return nil
        }

        let exact = devices.first { scan in
            scan.name == drive.deviceNode || scan.name.hasSuffix("/\(drive.bsdName)") || scan.name.contains(drive.bsdName)
        }
        return exact?.name
    }
}

enum SmartctlParser {
    struct ScanDevice: Hashable {
        var name: String
        var type: String?
        var protocolName: String?
        var openError: String?
    }

    static func parseScan(_ data: Data) -> [ScanDevice]? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = root["devices"] as? [[String: Any]]
        else { return nil }

        return devices.compactMap { item in
            guard let name = item.string("name") else { return nil }
            return ScanDevice(
                name: name,
                type: item.string("type"),
                protocolName: item.string("protocol"),
                openError: item.string("open_error")
            )
        }
    }

    static func parseSnapshot(_ data: Data, drive: DriveDevice, providerName: String, exitStatus: Int32) -> SmartSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SmartSnapshot.unavailable(for: drive, reason: "smartctl returned invalid JSON.")
        }

        if let openError = root.string("open_error") {
            return SmartSnapshot(
                driveID: drive.id,
                capturedAt: Date(),
                health: .unavailable,
                summary: openError,
                providerStatuses: [ProviderStatus(name: providerName, state: .limited, message: openError)],
                attributes: [],
                temperatureCelsius: nil,
                lifeRemainingPercent: nil,
                powerOnHours: nil,
                powerCycleCount: nil,
                mediaErrors: nil,
                unsafeShutdowns: nil,
                smartStatusRaw: nil,
                selfTestStatus: nil
            )
        }

        var attributes: [SmartAttribute] = []
        let smartStatusRaw = parseSmartStatus(root)
        let temperature = root.dictionary("temperature").double("current")
            ?? root.dictionary("nvme_smart_health_information_log").double("temperature")
        let powerOnHours = root.dictionary("power_on_time").int("hours")
        let powerCycles = root.int("power_cycle_count")
        let nvme = root.dictionary("nvme_smart_health_information_log")
        let mediaErrors = nvme.int64("media_errors")
        let unsafeShutdowns = nvme.int64("unsafe_shutdowns")
        let lifeRemaining = nvme.int("percentage_used").map { max(0, min(100, 100 - $0)) }

        appendNVMeAttributes(nvme, providerName: providerName, to: &attributes)
        appendATAAttributes(root, providerName: providerName, to: &attributes)

        let selfTest = root.dictionary("ata_smart_self_test_log").string("standard")
            ?? root.dictionary("self_test").string("status")

        let providerState: ProviderState = exitStatus == 0 ? .available : .limited
        var snapshot = SmartSnapshot(
            driveID: drive.id,
            capturedAt: Date(),
            health: .unavailable,
            summary: "smartctl data parsed.",
            providerStatuses: [
                ProviderStatus(name: providerName, state: providerState, message: exitStatus == 0 ? "Detailed SMART data available." : "smartctl returned partial data.")
            ],
            attributes: attributes,
            temperatureCelsius: temperature,
            lifeRemainingPercent: lifeRemaining,
            powerOnHours: powerOnHours,
            powerCycleCount: powerCycles,
            mediaErrors: mediaErrors,
            unsafeShutdowns: unsafeShutdowns,
            smartStatusRaw: smartStatusRaw,
            selfTestStatus: selfTest
        )
        let evaluator = DriveHealthEvaluator()
        snapshot.health = evaluator.evaluate(drive: drive, snapshot: snapshot)
        snapshot.summary = evaluator.summary(for: drive, snapshot: snapshot)
        return snapshot
    }

    private static func parseSmartStatus(_ root: [String: Any]) -> String? {
        let status = root.dictionary("smart_status")
        if let passed = status.bool("passed") {
            return passed ? "Passed" : "Failed"
        }
        return status.string("string")
    }

    private static func appendNVMeAttributes(_ nvme: [String: Any], providerName: String, to attributes: inout [SmartAttribute]) {
        let interesting = [
            ("critical_warning", "Critical Warning"),
            ("available_spare", "Available Spare"),
            ("available_spare_threshold", "Available Spare Threshold"),
            ("percentage_used", "Percentage Used"),
            ("media_errors", "Media Errors"),
            ("num_err_log_entries", "Error Log Entries"),
            ("unsafe_shutdowns", "Unsafe Shutdowns"),
            ("data_units_read", "Data Units Read"),
            ("data_units_written", "Data Units Written")
        ]

        for (key, name) in interesting {
            guard let value = nvme.valueDescription(key) else { continue }
            let warningKeys: Set<String> = ["critical_warning", "media_errors", "num_err_log_entries"]
            attributes.append(SmartAttribute(
                id: "nvme.\(key)",
                name: name,
                rawValue: value,
                current: nil,
                worst: nil,
                threshold: nil,
                status: nvme.int64(key).map { warningKeys.contains(key) && $0 > 0 ? .warning : .good } ?? .good,
                source: providerName
            ))
        }
    }

    private static func appendATAAttributes(_ root: [String: Any], providerName: String, to attributes: inout [SmartAttribute]) {
        let table = root.dictionary("ata_smart_attributes").arrayOfDictionaries("table")
        for item in table {
            guard let id = item.int("id") else { continue }
            let raw = item.dictionary("raw")
            let rawValue = raw.valueDescription("value") ?? raw.string("string") ?? ""
            let threshold = item.int("thresh")
            let current = item.int("value")
            let status = ataStatus(id: id, current: current, threshold: threshold, rawValue: raw.int64("value"))
            attributes.append(SmartAttribute(
                id: String(format: "0x%02X", id),
                name: item.string("name") ?? "Attribute \(id)",
                rawValue: rawValue,
                current: current,
                worst: item.int("worst"),
                threshold: threshold,
                status: status,
                source: providerName
            ))
        }
    }

    private static func ataStatus(id: Int, current: Int?, threshold: Int?, rawValue: Int64?) -> HealthStatus {
        if [0x05, 0xC5, 0xC6].contains(id), let rawValue, rawValue > 0 {
            return .warning
        }
        if let current, let threshold, threshold > 0, current < threshold {
            return .preFail
        }
        return .good
    }
}

final class SmartSnapshotService {
    private let nativeProvider: SmartProviding
    private let smartctlProvider: SmartProviding
    private let evaluator = DriveHealthEvaluator()

    init(nativeProvider: SmartProviding = NativeSmartProvider(), smartctlProvider: SmartProviding = SmartctlSmartProvider()) {
        self.nativeProvider = nativeProvider
        self.smartctlProvider = smartctlProvider
    }

    func snapshot(for drive: DriveDevice) async -> SmartSnapshot {
        async let native = nativeProvider.snapshot(for: drive)
        async let smartctl = smartctlProvider.snapshot(for: drive)

        let snapshots = await [native, smartctl].compactMap { $0 }
        guard !snapshots.isEmpty else {
            return SmartSnapshot.unavailable(for: drive, reason: "No SMART provider returned data.")
        }

        var merged = snapshots.first(where: { !$0.attributes.isEmpty || $0.health != .unavailable }) ?? snapshots[0]
        for snapshot in snapshots.dropFirst() {
            merged.providerStatuses.append(contentsOf: snapshot.providerStatuses.filter { status in
                !merged.providerStatuses.contains(where: { $0.name == status.name })
            })
            if !snapshot.attributes.isEmpty {
                let existingIDs = Set(merged.attributes.map(\.id))
                merged.attributes += snapshot.attributes.filter { !existingIDs.contains($0.id) }
            }
            merged.temperatureCelsius = snapshot.temperatureCelsius ?? merged.temperatureCelsius
            merged.lifeRemainingPercent = snapshot.lifeRemainingPercent ?? merged.lifeRemainingPercent
            merged.powerOnHours = snapshot.powerOnHours ?? merged.powerOnHours
            merged.powerCycleCount = snapshot.powerCycleCount ?? merged.powerCycleCount
            merged.mediaErrors = snapshot.mediaErrors ?? merged.mediaErrors
            merged.unsafeShutdowns = snapshot.unsafeShutdowns ?? merged.unsafeShutdowns
            merged.smartStatusRaw = snapshot.smartStatusRaw ?? merged.smartStatusRaw
            merged.selfTestStatus = snapshot.selfTestStatus ?? merged.selfTestStatus
        }

        merged.health = evaluator.evaluate(drive: drive, snapshot: merged)
        merged.summary = evaluator.summary(for: drive, snapshot: merged)
        return merged
    }
}

final class DriveHealthEvaluator {
    func evaluate(drive: DriveDevice, snapshot: SmartSnapshot) -> HealthStatus {
        if snapshot.providerStatuses.allSatisfy({ $0.state == .unavailable || $0.state == .failed }) && snapshot.attributes.isEmpty {
            return .unavailable
        }

        let status = (snapshot.smartStatusRaw ?? drive.smartStatusRaw ?? "").lowercased()
        if status.contains("fail") && !status.contains("not") {
            return .failed
        }

        var health: HealthStatus = .good
        if snapshot.attributes.contains(where: { $0.status == .failed }) {
            health = max(health, .failed)
        }
        if snapshot.attributes.contains(where: { $0.status == .preFail }) {
            health = max(health, .preFail)
        }
        if snapshot.attributes.contains(where: { $0.status == .warning }) {
            health = max(health, .warning)
        }

        if let mediaErrors = snapshot.mediaErrors, mediaErrors > 0 {
            health = max(health, .preFail)
        }
        if let temp = snapshot.temperatureCelsius {
            if temp >= 85 {
                health = max(health, .preFail)
            } else if temp >= 70 {
                health = max(health, .warning)
            }
        }
        if let life = snapshot.lifeRemainingPercent {
            if life <= 0 {
                health = .failed
            } else if life <= 10 {
                health = max(health, .preFail)
            } else if life <= 20 {
                health = max(health, .warning)
            }
        }

        let availableSpare = snapshot.attributeInt(named: "Available Spare")
        let availableSpareThreshold = snapshot.attributeInt(named: "Available Spare Threshold")
        if let spare = availableSpare, let threshold = availableSpareThreshold {
            if spare < threshold {
                health = max(health, .preFail)
            } else if spare == threshold {
                health = max(health, .warning)
            }
        }

        return health
    }

    func summary(for drive: DriveDevice, snapshot: SmartSnapshot) -> String {
        switch snapshot.health {
        case .good:
            return "SMART data does not show immediate risk for \(drive.displayName)."
        case .warning:
            return "Warning indicators are present. Review highlighted attributes and keep backups current."
        case .preFail:
            return "Pre-fail indicators are present. Backup immediately and plan replacement."
        case .failed:
            return "The drive reports failure. Stop non-essential writes and replace the drive."
        case .unavailable:
            return snapshot.providerStatuses.first?.message ?? "SMART data is unavailable for this drive."
        }
    }
}

struct ExternalSupportStatus: Codable, Hashable {
    var satDriverInstalled: Bool
    var smartctlInstalled: Bool
    var driverPaths: [String]
    var message: String
}

final class ExternalDriveSupportDetector {
    private let fileManager: FileManager
    private let smartctlProvider: SmartctlSmartProvider
    private let driverPaths: [String]

    init(
        fileManager: FileManager = .default,
        smartctlProvider: SmartctlSmartProvider = SmartctlSmartProvider(),
        driverPaths: [String] = [
            "/Library/Extensions/SATSMARTDriver.kext",
            "/System/Library/Extensions/SATSMARTDriver.kext"
        ]
    ) {
        self.fileManager = fileManager
        self.smartctlProvider = smartctlProvider
        self.driverPaths = driverPaths
    }

    func detect() -> ExternalSupportStatus {
        let installedPaths = driverPaths.filter { fileManager.fileExists(atPath: $0) }
        let smartctlInstalled = smartctlProvider.findExecutable() != nil
        let message: String
        if !installedPaths.isEmpty {
            message = "SAT SMART Driver appears installed. Reconnect external USB-SATA drives after installation or reboot."
        } else if smartctlInstalled {
            message = "smartctl is installed. Some USB/SAT bridges may still require SAT SMART Driver on macOS."
        } else {
            message = "External USB SMART often needs smartmontools and SAT SMART Driver; Thunderbolt/NVMe devices may expose data natively."
        }

        return ExternalSupportStatus(
            satDriverInstalled: !installedPaths.isEmpty,
            smartctlInstalled: smartctlInstalled,
            driverPaths: installedPaths,
            message: message
        )
    }
}

final class NotificationCoordinator {
    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyIfNeeded(drive: DriveDevice, snapshot: SmartSnapshot) {
        guard snapshot.health.severity >= HealthStatus.preFail.severity else { return }
        let content = UNMutableNotificationContent()
        content.title = "DIT Drive Health Alert"
        content.body = "\(drive.displayName): \(snapshot.health.title). \(snapshot.summary)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "dit-\(drive.id)-\(snapshot.health.rawValue)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

private func intValue(_ value: Int64?) -> Int? {
    value.map(Int.init)
}

private func combinedValue(prefix: String, keys: [String: Int64]) -> Int64? {
    if let value = keys[prefix] { return value }
    guard keys["\(prefix)_0"] != nil || keys["\(prefix)_1"] != nil else { return nil }
    let low = UInt64(bitPattern: keys["\(prefix)_0"] ?? 0)
    let high = UInt64(bitPattern: keys["\(prefix)_1"] ?? 0)
    let combined = (high << 32) | low
    return Int64(bitPattern: combined)
}

private extension SmartSnapshot {
    func attributeInt(named name: String) -> Int? {
        attributes.first(where: { $0.name == name })?.rawValue.components(separatedBy: CharacterSet.decimalDigits.inverted).first.flatMap(Int.init)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        self[key] as? String
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

    func double(_ key: String) -> Double? {
        if let double = self[key] as? Double { return double }
        if let int = self[key] as? Int { return Double(int) }
        if let number = self[key] as? NSNumber { return number.doubleValue }
        if let string = self[key] as? String { return Double(string) }
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

    func valueDescription(_ key: String) -> String? {
        if let string = self[key] as? String { return string }
        if let number = self[key] as? NSNumber { return number.stringValue }
        if let value = self[key] { return "\(value)" }
        return nil
    }
}
