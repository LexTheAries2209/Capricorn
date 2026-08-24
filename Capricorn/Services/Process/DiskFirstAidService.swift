// SPDX-License-Identifier: GPL-3.0-only
import Foundation

protocol DiskFirstAidRunning: Sendable {
    func prepare(drive: DriveDevice, health: HealthStatus) async throws -> DiskFirstAidPlan
    func run(_ plan: DiskFirstAidPlan) -> AsyncThrowingStream<DiskFirstAidEvent, Error>
    func requestStopAfterCurrent() async
}

protocol DiskFirstAidCommandRunning: AnyObject, Sendable {
    func run(
        _ executable: String,
        arguments: [String],
        stdout: @escaping @Sendable (String) -> Void,
        stderr: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult
}

extension StreamingDiskCheckCommandRunner: DiskFirstAidCommandRunning {}

enum DiskFirstAidServiceError: Error, LocalizedError {
    case invalidPreflight(String)
    case identityChanged(String)

    var errorDescription: String? {
        switch self {
        case let .invalidPreflight(message):
            message
        case let .identityChanged(message):
            message
        }
    }
}

final class DiskFirstAidService: DiskFirstAidRunning, @unchecked Sendable {
    private struct DiskInfo {
        var deviceIdentifier: String?
        var volumeUUID: String?
        var parentWholeDisk: String?
        var fileSystemType: String?
        var mountPoint: String?
        var isMounted: Bool?
        var isWritable: Bool?
        var isLocked: Bool
    }

    private let commandRunner: DiskFirstAidCommandRunning
    private let infoRunner: CommandRunning
    private let diskutilPath: String
    private let stopState = LockedState(false)

    init(
        commandRunner: DiskFirstAidCommandRunning = StreamingDiskCheckCommandRunner(),
        infoRunner: CommandRunning = ShellCommandRunner(),
        diskutilPath: String = "/usr/sbin/diskutil"
    ) {
        self.commandRunner = commandRunner
        self.infoRunner = infoRunner
        self.diskutilPath = diskutilPath
    }

    func prepare(drive: DriveDevice, health: HealthStatus) async throws -> DiskFirstAidPlan {
        let driveBlock = blockReason(for: drive, health: health)
        var targets: [DiskFirstAidTarget] = []

        for volume in uniqueVolumes(drive.displayableVolumes) {
            let target = await makeTarget(volume: volume, drive: drive, driveBlock: driveBlock)
            targets.append(target)
        }

        let blockedReason: DiskFirstAidBlockReason?
        if driveBlock != nil {
            blockedReason = driveBlock
        } else if !targets.contains(where: { $0.isEligible }) {
            blockedReason = .noEligibleVolumes
        } else {
            blockedReason = nil
        }

        return DiskFirstAidPlan(
            driveID: drive.id,
            driveName: drive.displayName,
            physicalDiskIdentifier: drive.bsdName,
            health: health,
            targets: targets,
            blockedReason: blockedReason,
            requiresHealthWarningConfirmation: health == .warning
        )
    }

    func run(_ plan: DiskFirstAidPlan) -> AsyncThrowingStream<DiskFirstAidEvent, Error> {
        stopState.withLock { $0 = false }
        return AsyncThrowingStream { continuation in
            _ = Task.detached(priority: .userInitiated) { [self] in
                await execute(plan, continuation: continuation)
            }
        }
    }

    func requestStopAfterCurrent() async {
        stopState.withLock { $0 = true }
    }

