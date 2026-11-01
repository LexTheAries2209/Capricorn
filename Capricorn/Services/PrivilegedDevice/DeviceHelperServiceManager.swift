// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class DeviceHelperServiceManager {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var isChanging = false
    private(set) var error: String?

    private var service: SMAppService { .daemon(plistName: DeviceHelperIdentity.plistName) }
    func refresh() { status = service.status }

    func enable() {
        guard !isChanging else { return }
        isChanging = true
        defer { isChanging = false; refresh() }
        error = nil
        do {
            let team = try DeviceHelperSigning.ownTeam()
            guard Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications" else {
                throw DeviceHelperError.rejected("Install the signed Capricorn application in /Applications before enabling the device service.")
            }
            try DeviceHelperSigning.verify(url: Bundle.main.bundleURL, identifier: DeviceHelperIdentity.appIdentifier,
                                           team: team, nested: true)
            if service.status != .enabled && service.status != .requiresApproval { try service.register() }
            if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = error.localizedDescription }
    }

    func disable() async {
        guard !isChanging else { return }
        isChanging = true
        defer { isChanging = false; refresh() }
        error = nil
        var prepared = false
        do {
            if service.status == .enabled {
                try await DeviceHelperClient.prepareToStop()
                prepared = true
            }
            try await service.unregister()
        }
        catch {
            if prepared, service.status == .enabled { try? await DeviceHelperClient.cancelStop() }
            self.error = error.localizedDescription
        }
    }
}
