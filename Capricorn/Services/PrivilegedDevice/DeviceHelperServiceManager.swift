// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation
import ServiceManagement

@MainActor
protocol DeviceHelperRegistering {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

@MainActor
private struct SystemDeviceHelperRegistration: DeviceHelperRegistering {
    private var service: SMAppService { .daemon(plistName: DeviceHelperIdentity.plistName) }
    var status: SMAppService.Status { service.status }
    func register() throws { try service.register() }
    func unregister() async throws { try await service.unregister() }
}

@MainActor
@Observable
final class DeviceHelperServiceManager: DeviceServiceUpdateCoordinating {
    static let shared = DeviceHelperServiceManager()
    static let updateReceiptKey = "deviceHelper.pendingUpdateRestoration"
    static let approvalMessage = "The device service needs system approval. Review it in Settings."
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var isChanging = false
    private(set) var error: String?
    private let registration: any DeviceHelperRegistering
    private let defaults: UserDefaults
    private let validateInstallation: () throws -> String
    private let stop: () async throws -> Void
    private let cancelStop: () async throws -> Void
    private let checkConnection: () async throws -> Void

    private struct UpdateReceipt: Codable {
        enum Phase: String, Codable { case preparing, stopped }
        var phase: Phase
        let team: String
    }

    init(
        registration: (any DeviceHelperRegistering)? = nil,
        defaults: UserDefaults = .standard,
        validateInstallation: @escaping () throws -> String = {
            try DeviceHelperLocation.validate(Bundle.main.bundleURL)
            let team = try DeviceHelperSigning.ownTeam()
            try DeviceHelperSigning.verify(url: Bundle.main.bundleURL, identifier: DeviceHelperIdentity.appIdentifier,
                                           team: team, nested: true)
            return team
        },
        stop: @escaping () async throws -> Void = { try await DeviceHelperClient.prepareToStop() },
        cancelStop: @escaping () async throws -> Void = { try await DeviceHelperClient.cancelStop() },
        checkConnection: @escaping () async throws -> Void = { try await DeviceHelperClient.checkConnection() }
    ) {
        self.registration = registration ?? SystemDeviceHelperRegistration()
        self.defaults = defaults
        self.validateInstallation = validateInstallation
        self.stop = stop
        self.cancelStop = cancelStop
        self.checkConnection = checkConnection
    }

    var requiresPreparation: Bool { isChanging || registration.status == .enabled }
    var requiresRestoration: Bool { defaults.data(forKey: Self.updateReceiptKey) != nil }
    func refresh() {
        status = registration.status
        if status == .enabled, error == Self.approvalMessage { error = nil }
    }

    func enable() {
        guard !isChanging else { return }
        isChanging = true
        defer { isChanging = false; refresh() }
        error = nil
        do {
            _ = try validateInstallation()
            clearReceipt()
            if registration.status != .enabled && registration.status != .requiresApproval { try registration.register() }
            if registration.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            if registration.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            else { self.error = error.localizedDescription }
        }
    }

    func disable() async {
        guard !isChanging else { return }
        isChanging = true
        defer { isChanging = false; refresh() }
        error = nil
        var prepared = false
        do {
            if registration.status == .enabled {
                try await stop()
                prepared = true
            }
            try await registration.unregister()
            clearReceipt()
        }
        catch {
            if prepared, registration.status == .enabled { try? await cancelStop() }
            self.error = error.localizedDescription
        }
    }

    func prepareForUpdate() async throws {
        guard !isChanging else { throw DeviceHelperError.rejected("The device service is busy. Wait for its current operation to complete.") }
        guard registration.status == .enabled else { return }
        isChanging = true
        defer { isChanging = false; refresh() }
        let team = try validateInstallation()
        // Journal before stopping, so a crash between unregister and app
        // replacement can be recovered by either the old or the new app.
        try writeReceipt(UpdateReceipt(phase: .preparing, team: team))
        var prepared = false
        do {
            try await stop()
            prepared = true
            try await registration.unregister()
            try writeReceipt(UpdateReceipt(phase: .stopped, team: team))
        } catch {
            let failure = error
            if registration.status == .enabled {
                if prepared { try await cancelStop() }
                clearReceipt()
            }
            throw failure
        }
    }

    func restoreAfterUpdate() async {
        guard !isChanging, let data = defaults.data(forKey: Self.updateReceiptKey) else { return }
        isChanging = true
        defer { isChanging = false; refresh() }
        error = nil
        do {
            let receipt = try JSONDecoder().decode(UpdateReceipt.self, from: data)
            guard try validateInstallation() == receipt.team else {
                throw DeviceHelperError.rejected("The device service signing team changed. Enable it explicitly in Settings.")
            }
            switch registration.status {
            case .requiresApproval:
                // System revocation takes priority over a saved update intent.
                clearReceipt()
                error = Self.approvalMessage
                return
            case .enabled:
                if receipt.phase == .preparing { try await cancelStop() }
            case .notRegistered, .notFound:
                do { try registration.register() }
                catch {
                    if registration.status != .requiresApproval { throw error }
                }
            @unknown default:
                throw DeviceHelperError.rejected("Device Service Unavailable")
            }
            if registration.status == .requiresApproval {
                clearReceipt()
                error = Self.approvalMessage
                return
            }
            guard registration.status == .enabled else {
                throw DeviceHelperError.rejected("Device Service Unavailable")
            }
            try await checkConnection()
            clearReceipt()
        } catch { self.error = error.localizedDescription }
    }

    private func writeReceipt(_ receipt: UpdateReceipt) throws {
        defaults.set(try JSONEncoder().encode(receipt), forKey: Self.updateReceiptKey)
        // Only update transitions need to survive immediate process termination.
        guard defaults.synchronize() else {
            throw DeviceHelperError.rejected("Unable to save the device service update state.")
        }
    }

    private func clearReceipt() {
        defaults.removeObject(forKey: Self.updateReceiptKey)
        defaults.synchronize()
    }
}
