// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct CommandResult: Sendable {
    var stdout: Data
    var stderr: Data
    var terminationStatus: Int32

    var stdoutString: String {
        String(data: stdout, encoding: .utf8) ?? ""
    }

    var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }
}

protocol CommandRunning {
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult
}

enum CommandError: Error, LocalizedError {
    case nonZeroExit(executable: String, status: Int32, stderr: String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case let .nonZeroExit(executable, status, stderr):
            "\(executable) exited with status \(status). \(stderr)"
        case let .launchFailed(message):
            message
        }
    }
}

final class ShellCommandRunner: CommandRunning {
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CommandError.launchFailed(error.localizedDescription))
                    return
                }

                let outputGroup = DispatchGroup()
                let outputLock = NSLock()
                var stdoutData = Data()
                var stderrData = Data()

                outputGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    outputLock.lock()
                    stdoutData = data
                    outputLock.unlock()
                    outputGroup.leave()
                }

                outputGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    let data = stderr.fileHandleForReading.readDataToEndOfFile()
                    outputLock.lock()
                    stderrData = data
                    outputLock.unlock()
                    outputGroup.leave()
                }

                process.waitUntilExit()
                outputGroup.wait()

                continuation.resume(returning: CommandResult(
                    stdout: stdoutData,
                    stderr: stderrData,
                    terminationStatus: process.terminationStatus
                ))
            }
        }
    }
}

protocol DiskCheckCommandRunning: AnyObject {
    func run(
        _ executable: String,
        arguments: [String],
        stdout: @escaping @Sendable (String) -> Void,
        stderr: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult
    func cancel()
}

final class StreamingDiskCheckCommandRunner: DiskCheckCommandRunning, @unchecked Sendable {
    private let processLock = NSLock()
    private var currentProcess: Process?

    func run(
        _ executable: String,
        arguments: [String],
        stdout onStdout: @escaping @Sendable (String) -> Void,
        stderr onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let dataLock = NSLock()
                var stdoutData = Data()
                var stderrData = Data()

                func append(_ data: Data, toStdout: Bool) {
                    guard !data.isEmpty else { return }
                    dataLock.lock()
                    if toStdout {
                        stdoutData.append(data)
                    } else {
                        stderrData.append(data)
                    }
                    dataLock.unlock()

                    guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
                    if toStdout {
                        onStdout(text)
                    } else {
                        onStderr(text)
                    }
                }

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    append(handle.availableData, toStdout: true)
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    append(handle.availableData, toStdout: false)
                }

                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                process.terminationHandler = { [weak self] finishedProcess in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    append(stdoutPipe.fileHandleForReading.readDataToEndOfFile(), toStdout: true)
                    append(stderrPipe.fileHandleForReading.readDataToEndOfFile(), toStdout: false)

                    self?.processLock.lock()
                    if self?.currentProcess === finishedProcess {
                        self?.currentProcess = nil
                    }
                    self?.processLock.unlock()

                    dataLock.lock()
                    let finalStdout = stdoutData
                    let finalStderr = stderrData
                    dataLock.unlock()

                    continuation.resume(returning: CommandResult(
                        stdout: finalStdout,
                        stderr: finalStderr,
                        terminationStatus: finishedProcess.terminationStatus
                    ))
                }

                do {
                    self.processLock.lock()
                    self.currentProcess = process
                    self.processLock.unlock()
                    try process.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    self.processLock.lock()
                    if self.currentProcess === process {
                        self.currentProcess = nil
                    }
                    self.processLock.unlock()
                    continuation.resume(throwing: CommandError.launchFailed(error.localizedDescription))
                }
            }
        }
    }

    func cancel() {
        processLock.lock()
        let process = currentProcess
        processLock.unlock()
        process?.terminate()
    }
}

