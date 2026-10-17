// SPDX-License-Identifier: GPL-3.0-only
import AppKit

@MainActor
final class CapricornAppDelegate: NSObject, NSApplicationDelegate {
    weak var updater: AppUpdater?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        updater?.applicationMayTerminate() == false ? .terminateCancel : .terminateNow
    }
}
