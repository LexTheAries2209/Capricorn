// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation

enum BenchmarkSessionState: Sendable, Equatable {
    case idle
    case running
    case stopping
}

enum WorkloadSessionState: Sendable, Equatable {
    case idle
    case running
    case stopping
}

@MainActor
@Observable
final class BenchmarkSessionModel {
    var state: BenchmarkSessionState = .idle
    var progress: BenchmarkProgress?
    var results: [BenchmarkResult] = []
    var error: String?
    var activitySamples: [DiskActivitySample] = []
    var currentActivity: DiskActivitySample?

    var isActive: Bool {
        state != .idle
    }
}

@MainActor
@Observable
final class LiveActivitySessionModel {
    var samples: [DiskActivitySample] = []
    var currentActivity: DiskActivitySample?
    var isMonitoring = false
    var selectedDriveID: String?
    var startedAt: Date?
    var endedAt: Date?
    var error: String?
    var workloadProgress: DiskActivityWorkloadProgress?
    var workloadError: String?
    var workloadState: WorkloadSessionState = .idle

    var isWorkloadActive: Bool {
        workloadState != .idle
    }
}

@MainActor
@Observable
final class DiskOperationsModel {
    var openFileInspection: DiskOpenFileInspection?
    var actionFailure: DiskActionFailure?
    var checkReport: DiskCheckReport?
    var isChecking = false
}
