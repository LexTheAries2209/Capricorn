// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit
import IOKit.storage
import Darwin

enum SNTBridge: String, CaseIterable, Sendable {
    case jmicron = "sntjmicron"
    case asmedia = "sntasmedia"
    case realtek = "sntrealtek"
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
    var attemptedBridges: [SNTBridge] = []
    var probeInterruption: String?

    var restorationConfirmed: Bool {
        phases.last == .restored
    }

    var message: String {
        if let probeInterruption { return probeInterruption }
        if snapshot?.hasSMARTPayload == true {
            return restorationConfirmed
                ? "SMART data was read and volume restoration completed."
                : "SMART data was read, but volume restoration could not be confirmed. Check the disk in Disk Utility."
        }
        if phases.isEmpty {
            return "SNT did not reach the USB capture workflow. Review the diagnostic output."
        }
        if restorationConfirmed, attemptedBridges.count == SNTBridge.allCases.count {
            return "JMicron, ASMedia and Realtek returned no SMART data. Volume restoration completed."
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
    func read(drive: DriveDevice, target: USBRawSmartTarget) async throws -> USBRawSmartResult
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
    private let userID: UInt32

    init(
        runner: CommandRunning = ShellCommandRunner(),
        userID: UInt32 = getuid()
    ) {
        self.runner = runner
        self.userID = userID
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        guard userID > 0, userID != UInt32.max else {
            throw USBRawSmartError.unavailable("SNT requires a logged-in user's Capricorn process.")
        }
        // Authorization runs in a system context. Rejoin the requesting user's
        // bootstrap/audit session without dropping the root credentials.
        // bsexec exits successfully without adopting that session on macOS 26.
        let command = ([
            "/bin/launchctl", "asuser", String(userID), "/usr/bin/env",
            "CAPRICORN_USBRAW_USER_UID=\(userID)"
        ] + [executable] + arguments).map(AdministratorCommandRunner.shellQuote).joined(separator: " ")
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
    let authorizeVolumes: @Sendable (DriveDevice) throws -> Void
    let inventoryProvider: DiskInventoryProviding

    init(
        runner: CommandRunning = ShellCommandRunner(),
        administratorRunner: CommandRunning = AdministratorUSBRawCommandRunner(),
        executableURL: URL? = Bundle.main.executableURL?
            .deletingLastPathComponent().appendingPathComponent("smartctl-usbraw"),
        targetResolver: @escaping @Sendable (DriveDevice) throws -> USBRawSmartTarget = {
            try USBRawSmartTargetResolver().target(for: $0)
        },
        authorizeVolumes: @escaping @Sendable (DriveDevice) throws -> Void = Self.authorizeMountedVolumes,
        inventoryProvider: DiskInventoryProviding = DiskutilInventoryProvider(networkProvider: nil)
    ) {
        self.runner = runner
        self.administratorRunner = administratorRunner
        self.executableURL = executableURL
        self.targetResolver = targetResolver
        self.authorizeVolumes = authorizeVolumes
        self.inventoryProvider = inventoryProvider
    }

    func target(for drive: DriveDevice) throws -> USBRawSmartTarget { try targetResolver(drive) }

    func read(drive: DriveDevice, target: USBRawSmartTarget) async throws -> USBRawSmartResult {
        guard let executableURL, FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw USBRawSmartError.unavailable("The experimental SNT tool is missing from this application.")
        }
        guard try self.target(for: drive) == target else {
            throw USBRawSmartError.unavailable("The USB device changed after confirmation. Refresh disks before trying SNT.")
        }
        // Passive discovery filters out composite devices and multiple disks/LUNs.
        // Never use --scan-open: that would capture before the explicit read.
        let scan = try await runner.run(executableURL.path, arguments: ["--scan", "-d", "usb", "--json=c"], timeout: 15)
        let devices = SmartctlParser.parseScan(scan.stdout)?.filter {
            URL(fileURLWithPath: $0.name).lastPathComponent == drive.bsdName
        } ?? []
        guard scan.terminationStatus == 0, devices.count == 1, let device = devices.first else {
            throw USBRawSmartError.unavailable("This USB device is unsupported or has multiple storage interfaces or disks. It was not captured.")
        }
        let detected = device.type.flatMap(SNTBridge.init(rawValue:))
        let bridges = detected.map { [$0] } ?? SNTBridge.allCases
        // Request removable-volume access from the user's app before entering
        // administrator authorization. A denial must leave the disk mounted.
        try authorizeVolumes(drive)
        guard try self.target(for: drive) == target else {
            throw USBRawSmartError.unavailable("The USB device changed after confirmation. Refresh disks before trying SNT.")
        }
        // The tool itself owns non-forced unmount and restoration. Do not put
        // either around the process in a script or lose its original mount list.
        return try await SmartctlCommandCoordinator.shared.run {
            try await probeBridges(bridges, drive: drive, target: target, executableURL: executableURL)
        }
    }

    private func probeBridges(
        _ bridges: [SNTBridge], drive: DriveDevice, target: USBRawSmartTarget, executableURL: URL
    ) async throws -> USBRawSmartResult {
        var currentTarget = target
        var previous: USBRawSmartResult?
        var transcripts: [String] = []
        var attempted: [SNTBridge] = []
        for bridge in bridges {
            var captureRequested = false
            do {
                try Task.checkCancellation()
                if previous == nil {
                    guard try self.target(for: drive) == target else {
                        throw USBRawSmartError.unavailable("The USB device changed after confirmation. Refresh disks before trying SNT.")
                    }
                } else {
                    // Release/re-enumeration can change both diskN and the USB
                    // registry ID. Revalidate stable identity before each capture.
                    let reconnected = try await reconnectedDrive(matching: drive)
                    currentTarget = try self.target(for: reconnected)
                    try authorizeVolumes(reconnected)
                    guard try self.target(for: reconnected) == currentTarget else {
                        throw USBRawSmartError.unavailable("The USB device changed after confirmation. Refresh disks before trying SNT.")
                    }
                }
                attempted.append(bridge)
                let header = "CAPRICORN_USBRAW_ATTEMPT\t\(attempted.count)\t\(bridge.rawValue)\t\(currentTarget.selector)\n"
                transcripts.append(header)
                captureRequested = true
                let command = try await administratorRunner.run("/usr/bin/env", arguments: [
                    "CAPRICORN_USBRAW_MANUAL=1", executableURL.path,
                    "-i", "-H", "-A", "--json=c", "-d", bridge.rawValue, currentTarget.selector
                ])
                var result = Self.parse(command, drive: drive, target: currentTarget, type: bridge.rawValue)
                transcripts[transcripts.count - 1] = header + result.transcript
                result.transcript = transcripts.joined(separator: "\n")
                result.attemptedBridges = attempted
                // Text/JSON output or Identify alone is not a SMART result.
                // Never capture again when release/restoration is uncertain.
                if result.snapshot?.hasSMARTPayload == true || !result.restorationConfirmed {
                    return result
                }
                previous = result
            } catch {
                guard var result = previous else { throw error }
                // A failed process call provides no cleanup evidence for this
                // attempt. The preceding attempt's restored marker is stale.
                if captureRequested {
                    result.phases = []
                    result.probeInterruption = "SNT protocol probing stopped, and volume restoration could not be confirmed. Check the disk in Disk Utility."
                } else {
                    result.probeInterruption = error.localizedDescription
                }
                result.attemptedBridges = attempted
                result.transcript = transcripts.joined(separator: "\n")
                    + "\nCAPRICORN_USBRAW_PROBE_STOP\t" + error.localizedDescription
                return result
            }
        }
        // The list always contains a detected bridge or all three protocols.
        guard let previous else { throw USBRawSmartError.unavailable("No SNT protocols were selected.") }
        return previous
    }

    private func reconnectedDrive(matching expected: DriveDevice) async throws -> DriveDevice {
        for attempt in 1...4 {
            try Task.checkCancellation()
            let matches = try await inventoryProvider.loadDrives().filter {
                DriveStableIdentityMatcher.matches(expected, $0)
            }
            if matches.count == 1, let drive = matches.first { return drive }
            guard matches.isEmpty, attempt < 4 else {
                throw USBRawSmartError.unavailable("The USB disk could not be uniquely identified between SNT protocols. Further capture was stopped.")
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw USBRawSmartError.unavailable("The USB disk could not be uniquely identified between SNT protocols. Further capture was stopped.")
    }

    static func authorizeMountedVolumes(for drive: DriveDevice) throws {
        for path in Set(drive.displayableVolumes.compactMap(\.mountPoint)) {
            // This filesystem operation lets TCC prompt in the GUI user's
            // context. Discard names; no file contents are read or modified.
            _ = try FileManager.default.contentsOfDirectory(atPath: path)
        }
    }

    /// Ordinary refresh cannot repeat a manual capture. Keep that reading's
    /// original timestamp until a verified provider supplies a new reading.
    /// AppModel matches stable disk identity before calling this method.
    static func retainingManualRead(
        in refreshed: SmartSnapshot, from previous: SmartSnapshot, for drive: DriveDevice
    ) -> SmartSnapshot {
        guard previous.selectedProvider == providerName, previous.hasSMARTPayload,
              refreshed.verifiedSource == nil else { return refreshed }
        var retained = previous
        retained.driveID = drive.id
        return retained
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
