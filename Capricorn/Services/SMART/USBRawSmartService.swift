// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit
import IOKit.storage

enum SNTBridge: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case jmicron = "sntjmicron"
    case asmedia = "sntasmedia"
    case realtek = "sntrealtek"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Detect Bridge"
        case .jmicron: "JMicron"
        case .asmedia: "ASMedia"
        case .realtek: "Realtek"
        }
    }
}

enum USBRawSmartPhase: String, CaseIterable, Sendable {
    case unmounting, capturing, reading, releasing, restoring, restored
    case restoreFailed = "restore_failed"

    var title: String {
        switch self {
        case .unmounting: "Unmount Volumes"
        case .capturing: "Capture USB Device"
        case .reading: "Read SMART"
        case .releasing: "Release USB Device"
        case .restoring: "Restore Volume Mounts"
        case .restored: "Volume Restoration Completed"
        case .restoreFailed: "Volume Restoration Failed"
        }
    }
}

struct USBRawSmartTarget: Equatable, Sendable {
    let registryID: UInt64
    var selector: String { "usbraw:\(registryID)" }
}

struct USBRawSmartResult: Sendable {
    var snapshot: SmartSnapshot?
    var phases: [USBRawSmartPhase]
    var transcript: String
    var exitStatus: Int32

    var restorationConfirmed: Bool {
        phases.last == .restored
    }

    var message: String {
        if snapshot?.hasSMARTPayload == true {
            return restorationConfirmed
                ? "SMART data was read and volume restoration completed."
                : "SMART data was read, but volume restoration could not be confirmed. Check the disk in Disk Utility."
        }
        if phases.isEmpty {
            return "SNT did not reach the USB capture workflow. Review the diagnostic output."
        }
        return restorationConfirmed
            ? "SNT returned no SMART data. Volume restoration completed."
            : "SNT did not complete. Volume restoration could not be confirmed. Check the disk in Disk Utility."
    }
}

struct USBRawSmartSession: Identifiable {
    enum State { case confirmation, running, completed }
    let id = UUID()
    let drive: DriveDevice
    let target: USBRawSmartTarget
    var bridge: SNTBridge = .automatic
    var state: State = .confirmation
    var result: USBRawSmartResult?
    var error: String?
}

enum USBRawSmartPolicy {
    static func isEligible(drive: DriveDevice, snapshot: SmartSnapshot?) -> Bool {
        guard !drive.isVirtual, !drive.isInternal, !drive.isSystemDisk,
              !drive.isNetwork, !drive.isMemoryCard,
              drive.protocolName.localizedCaseInsensitiveContains("USB"),
              let snapshot else { return false }
        return !snapshot.hasSMARTPayload
    }
}

enum USBRawSmartError: Error, LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case let .unavailable(message): message }
    }
}

protocol USBRawSmartRunning: Sendable {
    func target(for drive: DriveDevice) throws -> USBRawSmartTarget
    func read(drive: DriveDevice, target: USBRawSmartTarget, bridge: SNTBridge) async throws -> USBRawSmartResult
}

