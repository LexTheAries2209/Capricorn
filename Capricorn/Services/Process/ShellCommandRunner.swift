// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

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

protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult
}

protocol TimedCommandRunning: CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> CommandResult
}

extension CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        guard let timedRunner = self as? any TimedCommandRunning else {
            return try await run(executable, arguments: arguments)
        }
        return try await timedRunner.run(executable, arguments: arguments, timeout: timeout)
    }
}

enum CommandError: Error, LocalizedError {
    case nonZeroExit(executable: String, status: Int32, stderr: String)
    case launchFailed(String)
    case timedOut(executable: String, seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case let .nonZeroExit(executable, status, stderr):
            "\(executable) exited with status \(status). \(stderr)"
        case let .launchFailed(message):
            message
        case let .timedOut(executable, seconds):
            "\(executable) timed out after \(seconds.formatted(.number.precision(.fractionLength(0...1)))) seconds."
        }
    }
}

private struct BufferedCommandOutput {
    var stdout = Data()
    var stderr = Data()
}

private final class OneShotContinuation<Value: Sendable>: @unchecked Sendable {
    private let continuation: LockedState<CheckedContinuation<Value, Error>?>

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = LockedState(continuation)
    }

    func resume(returning value: Value) {
        let continuation = continuation.withLock { stored -> CheckedContinuation<Value, Error>? in
            defer { stored = nil }
            return stored
        }
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        let continuation = continuation.withLock { stored -> CheckedContinuation<Value, Error>? in
            defer { stored = nil }
            return stored
        }
        continuation?.resume(throwing: error)
    }
}

private final class CommandProcessHandle: @unchecked Sendable {
    enum StopReason {
        case none
        case cancelled
        case timedOut
    }

    private struct State {
        weak var process: Process?
        var stopReason = StopReason.none
        var isFinished = false
    }

    private let state = LockedState(State())

    var stopReason: StopReason {
        state.withLock { $0.stopReason }
    }

    var isCancelled: Bool {
        stopReason == .cancelled
    }

    func attach(_ process: Process) {
        let shouldStop = state.withLock { state in
            state.process = process
            return state.stopReason != .none
        }
        if shouldStop {
            terminate(process)
        }
    }

    func stop(_ reason: StopReason) {
        let process = state.withLock { state -> Process? in
            guard !state.isFinished, state.stopReason == .none else { return nil }
            state.stopReason = reason
            return state.process
        }
        if let process {
            terminate(process)
        }
    }

    func cancel() {
        stop(.cancelled)
    }

    func finish() -> StopReason {
        state.withLock { state in
            state.isFinished = true
            return state.stopReason
        }
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}

final class ShellCommandRunner: TimedCommandRunning, @unchecked Sendable {
    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        try await run(executable, arguments: arguments, timeout: nil)
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        try await run(executable, arguments: arguments, timeout: Optional(timeout))
    }

    private func run(_ executable: String, arguments: [String], timeout: TimeInterval?) async throws -> CommandResult {
        let processHandle = CommandProcessHandle()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let completion = OneShotContinuation(continuation)
                DispatchQueue.global(qos: .utility).async {
                    if processHandle.stopReason == .cancelled {
                        completion.resume(throwing: CancellationError())
                        return
                    }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments

                    let stdout = Pipe()
                    let stderr = Pipe()
                    process.standardOutput = stdout
                    process.standardError = stderr

                    do {
                        try process.run()
                        processHandle.attach(process)
                    } catch {
                        completion.resume(throwing: CommandError.launchFailed(error.localizedDescription))
                        return
                    }

                    let timeoutWorkItem = timeout.map { timeout in
                        DispatchWorkItem {
                            processHandle.stop(.timedOut)
                        }
                    }
                    if let timeout, let timeoutWorkItem {
                        DispatchQueue.global(qos: .utility).asyncAfter(
                            deadline: .now() + max(0, timeout),
                            execute: timeoutWorkItem
                        )
                    }

                    let outputGroup = DispatchGroup()
                    let output = LockedState(BufferedCommandOutput())

                    outputGroup.enter()
                    DispatchQueue.global(qos: .utility).async {
                        let data = stdout.fileHandleForReading.readDataToEndOfFile()
                        output.withLock { $0.stdout = data }
                        outputGroup.leave()
                    }

                    outputGroup.enter()
                    DispatchQueue.global(qos: .utility).async {
                        let data = stderr.fileHandleForReading.readDataToEndOfFile()
                        output.withLock { $0.stderr = data }
                        outputGroup.leave()
                    }

                    process.waitUntilExit()
                    timeoutWorkItem?.cancel()
                    let stopReason = processHandle.finish()
                    outputGroup.wait()

                    switch stopReason {
                    case .cancelled:
                        completion.resume(throwing: CancellationError())
                        return
                    case .timedOut:
                        completion.resume(throwing: CommandError.timedOut(
                            executable: executable,
                            seconds: timeout ?? 0
                        ))
                        return
                    case .none:
                        break
                    }
                    let finalOutput = output.snapshot()
                    completion.resume(returning: CommandResult(
                        stdout: finalOutput.stdout,
                        stderr: finalOutput.stderr,
                        terminationStatus: process.terminationStatus
                    ))
                }
            }
        } onCancel: {
            processHandle.stop(.cancelled)
        }
    }
}

