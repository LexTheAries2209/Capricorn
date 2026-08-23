// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import OSLog

struct DriveRefreshSnapshot: Sendable {
    var drives: [DriveDevice]
    var snapshots: [String: SmartSnapshot]
    var externalSupport: ExternalSupportStatus
}

enum DriveSnapshotUpdatePhase: Sendable, Equatable {
    case native
    case complete
}

struct DriveSnapshotUpdate: Sendable {
    var driveID: String
    var snapshot: SmartSnapshot
    var phase: DriveSnapshotUpdatePhase
}

protocol DriveRefreshing: Sendable {
    func discover(showVirtual: Bool) async throws -> DriveRefreshSnapshot
    func snapshotUpdates(for drives: [DriveDevice]) async -> AsyncStream<DriveSnapshotUpdate>
}

extension DriveRefreshing {
    func refresh(showVirtual: Bool) async throws -> DriveRefreshSnapshot {
        var discovery = try await discover(showVirtual: showVirtual)
        let updates = await snapshotUpdates(for: discovery.drives)
        for await update in updates {
            discovery.snapshots[update.driveID] = update.snapshot
        }
        return discovery
    }
}

actor DriveRefreshService: DriveRefreshing {
    private let inventoryProvider: DiskInventoryProviding
    private let smartService: SmartSnapshotService
    private let externalDetector: ExternalDriveSupportDetector
    private let maximumConcurrentSnapshots: Int

    init(
        inventoryProvider: DiskInventoryProviding = DiskutilInventoryProvider(),
        smartService: SmartSnapshotService = SmartSnapshotService(),
        externalDetector: ExternalDriveSupportDetector = ExternalDriveSupportDetector(),
        maximumConcurrentSnapshots: Int = 2
    ) {
        self.inventoryProvider = inventoryProvider
        self.smartService = smartService
        self.externalDetector = externalDetector
        self.maximumConcurrentSnapshots = max(1, maximumConcurrentSnapshots)
    }

    func discover(showVirtual: Bool) async throws -> DriveRefreshSnapshot {
        let interval = CapricornLog.inventorySignposter.beginInterval("Drive refresh")
        defer { CapricornLog.inventorySignposter.endInterval("Drive refresh", interval) }
        CapricornLog.inventory.info("Drive refresh started")
        let drives = try await inventoryProvider.loadDrives(showVirtual: showVirtual)
        let snapshot = DriveRefreshSnapshot(
            drives: drives,
            snapshots: Dictionary(uniqueKeysWithValues: drives.map { ($0.id, SmartSnapshot.refreshingNative(for: $0)) }),
            externalSupport: externalDetector.detect()
        )
        CapricornLog.inventory.info("Drive discovery completed with \(drives.count) drives")
        return snapshot
    }

    func snapshotUpdates(for drives: [DriveDevice]) async -> AsyncStream<DriveSnapshotUpdate> {
        let smartService = smartService
        let maximumConcurrentSnapshots = maximumConcurrentSnapshots
        let prioritizedDrives = Self.prioritized(drives)

        return AsyncStream { continuation in
            let task = Task {
                var nativeSnapshots: [String: SmartSnapshot] = [:]
                await withTaskGroup(of: (DriveDevice, SmartSnapshot).self) { group in
                    var iterator = prioritizedDrives.makeIterator()
                    for _ in 0..<min(maximumConcurrentSnapshots, prioritizedDrives.count) {
                        guard let drive = iterator.next() else { break }
                        group.addTask {
                            (drive, await smartService.nativeSnapshot(for: drive))
                        }
                    }

                    while let (drive, snapshot) = await group.next() {
                        guard !Task.isCancelled else { break }
                        nativeSnapshots[drive.id] = snapshot
                        continuation.yield(DriveSnapshotUpdate(
                            driveID: drive.id,
                            snapshot: snapshot,
                            phase: .native
                        ))
                        if let drive = iterator.next() {
                            group.addTask {
                                (drive, await smartService.nativeSnapshot(for: drive))
                            }
                        }
                    }
                }

                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                let smartctlTargets = await smartService.resolvedSmartctlTargetDescriptors(for: prioritizedDrives)
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                await withTaskGroup(of: (DriveDevice, SmartSnapshot).self) { group in
                    var iterator = prioritizedDrives.makeIterator()
                    for _ in 0..<min(maximumConcurrentSnapshots, prioritizedDrives.count) {
                        guard let drive = iterator.next(), let native = nativeSnapshots[drive.id] else { break }
                        group.addTask {
                            return (
                                drive,
                                await smartService.snapshot(
                                    for: drive,
                                    nativeSnapshot: native,
                                    smartctlTargetDescriptor: smartctlTargets[drive.id]
                                )
                            )
                        }
                    }

                    while let (drive, snapshot) = await group.next() {
                        guard !Task.isCancelled else { break }
                        continuation.yield(DriveSnapshotUpdate(
                            driveID: drive.id,
                            snapshot: snapshot,
                            phase: .complete
                        ))
                        if let drive = iterator.next(), let native = nativeSnapshots[drive.id] {
                            group.addTask {
                                return (
                                    drive,
                                    await smartService.snapshot(
                                        for: drive,
                                        nativeSnapshot: native,
                                        smartctlTargetDescriptor: smartctlTargets[drive.id]
                                    )
                                )
                            }
                        }
                    }
                }

                CapricornLog.inventory.info("SMART refresh completed for \(nativeSnapshots.count) drives")
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func prioritized(_ drives: [DriveDevice]) -> [DriveDevice] {
        drives.sorted { lhs, rhs in
            let lhsPriority = priority(for: lhs)
            let rhsPriority = priority(for: rhs)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.bsdName.localizedStandardCompare(rhs.bsdName) == .orderedAscending
        }
    }

    private static func priority(for drive: DriveDevice) -> Int {
        if drive.isSystemDisk { return 0 }
        if drive.isSolidState { return 1 }
        if drive.isNetwork || drive.isMemoryCard { return 3 }
        return 2
    }
}
