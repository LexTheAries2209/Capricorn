// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import Capricorn

final class DiskFirstAidTests: XCTestCase {
    func testPrepareAllowsOnlyExternalAPFSAndExFATVolumes() async throws {
        let infoRunner = FirstAidInfoRunner(infos: [
            "disk9s1": Self.info(identifier: "disk9s1", format: "APFS", uuid: "APFS-UUID"),
            "disk9s2": Self.info(identifier: "disk9s2", format: "ExFAT", uuid: "EXFAT-UUID"),
            "disk9s3": Self.info(identifier: "disk9s3", format: "NTFS", uuid: "NTFS-UUID")
        ])
        let service = DiskFirstAidService(commandRunner: FirstAidStreamingRunner(), infoRunner: infoRunner)
        var drive = Self.drive()
        drive.volumes = [
            Self.volume("disk9s1", name: "APFS", format: "APFS"),
            Self.volume("disk9s2", name: "Exchange", format: "ExFAT"),
            Self.volume("disk9s3", name: "Windows", format: "NTFS", isWritable: false)
        ]

        let plan = try await service.prepare(drive: drive, health: .good)

        XCTAssertNil(plan.blockedReason)
        XCTAssertTrue(plan.selectedTargetIDs.isEmpty)
        XCTAssertEqual(plan.targets.map(\.support), [.eligible, .eligible, .ntfsRequiresWindows])
        XCTAssertEqual(plan.eligibleTargets.map(\.deviceIdentifier), ["disk9s1", "disk9s2"])
        XCTAssertEqual(infoRunner.calls.map(\.arguments), [
            ["info", "-plist", "disk9s1"],
            ["info", "-plist", "disk9s2"],
            ["info", "-plist", "disk9s3"]
        ])
    }

    func testPrepareBlocksUnsafeDriveAndVolumeStates() async throws {
        let infoRunner = FirstAidInfoRunner(infos: [
            "disk9s1": Self.info(identifier: "disk9s1", format: "APFS", uuid: "A", writable: false),
            "disk9s2": Self.info(identifier: "disk9s2", format: "ExFAT", uuid: "B", locked: true)
        ])
        let service = DiskFirstAidService(commandRunner: FirstAidStreamingRunner(), infoRunner: infoRunner)
        var drive = Self.drive()
        drive.volumes = [
            Self.volume("disk9s1", name: "Read Only", format: "APFS"),
            Self.volume("disk9s2", name: "Locked", format: "ExFAT")
        ]

        let plan = try await service.prepare(drive: drive, health: .warning)
        XCTAssertEqual(plan.blockedReason, .noEligibleVolumes)
        XCTAssertTrue(plan.requiresHealthWarningConfirmation)
        XCTAssertEqual(plan.targets.map(\.support), [.readOnly, .locked])

        drive.isInternal = true
        drive.isRemovable = false
        let internalPlan = try await service.prepare(drive: drive, health: .good)
        XCTAssertEqual(internalPlan.blockedReason, .internalDisk)
        XCTAssertTrue(internalPlan.targets.allSatisfy { $0.support == .internalDisk })

        drive.isInternal = false
        let failingPlan = try await service.prepare(drive: drive, health: .failed)
        XCTAssertEqual(failingPlan.blockedReason, .unhealthyMedia)
        XCTAssertFalse(failingPlan.targets.contains(where: \.isEligible))
    }

    func testPrepareBlocksNetworkVirtualAndSystemTargets() async throws {
        let infoRunner = FirstAidInfoRunner(infos: [
            "disk9s1": Self.info(identifier: "disk9s1", format: "APFS", uuid: "A")
        ])
        let service = DiskFirstAidService(commandRunner: FirstAidStreamingRunner(), infoRunner: infoRunner)
        var drive = Self.drive()
        drive.volumes = [Self.volume("disk9s1", name: "APFS", format: "APFS")]

        drive.isNetwork = true
        let networkPlan = try await service.prepare(drive: drive, health: .good)
        XCTAssertEqual(networkPlan.blockedReason, .networkVolume)

        drive.isNetwork = false
        drive.isVirtual = true
        let virtualPlan = try await service.prepare(drive: drive, health: .good)
        XCTAssertEqual(virtualPlan.blockedReason, .virtualDisk)

        drive.isVirtual = false
        drive.isSystemDisk = true
        let systemDiskPlan = try await service.prepare(drive: drive, health: .good)
        XCTAssertEqual(systemDiskPlan.blockedReason, .systemDisk)

        drive.isSystemDisk = false
        drive.volumes[0].isSystem = true
        let systemVolumePlan = try await service.prepare(drive: drive, health: .good)
        XCTAssertEqual(systemVolumePlan.blockedReason, .noEligibleVolumes)
        XCTAssertEqual(systemVolumePlan.targets.first?.support, .systemVolume)
    }

