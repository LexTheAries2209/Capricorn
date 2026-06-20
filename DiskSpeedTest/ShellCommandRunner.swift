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
