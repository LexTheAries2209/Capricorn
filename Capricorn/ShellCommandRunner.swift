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

                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                continuation.resume(returning: CommandResult(
                    stdout: stdoutData,
                    stderr: stderrData,
                    terminationStatus: process.terminationStatus
                ))
            }
        }
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
        case .inspectOpenFiles, .revealInFinder, .refresh:
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