    private func execute(
        _ plan: DiskFirstAidPlan,
        continuation: AsyncThrowingStream<DiskFirstAidEvent, Error>.Continuation
    ) async {
        let selectedTargets = plan.selectedTargets
        var results: [DiskFirstAidTargetResult] = []

        for (index, target) in selectedTargets.enumerated() {
            if stopState.snapshot() {
                appendSkippedTargets(
                    selectedTargets.dropFirst(index),
                    to: &results,
                    plan: plan,
                    startIndex: index,
                    continuation: continuation
                )
                break
            }

            continuation.yield(.targetStarted(
                runID: plan.id,
                target: target,
                index: index,
                total: selectedTargets.count
            ))

            do {
                try await validateIdentity(target, parentWholeDisk: plan.physicalDiskIdentifier)
                let output = LockedState((stdout: "", stderr: ""))
                let result = try await commandRunner.run(
                    diskutilPath,
                    arguments: ["repairVolume", target.deviceIdentifier],
                    stdout: { text in
                        output.withLock { $0.stdout += text }
                        continuation.yield(.output(runID: plan.id, targetID: target.id, stream: .stdout, text: text))
                    },
                    stderr: { text in
                        output.withLock { $0.stderr += text }
                        continuation.yield(.output(runID: plan.id, targetID: target.id, stream: .stderr, text: text))
                    }
                )
                let captured = output.snapshot()
                let targetResult = DiskFirstAidTargetResult(
                    id: target.id,
                    target: target,
                    outcome: result.terminationStatus == 0 ? .succeeded : .failed,
                    terminationStatus: result.terminationStatus,
                    stdout: result.stdoutString.isEmpty ? captured.stdout : result.stdoutString,
                    stderr: result.stderrString.isEmpty ? captured.stderr : result.stderrString
                )
                results.append(targetResult)
                continuation.yield(.targetFinished(
                    runID: plan.id,
                    result: targetResult,
                    index: index,
                    total: selectedTargets.count
                ))

                if targetResult.outcome == .failed || stopState.snapshot() {
                    appendSkippedTargets(
                        selectedTargets.dropFirst(index + 1),
                        to: &results,
                        plan: plan,
                        startIndex: index + 1,
                        continuation: continuation
                    )
                    break
                }
            } catch {
                let targetResult = DiskFirstAidTargetResult(
                    id: target.id,
                    target: target,
                    outcome: .failed,
                    terminationStatus: nil,
                    stdout: "",
                    stderr: error.localizedDescription
                )
                results.append(targetResult)
                continuation.yield(.targetFinished(
                    runID: plan.id,
                    result: targetResult,
                    index: index,
                    total: selectedTargets.count
                ))
                appendSkippedTargets(
                    selectedTargets.dropFirst(index + 1),
                    to: &results,
                    plan: plan,
                    startIndex: index + 1,
                    continuation: continuation
                )
                break
            }
        }

        let report = DiskFirstAidReport(
            id: plan.id,
            driveID: plan.driveID,
            driveName: plan.driveName,
            capturedAt: Date(),
            results: results
        )
        continuation.yield(.completed(runID: plan.id, report: report))
        continuation.finish()
    }

    private func appendSkippedTargets(
        _ targets: ArraySlice<DiskFirstAidTarget>,
        to results: inout [DiskFirstAidTargetResult],
        plan: DiskFirstAidPlan,
        startIndex: Int,
        continuation: AsyncThrowingStream<DiskFirstAidEvent, Error>.Continuation
    ) {
        for (offset, target) in targets.enumerated() {
            let targetResult = DiskFirstAidTargetResult(
                id: target.id,
                target: target,
                outcome: .skipped,
                terminationStatus: nil,
                stdout: "",
                stderr: "Stopped before this volume was started."
            )
            results.append(targetResult)
            continuation.yield(.targetFinished(
                runID: plan.id,
                result: targetResult,
                index: startIndex + offset,
                total: plan.selectedTargets.count
            ))
        }
    }

    private func blockReason(for drive: DriveDevice, health: HealthStatus) -> DiskFirstAidBlockReason? {
        if drive.isNetwork { return .networkVolume }
        if drive.isVirtual { return .virtualDisk }
        if drive.isSystemDisk { return .systemDisk }
        if drive.isInternal && !drive.isRemovable { return .internalDisk }
        if health == .preFail || health == .failed { return .unhealthyMedia }
        return nil
    }

    private func makeTarget(
        volume: DriveDevice.Volume,
        drive: DriveDevice,
        driveBlock: DiskFirstAidBlockReason?
    ) async -> DiskFirstAidTarget {
        let identifier = normalizedDeviceIdentifier(volume.deviceIdentifier)
        let info = await loadInfo(for: identifier)
        let format = FileSystemFormatResolver.normalized(info?.fileSystemType ?? volume.fileSystemType)
        let mountPoint = info?.mountPoint ?? volume.mountPoint
        let isSystem = volume.isSystem || mountPoint == "/" || mountPoint?.hasPrefix("/System/Volumes") == true
        let isWritable = info?.isWritable ?? (drive.isWritable && volume.isWritable)
        let isLocked = info?.isLocked ?? false

        let support: DiskFirstAidTargetSupport
        if let driveBlock {
            support = targetSupport(for: driveBlock)
        } else if isSystem {
            support = .systemVolume
        } else if identifier.isEmpty {
            support = .missingDevice
        } else if isLocked {
            support = .locked
        } else if !isWritable {
            support = .readOnly
        } else {
            switch format {
            case "APFS", "ExFAT":
                support = info == nil ? .preflightFailed : .eligible
            case "NTFS":
                support = .ntfsRequiresWindows
            default:
                support = .unsupportedFormat
            }
        }

        return DiskFirstAidTarget(
            deviceIdentifier: identifier,
            volumeUUID: info?.volumeUUID,
            parentWholeDisk: info?.parentWholeDisk ?? drive.bsdName,
            volumeName: volume.name,
            fileSystemType: format,
            mountPoint: mountPoint,
            sizeBytes: volume.sizeBytes,
            isMounted: mountedState(info: info, fallback: mountPoint != nil),
            isWritable: isWritable,
            isLocked: isLocked,
            isSystem: isSystem,
            support: support
        )
    }