    func testRunUsesOnlyDiskutilRepairVolumeAndStreamsOutput() async throws {
        let infoRunner = FirstAidInfoRunner(infos: [
            "disk9s1": Self.info(identifier: "disk9s1", format: "APFS", uuid: "A"),
            "disk9s2": Self.info(identifier: "disk9s2", format: "ExFAT", uuid: "B")
        ])
        let commandRunner = FirstAidStreamingRunner(stdout: "Checking filesystem\n")
        let service = DiskFirstAidService(commandRunner: commandRunner, infoRunner: infoRunner)
        var plan = Self.plan(targets: [
            Self.target("disk9s1", name: "APFS", format: "APFS", uuid: "A"),
            Self.target("disk9s2", name: "ExFAT", format: "ExFAT", uuid: "B")
        ])
        plan.selectedTargetIDs = ["disk9s1", "disk9s2"]
        var outputEvents: [String] = []
        var report: DiskFirstAidReport?

        for try await event in service.run(plan) {
            switch event {
            case let .output(_, _, _, text):
                outputEvents.append(text)
            case let .completed(_, completedReport):
                report = completedReport
            case .targetStarted, .targetFinished:
                break
            }
        }

        XCTAssertEqual(commandRunner.calls.map(\.executable), ["/usr/sbin/diskutil", "/usr/sbin/diskutil"])
        XCTAssertEqual(commandRunner.calls.map(\.arguments), [
            ["repairVolume", "disk9s1"],
            ["repairVolume", "disk9s2"]
        ])
        let allArguments = commandRunner.calls.flatMap(\.arguments).joined(separator: " ").lowercased()
        for forbidden in ["repairdisk", "erase", "partition", "fsck", "force"] {
            XCTAssertFalse(allArguments.contains(forbidden))
        }
        XCTAssertEqual(outputEvents, ["Checking filesystem\n", "Checking filesystem\n"])
        XCTAssertEqual(report?.results.map(\.outcome), [.succeeded, .succeeded])
    }

    func testIdentityChangeStopsBeforeRepairCommand() async throws {
        let infoRunner = FirstAidInfoRunner(infos: [
            "disk9s1": Self.info(identifier: "disk9s1", format: "APFS", uuid: "CHANGED")
        ])
        let commandRunner = FirstAidStreamingRunner()
        let service = DiskFirstAidService(commandRunner: commandRunner, infoRunner: infoRunner)
        var plan = Self.plan(targets: [
            Self.target("disk9s1", name: "APFS", format: "APFS", uuid: "ORIGINAL")
        ])
        plan.selectedTargetIDs = ["disk9s1"]
        var report: DiskFirstAidReport?

        for try await event in service.run(plan) {
            if case let .completed(_, completedReport) = event {
                report = completedReport
            }
        }

        XCTAssertTrue(commandRunner.calls.isEmpty)
        XCTAssertEqual(report?.results.first?.outcome, .failed)
        XCTAssertTrue(report?.results.first?.stderr.contains("UUID changed") == true)
    }

    func testFormatOrParentChangeStopsBeforeRepairCommand() async throws {
        let infoRunner = FirstAidInfoRunner(infos: [
            "disk9s1": [
                "DeviceIdentifier": "disk9s1",
                "ParentWholeDisk": "disk10",
                "VolumeUUID": "A",
                "FilesystemName": "ExFAT",
                "Mounted": true,
                "Writable": true,
                "Locked": false
            ]
        ])
        let commandRunner = FirstAidStreamingRunner()
        let service = DiskFirstAidService(commandRunner: commandRunner, infoRunner: infoRunner)
        var plan = Self.plan(targets: [
            Self.target("disk9s1", name: "APFS", format: "APFS", uuid: "A")
        ])
        plan.selectedTargetIDs = ["disk9s1"]

        var report: DiskFirstAidReport?
        for try await event in service.run(plan) {
            if case let .completed(_, completedReport) = event {
                report = completedReport
            }
        }

        XCTAssertTrue(commandRunner.calls.isEmpty)
        XCTAssertEqual(report?.results.first?.outcome, .failed)
        XCTAssertTrue(report?.results.first?.stderr.contains("physical disk") == true)
    }

