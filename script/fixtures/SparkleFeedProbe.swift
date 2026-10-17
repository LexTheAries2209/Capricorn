// SPDX-License-Identifier: GPL-3.0-only
// Read-only Sparkle feed check; no Capricorn models or user history are loaded.
import AppKit
import Sparkle

@main
struct FeedProbeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = FeedProbeDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class FeedProbeDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var updater: SPUUpdater?
    private var result: [String: String] = [:]
    private var finished = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let driver = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
            let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
            self.updater = updater
            updater.automaticallyChecksForUpdates = false
            updater.automaticallyDownloadsUpdates = false
            try updater.start()
            updater.checkForUpdateInformation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.finish(["result": "timeout"])
            }
        } catch {
            finish(["result": "error", "detail": error.localizedDescription])
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        result = [
            "result": "available",
            "build": item.versionString,
            "version": item.displayVersionString,
            "downloadURL": item.fileURL?.absoluteString ?? ""
        ]
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        result = ["result": "upToDate"]
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if !result.isEmpty {
            finish(result)
        } else {
            finish(["result": "error", "detail": error?.localizedDescription ?? "No feed result"])
        }
    }

    private func finish(_ result: [String: String]) {
        guard !finished else { return }
        finished = true
        let path = Bundle.main.object(forInfoDictionaryKey: "ProbeOutputPath") as! String
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }
}
