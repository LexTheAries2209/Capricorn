// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit
import IOKit.storage
import OSLog
import UserNotifications

protocol SmartProviding: Sendable {
    var providerName: String { get }
    func snapshot(for drive: DriveDevice) async -> SmartSnapshot?
}

protocol SmartctlTargetProviding: SmartProviding {
    func resolvedTargets(for drives: [DriveDevice]) async -> [String: String]
    func snapshot(for drive: DriveDevice, resolvedTarget: String?) async -> SmartSnapshot?
}

struct SmartctlTargetDescriptor: Hashable, Sendable {
    var path: String
    var type: String?
    var protocolName: String? = nil
    var openError: String? = nil
}

protocol SmartctlIOServiceTargetResolving: Sendable {
    func targetDescriptor(for drive: DriveDevice) -> SmartctlTargetDescriptor?
}

struct IOKitSmartctlTargetResolver: SmartctlIOServiceTargetResolving {
    func targetDescriptor(for drive: DriveDevice) -> SmartctlTargetDescriptor? {
        guard let media = copyWholeMedia(bsdName: drive.bsdName) else { return nil }
        defer { IOObjectRelease(media) }
        guard let nvme = copyNVMeAncestor(from: media) else { return nil }
        defer { IOObjectRelease(nvme) }

        var path = [CChar](repeating: 0, count: 4_096)
        guard IORegistryEntryGetPath(nvme, kIOServicePlane, &path) == KERN_SUCCESS else { return nil }
        let value = String(cString: path)
        guard !value.isEmpty else { return nil }
        return SmartctlTargetDescriptor(
            path: value.hasPrefix("IOService:") ? value : "IOService:\(value)",
            type: "nvme"
        )
    }

    private func copyWholeMedia(bsdName: String) -> io_registry_entry_t? {
        guard let matching = IOServiceMatching(kIOMediaClass) else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let media = IOIteratorNext(iterator)
            guard media != 0 else { return nil }
            let name = copyStringProperty(media, key: kIOBSDNameKey)
            let whole = copyBoolProperty(media, key: kIOMediaWholeKey)
            if name == bsdName, whole == true {
                return media
            }
            IOObjectRelease(media)
        }
    }

    private func copyNVMeAncestor(from entry: io_registry_entry_t) -> io_registry_entry_t? {
        var current = entry
        var ownsCurrent = false

        while true {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                if ownsCurrent { IOObjectRelease(current) }
                return nil
            }
            if ownsCurrent { IOObjectRelease(current) }
            if IOObjectConformsTo(parent, "IONVMeBlockStorageDevice") != 0 {
                return parent
            }
            current = parent
            ownsCurrent = true
        }
    }

    private func copyStringProperty(_ entry: io_registry_entry_t, key: String) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private func copyBoolProperty(_ entry: io_registry_entry_t, key: String) -> Bool? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }
}

struct NativeSmartData: Equatable, Sendable {
    var smartStatusRaw: String?
    var deviceSpecificKeys: [String: Int64]
}

enum NativeSmartProbeResult: Equatable, Sendable {
    case available(NativeSmartData)
    case limited(NativeSmartData, message: String)
    case unsupported(message: String)
    case failed(message: String)
}

protocol NativeSmartProbing: Sendable {
    func probe(drive: DriveDevice) async -> NativeSmartProbeResult
}

enum NativeSmartDataParser {
    static func parse(_ data: Data) throws -> NativeSmartData {
        guard let info = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw DiskutilParserError.invalidPlist
        }

        let status = cleanString(info["SMARTStatus"] as? String)
        let dictionary = info["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any] ?? [:]
        var keys: [String: Int64] = [:]
        for (key, value) in dictionary {
            if let number = value as? NSNumber {
                keys[key] = number.int64Value
            } else if let value = value as? Int64 {
                keys[key] = value
            } else if let value = value as? String, let integer = Int64(value) {
                keys[key] = integer
            }
        }
        return NativeSmartData(smartStatusRaw: status, deviceSpecificKeys: keys)
    }

