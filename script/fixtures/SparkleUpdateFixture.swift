// SPDX-License-Identifier: GPL-3.0-only
// Compiled only by scripts/test-sparkle-update.py, never into Capricorn.
import AppKit
import Sparkle
import SwiftData

enum AppLanguage: String {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    func t(_ value: String) -> String { value }
}

enum ApplicationRuntime {
    static let allowsAutomaticStartupTasks = false
}

@Model
final class UpdateFixtureHistory {
    var marker: String
    init(marker: String) { self.marker = marker }
}

@main
struct UpdateFixtureMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = UpdateFixtureDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class UpdateFixtureDelegate: NSObject, NSApplicationDelegate {
    private var owner: AppUpdater?
    private var updater: SPUUpdater?
    private var container: ModelContainer?
    private var conflicts: [AppUpdateConflict] = []
    private var timer: Timer?
    private var root: URL!
    private var scenario = ""
    private var hasFinished = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "CapricornFixtureRoot") as! String)
            scenario = Bundle.main.object(forInfoDictionaryKey: "CapricornFixtureScenario") as! String
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
            let configuration = ModelConfiguration(url: root.appendingPathComponent("history.store"))
            let container = try ModelContainer(for: UpdateFixtureHistory.self, configurations: configuration)
            self.container = container
            let records = try container.mainContext.fetch(FetchDescriptor<UpdateFixtureHistory>())
            if build == "1001" {
                finish([
                    "result": "updated",
                    "build": build,
                    "historyRetained": records.contains { $0.marker == "history-before-update" },
                    "preferencesRetained": UserDefaults.standard.string(forKey: "fixtureMarker") == "preference-before-update"
                ])
                return
            }
            UserDefaults.standard.set("preference-before-update", forKey: "fixtureMarker")
            if records.isEmpty {
                container.mainContext.insert(UpdateFixtureHistory(marker: "history-before-update"))
                try container.mainContext.save()
            }
            if scenario == "conflict" { conflicts = [.benchmark] }
            let safety = AppUpdateSafetyGate(
                conflicts: { [weak self] in self?.conflicts ?? [.diskCommand] },
                save: { try container.mainContext.save() }
            )
            let owner = AppUpdater(
                safety: safety, language: { .english }, allowsStartup: false,
                presentAlert: { [weak self] title, detail in
                    self?.finish(["result": "blocked", "title": title, "detail": detail, "build": build])
                }
            )
            self.owner = owner
            guard owner.authorizeUpdate() else { return }
            let standard = AutomatedFixtureUserDriver { [weak self] error in
                self?.finish(["result": "unexpected", "detail": error])
            }
            let driver = GuardedUpdateUserDriver(standard: standard, owner: owner)
            let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: owner)
            self.updater = updater
            try updater.start()
            if scenario == "automatic" {
                updater.checkForUpdatesInBackground()
                timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.owner?.hasPendingInstallation == true else { return }
                        NSApp.terminate(nil)
                    }
                }
            } else {
                updater.checkForUpdates()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 40) { [weak self] in
                self?.finish(["result": "timeout"])
            }
        } catch {
            finish(["result": "fixture-error", "detail": error.localizedDescription])
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        owner?.applicationMayTerminate() == false ? .terminateCancel : .terminateNow
    }

    private func finish(_ result: [String: Any]) {
        guard !hasFinished else { return }
        hasFinished = true
        timer?.invalidate()
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: root.appendingPathComponent("result.json"))
        }
        NSApp.terminate(nil)
    }
}

@MainActor
private final class AutomatedFixtureUserDriver: NSObject, SPUUserDriver {
    let fail: (String) -> Void
    init(fail: @escaping (String) -> Void) { self.fail = fail }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        fail("No update: \(error.localizedDescription)")
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        fail(error.localizedDescription)
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}