    func testFormatChangeStopsBeforeRepairCommand() async throws {
        let infoRunner = FirstAidInfoRunner(infos: [
            "disk9s1": Self.info(identifier: "disk9s1", format: "ExFAT", uuid: "A")
        ])
        let commandRunner = FirstAidStreamingRunner()
        let service = DiskFirstAidService(commandRunner: commandRunner, infoRunner: infoRunner)
        var plan = Self.plan(targets: [
            Self.target("disk9s1", name: "APFS", format: "APFS", uuid: "A")
        ])
        plan.selectedTargetIDs = ["disk9s1"]

        var report: DiskFirstAidReport?
        for try await event in service.run(plan) {
            if case let .completed(_, completedReport) = event {
                report = completedReport
            }
        }

        XCTAssertTrue(commandRunner.calls.isEmpty)
        XCTAssertEqual(report?.results.first?.outcome, .failed)
        XCTAssertTrue(report?.results.first?.stderr.contains("format changed") == true)
    }

    func testStopRequestFinishesCurrentVolumeAndSkipsRemainingTargets() async throws {
        let infoRunner = FirstAidInfoRunner(infos: [
            "disk9s1": Self.info(identifier: "disk9s1", format: "APFS", uuid: "A"),
            "disk9s2": Self.info(identifier: "disk9s2", format: "ExFAT", uuid: "B")
        ])
        let commandRunner = FirstAidStreamingRunner(delayNanoseconds: 30_000_000)
        let service = DiskFirstAidService(commandRunner: commandRunner, infoRunner: infoRunner)
        var plan = Self.plan(targets: [
            Self.target("disk9s1", name: "APFS", format: "APFS", uuid: "A"),
            Self.target("disk9s2", name: "ExFAT", format: "ExFAT", uuid: "B")
        ])
        plan.selectedTargetIDs = ["disk9s1", "disk9s2"]
        var report: DiskFirstAidReport?

        for try await event in service.run(plan) {
            switch event {
            case .targetStarted(_, _, 0, _):
                await service.requestStopAfterCurrent()
            case let .completed(_, completedReport):
                report = completedReport
            case .targetStarted, .output, .targetFinished:
                break
            }
        }

        XCTAssertEqual(commandRunner.calls.map(\.arguments), [["repairVolume", "disk9s1"]])
        XCTAssertEqual(report?.results.map(\.outcome), [.succeeded, .skipped])
    }

    func testNonZeroExitPreservesPartialResultsAndSkipsRemainingTargets() async throws {
        let infoRunner = FirstAidInfoRunner(infos: [
            "disk9s1": Self.info(identifier: "disk9s1", format: "APFS", uuid: "A"),
            "disk9s2": Self.info(identifier: "disk9s2", format: "ExFAT", uuid: "B"),
            "disk9s3": Self.info(identifier: "disk9s3", format: "APFS", uuid: "C")
        ])
        let commandRunner = FirstAidStreamingRunner(terminationStatuses: [0, 8])
        let service = DiskFirstAidService(commandRunner: commandRunner, infoRunner: infoRunner)
        var plan = Self.plan(targets: [
            Self.target("disk9s1", name: "First", format: "APFS", uuid: "A"),
            Self.target("disk9s2", name: "Second", format: "ExFAT", uuid: "B"),
            Self.target("disk9s3", name: "Third", format: "APFS", uuid: "C")
        ])
        plan.selectedTargetIDs = ["disk9s1", "disk9s2", "disk9s3"]

        var report: DiskFirstAidReport?
        for try await event in service.run(plan) {
            if case let .completed(_, completedReport) = event {
                report = completedReport
            }
        }

        XCTAssertEqual(commandRunner.calls.map(\.arguments), [
            ["repairVolume", "disk9s1"],
            ["repairVolume", "disk9s2"]
        ])
        XCTAssertEqual(report?.results.map(\.outcome), [.succeeded, .failed, .skipped])
        XCTAssertEqual(report?.results.map(\.terminationStatus), [0, 8, nil])
    }