    private static func cleanString(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

final class DiskutilNativeSmartProbe: NativeSmartProbing, @unchecked Sendable {
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    private let runner: CommandRunning
    private let diskutilPath: String
    private let timeout: TimeInterval
    private let retryDelays: [TimeInterval]
    private let sleeper: Sleeper

    init(
        runner: CommandRunning = ShellCommandRunner(),
        diskutilPath: String = "/usr/sbin/diskutil",
        timeout: TimeInterval = 5,
        retryDelays: [TimeInterval] = [0, 1, 3],
        sleeper: @escaping Sleeper = { delay in
            guard delay > 0 else { return }
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    ) {
        self.runner = runner
        self.diskutilPath = diskutilPath
        self.timeout = timeout
        self.retryDelays = retryDelays.isEmpty ? [0] : retryDelays
        self.sleeper = sleeper
    }

    func probe(drive: DriveDevice) async -> NativeSmartProbeResult {
        if drive.isNetwork {
            return .unsupported(message: "Network volumes do not expose local SMART data.")
        }
        if drive.isMemoryCard {
            return .unsupported(message: "SD cards do not expose standard SMART health data on macOS.")
        }

        var lastLimitedData: NativeSmartData?
        var lastErrorMessage = "Native SMART data is temporarily unavailable."

        for (index, delay) in retryDelays.enumerated() {
            do {
                try await sleeper(delay)
                try Task.checkCancellation()
                let startedAt = Date()
                let result = try await runner.run(
                    diskutilPath,
                    arguments: ["info", "-plist", drive.bsdName],
                    timeout: timeout
                )
                let duration = Date().timeIntervalSince(startedAt)
                CapricornLog.inventory.debug(
                    "Native SMART probe \(drive.bsdName, privacy: .public) attempt \(index + 1) completed in \(duration, format: .fixed(precision: 3)) seconds with status \(result.terminationStatus)"
                )

                if result.terminationStatus != 0 {
                    let output = result.stdoutString + "\n" + result.stderrString
                    if Self.explicitlyReportsUnsupported(output) {
                        return .unsupported(message: "Native SMART is not supported for this device.")
                    }
                    lastErrorMessage = "diskutil could not read Native SMART data."
                    continue
                }

                let data = try NativeSmartDataParser.parse(result.stdout)
                if Self.explicitlyReportsUnsupported(data.smartStatusRaw ?? "") {
                    return .unsupported(message: "Native SMART is not supported for this device.")
                }
                if !data.deviceSpecificKeys.isEmpty {
                    return .available(data)
                }
                if data.smartStatusRaw != nil {
                    lastLimitedData = data
                    lastErrorMessage = "Native SMART attributes were not returned yet."
                } else {
                    lastErrorMessage = "Native SMART fields were not returned yet."
                }
            } catch is CancellationError {
                return .failed(message: "Native SMART refresh was cancelled.")
            } catch let error as CommandError {
                lastErrorMessage = error.localizedDescription
                CapricornLog.inventory.notice(
                    "Native SMART probe \(drive.bsdName, privacy: .public) attempt \(index + 1) failed: \(error.localizedDescription, privacy: .public)"
                )
            } catch {
                lastErrorMessage = error.localizedDescription
                CapricornLog.inventory.notice(
                    "Native SMART probe \(drive.bsdName, privacy: .public) attempt \(index + 1) returned invalid data: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        if let lastLimitedData {
            return .limited(lastLimitedData, message: "Native SMART status is available, but attributes were not returned after retrying.")
        }
        return .failed(message: "Native SMART data could not be read after 3 attempts. \(lastErrorMessage)")
    }

    private static func explicitlyReportsUnsupported(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("not supported") || normalized.contains("unsupported")
    }
}

final class NativeSmartProvider: SmartProviding, @unchecked Sendable {
    let providerName = "Native macOS"
    private let evaluator = DriveHealthEvaluator()
    private let probe: NativeSmartProbing

    init(probe: NativeSmartProbing = DiskutilNativeSmartProbe()) {
        self.probe = probe
    }

    func snapshot(for drive: DriveDevice) async -> SmartSnapshot? {
        switch await probe.probe(drive: drive) {
        case let .available(data):
            return snapshot(for: drive, data: data, state: .available, message: data.smartStatusRaw ?? "Native SMART keys parsed.")
        case let .limited(data, message):
            return snapshot(for: drive, data: data, state: .limited, message: message)
        case let .unsupported(message):
            return unavailableSnapshot(for: drive, state: .unavailable, message: message)
        case let .failed(message):
            return unavailableSnapshot(for: drive, state: .failed, message: message)
        }
    }

    private func snapshot(
        for drive: DriveDevice,
        data: NativeSmartData,
        state: ProviderState,
        message: String
    ) -> SmartSnapshot {
        var attributes: [SmartAttribute] = []
        let keys = data.deviceSpecificKeys
        let temperatureC = nativeTemperature(from: keys["TEMPERATURE"])
        let percentageUsed = intValue(keys["PERCENTAGE_USED"])
        let spareAvailable = intValue(keys["AVAILABLE_SPARE"])
        let spareThreshold = intValue(keys["AVAILABLE_SPARE_THRESHOLD"])
        let lifeRemaining = percentageUsed.map { max(0, min(100, 100 - $0)) }
        let mediaErrors = combinedValue(prefix: "MEDIA_ERRORS", keys: keys)
        let unsafeShutdowns = combinedValue(prefix: "UNSAFE_SHUTDOWNS", keys: keys)
        let powerOnHours = intValue(combinedValue(prefix: "POWER_ON_HOURS", keys: keys))
        let powerCycles = intValue(combinedValue(prefix: "POWER_CYCLES", keys: keys))

        appendNative("AVAILABLE_SPARE", "Available Spare", keys, to: &attributes, suffix: "%")
        appendNative("AVAILABLE_SPARE_THRESHOLD", "Available Spare Threshold", keys, to: &attributes, suffix: "%")
        appendNative("PERCENTAGE_USED", "Percentage Used", keys, to: &attributes, suffix: "%")
        appendNativeTemperature(keys, to: &attributes)
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
            summary: data.smartStatusRaw ?? message,
            providerStatuses: [
                ProviderStatus(
                    name: providerName,
                    state: state,
                    message: message
                )
            ],
            attributes: attributes,
            temperatureCelsius: temperatureC,
            lifeRemainingPercent: lifeRemaining,
            powerOnHours: powerOnHours,
            powerCycleCount: powerCycles,
            mediaErrors: mediaErrors,
            unsafeShutdowns: unsafeShutdowns,
            smartStatusRaw: data.smartStatusRaw,
            selfTestStatus: nil,
            enduranceUsedPercent: percentageUsed,
            spareAvailablePercent: spareAvailable,
            spareAvailableThresholdPercent: spareThreshold
        )
        snapshot.nativeSmartCapturedAt = snapshot.capturedAt
        snapshot.health = evaluator.evaluate(drive: drive, snapshot: snapshot)
        snapshot.summary = evaluator.summary(for: drive, snapshot: snapshot)
        return snapshot
    }

    private func unavailableSnapshot(for drive: DriveDevice, state: ProviderState, message: String) -> SmartSnapshot {
        SmartSnapshot(
            driveID: drive.id,
            capturedAt: Date(),
            health: .unavailable,
            summary: message,
            providerStatuses: [ProviderStatus(name: providerName, state: state, message: message)],
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

    private func nativeTemperature(from kelvin: Int64?) -> Double? {
        guard let kelvin else { return nil }
        if kelvin > 200 {
            return Double(kelvin) - 273.15
        }
        return Double(kelvin)
    }

    private func appendNativeTemperature(_ keys: [String: Int64], to attributes: inout [SmartAttribute]) {
        guard let value = keys["TEMPERATURE"] else { return }
        let rawValue: String
        if value > 200 {
            let celsius = String(format: "%.0f", Double(value) - 273.15)
            rawValue = "\(value) K (\(celsius) °C)"
        } else {
            rawValue = "\(value) °C"
        }
        attributes.append(SmartAttribute(
            id: "TEMPERATURE",
            name: "Temperature",
            rawValue: rawValue,
            current: nil,
            worst: nil,
            threshold: nil,
            status: .good,
            source: providerName
        ))
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
        let raw = multiplier == 1 ? "\(value)" : formatSmartDataUnits(value, unitBytes: multiplier)
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

func formatSmartDataUnits(_ units: Int64, unitBytes: Int64 = 512_000) -> String {
    let scaled = units.multipliedReportingOverflow(by: unitBytes)
    if !scaled.overflow {
        return "\(formatByteCount(scaled.partialValue)) (\(units) units)"
    }

    let terabytes = Double(units) * Double(unitBytes) / 1_000_000_000_000
    let formattedTerabytes = String(format: "%.2f", terabytes)
    return "\(formattedTerabytes) TB (\(units) units)"
}

func formatSmartLogicalBlocks(_ logicalBlocks: Int64, blockSizeBytes: Int64) -> String {
    guard blockSizeBytes > 0 else { return "\(logicalBlocks)" }

    let scaled = logicalBlocks.multipliedReportingOverflow(by: blockSizeBytes)
    let byteCount: String
    if scaled.overflow {
        let terabytes = Double(logicalBlocks) * Double(blockSizeBytes) / 1_000_000_000_000
        byteCount = String(format: "%.2f TB", terabytes)
    } else {
        byteCount = formatByteCount(scaled.partialValue)
    }
    return "\(byteCount) (\(logicalBlocks) LBA, \(blockSizeBytes) B/LBA)"
}

enum SmartctlExecutableOrigin: String, Codable, Hashable, Sendable {
    case bundled
}

struct SmartctlExecutableDescriptor: Hashable, Sendable {
    var path: String
    var origin: SmartctlExecutableOrigin
    var driveDatabasePath: String?
}

struct SmartctlExecutableInfo: Hashable, Sendable {
    var path: String?
    var origin: SmartctlExecutableOrigin?
    var version: String?
    var driveDatabaseVersion: String?
    var isCompatible: Bool?
    var error: String?
}

enum BundledSmartctlMetadata {
    static let version = "7.5"
    static let driveDatabaseVersion = "7.5"
    static let minimumCompatibleMajorVersion = 7
}

/// Keeps smartctl scans, reads, and self-tests from overlapping at the process level.
/// The stronger global ordering is intentional because macOS bridges can expose one
/// physical disk through multiple device nodes at the same time.
actor SmartctlCommandCoordinator {
    static let shared = SmartctlCommandCoordinator()

    private var running = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        guard running else {
            running = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if let continuation = waiters.first {
            waiters.removeFirst()
            continuation.resume()
        } else {
            running = false
        }
    }
}

final class SmartctlSmartProvider: SmartctlTargetProviding, @unchecked Sendable {
    let providerName = "smartctl"
    private let runner: CommandRunning
    private let fileManager: FileManager
    private let bundle: Bundle
    private let bundledExecutableURL: URL?
    private let bundledDriveDatabaseURL: URL?
    private let commandCoordinator: SmartctlCommandCoordinator
    private let ioServiceTargetResolver: any SmartctlIOServiceTargetResolving
    private let avoidsWakingSleepingDisks: @Sendable () -> Bool

    init(
        runner: CommandRunning = ShellCommandRunner(),
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        bundledExecutableURL: URL? = nil,
        bundledDriveDatabaseURL: URL? = nil,
        commandCoordinator: SmartctlCommandCoordinator = .shared,
        ioServiceTargetResolver: any SmartctlIOServiceTargetResolving = IOKitSmartctlTargetResolver(),
        avoidsWakingSleepingDisks: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.object(forKey: AppPreferences.Key.avoidWakingSleepingDisks) as? Bool ?? true
        }
    ) {
        self.runner = runner
        self.fileManager = fileManager
        self.bundle = bundle
        self.bundledExecutableURL = bundledExecutableURL
        self.bundledDriveDatabaseURL = bundledDriveDatabaseURL
        self.commandCoordinator = commandCoordinator
        self.ioServiceTargetResolver = ioServiceTargetResolver
        self.avoidsWakingSleepingDisks = avoidsWakingSleepingDisks
    }

    func snapshot(for drive: DriveDevice) async -> SmartSnapshot? {
        let target = await resolvedTargetDescriptors(for: [drive])[drive.id]
        return await snapshot(for: drive, resolvedTargetDescriptor: target)
    }

    func snapshot(for drive: DriveDevice, resolvedTarget: String?) async -> SmartSnapshot? {
        await snapshot(
            for: drive,
            resolvedTargetDescriptor: resolvedTarget.map { SmartctlTargetDescriptor(path: $0, type: nil) }
        )
    }

    func snapshot(for drive: DriveDevice, resolvedTargetDescriptor: SmartctlTargetDescriptor?) async -> SmartSnapshot? {
        if drive.isNetwork {
            return SmartSnapshot.unavailable(for: drive, reason: "Network volumes do not expose local SMART data.")
        }
        if drive.isMemoryCard {
            return SmartSnapshot.unavailable(for: drive, reason: "SD cards do not expose standard SMART health data on macOS.")
        }

        guard let executable = resolvedExecutable() else {
            return SmartSnapshot(
                driveID: drive.id,
                capturedAt: Date(),
                health: .unavailable,
                summary: "The bundled smartctl executable is unavailable.",
                providerStatuses: [ProviderStatus(name: providerName, state: .unavailable, message: "Bundled smartctl is unavailable.")],
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

        let target = resolvedTargetDescriptor?.path ?? drive.deviceNode
        if avoidsWakingSleepingDisks(),
           !drive.isSolidState,
           resolvedTargetDescriptor?.type?.isEmpty != false {
            var snapshot = SmartSnapshot.unavailable(
                for: drive,
                reason: "SMART refresh was skipped because smartctl could not determine a safe device type without opening the disk."
            )
            snapshot.providerStatuses = [
                ProviderStatus(
                    name: providerName,
                    state: .limited,
                    message: "Disable sleep protection to allow smartctl device-type autodetection for this disk."
                )
            ]
            snapshot.smartctlDiagnostics = SmartctlDiagnostics(
                targetPath: target,
                protocolName: resolvedTargetDescriptor?.protocolName ?? drive.protocolName,
                readSkippedToAvoidWake: true,
                executablePath: executable.path,
                executableOrigin: executable.origin.rawValue
            )
            return snapshot
        }
        do {
            let result = try await commandCoordinator.run { [self] in
                try await self.runner.run(
                    executable.path,
                    arguments: self.smartReadArguments(for: drive, target: resolvedTargetDescriptor, fallback: target, executable: executable)
                )
            }
            return annotate(
                SmartctlParser.parseSnapshot(
                result.stdout,
                drive: drive,
                providerName: providerName,
                exitStatus: result.terminationStatus,
                stderr: result.stderr,
                targetDescriptor: resolvedTargetDescriptor
                ), with: executable
            )
        } catch {
            var snapshot = SmartSnapshot(
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
            snapshot.smartctlDiagnostics = SmartctlDiagnostics(
                targetPath: target,
                deviceType: resolvedTargetDescriptor?.type,
                protocolName: resolvedTargetDescriptor?.protocolName ?? drive.protocolName,
                readSkippedToAvoidWake: false,
                openError: error.localizedDescription,
                executablePath: executable.path,
                executableOrigin: executable.origin.rawValue
            )
            return snapshot
        }
    }

    func resolvedTargets(for drives: [DriveDevice]) async -> [String: String] {
        await resolvedTargetDescriptors(for: drives).mapValues(\.path)
    }

    func resolvedTargetDescriptors(for drives: [DriveDevice]) async -> [String: SmartctlTargetDescriptor] {
        guard !drives.isEmpty,
              let executable = resolvedExecutable(),
              let result = try? await commandCoordinator.run({ [self] in
                  try await self.runner.run(
                      executable.path,
                      arguments: self.argumentsAddingDriveDatabase(
                          [self.avoidsWakingSleepingDisks() ? "--scan" : "--scan-open", "--json"],
                          executable: executable
                      )
                  )
              }),
              let devices = SmartctlParser.parseScan(result.stdout) else {
            return [:]
        }

        return drives.reduce(into: [:]) { targets, drive in
            let directMatch = devices.first(where: {
                $0.name == drive.deviceNode
                    || $0.name.hasSuffix("/\(drive.bsdName)")
                    || $0.name.contains(drive.bsdName)
            })
            if let directMatch {
                targets[drive.id] = SmartctlTargetDescriptor(
                    path: directMatch.name,
                    type: directMatch.type,
                    protocolName: directMatch.protocolName,
                    openError: directMatch.openError
                )
                return
            }

            guard let resolved = ioServiceTargetResolver.targetDescriptor(for: drive) else { return }
            let scanned = devices.first(where: { $0.name == resolved.path })
            targets[drive.id] = SmartctlTargetDescriptor(
                path: scanned?.name ?? resolved.path,
                type: scanned?.type ?? resolved.type,
                protocolName: scanned?.protocolName ?? resolved.protocolName ?? drive.protocolName,
                openError: scanned?.openError ?? resolved.openError
            )
        }
    }

    func smartReadArguments(
        for drive: DriveDevice,
        target: SmartctlTargetDescriptor?,
        fallback: String,
        executable: SmartctlExecutableDescriptor? = nil
    ) -> [String] {
        var arguments = ["-a", "--json"]
        if avoidsWakingSleepingDisks(), Self.supportsPowerModeCheck(target: target, drive: drive) {
            arguments.insert(contentsOf: ["-n", "standby,0"], at: 0)
        }
        return commandArguments(arguments, target: target, fallback: fallback, executable: executable)
    }

    private static func supportsPowerModeCheck(target: SmartctlTargetDescriptor?, drive: DriveDevice) -> Bool {
        let type = target?.type?.lowercased() ?? ""
        guard !type.isEmpty else { return false }
        if type == "nvme" || (type.hasPrefix("snt") && !type.hasSuffix("/sat")) {
            return false
        }
        return !drive.protocolName.localizedCaseInsensitiveContains("nvme") || type.hasSuffix("/sat")
    }

    func commandArguments(
        _ base: [String],
        target: SmartctlTargetDescriptor?,
        fallback: String,
        executable: SmartctlExecutableDescriptor? = nil
    ) -> [String] {
        var arguments = base
        if let type = target?.type, !type.isEmpty, type.lowercased() != "auto" {
            arguments += ["-d", type]
        }
        arguments.append(target?.path ?? fallback)
        guard let executable = executable ?? resolvedExecutable() else { return arguments }
        return argumentsAddingDriveDatabase(arguments, executable: executable)
    }

    func resolvedExecutable() -> SmartctlExecutableDescriptor? {
        let bundledURL = bundledExecutableURL ?? bundle.url(
            forResource: "smartctl",
            withExtension: nil
        )
        let driveDatabaseURL = bundledDriveDatabaseURL ?? bundle.url(
            forResource: "drivedb",
            withExtension: "h"
        )
        guard let bundledURL,
              let driveDatabaseURL,
              fileManager.isExecutableFile(atPath: bundledURL.path),
              fileManager.isReadableFile(atPath: driveDatabaseURL.path) else { return nil }
        return SmartctlExecutableDescriptor(
            path: bundledURL.path,
            origin: .bundled,
            driveDatabasePath: driveDatabaseURL.path
        )
    }

    func findExecutable() -> String? {
        resolvedExecutable()?.path
    }

    func executableInfo() async -> SmartctlExecutableInfo {
        guard let executable = resolvedExecutable() else {
            return SmartctlExecutableInfo(path: nil, origin: nil, version: nil, driveDatabaseVersion: nil, isCompatible: nil, error: "Bundled smartctl is unavailable.")
        }
        do {
            let result = try await commandCoordinator.run { [self] in
                try await self.runner.run(executable.path, arguments: ["--version"])
            }
            let output = [result.stdoutString, result.stderrString].joined(separator: "\n")
            let version = Self.smartctlVersion(in: output)
            return SmartctlExecutableInfo(
                path: executable.path,
                origin: executable.origin,
                version: version,
                driveDatabaseVersion: executable.origin == .bundled ? BundledSmartctlMetadata.driveDatabaseVersion : nil,
                isCompatible: result.terminationStatus == 0 ? version.map(Self.isCompatibleVersion) : nil,
                error: result.terminationStatus == 0 ? nil : SmartctlParser.commandFailureMessage(result)
            )
        } catch {
            return SmartctlExecutableInfo(path: executable.path, origin: executable.origin, version: nil, driveDatabaseVersion: nil, isCompatible: nil, error: error.localizedDescription)
        }
    }

    private func annotate(_ snapshot: SmartSnapshot, with executable: SmartctlExecutableDescriptor) -> SmartSnapshot {
        var snapshot = snapshot
        var diagnostics = snapshot.smartctlDiagnostics ?? SmartctlDiagnostics(
            version: nil,
            driveDatabaseVersion: nil,
            targetPath: nil,
            deviceType: nil,
            protocolName: nil,
            powerMode: nil,
            readSkippedToAvoidWake: nil,
            openError: nil,
            executablePath: nil,
            executableOrigin: nil
        )
        diagnostics.executablePath = executable.path
        diagnostics.executableOrigin = executable.origin.rawValue
        if executable.origin == .bundled {
            diagnostics.version = diagnostics.version ?? BundledSmartctlMetadata.version
            diagnostics.driveDatabaseVersion = diagnostics.driveDatabaseVersion ?? BundledSmartctlMetadata.driveDatabaseVersion
        }
        snapshot.smartctlDiagnostics = diagnostics
        return snapshot
    }

    private static func smartctlVersion(in output: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: #"smartctl\s+([0-9]+(?:\.[0-9]+)+)"#, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = expression.firstMatch(in: output, range: range),
              let versionRange = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[versionRange])
    }

    private static func isCompatibleVersion(_ version: String) -> Bool {
        guard let majorVersion = Int(version.split(separator: ".", maxSplits: 1).first ?? "") else { return false }
        return majorVersion >= BundledSmartctlMetadata.minimumCompatibleMajorVersion
    }

    private func argumentsAddingDriveDatabase(
        _ arguments: [String],
        executable: SmartctlExecutableDescriptor
    ) -> [String] {
        guard let driveDatabasePath = executable.driveDatabasePath else { return arguments }
        return ["--drivedb=\(driveDatabasePath)"] + arguments
    }

}

struct SmartSelfTestStartResult: Sendable {
    var message: String
    var estimatedDurationSeconds: Int?
}

enum SmartSelfTestServiceError: Error, LocalizedError, Sendable {
    case unsupported(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unsupported(message), let .commandFailed(message): message
        }
    }
}

final class SmartSelfTestService: @unchecked Sendable {
    static let macOSNativeNVMeUnavailableMessage = "This NVMe drive reports self-test support, but smartctl on macOS cannot send Device Self-test command 0x14. Identify (0x06) and Get Log Page (0x02) remain available."

    private let smartctlProvider: SmartctlSmartProvider
    private let administratorRunner: CommandRunning
    private let commandCoordinator: SmartctlCommandCoordinator

    init(
        smartctlProvider: SmartctlSmartProvider = SmartctlSmartProvider(),
        administratorRunner: CommandRunning = AdministratorCommandRunner(),
        commandCoordinator: SmartctlCommandCoordinator = .shared
    ) {
        self.smartctlProvider = smartctlProvider
        self.administratorRunner = administratorRunner
        self.commandCoordinator = commandCoordinator
    }

    func start(kind: SmartSelfTestKind, drive: DriveDevice) async throws -> SmartSelfTestStartResult {
        guard kind == .short || kind == .long else {
            throw SmartSelfTestServiceError.unsupported("Only short and extended self-tests can be started.")
        }
        let capability = try await capability(for: drive)
        guard capability.supports(kind) else {
            let message = kind == .short
                ? "Quick self-test is not supported by this drive."
                : "Full self-test is not supported by this drive."
            throw SmartSelfTestServiceError.unsupported(message)
        }
        let executable = try executable(for: drive)
        let target = await targetDescriptor(for: drive)
        let arguments = smartctlProvider.commandArguments(
            ["-t", kind == .short ? "short" : "long", "--json"],
            target: target,
            fallback: drive.deviceNode,
            executable: executable
        )
        let result = try await commandCoordinator.run { [self] in
            try await self.administratorRunner.run(executable.path, arguments: arguments)
        }
        guard result.terminationStatus == 0 else {
            throw SmartSelfTestServiceError.commandFailed(SmartctlParser.commandFailureMessage(result))
        }
        return SmartSelfTestStartResult(
            message: Self.combinedMessage(result),
            estimatedDurationSeconds: Self.estimatedDuration(in: Self.combinedMessage(result))
        )
    }

    func abort(drive: DriveDevice) async throws {
        let executable = try executable(for: drive)
        let target = await targetDescriptor(for: drive)
        if Self.usesMacOSNativeNVMeTransport(target: target, drive: drive) {
            throw SmartSelfTestServiceError.unsupported(Self.macOSNativeNVMeUnavailableMessage)
        }
        let arguments = smartctlProvider.commandArguments(
            ["-X"],
            target: target,
            fallback: drive.deviceNode,
            executable: executable
        )
        let result = try await commandCoordinator.run { [self] in
            try await self.administratorRunner.run(executable.path, arguments: arguments)
        }
        guard result.terminationStatus == 0 else {
            throw SmartSelfTestServiceError.commandFailed(SmartctlParser.commandFailureMessage(result))
        }
    }

    func capability(for drive: DriveDevice) async throws -> SmartSelfTestCapability {
        let executable = try executable(for: drive)
        let target = await targetDescriptor(for: drive)
        let arguments = smartctlProvider.commandArguments(
            ["-c", "--json"],
            target: target,
            fallback: drive.deviceNode,
            executable: executable
        )
        let result = try await commandCoordinator.run { [self] in
            try await self.administratorRunner.run(executable.path, arguments: arguments)
        }
        guard let capability = SmartctlParser.parseSelfTestCapability(result) else {
            throw SmartSelfTestServiceError.commandFailed(SmartctlParser.commandFailureMessage(result))
        }
        guard capability.shortSupported || capability.longSupported else {
            throw SmartSelfTestServiceError.unsupported(capability.message)
        }
        if Self.usesMacOSNativeNVMeTransport(target: target, drive: drive) {
            throw SmartSelfTestServiceError.unsupported(Self.macOSNativeNVMeUnavailableMessage)
        }
        return capability
    }

    func targetDescriptor(for drive: DriveDevice) async -> SmartctlTargetDescriptor? {
        await smartctlProvider.resolvedTargetDescriptors(for: [drive])[drive.id]
    }

    private func executable(for drive: DriveDevice) throws -> SmartctlExecutableDescriptor {
        if drive.isNetwork {
            throw SmartSelfTestServiceError.unsupported("Network drives do not support hardware SMART self-tests.")
        }
        if drive.isMemoryCard {
            throw SmartSelfTestServiceError.unsupported("Memory cards do not support hardware SMART self-tests.")
        }
        guard let executable = smartctlProvider.resolvedExecutable() else {
            throw SmartSelfTestServiceError.unsupported("Bundled smartctl is unavailable.")
        }
        return executable
    }

    private static func usesMacOSNativeNVMeTransport(
        target: SmartctlTargetDescriptor?,
        drive: DriveDevice
    ) -> Bool {
#if os(macOS)
        if target?.type?.caseInsensitiveCompare("nvme") == .orderedSame {
            return true
        }
        return target == nil && drive.protocolName.localizedCaseInsensitiveContains("nvme")
#else
        return false
#endif
    }

    private static func combinedMessage(_ result: CommandResult) -> String {
        let message = [result.stdoutString, result.stderrString]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return message.isEmpty ? "SMART self-test command failed." : message
    }

    private static func estimatedDuration(in message: String) -> Int? {
        let pattern = #"(?i)(?:wait|completion|within|in)\D{0,30}(\d+)\s*(?:minutes?|mins?|seconds?|secs?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let valueRange = Range(match.range(at: 1), in: message),
              let value = Int(message[valueRange]) else {
            return nil
        }
        let lowercased = message.lowercased()
        return lowercased.contains("second") || lowercased.contains("sec") ? value : value * 60
    }
}

enum SmartctlParser {
    struct ScanDevice: Hashable {
        var name: String
        var type: String?
        var protocolName: String?
        var openError: String?
    }

    static func parseSelfTestCapability(_ result: CommandResult) -> SmartSelfTestCapability? {
        guard let root = commandJSONRoot(result) else { return nil }
        let exitStatus = root.dictionary("smartctl").int("exit_status") ?? Int(result.terminationStatus)
        guard exitStatus & 0x03 == 0 else { return nil }

        let ataSelfTest = root.dictionary("ata_smart_data").dictionary("self_test")
        let polling = ataSelfTest.dictionary("polling_minutes")
        let ataShort = positive(polling.int("short"))
            ?? ataSelfTest.bool("short_supported")
            ?? ataSelfTest.bool("supports_short")
        let ataLong = positive(polling.int("extended"))
            ?? positive(polling.int("long"))
            ?? ataSelfTest.bool("extended_supported")
            ?? ataSelfTest.bool("long_supported")
            ?? ataSelfTest.bool("supports_extended")

        let nvmeSelfTest = root.dictionary("nvme_optional_admin_commands").bool("self_test")
        let output = combinedOutput(result).lowercased()
        if output.contains("self-tests not supported") || output.contains("self-test not supported") {
            return SmartSelfTestCapability(
                shortSupported: false,
                longSupported: false,
                message: "SMART self-test capability could not be confirmed."
            )
        }

        let shortSupported = nvmeSelfTest ?? ataShort ?? false
        let longSupported = nvmeSelfTest ?? ataLong ?? false
        return SmartSelfTestCapability(
            shortSupported: shortSupported,
            longSupported: longSupported,
            message: shortSupported || longSupported
                ? "Self-test capability confirmed."
                : "SMART self-test capability could not be confirmed."
        )
    }

    static func commandFailureMessage(_ result: CommandResult) -> String {
        if let root = commandJSONRoot(result) {
            if let openError = root.string("open_error") {
                return friendlyOpenError(openError)
            }
            let messages = smartctlMessages(root)
            if let message = messages.first(where: { !$0.isEmpty }) {
                return friendlyOpenError(message)
            }
        }
        let output = combinedOutput(result).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return "SMART self-test command failed." }
        if output.localizedCaseInsensitiveContains("NVMe admin command 0x14 is not supported") {
            return SmartSelfTestService.macOSNativeNVMeUnavailableMessage
        }
        if output.localizedCaseInsensitiveContains("IOCreatePlugInInterfaceForService failed") {
            return "The device could not be opened by smartctl."
        }
        return output.count > 500 ? String(output.prefix(500)) + "…" : output
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

    static func parseSnapshot(
        _ data: Data,
        drive: DriveDevice,
        providerName: String,
        exitStatus: Int32,
        stderr: Data = Data(),
        targetDescriptor: SmartctlTargetDescriptor? = nil
    ) -> SmartSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            var snapshot = SmartSnapshot.unavailable(for: drive, reason: "smartctl returned invalid JSON.")
            snapshot.smartctlDiagnostics = diagnostics(root: nil, target: targetDescriptor, readSkipped: false)
            return snapshot
        }

        let embeddedExitStatus = root.dictionary("smartctl").int("exit_status") ?? Int(exitStatus)
        let powerMode = root.dictionary("power_mode").string("name")
        let readSkipped = smartReadWasSkipped(root: root, powerMode: powerMode)
        let smartctlDiagnostics = diagnostics(root: root, target: targetDescriptor, readSkipped: readSkipped)
        if readSkipped {
            var snapshot = SmartSnapshot.unavailable(
                for: drive,
                reason: "SMART refresh was skipped because the drive is in standby or sleep mode."
            )
            snapshot.providerStatuses = [
                ProviderStatus(
                    name: providerName,
                    state: .limited,
                    message: "The previous SMART data was retained to avoid waking the sleeping drive."
                )
            ]
            snapshot.smartctlDiagnostics = smartctlDiagnostics
            return snapshot
        }
        let fatalMessage = root.string("open_error")
            ?? (embeddedExitStatus & 0x03 != 0 ? smartctlMessages(root).first : nil)
        if let openError = fatalMessage {
            var snapshot = SmartSnapshot(
                driveID: drive.id,
                capturedAt: Date(),
                health: .unavailable,
                summary: openError,
                providerStatuses: [ProviderStatus(name: providerName, state: .failed, message: friendlyOpenError(openError))],
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
            snapshot.smartctlDiagnostics = smartctlDiagnostics
            return snapshot
        }

        // smartctl can identify a bridge and return model information even
        // when the SMART command itself failed (for example, an NVMe device
        // exposed through an IOSAT/SAT-looking bridge).  Identification is
        // not SMART data, so never report this response as available.
        guard hasSMARTPayload(root) else {
            let message = smartctlMessages(root).first
                ?? (embeddedExitStatus == 0
                    ? "smartctl did not return SMART data."
                    : "smartctl did not return SMART data (exit status \(embeddedExitStatus)).")
            var snapshot = SmartSnapshot(
                driveID: drive.id,
                capturedAt: Date(),
                health: .unavailable,
                summary: message,
                providerStatuses: [
                    ProviderStatus(
                        name: providerName,
                        state: embeddedExitStatus == 0 ? .unavailable : .failed,
                        message: message
                    )
                ],
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
            snapshot.smartctlDiagnostics = smartctlDiagnostics
            return snapshot
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
        let enduranceUsed = root.dictionary("endurance_used").int("current_percent")
            ?? nvme.int("percentage_used")
        let spareAvailable = root.dictionary("spare_available").int("current_percent")
            ?? nvme.int("available_spare")
        let spareThreshold = root.dictionary("spare_available").int("threshold_percent")
            ?? nvme.int("available_spare_threshold")
        let lifeRemaining = enduranceUsed.map { max(0, min(100, 100 - $0)) }

        appendNVMeAttributes(nvme, providerName: providerName, to: &attributes)
        appendATAAttributes(root, drive: drive, providerName: providerName, to: &attributes)
        appendUnifiedHealthAttributes(
            enduranceUsed: enduranceUsed,
            spareAvailable: spareAvailable,
            spareThreshold: spareThreshold,
            providerName: providerName,
            to: &attributes
        )

        let rawOutput = cappedRawOutput(stdout: data, stderr: stderr)
        let selfTestReport = parseSelfTestReport(root, rawOutput: rawOutput)
        let selfTest = selfTestReport.map(Self.selfTestSummary)

        let providerState: ProviderState = embeddedExitStatus == 0 ? .available : .limited
        var snapshot = SmartSnapshot(
            driveID: drive.id,
            capturedAt: Date(),
            health: .unavailable,
            summary: "smartctl data parsed.",
            providerStatuses: [
                ProviderStatus(name: providerName, state: providerState, message: providerState == .available ? "Detailed SMART data available." : "smartctl returned partial data.")
            ],
            attributes: attributes,
            temperatureCelsius: temperature,
            lifeRemainingPercent: lifeRemaining,
            powerOnHours: powerOnHours,
            powerCycleCount: powerCycles,
            mediaErrors: mediaErrors,
            unsafeShutdowns: unsafeShutdowns,
            smartStatusRaw: smartStatusRaw,
            selfTestStatus: selfTest,
            selfTestReport: selfTestReport,
            enduranceUsedPercent: enduranceUsed,
            spareAvailablePercent: spareAvailable,
            spareAvailableThresholdPercent: spareThreshold,
            smartctlDiagnostics: smartctlDiagnostics
        )
        let evaluator = DriveHealthEvaluator()
        snapshot.health = evaluator.evaluate(drive: drive, snapshot: snapshot)
        snapshot.summary = evaluator.summary(for: drive, snapshot: snapshot)
        return snapshot
    }

    private static func diagnostics(
        root: [String: Any]?,
        target: SmartctlTargetDescriptor?,
        readSkipped: Bool
    ) -> SmartctlDiagnostics {
        let smartctl = root?.dictionary("smartctl") ?? [:]
        let device = root?.dictionary("device") ?? [:]
        let versionValues = (smartctl["version"] as? [Any])?.compactMap { value -> String? in
            if let number = value as? NSNumber { return number.stringValue }
            if let string = value as? String { return string }
            return nil
        }
        let version = versionValues.flatMap { $0.isEmpty ? nil : $0.joined(separator: ".") }
        let databaseVersion = smartctl.dictionary("drive_database_version").string("string")
        let openError = root?.string("open_error") ?? target?.openError
        return SmartctlDiagnostics(
            version: version,
            driveDatabaseVersion: databaseVersion,
            targetPath: device.string("name") ?? target?.path,
            deviceType: device.string("type") ?? target?.type,
            protocolName: device.string("protocol") ?? target?.protocolName,
            powerMode: root?.dictionary("power_mode").string("name"),
            readSkippedToAvoidWake: readSkipped,
            openError: openError
        )
    }

    private static func smartReadWasSkipped(root: [String: Any], powerMode: String?) -> Bool {
        guard let powerMode = powerMode?.uppercased(),
              powerMode == "SLEEP" || powerMode.hasPrefix("STANDBY") else {
            return false
        }
        return root["smart_status"] == nil
            && root["ata_smart_attributes"] == nil
            && root["nvme_smart_health_information_log"] == nil
    }

    private static func parseSelfTestReport(_ root: [String: Any], rawOutput: String?) -> SmartSelfTestReport? {
        var entries: [SmartSelfTestEntry] = []
        var currentKind: SmartSelfTestKind?
        var currentRemaining: Int?
        var currentState: SmartSelfTestState = .noLog
        var shortSupported: Bool?
        var longSupported: Bool?

        let ataLog = root.dictionary("ata_smart_self_test_log")
        let standard = ataLog["standard"]
        if let table = standard as? [[String: Any]] {
            entries = table.enumerated().compactMap { index, item in
                parseSelfTestEntry(item, index: index)
            }
        } else if let standardDictionary = standard as? [String: Any] {
            if let table = standardDictionary["table"] as? [[String: Any]] {
                entries = table.enumerated().compactMap { index, item in
                    parseSelfTestEntry(item, index: index)
                }
            }
            if let standardStatus = selfTestStatusValue(standardDictionary) {
                currentState = classifySelfTestState(status: standardStatus, passed: standardDictionary.bool("passed"), remaining: standardDictionary.int("remaining_percent"))
                currentRemaining = standardDictionary.int("remaining_percent")
            }
        } else if let standardString = standard as? String {
            currentState = classifySelfTestState(status: standardString, passed: nil, remaining: nil)
        }

        let ataCurrent = ataLog.dictionary("current")
        if !ataCurrent.isEmpty {
            currentKind = parseSelfTestKind(ataCurrent.valueDescription("type"))
            currentRemaining = ataCurrent.int("remaining_percent")
            currentState = classifySelfTestState(
                status: selfTestStatusValue(ataCurrent) ?? "",
                passed: ataCurrent.bool("passed"),
                remaining: currentRemaining
            )
        }

        let nvmeLog = root.dictionary("nvme_self_test_log")
        if !nvmeLog.isEmpty {
            currentRemaining = nvmeLog.int("current_self_test_completion_percent") ?? currentRemaining
            let operation = nvmeLog.valueDescription("current_self_test_operation")
            let resultItems = nvmeLog.arrayOfDictionaries("self_test_results")
            if resultItems.isEmpty, let result = nvmeLog["self_test_result"] as? [String: Any] {
                entries = [parseSelfTestEntry(result, index: 0)].compactMap { $0 }
            } else if !resultItems.isEmpty {
                entries = resultItems.enumerated().compactMap { index, item in
                    parseSelfTestEntry(item, index: index)
                }
            }
            currentKind = operation.flatMap(parseSelfTestKind)
            currentState = classifySelfTestState(
                status: operation ?? nvmeLog.valueDescription("status") ?? "",
                passed: nvmeLog.bool("passed"),
                remaining: currentRemaining
            )
        }

        let generic = root.dictionary("self_test")
        if !generic.isEmpty && entries.isEmpty {
            let status = selfTestStatusValue(generic) ?? ""
            currentState = classifySelfTestState(status: status, passed: generic.bool("passed"), remaining: generic.int("remaining_percent"))
            currentRemaining = generic.int("remaining_percent")
            currentKind = parseSelfTestKind(generic.valueDescription("type"))
        }

        if let support = root.dictionary("ata_smart_data")["self_test"] as? [String: Any] {
            let polling = support.dictionary("polling_minutes")
            shortSupported = positive(polling.int("short"))
                ?? support.bool("short_supported")
                ?? support.bool("supports_short")
                ?? shortSupported
            longSupported = positive(polling.int("extended"))
                ?? positive(polling.int("long"))
                ?? support.bool("extended_supported")
                ?? support.bool("long_supported")
                ?? support.bool("supports_extended")
                ?? longSupported
        }
        if let supported = root.dictionary("nvme_optional_admin_commands").bool("self_test") {
            shortSupported = supported
            longSupported = supported
        }

        let hasSelfTestPayload = !ataLog.isEmpty || !nvmeLog.isEmpty || !generic.isEmpty
        if !hasSelfTestPayload {
            return nil
        }

        if entries.isEmpty && currentState == .noLog {
            currentState = .unknown
        } else if let latest = entries.first, currentState == .noLog {
            currentState = latest.state
        }

        return SmartSelfTestReport(
            state: currentState,
            currentKind: currentKind,
            currentRemainingPercent: currentRemaining,
            entries: entries,
            shortSupported: shortSupported,
            longSupported: longSupported,
            rawOutput: rawOutput,
            capturedAt: Date()
        )
    }

    private static func parseSelfTestEntry(_ item: [String: Any], index: Int) -> SmartSelfTestEntry? {
        let typeValue = item.valueDescription("type") ?? item.valueDescription("test_type") ?? item.valueDescription("name")
        let statusValue = selfTestStatusValue(item) ?? item.valueDescription("result") ?? "Unknown"
        let remaining = item.int("remaining_percent")
        let passed = item.bool("passed") ?? item.dictionary("status").bool("passed")
        let state = classifySelfTestState(status: statusValue, passed: passed, remaining: remaining)
        let kind = parseSelfTestKind(typeValue)
        let lifetime = item.int("lifetime_hours") ?? item.int("power_on_hours")
        let lba = item.int64("lba")
        guard typeValue != nil || item["status"] != nil || item["result"] != nil else { return nil }
        return SmartSelfTestEntry(
            id: "\(index)-\(lifetime ?? -1)-\(lba ?? 0)",
            kind: kind,
            state: state,
            status: statusValue,
            remainingPercent: remaining,
            lifetimeHours: lifetime,
            failingLBA: lba.map(UInt64.init),
            rawStatus: item.valueDescription("status")
        )
    }

    private static func selfTestStatusValue(_ item: [String: Any]) -> String? {
        if let status = item["status"] as? [String: Any] {
            return status.valueDescription("string") ?? status.valueDescription("name") ?? status.valueDescription("status")
        }
        return item.valueDescription("status")
    }

    private static func parseSelfTestKind(_ value: String?) -> SmartSelfTestKind {
        let lowercased = (value ?? "").lowercased()
        if lowercased.contains("short") { return .short }
        if lowercased.contains("long") || lowercased.contains("extended") { return .long }
        if lowercased.isEmpty { return .unknown }
        return .vendor
    }

    private static func classifySelfTestState(status: String, passed: Bool?, remaining: Int?) -> SmartSelfTestState {
        if remaining != nil && remaining != 100 { return .running }
        if passed == true { return .passed }
        let lowercased = status.lowercased()
        if lowercased.contains("no self-test") || lowercased.contains("no test") { return .noLog }
        if lowercased.contains("in progress") || lowercased.contains("running") { return .running }
        if lowercased.contains("abort") || lowercased.contains("interrupt") { return .aborted }
        if lowercased.contains("error") || lowercased.contains("fail") { return .failed }
        if lowercased.contains("completed without error") || lowercased.contains("passed") || lowercased.contains("success") { return .passed }
        if status.isEmpty { return .noLog }
        return .unknown
    }

    private static func selfTestSummary(_ report: SmartSelfTestReport) -> String {
        if let latest = report.latestEntry {
            return "\(latest.kind.displayName): \(latest.status)"
        }
        switch report.state {
        case .running: return "Self-test in progress"
        case .noLog: return "No self-tests have been logged"
        case .passed: return "Self-test passed"
        case .failed: return "Self-test failed"
        case .aborted: return "Self-test aborted"
        case .unknown: return "Self-test status unknown"
        }
    }

    private static func cappedRawOutput(stdout: Data, stderr: Data) -> String? {
        let stdoutText = String(data: stdout, encoding: .utf8) ?? ""
        let stderrText = String(data: stderr, encoding: .utf8) ?? ""
        let combined = [stdoutText, stderrText].filter { !$0.isEmpty }.joined(separator: "\n")
        guard !combined.isEmpty else { return nil }
        let cap = 256 * 1024
        return combined.count > cap ? String(combined.prefix(cap)) + "\n[output truncated]" : combined
    }

    private static func commandJSONRoot(_ result: CommandResult) -> [String: Any]? {
        if let root = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] {
            return root
        }
        let output = combinedOutput(result)
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start <= end else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: Data(output[start...end].utf8)) as? [String: Any]
    }

    private static func combinedOutput(_ result: CommandResult) -> String {
        [result.stdoutString, result.stderrString]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private static func smartctlMessages(_ root: [String: Any]) -> [String] {
        root.dictionary("smartctl")
            .arrayOfDictionaries("messages")
            .compactMap { $0.string("string") ?? $0.string("message") }
    }

    private static func friendlyOpenError(_ message: String) -> String {
        message.localizedCaseInsensitiveContains("IOCreatePlugInInterfaceForService failed")
            ? "The device could not be opened by smartctl."
            : message
    }

    private static func positive(_ value: Int?) -> Bool? {
        value.map { $0 > 0 }
    }

    private static func parseSmartStatus(_ root: [String: Any]) -> String? {
        let status = root.dictionary("smart_status")
        if let passed = status.bool("passed") {
            return passed ? "Passed" : "Failed"
        }
        return status.string("string")
    }

    private static func hasSMARTPayload(_ root: [String: Any]) -> Bool {
        if root["smart_status"] != nil || root["ata_smart_data"] != nil {
            return true
        }
        if !root.dictionary("ata_smart_attributes").arrayOfDictionaries("table").isEmpty {
            return true
        }
        if !root.dictionary("nvme_smart_health_information_log").isEmpty {
            return true
        }
        return !root.dictionary("ata_smart_error_log").isEmpty
            || !root.dictionary("ata_smart_self_test_log").isEmpty
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
            let rawValue: String
            if key == "data_units_read" || key == "data_units_written", let units = nvme.int64(key) {
                rawValue = formatSmartDataUnits(units)
            } else {
                rawValue = value
            }
            let warningKeys: Set<String> = ["critical_warning", "media_errors", "num_err_log_entries"]
            attributes.append(SmartAttribute(
                id: "nvme.\(key)",
                name: name,
                rawValue: rawValue,
                current: nil,
                worst: nil,
                threshold: nil,
                status: nvme.int64(key).map { warningKeys.contains(key) && $0 > 0 ? .warning : .good } ?? .good,
                source: providerName
            ))
        }
    }

    private static func appendUnifiedHealthAttributes(
        enduranceUsed: Int?,
        spareAvailable: Int?,
        spareThreshold: Int?,
        providerName: String,
        to attributes: inout [SmartAttribute]
    ) {
        if let enduranceUsed,
           !attributes.contains(where: { $0.name == "Percentage Used" }) {
            let remaining = max(0, min(100, 100 - enduranceUsed))
            attributes.append(SmartAttribute(
                id: "smartctl.endurance_used",
                name: "Percentage Used",
                rawValue: "\(enduranceUsed)%",
                current: nil,
                worst: nil,
                threshold: nil,
                status: remaining <= 10 ? .preFail : (remaining <= 20 ? .warning : .good),
                source: providerName
            ))
        }

        if let spareAvailable,
           !attributes.contains(where: { $0.name == "Available Spare" }) {
            let status: HealthStatus
            if let spareThreshold, spareAvailable < spareThreshold {
                status = .preFail
            } else if let spareThreshold, spareAvailable == spareThreshold {
                status = .warning
            } else {
                status = .good
            }
            attributes.append(SmartAttribute(
                id: "smartctl.spare_available",
                name: "Available Spare",
                rawValue: "\(spareAvailable)%",
                current: nil,
                worst: nil,
                threshold: nil,
                status: status,
                source: providerName
            ))
        }

        if let spareThreshold,
           !attributes.contains(where: { $0.name == "Available Spare Threshold" }) {
            attributes.append(SmartAttribute(
                id: "smartctl.spare_available_threshold",
                name: "Available Spare Threshold",
                rawValue: "\(spareThreshold)%",
                current: nil,
                worst: nil,
                threshold: nil,
                status: .good,
                source: providerName
            ))
        }
    }

    private static func appendATAAttributes(
        _ root: [String: Any],
        drive: DriveDevice,
        providerName: String,
        to attributes: inout [SmartAttribute]
    ) {
        let table = root.dictionary("ata_smart_attributes").arrayOfDictionaries("table")
        let reportedBlockSize = root.int64("logical_block_size")
        let logicalBlockSize = reportedBlockSize.flatMap { $0 > 0 ? $0 : nil }
            ?? (drive.blockSize > 0 ? Int64(drive.blockSize) : nil)
        for item in table {
            guard let id = item.int("id") else { continue }
            let raw = item.dictionary("raw")
            let name = item.string("name") ?? "Attribute \(id)"
            let rawValue = ataRawValue(
                name: name,
                raw: raw,
                logicalBlockSize: logicalBlockSize
            )
            let threshold = item.int("thresh")
            let current = item.int("value")
            let status = ataStatus(id: id, current: current, threshold: threshold, rawValue: raw.int64("value"))
            attributes.append(SmartAttribute(
                id: String(format: "0x%02X", id),
                name: name,
                rawValue: rawValue,
                current: current,
                worst: item.int("worst"),
                threshold: threshold,
                status: status,
                source: providerName
            ))
        }
    }

    private static func ataRawValue(
        name: String,
        raw: [String: Any],
        logicalBlockSize: Int64?
    ) -> String {
        let fallback = raw.string("string") ?? raw.valueDescription("value") ?? ""
        guard isLogicalBlockCounter(name),
              let logicalBlocks = raw.int64("value"),
              logicalBlocks >= 0,
              let logicalBlockSize else {
            return fallback
        }
        return formatSmartLogicalBlocks(logicalBlocks, blockSizeBytes: logicalBlockSize)
    }

    private static func isLogicalBlockCounter(_ name: String) -> Bool {
        let key = name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
            .split(separator: " ")
            .joined(separator: " ")
        return key == "total lbas written" || key == "total lbas read"
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

final class SmartSnapshotService: @unchecked Sendable {
    private let nativeProvider: SmartProviding
    private let smartctlProvider: SmartProviding
    private let evaluator = DriveHealthEvaluator()

    init(nativeProvider: SmartProviding = NativeSmartProvider(), smartctlProvider: SmartProviding = SmartctlSmartProvider()) {
        self.nativeProvider = nativeProvider
        self.smartctlProvider = smartctlProvider
    }

    func snapshot(for drive: DriveDevice) async -> SmartSnapshot {
        await snapshot(for: drive, smartctlTarget: nil)
    }

    func resolvedSmartctlTargets(for drives: [DriveDevice]) async -> [String: String] {
        guard let targetProvider = smartctlProvider as? any SmartctlTargetProviding else {
            return [:]
        }
        return await targetProvider.resolvedTargets(for: drives)
    }

    func resolvedSmartctlTargetDescriptors(for drives: [DriveDevice]) async -> [String: SmartctlTargetDescriptor] {
        if let targetProvider = smartctlProvider as? SmartctlSmartProvider {
            return await targetProvider.resolvedTargetDescriptors(for: drives)
        }
        guard let targetProvider = smartctlProvider as? any SmartctlTargetProviding else {
            return [:]
        }
        return await targetProvider.resolvedTargets(for: drives).mapValues {
            SmartctlTargetDescriptor(path: $0, type: nil)
        }
    }

    func snapshot(for drive: DriveDevice, smartctlTarget: String?) async -> SmartSnapshot {
        await snapshot(
            for: drive,
            smartctlTargetDescriptor: smartctlTarget.map { SmartctlTargetDescriptor(path: $0, type: nil) }
        )
    }

    func snapshot(for drive: DriveDevice, smartctlTargetDescriptor: SmartctlTargetDescriptor?) async -> SmartSnapshot {
        async let native = nativeProvider.snapshot(for: drive)
        async let smartctl = smartctlSnapshot(for: drive, resolvedTargetDescriptor: smartctlTargetDescriptor)

        return merge(
            snapshots: await [native, smartctl].compactMap { $0 },
            for: drive
        )
    }

    func nativeSnapshot(for drive: DriveDevice) async -> SmartSnapshot {
        await nativeProvider.snapshot(for: drive)
            ?? SmartSnapshot.unavailable(for: drive, reason: "Native SMART provider returned no data.")
    }

    func snapshot(
        for drive: DriveDevice,
        nativeSnapshot: SmartSnapshot,
        smartctlTargetDescriptor: SmartctlTargetDescriptor?
    ) async -> SmartSnapshot {
        let smartctl = await smartctlSnapshot(for: drive, resolvedTargetDescriptor: smartctlTargetDescriptor)
        return merge(
            snapshots: [nativeSnapshot, smartctl].compactMap { $0 },
            for: drive
        )
    }

    private func merge(snapshots: [SmartSnapshot], for drive: DriveDevice) -> SmartSnapshot {
        guard !snapshots.isEmpty else {
            return SmartSnapshot.unavailable(for: drive, reason: "No SMART provider returned data.")
        }

        // Native is intentionally first. Starting from it preserves its failed
        // or limited provider status when smartctl is the only successful
        // source, which is required for last-known-good Native retention.
        var merged = snapshots[0]
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
            merged.selfTestReport = snapshot.selfTestReport ?? merged.selfTestReport
            merged.enduranceUsedPercent = snapshot.enduranceUsedPercent ?? merged.enduranceUsedPercent
            merged.spareAvailablePercent = snapshot.spareAvailablePercent ?? merged.spareAvailablePercent
            merged.spareAvailableThresholdPercent = snapshot.spareAvailableThresholdPercent ?? merged.spareAvailableThresholdPercent
            merged.smartctlDiagnostics = snapshot.smartctlDiagnostics ?? merged.smartctlDiagnostics
            merged.nativeSmartCapturedAt = snapshot.nativeSmartCapturedAt ?? merged.nativeSmartCapturedAt
        }

        merged.health = evaluator.evaluate(drive: drive, snapshot: merged)
        merged.summary = evaluator.summary(for: drive, snapshot: merged)
        return merged
    }

    private func smartctlSnapshot(for drive: DriveDevice, resolvedTargetDescriptor: SmartctlTargetDescriptor?) async -> SmartSnapshot? {
        if let targetProvider = smartctlProvider as? SmartctlSmartProvider {
            return await targetProvider.snapshot(for: drive, resolvedTargetDescriptor: resolvedTargetDescriptor)
        }
        if let targetProvider = smartctlProvider as? any SmartctlTargetProviding {
            return await targetProvider.snapshot(for: drive, resolvedTarget: resolvedTargetDescriptor?.path)
        }
        return await smartctlProvider.snapshot(for: drive)
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
        let healthAttributes = snapshot.attributes.filter { !Self.isTemperatureAttribute($0) }
        if healthAttributes.contains(where: { $0.status == .failed }) {
            health = max(health, .failed)
        }
        if healthAttributes.contains(where: { $0.status == .preFail }) {
            health = max(health, .preFail)
        }
        if healthAttributes.contains(where: { $0.status == .warning }) {
            health = max(health, .warning)
        }

        if let mediaErrors = snapshot.mediaErrors, mediaErrors > 0 {
            health = max(health, .preFail)
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

        let availableSpare = snapshot.spareAvailablePercent ?? snapshot.attributeInt(named: "Available Spare")
        let availableSpareThreshold = snapshot.spareAvailableThresholdPercent
            ?? snapshot.attributeInt(named: "Available Spare Threshold")
        if let spare = availableSpare, let threshold = availableSpareThreshold {
            if spare < threshold {
                health = max(health, .preFail)
            } else if spare == threshold {
                health = max(health, .warning)
            }
        }

        return health
    }

    private static func isTemperatureAttribute(_ attribute: SmartAttribute) -> Bool {
        let key = "\(attribute.id) \(attribute.name)"
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
        return key.contains("temperature") || key.contains("温度")
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

final class NotificationCoordinator {
    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyIfNeeded(drive: DriveDevice, snapshot: SmartSnapshot) {
        guard snapshot.health.severity >= HealthStatus.preFail.severity else { return }
        let content = UNMutableNotificationContent()
        content.title = "Capricorn Drive Health Alert"
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
