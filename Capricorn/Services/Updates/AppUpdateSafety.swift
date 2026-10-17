// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum AppUpdateConflict: String, CaseIterable, Equatable, Sendable {
    case benchmark = "Benchmark"
    case workload = "Large File Workload"
    case monitoring = "Live Activity"
    case diskCheck = "Disk Check"
    case firstAid = "First Aid"
    case selfTest = "SMART Self-Tests"
    case diskCommand = "Disk Actions"
    case diagnostics = "SMART Diagnostics"
    case refresh = "Refresh Disks"
    case installation = "Installing update…"
}

struct AppUpdateBlockedError: Error, Equatable {
    let conflicts: [AppUpdateConflict]
}

/// Installation reserves the app before Sparkle can request termination.
/// A rejected attempt is never resumed automatically after tasks finish.
@MainActor
final class AppUpdateSafetyGate {
    private let conflicts: () -> [AppUpdateConflict]
    private let reserve: () -> Void
    private let release: () -> Void
    private let save: () throws -> Void
    private(set) var isReserved = false

    init(
        conflicts: @escaping () -> [AppUpdateConflict],
        reserve: @escaping () -> Void = {},
        release: @escaping () -> Void = {},
        save: @escaping () throws -> Void = {}
    ) {
        self.conflicts = conflicts
        self.reserve = reserve
        self.release = release
        self.save = save
    }

    func check() throws {
        let current = conflicts().filter { !isReserved || $0 != .installation }
        guard current.isEmpty else { throw AppUpdateBlockedError(conflicts: current) }
    }

    func beginInstallation() throws {
        try check()
        guard !isReserved else { return }
        reserve()
        isReserved = true
        do {
            try save()
        } catch {
            endInstallation()
            throw error
        }
    }

    func endInstallation() {
        guard isReserved else { return }
        isReserved = false
        release()
    }
}