private final class LockedDiskCheckOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutText = ""
    private var stderrText = ""

    func appendStdout(_ text: String) {
        append(text, toStdout: true)
    }

    func appendStderr(_ text: String) {
        append(text, toStdout: false)
    }

    var snapshot: (stdout: String, stderr: String) {
        lock.lock()
        defer { lock.unlock() }
        return (stdoutText, stderrText)
    }

    private func append(_ text: String, toStdout: Bool) {
        guard !text.isEmpty else { return }
        lock.lock()
        if toStdout {
            stdoutText += text
        } else {
            stderrText += text
        }
        lock.unlock()
    }
}

private final class LockedDiskCheckCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<CommandResult, Error>?

    func finish(_ result: Result<CommandResult, Error>) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }

    var result: Result<CommandResult, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }
}

enum DiskOpenFileParser {
    static func parse(_ output: String) -> [DiskOpenFileProcess] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap(parseLine)
    }

    private static func parseLine(_ line: Substring) -> DiskOpenFileProcess? {
        let parts = line.split(maxSplits: 8, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard parts.count >= 9,
              let pid = Int(parts[1]),
              String(parts[0]).uppercased() != "COMMAND" else {
            return nil
        }

        return DiskOpenFileProcess(
            command: String(parts[0]),
            pid: pid,
            user: String(parts[2]),
            path: String(parts[8])
        )
    }
}

final class DiskOpenFileService {
    private let runner: CommandRunning
    private let lsofPath: String

    init(
        runner: CommandRunning = ShellCommandRunner(),
        lsofPath: String = "/usr/sbin/lsof"
    ) {
        self.runner = runner
        self.lsofPath = lsofPath
    }

    func inspectOpenFiles(on drive: DriveDevice) async throws -> DiskOpenFileInspection {
        guard let mountPoint = drive.primaryMountPoint else {
            throw DiskActionError.missingMountPoint
        }

        let result = try await runner.run(lsofPath, arguments: ["+f", "--", mountPoint])
        if result.terminationStatus != 0, result.stdoutString.isEmpty, !result.stderrString.isEmpty {
            throw CommandError.nonZeroExit(executable: lsofPath, status: result.terminationStatus, stderr: result.stderrString)
        }

        return DiskOpenFileInspection(
            driveID: drive.id,
            driveName: drive.displayName,
            mountPoint: mountPoint,
            processes: DiskOpenFileParser.parse(result.stdoutString)
        )
    }
}

enum DiskActionError: Error, LocalizedError {
    case missingMountPoint
    case missingVolume
    case missingName
    case unsupportedAction
    case unsupportedNetworkMount
    case protectedSystemDisk

    var errorDescription: String? {
        switch self {
        case .missingMountPoint:
            "No mounted volume is available for this action."
        case .missingVolume:
            "No suitable volume is available for this action."
        case .missingName:
            "A volume name is required."
        case .unsupportedAction:
            "This disk action is not supported for the selected drive."
        case .unsupportedNetworkMount:
            "This network volume cannot be opened from its mount source."
        case .protectedSystemDisk:
            "System internal disks cannot be mounted, unmounted, or ejected from Capricorn."
        }
    }
}

final class DiskActionService {
    private let runner: CommandRunning
    private let diskutilPath: String
    private let openPath: String

    init(
        runner: CommandRunning = ShellCommandRunner(),
        diskutilPath: String = "/usr/sbin/diskutil",
        openPath: String = "/usr/bin/open"
    ) {
        self.runner = runner
        self.diskutilPath = diskutilPath
        self.openPath = openPath
    }

