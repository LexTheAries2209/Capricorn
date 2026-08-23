// SPDX-License-Identifier: GPL-3.0-only
import Foundation
@testable import Capricorn

@MainActor
enum AsyncTestWaiter {
    static func wait(
        timeout: TimeInterval = 1,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        until condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        return await condition()
    }
}

final class SequencedInventoryProvider: DiskInventoryProviding, @unchecked Sendable {
    private struct State {
        var responses: [Response]
        var calls = 0
    }

    struct Response {
        var delayNanoseconds: UInt64
        var drives: [DriveDevice]
    }

    private let state: LockedState<State>

    init(responses: [Response]) {
        state = LockedState(State(responses: responses))
    }

    var callCount: Int {
        state.snapshot().calls
    }

    func loadDrives(showVirtual: Bool) async throws -> [DriveDevice] {
        let response = state.withLock { state -> Response in
            let index = min(state.calls, max(0, state.responses.count - 1))
            defer { state.calls += 1 }
            return state.responses[index]
        }

        if response.delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: response.delayNanoseconds)
        }
        return response.drives
    }
}

struct StaticDriveSerialProvider: DriveSerialNumberProviding {
    var serialNumbersByBSDName: [String: String]

    func serialNumbers(for drives: [DriveDevice]) async -> [String: String] {
        let requestedBSDNames = Set(drives.map(\.bsdName))
        return serialNumbersByBSDName.filter { requestedBSDNames.contains($0.key) }
    }
}

struct UnavailableSmartProvider: SmartProviding {
    let providerName = "Test"

    func snapshot(for drive: DriveDevice) async -> SmartSnapshot? {
        SmartSnapshot.unavailable(for: drive, reason: "Test provider")
    }
}

final class RecordingSmartProvider: SmartProviding, @unchecked Sendable {
    private let driveIDs = LockedState<[String]>([])

    var requestedDriveIDs: [String] {
        driveIDs.snapshot()
    }

    func snapshot(for drive: DriveDevice) async -> SmartSnapshot? {
        driveIDs.withLock { $0.append(drive.id) }
        return SmartSnapshot.unavailable(for: drive, reason: "Recorded")
    }

    let providerName = "Recording"
}

final class ConcurrentDiskutilCommandRunner: CommandRunning, @unchecked Sendable {
    private struct State {
        var activeInfoCalls = 0
        var maximumConcurrentInfoCalls = 0
    }

    private let state = LockedState(State())

    var maximumConcurrentInfoCalls: Int {
        state.snapshot().maximumConcurrentInfoCalls
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        if arguments == ["list", "-plist"] {
            return CommandResult(stdout: Self.listData, stderr: Data(), terminationStatus: 0)
        }
        guard arguments.count == 3, arguments[0] == "info", arguments[1] == "-plist" else {
            return CommandResult(stdout: Data(), stderr: Data(), terminationStatus: 1)
        }

        state.withLock { state in
            state.activeInfoCalls += 1
            state.maximumConcurrentInfoCalls = max(state.maximumConcurrentInfoCalls, state.activeInfoCalls)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        state.withLock { $0.activeInfoCalls -= 1 }

        return CommandResult(
            stdout: Self.infoData(for: arguments[2]),
            stderr: Data(),
            terminationStatus: 0
        )
    }

    private static let listData = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>WholeDisks</key><array><string>disk8</string><string>disk9</string></array>
      <key>AllDisksAndPartitions</key><array>
        <dict><key>DeviceIdentifier</key><string>disk8</string></dict>
        <dict><key>DeviceIdentifier</key><string>disk9</string></dict>
      </array>
    </dict></plist>
    """.utf8)

    private static func infoData(for diskID: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>DeviceIdentifier</key><string>\(diskID)</string>
          <key>DeviceNode</key><string>/dev/\(diskID)</string>
          <key>WholeDisk</key><true/>
          <key>MediaName</key><string>Drive \(diskID)</string>
          <key>BusProtocol</key><string>USB</string>
          <key>TotalSize</key><integer>1000000</integer>
          <key>WritableMedia</key><true/>
        </dict></plist>
        """.utf8)
    }
}

final class CountingSmartctlCommandRunner: CommandRunning, @unchecked Sendable {
    private let scans = LockedState(0)

    var scanCallCount: Int {
        scans.snapshot()
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        if arguments == ["--scan", "--json"] || arguments == ["--scan-open", "--json"] {
            scans.withLock { $0 += 1 }
            let json = """
            {"devices":[
              {"name":"/dev/disk8","type":"nvme","protocol":"NVMe"},
              {"name":"/dev/disk9","type":"sat","protocol":"ATA"}
            ]}
            """
            return CommandResult(stdout: Data(json.utf8), stderr: Data(), terminationStatus: 0)
        }
        return CommandResult(stdout: Data("{}".utf8), stderr: Data(), terminationStatus: 0)
    }
}

final class RestartableLateCallbackWorkloadRunner: DiskActivityWorkloadRunning, @unchecked Sendable {
    private struct State {
        var startedRuns = 0
        var cancellationCount = 0
    }

    private let state = LockedState(State())

    var runCount: Int {
        state.snapshot().startedRuns
    }

    func run(
        configuration: DiskActivityWorkloadConfiguration,
        drive: DriveDevice,
        progress: @escaping @Sendable (DiskActivityWorkloadProgress) -> Void
    ) async throws {
        let runIndex = state.withLock { state -> Int in
            state.startedRuns += 1
            return state.startedRuns
        }

        progress(Self.progress(configuration: configuration, runIndex: runIndex, message: "Run \(runIndex) active"))

        while cancellationCountSnapshot < runIndex {
            if Task.isCancelled {
                break
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        if runIndex == 1 {
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                progress(Self.progress(configuration: configuration, runIndex: runIndex, message: "Late run 1 progress"))
            }
        }
        throw BenchmarkError.cancelled
    }

    func cancel() {
        state.withLock { $0.cancellationCount += 1 }
    }

    private var cancellationCountSnapshot: Int {
        state.snapshot().cancellationCount
    }

    private static func progress(
        configuration: DiskActivityWorkloadConfiguration,
        runIndex: Int,
        message: String
    ) -> DiskActivityWorkloadProgress {
        DiskActivityWorkloadProgress(
            operation: configuration.operation,
            phase: .writing,
            loopIndex: runIndex,
            completedBytes: Int64(runIndex),
            totalBytes: configuration.fileSizeBytes,
            message: message
        )
    }
}