    private static func drive() -> DriveDevice {
        DriveDevice(
            bsdName: "disk9",
            deviceNode: "/dev/disk9",
            displayName: "External Test Disk",
            mediaName: "External Test Disk",
            protocolName: "USB",
            sizeBytes: 2_000,
            blockSize: 512,
            isInternal: false,
            isRemovable: true,
            isSolidState: true,
            isWritable: true,
            isVirtual: false,
            isSystemDisk: false,
            smartStatusRaw: nil,
            nativeSmartKeys: [:],
            volumes: [],
            model: nil,
            serialNumber: nil
        )
    }

    private static func volume(
        _ identifier: String,
        name: String,
        format: String,
        isWritable: Bool = true
    ) -> DriveDevice.Volume {
        DriveDevice.Volume(
            deviceIdentifier: identifier,
            name: name,
            mountPoint: "/Volumes/\(name)",
            sizeBytes: 1_000,
            isWritable: isWritable,
            isSystem: false,
            fileSystemType: format
        )
    }

    private static func target(
        _ identifier: String,
        name: String,
        format: String,
        uuid: String
    ) -> DiskFirstAidTarget {
        DiskFirstAidTarget(
            deviceIdentifier: identifier,
            volumeUUID: uuid,
            parentWholeDisk: "disk9",
            volumeName: name,
            fileSystemType: format,
            mountPoint: "/Volumes/\(name)",
            sizeBytes: 1_000,
            isMounted: true,
            isWritable: true,
            isLocked: false,
            isSystem: false,
            support: .eligible
        )
    }

    private static func plan(targets: [DiskFirstAidTarget]) -> DiskFirstAidPlan {
        DiskFirstAidPlan(
            driveID: "disk9",
            driveName: "External Test Disk",
            physicalDiskIdentifier: "disk9",
            health: .good,
            targets: targets,
            blockedReason: nil,
            requiresHealthWarningConfirmation: false
        )
    }

    private static func info(
        identifier: String,
        format: String,
        uuid: String,
        writable: Bool = true,
        locked: Bool = false
    ) -> [String: Any] {
        [
            "DeviceIdentifier": identifier,
            "ParentWholeDisk": "disk9",
            "VolumeUUID": uuid,
            "FilesystemName": format,
            "MountPoint": "/Volumes/\(identifier)",
            "Mounted": true,
            "Writable": writable,
            "Locked": locked
        ]
    }
}

private final class FirstAidInfoRunner: CommandRunning, @unchecked Sendable {
    struct Call: Sendable {
        var executable: String
        var arguments: [String]
    }

    private let infos: [String: [String: Any]]
    private let recordedCalls = LockedState<[Call]>([])

    init(infos: [String: [String: Any]]) {
        self.infos = infos
    }

    var calls: [Call] {
        recordedCalls.snapshot()
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        recordedCalls.withLock { $0.append(Call(executable: executable, arguments: arguments)) }
        let identifier = arguments.last ?? ""
        guard let info = infos[identifier] else {
            return CommandResult(stdout: Data(), stderr: Data("missing".utf8), terminationStatus: 1)
        }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        return CommandResult(stdout: data, stderr: Data(), terminationStatus: 0)
    }
}

private final class FirstAidStreamingRunner: DiskFirstAidCommandRunning, @unchecked Sendable {
    struct Call: Sendable {
        var executable: String
        var arguments: [String]
    }

    private let recordedCalls = LockedState<[Call]>([])
    private let stdout: String
    private let stderr: String
    private let terminationStatus: Int32
    private let terminationStatuses: [Int32]?
    private let delayNanoseconds: UInt64

    init(
        stdout: String = "",
        stderr: String = "",
        terminationStatus: Int32 = 0,
        terminationStatuses: [Int32]? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.terminationStatus = terminationStatus
        self.terminationStatuses = terminationStatuses
        self.delayNanoseconds = delayNanoseconds
    }

    var calls: [Call] {
        recordedCalls.snapshot()
    }

    func run(
        _ executable: String,
        arguments: [String],
        stdout onStdout: @escaping @Sendable (String) -> Void,
        stderr onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult {
        let callIndex = recordedCalls.withLock { calls -> Int in
            calls.append(Call(executable: executable, arguments: arguments))
            return calls.count - 1
        }
        if !stdout.isEmpty { onStdout(stdout) }
        if !stderr.isEmpty { onStderr(stderr) }
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let status = terminationStatuses.flatMap { statuses in
            statuses.indices.contains(callIndex) ? statuses[callIndex] : nil
        } ?? terminationStatus
        return CommandResult(
            stdout: Data(stdout.utf8),
            stderr: Data(stderr.utf8),
            terminationStatus: status
        )
    }
}