    func perform(_ action: DiskSidebarAction, on drive: DriveDevice, newName: String? = nil) async throws {
        if DiskSidebarActionPolicy.isProtectedSystemControlAction(action, for: drive) {
            throw DiskActionError.protectedSystemDisk
        }

        switch action {
        case .mount:
            if drive.isNetwork {
                guard let url = DiskSidebarActionPolicy.networkMountURL(for: drive) else {
                    throw DiskActionError.unsupportedNetworkMount
                }
                try await run(openPath, arguments: [url.absoluteString])
            } else {
                try await runDiskutil(["mountDisk", drive.bsdName])
            }
        case .unmount:
            if drive.isNetwork {
                try await runDiskutil(["unmount", try mountedPath(for: drive)])
            } else {
                try await runDiskutil(["unmountDisk", drive.bsdName])
            }
        case .forceUnmount:
            guard !drive.isNetwork else { throw DiskActionError.unsupportedAction }
            try await runDiskutil(["unmountDisk", "force", drive.bsdName])
        case .eject:
            guard !drive.isNetwork else { throw DiskActionError.unsupportedAction }
            try await runDiskutil(["eject", drive.bsdName])
        case .rename:
            guard !drive.isNetwork else { throw DiskActionError.unsupportedAction }
            guard let newName = newName?.trimmingCharacters(in: .whitespacesAndNewlines), !newName.isEmpty else {
                throw DiskActionError.missingName
            }
            try await runDiskutil(["renameVolume", try renameTarget(for: drive), newName])
        case .disconnect:
            guard drive.isNetwork else { throw DiskActionError.unsupportedAction }
            try await runDiskutil(["unmount", try mountedPath(for: drive)])
        case .inspectOpenFiles, .checkLog, .detailedCheck, .revealInFinder, .refresh:
            throw DiskActionError.unsupportedAction
        }
    }

    private func runDiskutil(_ arguments: [String]) async throws {
        try await run(diskutilPath, arguments: arguments)
    }

    private func run(_ executable: String, arguments: [String]) async throws {
        let result = try await runner.run(executable, arguments: arguments)
        guard result.terminationStatus == 0 else {
            throw CommandError.nonZeroExit(executable: executable, status: result.terminationStatus, stderr: result.stderrString)
        }
    }

    private func mountedPath(for drive: DriveDevice) throws -> String {
        guard let mountPoint = drive.primaryMountPoint else {
            throw DiskActionError.missingMountPoint
        }
        return mountPoint
    }

    private func renameTarget(for drive: DriveDevice) throws -> String {
        guard let volume = drive.actionTargetVolume else {
            throw DiskActionError.missingVolume
        }
        return volume.mountPoint ?? volume.deviceIdentifier
    }
}

final class DiskCheckService {
    private struct CommandPlan {
        var title: String
        var executable: String?
        var arguments: [String]
        var unsupportedMessage: String?
    }

    private let runner: DiskCheckCommandRunning
    private let diskutilPath: String
    private let fsckAPFSPath: String
    private let fsckHFSPath: String
    private let fsckExFATPath: String
    private let fsckMSDOSPath: String
    private let updateIntervalNanoseconds: UInt64

    init(
        runner: DiskCheckCommandRunning = StreamingDiskCheckCommandRunner(),
        diskutilPath: String = "/usr/sbin/diskutil",
        fsckAPFSPath: String = "/sbin/fsck_apfs",
        fsckHFSPath: String = "/sbin/fsck_hfs",
        fsckExFATPath: String = "/sbin/fsck_exfat",
        fsckMSDOSPath: String = "/sbin/fsck_msdos",
        updateIntervalNanoseconds: UInt64 = 250_000_000
    ) {
        self.runner = runner
        self.diskutilPath = diskutilPath
        self.fsckAPFSPath = fsckAPFSPath
        self.fsckHFSPath = fsckHFSPath
        self.fsckExFATPath = fsckExFATPath
        self.fsckMSDOSPath = fsckMSDOSPath
        self.updateIntervalNanoseconds = updateIntervalNanoseconds
    }

    func cancel() {
        runner.cancel()
    }