/// Resolves a whole physical disk to the live USB device. The registry ID is
/// frozen before confirmation, so a reused diskN cannot select a different disk.
struct USBRawSmartTargetResolver: Sendable {
    func target(for drive: DriveDevice) throws -> USBRawSmartTarget {
        guard !drive.isInternal, !drive.isSystemDisk, !drive.isVirtual,
              !drive.isNetwork, !drive.isMemoryCard,
              let matching = IOBSDNameMatching(kIOMainPortDefault, 0, drive.bsdName) else {
            throw USBRawSmartError.unavailable("The selected USB disk is no longer available.")
        }
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard entry != 0 else {
            throw USBRawSmartError.unavailable("The selected USB disk is no longer available.")
        }
        guard (IORegistryEntryCreateCFProperty(entry, kIOMediaWholeKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.boolValue == true,
              (IORegistryEntryCreateCFProperty(entry, kIOMediaSizeKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber)?.int64Value == drive.sizeBytes else {
            IOObjectRelease(entry)
            throw USBRawSmartError.unavailable("The physical disk identity changed. Refresh disks before trying SNT.")
        }
        while entry != 0 {
            if IOObjectConformsTo(entry, "IOUSBHostDevice") != 0 {
                var identifier: UInt64 = 0
                let status = IORegistryEntryGetRegistryEntryID(entry, &identifier)
                IOObjectRelease(entry)
                if status == KERN_SUCCESS, identifier > 0 {
                    return USBRawSmartTarget(registryID: identifier)
                }
                break
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            entry = status == KERN_SUCCESS ? parent : 0
        }
        throw USBRawSmartError.unavailable("No supported physical USB device was found for this disk.")
    }
}

/// Preserves smartctl's JSON and true exit status, even when it reports health
/// warnings or cleanup failure. AppleScript otherwise discards stdout on error.
final class AdministratorUSBRawCommandRunner: CommandRunning, @unchecked Sendable {
    static let statusMarker = "CAPRICORN_USBRAW_EXIT="
    private let runner: CommandRunning

    init(runner: CommandRunning = ShellCommandRunner()) { self.runner = runner }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        let command = ([executable] + arguments).map(AdministratorCommandRunner.shellQuote).joined(separator: " ")
        let wrapper = "\(command) 2>&1; capricorn_status=$?; printf '\\n\(Self.statusMarker)%d\\n' \"$capricorn_status\""
        let result = try await runner.run("/usr/bin/osascript", arguments: [
            "-e", AdministratorCommandRunner.script(for: "/bin/sh", arguments: ["-c", wrapper])
        ])
        guard result.terminationStatus == 0 else {
            throw USBRawSmartError.unavailable(result.stderrString)
        }
        return try Self.decode(result.stdoutString)
    }

    static func decode(_ output: String) throws -> CommandResult {
        var lines = output.components(separatedBy: .newlines)
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard let last = lines.popLast(), last.hasPrefix(statusMarker),
              let status = Int32(last.dropFirst(statusMarker.count)), (0...255).contains(status) else {
            throw USBRawSmartError.unavailable("The SNT process exit status is missing. Check the disk in Disk Utility.")
        }
        return CommandResult(stdout: Data(lines.joined(separator: "\n").utf8), stderr: Data(), terminationStatus: status)
    }
}

struct USBRawSmartService: USBRawSmartRunning {
    static let providerName = "Darwin Raw USB (Experimental)"
    let runner: CommandRunning
    let administratorRunner: CommandRunning
    let executableURL: URL?
    let targetResolver: @Sendable (DriveDevice) throws -> USBRawSmartTarget

    init(
        runner: CommandRunning = ShellCommandRunner(),
        administratorRunner: CommandRunning = AdministratorUSBRawCommandRunner(),
        executableURL: URL? = Bundle.main.url(forResource: "smartctl-usbraw", withExtension: nil),
        targetResolver: @escaping @Sendable (DriveDevice) throws -> USBRawSmartTarget = {
            try USBRawSmartTargetResolver().target(for: $0)
        }
    ) {
        self.runner = runner
        self.administratorRunner = administratorRunner
        self.executableURL = executableURL
        self.targetResolver = targetResolver
    }

    func target(for drive: DriveDevice) throws -> USBRawSmartTarget { try targetResolver(drive) }

    func read(drive: DriveDevice, target: USBRawSmartTarget, bridge: SNTBridge) async throws -> USBRawSmartResult {
        guard let executableURL, FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw USBRawSmartError.unavailable("The experimental SNT tool is missing from this application.")
        }
        guard try self.target(for: drive) == target else {
            throw USBRawSmartError.unavailable("The USB device changed after confirmation. Refresh disks before trying SNT.")
        }
        // Passive discovery filters out composite devices and multiple disks/LUNs.
        // Never use --scan-open: that would capture before the explicit read.
        let scan = try await runner.run(executableURL.path, arguments: ["--scan", "-d", "usb", "--json=c"], timeout: 15)
        guard scan.terminationStatus == 0,
              let devices = SmartctlParser.parseScan(scan.stdout),
              let device = devices.first(where: {
                  URL(fileURLWithPath: $0.name).lastPathComponent == drive.bsdName
              }) else {
            throw USBRawSmartError.unavailable("This USB device is unsupported or has multiple storage interfaces or disks. It was not captured.")
        }
        let type: String
        if bridge == .automatic {
            guard let detected = device.type, SNTBridge(rawValue: detected) != nil, detected != "automatic" else {
                throw USBRawSmartError.unavailable("The SNT bridge could not be detected. Select its verified chipset before trying again.")
            }
            type = detected
        } else {
            type = bridge.rawValue
        }
        guard try self.target(for: drive) == target else {
            throw USBRawSmartError.unavailable("The USB device changed after confirmation. Refresh disks before trying SNT.")
        }
        // The tool itself owns non-forced unmount and restoration. Do not put
        // either around the process in a script or lose its original mount list.
        let result = try await SmartctlCommandCoordinator.shared.run {
            try await administratorRunner.run("/usr/bin/env", arguments: [
                "CAPRICORN_USBRAW_MANUAL=1", executableURL.path,
                "-i", "-H", "-A", "--json=c", "-d", type, target.selector
            ])
        }
        return Self.parse(result, drive: drive, target: target, type: type)
    }

    static func parse(_ result: CommandResult, drive: DriveDevice, target: USBRawSmartTarget, type: String) -> USBRawSmartResult {
        let transcript = [result.stdoutString, result.stderrString].filter { !$0.isEmpty }.joined(separator: "\n")
        let lines = transcript.components(separatedBy: .newlines)
        let prefix = "CAPRICORN_USBRAW\t"
        let phases = lines.compactMap { line -> USBRawSmartPhase? in
            guard line.hasPrefix(prefix) else { return nil }
            return USBRawSmartPhase(rawValue: String(line.dropFirst(prefix.count)))
        }
        let json = lines.compactMap { line -> Data? in
            guard let data = line.data(using: .utf8),
                  var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  root["smartctl"] != nil else { return nil }
            // A close/restore failure can set smartctl's fatal bit after valid
            // health data was obtained. Preserve that reading independently;
            // the original status and transcript remain in the session result.
            if phases.contains(.reading), phases.contains(.restoreFailed),
               let health = root["nvme_smart_health_information_log"] as? [String: Any],
               !health.isEmpty, var tool = root["smartctl"] as? [String: Any] {
                tool["exit_status"] = (tool["exit_status"] as? Int ?? Int(result.terminationStatus)) & ~0x03
                root["smartctl"] = tool
                return try? JSONSerialization.data(withJSONObject: root)
            }
            return data
        }.last
        var snapshot = json.map {
            SmartctlParser.parseSnapshot($0, drive: drive, providerName: providerName,
                exitStatus: result.terminationStatus, targetDescriptor: SmartctlTargetDescriptor(
                    path: target.selector, type: type, protocolName: "NVMe", openError: nil))
        }
        if snapshot?.hasSMARTPayload == true {
            snapshot?.selectedProvider = providerName
            snapshot?.selectedTransport = type
            snapshot?.smartctlDiagnostics?.executablePath = "smartctl-usbraw"
            snapshot?.smartctlDiagnostics?.selectedTransport = type
            if phases.contains(.restoreFailed) {
                snapshot?.providerStatuses = [ProviderStatus(
                    name: providerName, state: .limited,
                    message: "SMART data was read, but volume restoration could not be confirmed. Check the disk in Disk Utility.")]
            }
        }
        return USBRawSmartResult(snapshot: snapshot, phases: phases, transcript: transcript, exitStatus: result.terminationStatus)
    }
}