    private func targetSupport(for reason: DiskFirstAidBlockReason) -> DiskFirstAidTargetSupport {
        switch reason {
        case .networkVolume: .networkVolume
        case .virtualDisk: .virtualDisk
        case .internalDisk: .internalDisk
        case .systemDisk: .systemVolume
        case .unhealthyMedia: .preflightFailed
        case .noEligibleVolumes: .preflightFailed
        }
    }

    private func validateIdentity(_ target: DiskFirstAidTarget, parentWholeDisk: String) async throws {
        guard let info = await loadInfo(for: target.deviceIdentifier) else {
            throw DiskFirstAidServiceError.identityChanged("The disk information could not be refreshed before First Aid.")
        }
        guard let identifier = info.deviceIdentifier,
              normalizedDeviceIdentifier(identifier) == target.deviceIdentifier else {
            throw DiskFirstAidServiceError.identityChanged("The volume identifier changed before First Aid started.")
        }
        if let expectedUUID = target.volumeUUID,
           info.volumeUUID != expectedUUID {
            throw DiskFirstAidServiceError.identityChanged("The volume UUID changed before First Aid started.")
        }
        if !parentWholeDisk.isEmpty,
           info.parentWholeDisk != parentWholeDisk {
            throw DiskFirstAidServiceError.identityChanged("The volume is no longer attached to the selected physical disk.")
        }
        if let expectedFormat = target.fileSystemType,
           FileSystemFormatResolver.normalized(info.fileSystemType) != expectedFormat {
            throw DiskFirstAidServiceError.identityChanged("The volume format changed before First Aid started.")
        }
        if info.isLocked {
            throw DiskFirstAidServiceError.invalidPreflight("Unlock the volume before running First Aid.")
        }
        if info.isWritable == false {
            throw DiskFirstAidServiceError.invalidPreflight("The volume or media is read-only and cannot be repaired.")
        }
    }

    private func loadInfo(for identifier: String) async -> DiskInfo? {
        guard !identifier.isEmpty else { return nil }
        do {
            let result = try await infoRunner.run(diskutilPath, arguments: ["info", "-plist", identifier])
            guard result.terminationStatus == 0,
                  let propertyList = try PropertyListSerialization.propertyList(from: result.stdout, options: [], format: nil) as? [String: Any] else {
                return nil
            }
            return DiskInfo(
                deviceIdentifier: string(in: propertyList, keys: ["DeviceIdentifier"]),
                volumeUUID: string(in: propertyList, keys: ["VolumeUUID", "APFSVolumeUUID"]),
                parentWholeDisk: string(in: propertyList, keys: ["ParentWholeDisk"]),
                fileSystemType: string(in: propertyList, keys: ["FilesystemName", "FileSystemName", "FilesystemType", "FileSystemType", "FileSystemPersonality"]),
                mountPoint: string(in: propertyList, keys: ["MountPoint"]),
                isMounted: bool(in: propertyList, keys: ["Mounted"]),
                isWritable: writable(in: propertyList),
                isLocked: bool(in: propertyList, keys: ["Locked", "APFSVolumeLocked"]) ?? false
            )
        } catch {
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

    private func writable(in dictionary: [String: Any]) -> Bool? {
        if let value = bool(in: dictionary, keys: ["Writable", "WritableVolume"]) {
            return value
        }
        if let readOnly = bool(in: dictionary, keys: ["ReadOnly", "ReadOnlyVolume", "ReadOnlyMedia"]) {
            return !readOnly
        }
        return nil
    }

    private func mountedState(info: DiskInfo?, fallback: Bool) -> Bool {
        guard let info, let isMounted = info.isMounted else { return fallback }
        return isMounted
    }

    private func normalizedDeviceIdentifier(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/dev/") {
            return String(trimmed.dropFirst("/dev/".count))
        }
        return trimmed
    }

    private func uniqueVolumes(_ volumes: [DriveDevice.Volume]) -> [DriveDevice.Volume] {
        var seen = Set<String>()
        return volumes.filter(RepresentativeVolumeResolver.isVisibleVolume).filter { volume in
            let key = normalizedDeviceIdentifier(volume.deviceIdentifier)
            guard !key.isEmpty, seen.insert(key).inserted else { return false }
            return true
        }
    }
}
