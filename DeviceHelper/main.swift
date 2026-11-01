// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

do {
    guard geteuid() == 0 else {
        throw DeviceHelperError.rejected("The device service must be started by launchd as root.")
    }
    let team = try DeviceHelperSigning.ownTeam()
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    try DeviceHelperSigning.verify(url: app, identifier: DeviceHelperIdentity.appIdentifier, team: team)
    let delegate = DeviceHelperListener(appURL: app, team: team)
    let listener = NSXPCListener(machServiceName: DeviceHelperIdentity.service)
    listener.setConnectionCodeSigningRequirement(delegate.requirement)
    listener.delegate = delegate
    listener.activate()
    withExtendedLifetime((listener, delegate)) { RunLoop.current.run() }
} catch {
    fputs("CapricornDeviceHelper: \(error.localizedDescription)\n", stderr)
    exit(1)
}