final class AdministratorCommandRunner: CommandRunning, @unchecked Sendable {
    private let runner: CommandRunning

    init(runner: CommandRunning = ShellCommandRunner()) {
        self.runner = runner
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        return try await runner.run(
            "/usr/bin/osascript",
            arguments: ["-e", Self.script(for: executable, arguments: arguments)]
        )
    }

    static func script(for executable: String, arguments: [String]) -> String {
        let command = ([executable] + arguments).map(shellQuote).joined(separator: " ")
        return "do shell script \(appleScriptQuote(command)) with administrator privileges"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Runs only filesystem checkers through macOS's administrator authorization prompt.
/// The prompt grants the child command root access without changing device-node permissions.
final class AdministratorDiskCheckCommandRunner: DiskCheckCommandRunning, @unchecked Sendable {
    private let runner: StreamingDiskCheckCommandRunner

    init(runner: StreamingDiskCheckCommandRunner = StreamingDiskCheckCommandRunner()) {
        self.runner = runner
    }

    func run(
        _ executable: String,
        arguments: [String],
        stdout onStdout: @escaping @Sendable (String) -> Void,
        stderr onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult {
        try await runner.run(
            "/usr/bin/osascript",
            arguments: ["-e", AdministratorCommandRunner.script(for: executable, arguments: arguments)],
            stdout: onStdout,
            stderr: onStderr
        )
    }

    func cancel() {
        runner.cancel()
    }
}

protocol DiskCheckCommandRunning: AnyObject, Sendable {
    func run(
        _ executable: String,
        arguments: [String],
        stdout: @escaping @Sendable (String) -> Void,
        stderr: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult
    func cancel()
}

private final class StreamingCommandBuffer: @unchecked Sendable {
    private let output = LockedState(BufferedCommandOutput())

    func append(
        _ data: Data,
        toStdout: Bool,
        onStdout: @escaping @Sendable (String) -> Void,
        onStderr: @escaping @Sendable (String) -> Void
    ) {
        guard !data.isEmpty else { return }
        output.withLock { output in
            if toStdout {
                output.stdout.append(data)
            } else {
                output.stderr.append(data)
            }
        }

        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        if toStdout {
            onStdout(text)
        } else {
            onStderr(text)
        }
    }

    func snapshot() -> BufferedCommandOutput {
        output.snapshot()
    }
}

final class StreamingDiskCheckCommandRunner: DiskCheckCommandRunning, @unchecked Sendable {
    private let currentHandle = LockedState<CommandProcessHandle?>(nil)

    func run(
        _ executable: String,
        arguments: [String],
        stdout onStdout: @escaping @Sendable (String) -> Void,
        stderr onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult {
        let processHandle = CommandProcessHandle()
        currentHandle.withLock { $0 = processHandle }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let completion = OneShotContinuation(continuation)
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    let output = StreamingCommandBuffer()

                    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                        output.append(handle.availableData, toStdout: true, onStdout: onStdout, onStderr: onStderr)
                    }
                    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                        output.append(handle.availableData, toStdout: false, onStdout: onStdout, onStderr: onStderr)
                    }

                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe
                    process.terminationHandler = { [weak self] finishedProcess in
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil
                        output.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile(), toStdout: true, onStdout: onStdout, onStderr: onStderr)
                        output.append(stderrPipe.fileHandleForReading.readDataToEndOfFile(), toStdout: false, onStdout: onStdout, onStderr: onStderr)

                        self?.clearCurrentHandle(processHandle)
                        if processHandle.isCancelled {
                            completion.resume(throwing: CancellationError())
                        } else {
                            let finalOutput = output.snapshot()
                            completion.resume(returning: CommandResult(
                                stdout: finalOutput.stdout,
                                stderr: finalOutput.stderr,
                                terminationStatus: finishedProcess.terminationStatus
                            ))
                        }
                    }

                    do {
                        try process.run()
                        processHandle.attach(process)
                    } catch {
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil
                        self?.clearCurrentHandle(processHandle)
                        completion.resume(throwing: CommandError.launchFailed(error.localizedDescription))
                    }
                }
            }
        } onCancel: {
            processHandle.cancel()
        }
    }

    func cancel() {
        currentHandle.snapshot()?.cancel()
    }

    private func clearCurrentHandle(_ handle: CommandProcessHandle) {
        currentHandle.withLock { current in
            if current === handle {
                current = nil
            }
        }
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

        return try await inspectOpenFiles(
            at: mountPoint,
            driveID: drive.id,
            driveName: drive.displayName
        )
    }

    func inspectOpenFiles(
        at mountPoint: String,
        driveID: String,
        driveName: String
    ) async throws -> DiskOpenFileInspection {
        guard !mountPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DiskActionError.missingMountPoint
        }

        let result = try await runner.run(lsofPath, arguments: ["+f", "--", mountPoint])
        if result.terminationStatus != 0, result.stdoutString.isEmpty, !result.stderrString.isEmpty {
            throw CommandError.nonZeroExit(executable: lsofPath, status: result.terminationStatus, stderr: result.stderrString)
        }

        return DiskOpenFileInspection(
            driveID: driveID,
            driveName: driveName,
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

    func perform(
        _ action: DiskSidebarAction,
        on drive: DriveDevice,
        newName: String? = nil,
        targetVolumeID: String? = nil
    ) async throws {
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
            try await runDiskutil(["renameVolume", try renameTarget(for: drive, targetVolumeID: targetVolumeID), newName])
        case .disconnect:
            guard drive.isNetwork else { throw DiskActionError.unsupportedAction }
            try await runDiskutil(["unmount", try mountedPath(for: drive)])
        case .inspectOpenFiles, .checkLog, .detailedCheck, .firstAid, .revealInFinder, .refresh:
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

    private func renameTarget(for drive: DriveDevice, targetVolumeID: String?) throws -> String {
        let volume = targetVolumeID.flatMap { volumeID in
            drive.volumes.first(where: { $0.deviceIdentifier == volumeID })
        } ?? RepresentativeVolumeResolver.resolve(for: drive)
        guard let volume, RepresentativeVolumeResolver.isSelectable(volume) else {
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
        var volumeIdentifier: String? = nil
    }

    private enum DetailedCheckPreparation {
        case ready(mountSession: MountSession?)
        case failed(status: Int32?, message: String)
    }

    private struct MountSession {
        var volumeIdentifier: String
        var isReadOnly: Bool
    }

    private let runner: DiskCheckCommandRunning
    private let diskutilPath: String
    private let fsckHFSPath: String
    private let fsckExFATPath: String
    private let fsckMSDOSPath: String
    private let privilegedRunner: DiskCheckCommandRunning
    private let updateIntervalNanoseconds: UInt64

    init(
        runner: DiskCheckCommandRunning = StreamingDiskCheckCommandRunner(),
        diskutilPath: String = "/usr/sbin/diskutil",
        fsckHFSPath: String = "/sbin/fsck_hfs",
        fsckExFATPath: String = "/sbin/fsck_exfat",
        fsckMSDOSPath: String = "/sbin/fsck_msdos",
        privilegedRunner: DiskCheckCommandRunning? = nil,
        updateIntervalNanoseconds: UInt64 = 250_000_000
    ) {
        self.runner = runner
        self.diskutilPath = diskutilPath
        self.fsckHFSPath = fsckHFSPath
        self.fsckExFATPath = fsckExFATPath
        self.fsckMSDOSPath = fsckMSDOSPath
        self.privilegedRunner = privilegedRunner
            ?? (runner is StreamingDiskCheckCommandRunner
                ? AdministratorDiskCheckCommandRunner()
                : runner)
        self.updateIntervalNanoseconds = updateIntervalNanoseconds
    }

    func cancel() {
        runner.cancel()
        privilegedRunner.cancel()
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
            var mountSession: MountSession?
            if mode == .detailed, let volumeIdentifier = plan.volumeIdentifier {
                switch await prepareDetailedCheck(
                    volumeIdentifier: volumeIdentifier,
                    fallbackVolume: drive.volumes.first(where: { $0.deviceIdentifier == volumeIdentifier }),
                    output: streamedOutput
                ) {
                case let .ready(session):
                    mountSession = session
                case let .failed(status, message):
                    let snapshot = streamedOutput.snapshot
                    updateEntry(
                        entryID,
                        in: &report,
                        terminationStatus: status,
                        stdout: snapshot.stdout,
                        stderr: [snapshot.stderr, message]
                            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            .joined(separator: "\n"),
                        isRunning: false
                    )
                    if let onUpdate {
                        await onUpdate(report)
                    }
                    continue
                }
            }
            let completion = LockedDiskCheckCompletion()
            let commandRunner = requiresAdministrator(executable)
                ? privilegedRunner
                : runner
            let commandTask = Task {
                do {
                    let result = try await commandRunner.run(
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
                        var terminationStatus = commandResult.terminationStatus
                        var snapshot = streamedOutput.snapshot
                        let stdout = snapshot.stdout.isEmpty ? commandResult.stdoutString : snapshot.stdout
                        let stderr = snapshot.stderr.isEmpty ? commandResult.stderrString : snapshot.stderr
                        if let mountSession {
                            let remountResult = await remountVolume(mountSession, output: streamedOutput)
                            if let remountResult, remountResult.terminationStatus != 0, terminationStatus == 0 {
                                terminationStatus = remountResult.terminationStatus
                            } else if remountResult == nil, terminationStatus == 0 {
                                terminationStatus = 1
                            }
                            snapshot = streamedOutput.snapshot
                        }
                        updateEntry(
                            entryID,
                            in: &report,
                            terminationStatus: terminationStatus,
                            stdout: snapshot.stdout.isEmpty ? stdout : snapshot.stdout,
                            stderr: snapshot.stderr.isEmpty ? stderr : snapshot.stderr,
                            isRunning: false
                        )
                    case let .failure(error):
                        let snapshot = streamedOutput.snapshot
                        if let mountSession {
                            _ = await remountVolume(mountSession, output: streamedOutput)
                        }
                        let finalSnapshot = streamedOutput.snapshot
                        updateEntry(
                            entryID,
                            in: &report,
                            terminationStatus: nil,
                            stdout: finalSnapshot.stdout.isEmpty ? snapshot.stdout : finalSnapshot.stdout,
                            stderr: [finalSnapshot.stderr, error.localizedDescription]
                                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                .joined(separator: "\n"),
                            isRunning: false
                        )
                    }
                    break
                }

                if Task.isCancelled {
                    commandRunner.cancel()
                    commandTask.cancel()
                    if let mountSession {
                        _ = await remountVolume(mountSession, output: streamedOutput)
                    }
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

    private func commandPlans(
        for mode: DiskCheckMode,
        drive: DriveDevice
    ) -> [CommandPlan] {
        guard !drive.isNetwork else {
            return [CommandPlan(
                title: "Network Volume",
                executable: nil,
                arguments: [],
                unsupportedMessage: "Network volumes do not expose a local block device for diskutil or fsck checks."
            )]
        }

        guard !drive.isSystemDisk else {
            return [CommandPlan(
                title: "System Disk Check Unavailable",
                executable: nil,
                arguments: [drive.bsdName],
                unsupportedMessage: "System disk checks are unavailable in Capricorn."
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

        for volume in uniqueVolumes(drive.displayableVolumes) {
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
        uniqueVolumes(drive.displayableVolumes).map { volume in
            guard let format = FileSystemFormatResolver.normalized(volume.fileSystemType) else {
                return CommandPlan(
                    title: "Volume: \(volume.name)",
                    executable: nil,
                    arguments: [volume.deviceIdentifier],
                    unsupportedMessage: "No filesystem type is available for selecting a detailed checker."
                )
            }

            if format == "APFS" {
                // diskutil delegates APFS verification to Disk Management, which owns raw-device access.
                return CommandPlan(
                    title: "APFS Volume: \(volume.name)",
                    executable: diskutilPath,
                    arguments: ["verifyVolume", volume.deviceIdentifier],
                    unsupportedMessage: nil
                )
            }

            guard let rawDevice = rawDevicePath(for: volume.deviceIdentifier) else {
                return CommandPlan(
                    title: "Volume: \(volume.name)",
                    executable: nil,
                    arguments: [volume.deviceIdentifier],
                    unsupportedMessage: "Detailed fsck checks require a local disk device identifier."
                )
            }

            switch format {
            case "HFS+":
                return CommandPlan(title: "HFS+ Volume: \(volume.name)", executable: fsckHFSPath, arguments: ["-n", "-x", rawDevice], unsupportedMessage: nil, volumeIdentifier: volume.deviceIdentifier)
            case "ExFAT":
                return CommandPlan(title: "ExFAT Volume: \(volume.name)", executable: fsckExFATPath, arguments: ["-n", "-x", rawDevice], unsupportedMessage: nil, volumeIdentifier: volume.deviceIdentifier)
            case "FAT32", "MS-DOS":
                return CommandPlan(title: "FAT Volume: \(volume.name)", executable: fsckMSDOSPath, arguments: ["-n", rawDevice], unsupportedMessage: nil, volumeIdentifier: volume.deviceIdentifier)
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

    private func prepareDetailedCheck(
        volumeIdentifier: String,
        fallbackVolume: DriveDevice.Volume?,
        output: LockedDiskCheckOutput
    ) async -> DetailedCheckPreparation {
        let infoResult: CommandResult
        do {
            infoResult = try await runner.run(
                diskutilPath,
                arguments: ["info", "-plist", volumeIdentifier],
                stdout: { _ in },
                stderr: { _ in }
            )
        } catch {
            return .failed(
                status: nil,
                message: "Unable to inspect whether the volume is mounted and read-only: \(error.localizedDescription)"
            )
        }

        guard infoResult.terminationStatus == 0,
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: infoResult.stdout,
                  options: [],
                  format: nil
              ) as? [String: Any] else {
            return .failed(
                status: infoResult.terminationStatus,
                message: "Unable to inspect whether the volume is mounted and read-only."
            )
        }

        let isMounted = bool(in: propertyList, keys: ["Mounted"])
            ?? (fallbackVolume?.mountPoint != nil)
        let isReadOnly = readOnly(in: propertyList)
            ?? !(fallbackVolume?.isWritable ?? true)

        output.appendStderr(
            "Preflight: mounted=\(isMounted), read-only=\(isReadOnly).\n"
        )

        guard isMounted else {
            return .ready(mountSession: nil)
        }

        let unmountTarget = string(in: propertyList, keys: ["APFSContainerReference"])
            ?? volumeIdentifier
        let unmountArguments = unmountTarget == volumeIdentifier
            ? ["unmount", volumeIdentifier]
            : ["unmountDisk", unmountTarget]
        guard let result = await runAuxiliary(
            diskutilPath,
            arguments: unmountArguments,
            output: output
        ) else {
            return .failed(
                status: nil,
                message: "The mounted volume could not be unloaded, so the filesystem check was not started."
            )
        }
        guard result.terminationStatus == 0 else {
            return .failed(
                status: result.terminationStatus,
                message: "The mounted volume could not be unloaded, so the filesystem check was not started."
            )
        }

        return .ready(mountSession: MountSession(
            volumeIdentifier: volumeIdentifier,
            isReadOnly: isReadOnly
        ))
    }

    private func remountVolume(
        _ session: MountSession,
        output: LockedDiskCheckOutput
    ) async -> CommandResult? {
        let arguments = session.isReadOnly
            ? ["mount", "readOnly", session.volumeIdentifier]
            : ["mount", session.volumeIdentifier]
        output.appendStderr(
            "Restoring volume mount (read-only=\(session.isReadOnly)).\n"
        )
        return await runAuxiliary(diskutilPath, arguments: arguments, output: output)
    }

    private func runAuxiliary(
        _ executable: String,
        arguments: [String],
        output: LockedDiskCheckOutput
    ) async -> CommandResult? {
        do {
            return try await runner.run(
                executable,
                arguments: arguments,
                stdout: { output.appendStdout($0) },
                stderr: { output.appendStderr($0) }
            )
        } catch {
            output.appendStderr(error.localizedDescription + "\n")
            return nil
        }
    }

    private func string(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func bool(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool { return value }
            if let value = dictionary[key] as? NSNumber { return value.boolValue }
        }
        return nil
    }

    private func readOnly(in dictionary: [String: Any]) -> Bool? {
        if let value = bool(in: dictionary, keys: ["ReadOnly", "ReadOnlyVolume", "ReadOnlyMedia"]) {
            return value
        }
        if let writable = bool(in: dictionary, keys: ["Writable", "WritableVolume"]) {
            return !writable
        }
        return nil
    }

    private func uniqueVolumes(_ volumes: [DriveDevice.Volume]) -> [DriveDevice.Volume] {
        var seen = Set<String>()
        return volumes.filter(RepresentativeVolumeResolver.isVisibleVolume).filter { volume in
            let key = volume.mountPoint ?? volume.deviceIdentifier
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func requiresAdministrator(_ executable: String) -> Bool {
        executable == fsckHFSPath
            || executable == fsckExFATPath
            || executable == fsckMSDOSPath
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