    func check(
        _ mode: DiskCheckMode,
        drive: DriveDevice,
        onUpdate: ((DiskCheckReport) async -> Void)? = nil
    ) async -> DiskCheckReport {
        let plans = commandPlans(for: mode, drive: drive)
        var report = DiskCheckReport(
            mode: mode,
            driveID: drive.id,
            driveName: drive.displayName,
            entries: []
        )

        for plan in plans {
            guard let executable = plan.executable else {
                report.entries.append(DiskCheckEntry(
                    title: plan.title,
                    executable: nil,
                    arguments: plan.arguments,
                    terminationStatus: nil,
                    stdout: "",
                    stderr: plan.unsupportedMessage ?? "No checker is available for this target."
                ))
                if let onUpdate {
                    await onUpdate(report)
                }
                continue
            }

            let entryID = UUID()
            report.entries.append(DiskCheckEntry(
                id: entryID,
                title: plan.title,
                executable: executable,
                arguments: plan.arguments,
                terminationStatus: nil,
                stdout: "",
                stderr: "",
                isRunning: true
            ))
            if let onUpdate {
                await onUpdate(report)
            }

            let streamedOutput = LockedDiskCheckOutput()
            let completion = LockedDiskCheckCompletion()
            let commandTask = Task {
                do {
                    let result = try await runner.run(
                        executable,
                        arguments: plan.arguments,
                        stdout: { streamedOutput.appendStdout($0) },
                        stderr: { streamedOutput.appendStderr($0) }
                    )
                    completion.finish(.success(result))
                } catch {
                    completion.finish(.failure(error))
                }
            }
            var lastStdout = ""
            var lastStderr = ""

            while true {
                if let result = completion.result {
                    commandTask.cancel()
                    switch result {
                    case let .success(commandResult):
                        updateEntry(
                            entryID,
                            in: &report,
                            terminationStatus: commandResult.terminationStatus,
                            stdout: commandResult.stdoutString,
                            stderr: commandResult.stderrString,
                            isRunning: false
                        )
                    case let .failure(error):
                        let snapshot = streamedOutput.snapshot
                        updateEntry(
                            entryID,
                            in: &report,
                            terminationStatus: nil,
                            stdout: snapshot.stdout,
                            stderr: [snapshot.stderr, error.localizedDescription]
                                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                .joined(separator: "\n"),
                            isRunning: false
                        )
                    }
                    break
                }

                if Task.isCancelled {
                    runner.cancel()
                    commandTask.cancel()
                    let snapshot = streamedOutput.snapshot
                    updateEntry(
                        entryID,
                        in: &report,
                        terminationStatus: nil,
                        stdout: snapshot.stdout,
                        stderr: [snapshot.stderr, "Disk check was cancelled."]
                            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            .joined(separator: "\n"),
                        isRunning: false
                    )
                    break
                }

                if updateIntervalNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: updateIntervalNanoseconds)
                } else {
                    await Task.yield()
                }

                let snapshot = streamedOutput.snapshot
                if snapshot.stdout != lastStdout || snapshot.stderr != lastStderr {
                    lastStdout = snapshot.stdout
                    lastStderr = snapshot.stderr
                    updateEntry(
                        entryID,
                        in: &report,
                        terminationStatus: nil,
                        stdout: snapshot.stdout,
                        stderr: snapshot.stderr,
                        isRunning: true
                    )
                    if let onUpdate {
                        await onUpdate(report)
                    }
                }
            }

