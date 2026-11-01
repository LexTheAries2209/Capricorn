// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation
import ServiceManagement

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
    case deviceService = "Disable the device service in Settings before updating"
}

struct AppUpdateBlockedError: Error, Equatable {
    let conflicts: [AppUpdateConflict]
}

/// Installation reserves the app before Sparkle can request termination.
/// A rejected attempt is never resumed automatically after tasks finish.
@MainActor
@Observable
final class AppUpdateSafetyGate {
    private let conflicts: () -> [AppUpdateConflict]
    private let reserve: () -> Void
    private let release: () -> Void
    private let save: () throws -> Void
    private let deviceServiceEnabled: () -> Bool
    private(set) var isReserved = false

    init(
        conflicts: @escaping () -> [AppUpdateConflict],
        reserve: @escaping () -> Void = {},
        release: @escaping () -> Void = {},
        save: @escaping () throws -> Void = {},
        deviceServiceEnabled: @escaping () -> Bool = {
            let status = SMAppService.daemon(plistName: DeviceHelperIdentity.plistName).status
            return status == .enabled || status == .requiresApproval
        }
    ) {
        self.conflicts = conflicts
        self.reserve = reserve
        self.release = release
        self.save = save
        self.deviceServiceEnabled = deviceServiceEnabled
    }

    func check() throws {
        var current = conflicts().filter { !isReserved || $0 != .installation }
        // Do not replace a bundle while its root helper holds an older signed
        // snapshot. The user can safely stop it in Settings and re-enable after.
        if deviceServiceEnabled(), !current.contains(.deviceService) { current.append(.deviceService) }
        guard current.isEmpty else { throw AppUpdateBlockedError(conflicts: current) }
    }

    func beginInstallation() throws {
        try check()
        if !isReserved {
            reserve()
            isReserved = true
        }
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
