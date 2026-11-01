// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin
import OSLog

let logger = Logger(subsystem: "lex.Capricorn", category: "DeviceHelper")

do {
    guard geteuid() == 0 else {
        throw DeviceHelperError.rejected("The device service must be started by launchd as root.")
    }
    let team = try DeviceHelperSigning.ownTeam()
    let app = try DeviceHelperSigning.containingApp()
    try DeviceHelperSigning.verify(url: app, identifier: DeviceHelperIdentity.appIdentifier, team: team)
    let delegate = DeviceHelperListener(appURL: app, team: team, installation: try DeviceHelperSigning.codeIdentity(app))
    let listener = NSXPCListener(machServiceName: DeviceHelperIdentity.service)
    listener.setConnectionCodeSigningRequirement(delegate.requirement)
    listener.delegate = delegate
    listener.activate()
    logger.notice("Signed device service is listening as root.")
    withExtendedLifetime((listener, delegate)) { RunLoop.current.run() }
} catch {
    logger.error("Device service startup failed: \(error.localizedDescription, privacy: .public)")
    fputs("CapricornDeviceHelper: \(error.localizedDescription)\n", stderr)
    exit(1)
}