            if let onUpdate {
                await onUpdate(report)
            }
        }

        if report.entries.isEmpty {
            report.entries.append(DiskCheckEntry(
                title: "No Check Target",
                executable: nil,
                arguments: [],
                terminationStatus: nil,
                stdout: "",
                stderr: "No local disk or volume target is available for checking."
            ))
            if let onUpdate {
                await onUpdate(report)
            }
        }

        return report
    }

    private func commandPlans(for mode: DiskCheckMode, drive: DriveDevice) -> [CommandPlan] {
        guard !drive.isNetwork else {
            return [CommandPlan(
                title: "Network Volume",
                executable: nil,
                arguments: [],
                unsupportedMessage: "Network volumes do not expose a local block device for diskutil or fsck checks."
            )]
        }

        guard !DiskSidebarActionPolicy.isProtectedInternalSystemDisk(drive) else {
            return [CommandPlan(
                title: "Protected System Disk",
                executable: nil,
                arguments: [drive.bsdName],
                unsupportedMessage: "System internal disks are protected from live filesystem checks in Capricorn. Use macOS Recovery and Disk Utility First Aid for a full system disk check."
            )]
        }

        switch mode {
        case .ordinary:
            return ordinaryPlans(for: drive)
        case .detailed:
            return detailedPlans(for: drive)
        }
    }

    private func ordinaryPlans(for drive: DriveDevice) -> [CommandPlan] {
        var plans: [CommandPlan] = []
        if !drive.bsdName.isEmpty {
            plans.append(CommandPlan(
                title: "Partition Map: \(drive.bsdName)",
                executable: diskutilPath,
                arguments: ["verifyDisk", drive.bsdName],
                unsupportedMessage: nil
            ))
        }

        for volume in uniqueVolumes(drive.volumes) {
            plans.append(CommandPlan(
                title: "Volume: \(volume.name)",
                executable: diskutilPath,
                arguments: ["verifyVolume", volume.mountPoint ?? volume.deviceIdentifier],
                unsupportedMessage: nil
            ))
        }

        return plans
    }

    private func detailedPlans(for drive: DriveDevice) -> [CommandPlan] {
        uniqueVolumes(drive.volumes).map { volume in
            guard let rawDevice = rawDevicePath(for: volume.deviceIdentifier) else {
                return CommandPlan(
                    title: "Volume: \(volume.name)",
                    executable: nil,
                    arguments: [volume.deviceIdentifier],
                    unsupportedMessage: "Detailed fsck checks require a local disk device identifier."
                )
            }

            guard let format = FileSystemFormatResolver.normalized(volume.fileSystemType) else {
                return CommandPlan(
                    title: "Volume: \(volume.name)",
                    executable: nil,
                    arguments: [rawDevice],
                    unsupportedMessage: "No filesystem type is available for selecting a detailed checker."
                )
            }

            switch format {
            case "APFS":
                return CommandPlan(title: "APFS Volume: \(volume.name)", executable: fsckAPFSPath, arguments: ["-n", "-x", rawDevice], unsupportedMessage: nil)
            case "HFS+":
                return CommandPlan(title: "HFS+ Volume: \(volume.name)", executable: fsckHFSPath, arguments: ["-n", "-x", rawDevice], unsupportedMessage: nil)
            case "ExFAT":
                return CommandPlan(title: "ExFAT Volume: \(volume.name)", executable: fsckExFATPath, arguments: ["-n", "-x", rawDevice], unsupportedMessage: nil)
            case "FAT32", "MS-DOS":
                return CommandPlan(title: "FAT Volume: \(volume.name)", executable: fsckMSDOSPath, arguments: ["-n", rawDevice], unsupportedMessage: nil)
            default:
                return CommandPlan(
                    title: "\(format) Volume: \(volume.name)",
                    executable: nil,
                    arguments: [rawDevice],
                    unsupportedMessage: "No native detailed checker is available for \(format) on macOS."
                )
            }
        }
    }

    private func uniqueVolumes(_ volumes: [DriveDevice.Volume]) -> [DriveDevice.Volume] {
        var seen = Set<String>()
        return volumes.filter { volume in
            let key = volume.mountPoint ?? volume.deviceIdentifier
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func rawDevicePath(for identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/dev/rdisk") {
            return trimmed
        }
        if trimmed.hasPrefix("/dev/disk") {
            return trimmed.replacingOccurrences(of: "/dev/disk", with: "/dev/rdisk")
        }
        if trimmed.hasPrefix("disk") {
            return "/dev/r\(trimmed)"
        }
        return nil
    }

    private func updateEntry(
        _ id: UUID,
        in report: inout DiskCheckReport,
        terminationStatus: Int32?,
        stdout: String,
        stderr: String,
        isRunning: Bool
    ) {
        guard let index = report.entries.firstIndex(where: { $0.id == id }) else { return }
        report.entries[index].terminationStatus = terminationStatus
        report.entries[index].stdout = stdout
        report.entries[index].stderr = stderr
        report.entries[index].isRunning = isRunning
    }
}
