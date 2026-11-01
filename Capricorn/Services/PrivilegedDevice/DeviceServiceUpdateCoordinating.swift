// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@MainActor
protocol DeviceServiceUpdateCoordinating: AnyObject {
    var requiresPreparation: Bool { get }
    var requiresRestoration: Bool { get }
    func prepareForUpdate() async throws
    func restoreAfterUpdate() async
}

@MainActor
final class NoDeviceServiceUpdates: DeviceServiceUpdateCoordinating {
    var requiresPreparation: Bool { false }
    var requiresRestoration: Bool { false }
    func prepareForUpdate() async throws {}
    func restoreAfterUpdate() async {}
}
