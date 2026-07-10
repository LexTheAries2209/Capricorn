// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import OSLog

struct DriveRefreshSnapshot: Sendable {
    var drives: [DriveDevice]
    var snapshots: [String: SmartSnapshot]
    var externalSupport: ExternalSupportStatus
}

protocol DriveRefreshing: Sendable {
    func refresh(showVirtual: Bool) async throws -> DriveRefreshSnapshot
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
        maximumConcurrentSnapshots: Int = 4
    ) {
        self.inventoryProvider = inventoryProvider
        self.smartService = smartService
        self.externalDetector = externalDetector
        self.maximumConcurrentSnapshots = max(1, maximumConcurrentSnapshots)
    }

    func refresh(showVirtual: Bool) async throws -> DriveRefreshSnapshot {
        let interval = CapricornLog.inventorySignposter.beginInterval("Drive refresh")
        defer { CapricornLog.inventorySignposter.endInterval("Drive refresh", interval) }
        CapricornLog.inventory.info("Drive refresh started")
        let drives = try await inventoryProvider.loadDrives(showVirtual: showVirtual)
        let targets = await smartService.resolvedSmartctlTargets(for: drives)
        let snapshots = await loadSnapshots(for: drives, smartctlTargets: targets)
        let snapshot = DriveRefreshSnapshot(
            drives: drives,
            snapshots: snapshots,
            externalSupport: externalDetector.detect()
        )
        CapricornLog.inventory.info("Drive refresh completed with \(drives.count) drives")
        return snapshot
    }

    private func loadSnapshots(
        for drives: [DriveDevice],
        smartctlTargets: [String: String]
    ) async -> [String: SmartSnapshot] {
        guard !drives.isEmpty else { return [:] }
        let smartService = smartService
        let maximumConcurrentSnapshots = maximumConcurrentSnapshots

        return await withTaskGroup(of: (String, SmartSnapshot).self) { group in
            var iterator = drives.makeIterator()
            for _ in 0..<min(maximumConcurrentSnapshots, drives.count) {
                guard let drive = iterator.next() else { break }
                group.addTask {
                    (drive.id, await smartService.snapshot(for: drive, smartctlTarget: smartctlTargets[drive.id]))
                }
            }

            var snapshots: [String: SmartSnapshot] = [:]
            while let (driveID, snapshot) = await group.next() {
                snapshots[driveID] = snapshot
                if let drive = iterator.next() {
                    group.addTask {
                        (drive.id, await smartService.snapshot(for: drive, smartctlTarget: smartctlTargets[drive.id]))
                    }
                }
            }
            return snapshots
        }
    }
}
