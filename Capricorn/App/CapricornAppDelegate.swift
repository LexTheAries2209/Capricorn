// SPDX-License-Identifier: GPL-3.0-only
import AppKit

@MainActor
final class CapricornAppDelegate: NSObject, NSApplicationDelegate {
    weak var updater: AppUpdater?
    weak var appModel: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--review-desktop-topology") {
            DispatchQueue.main.async {
                StorageDesktopReviewController.shared.open()
            }
        }
        #endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // The raw process must finish releasing the device and restoring mounts.
        if appModel?.isUSBRawSmartActive == true { return .terminateCancel }
        return updater?.applicationMayTerminate() == false ? .terminateCancel : .terminateNow
    }
}
