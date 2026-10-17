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
    private var launchCheckStartedAt: TimeInterval = 0
    private var launchCheckTimedOutAt: TimeInterval?
    private var manualRetryStarted = false
    private var availableSince: TimeInterval?
    private var quitResult: [String: Any]?
    private var developerOptionsEnabled = false
    private var automaticUpdatesEnabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "CapricornFixtureRoot") as! String)
            scenario = Bundle.main.object(forInfoDictionaryKey: "CapricornFixtureScenario") as! String
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
            let configuration = ModelConfiguration(url: root.appendingPathComponent("history.store"))
            let container = try ModelContainer(for: UpdateFixtureHistory.self, configurations: configuration)
            self.container = container
            let records = try container.mainContext.fetch(FetchDescriptor<UpdateFixtureHistory>())
            if build == "0042" {
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
            developerOptionsEnabled = scenario.hasPrefix("developer-auto") && scenario != "developer-auto-disabled"
            automaticUpdatesEnabled = scenario.hasPrefix("developer-auto")
            let usesLaunchCheck = [
                "manual-only", "launch-checks", "launch-disabled", "launch-conflict", "launch-timeout",
                "developer-auto", "developer-auto-disabled", "developer-auto-conflict"
            ].contains(scenario)
            let defaults = UserDefaults.standard
            if scenario == "launch-checks" {
                if !FileManager.default.fileExists(atPath: root.appendingPathComponent("first-launch-result.json").path) {
                    defaults.removeObject(forKey: AppUpdater.PreferenceKey.checksOnLaunch)
                    defaults.set(true, forKey: AppUpdater.PreferenceKey.legacyAutomaticChecks)
                }
                // A recent attempt must not suppress the next process's launch check.
                defaults.set(Date(), forKey: AppUpdater.PreferenceKey.lastCheck)
                defaults.set(false, forKey: AppUpdater.PreferenceKey.legacyAutomaticDownloads)
            } else if usesLaunchCheck {
                defaults.set(scenario != "launch-disabled", forKey: AppUpdater.PreferenceKey.checksOnLaunch)
                defaults.set(true, forKey: AppUpdater.PreferenceKey.legacyAutomaticChecks)
                defaults.set(scenario == "manual-only", forKey: AppUpdater.PreferenceKey.legacyAutomaticDownloads)
            }
            if ["conflict", "launch-conflict", "developer-auto-conflict"].contains(scenario) {
                conflicts = [.benchmark]
            }
            let safety = AppUpdateSafetyGate(
                conflicts: { [weak self] in self?.conflicts ?? [.diskCommand] },
                save: { try container.mainContext.save() }
            )
            let owner = AppUpdater(
                safety: safety, language: { .english }, allowsStartup: usesLaunchCheck,
                presentAlert: { [weak self] title, detail in
                    if let self, self.scenario == "launch-timeout", self.manualRetryStarted,
                       self.owner?.state == .upToDate, let timedOutAt = self.launchCheckTimedOutAt {
                        self.finish([
                            "result": "timed-out-then-retried", "build": build,
                            "timeoutElapsed": timedOutAt - self.launchCheckStartedAt
                        ])
                        return
                    }
                    self?.finish(["result": "blocked", "title": title, "detail": detail, "build": build])
                },
                automaticUpdatesEnabled: { [weak self] in
                    self?.developerOptionsEnabled == true && self?.automaticUpdatesEnabled == true
                }
            )
            self.owner = owner
            if usesLaunchCheck {
                let enabledBeforeLaunch = owner.automaticallyChecksForUpdates
                launchCheckStartedAt = ProcessInfo.processInfo.systemUptime
                owner.applicationDidLaunch()
                owner.applicationDidLaunch() // Repeated scene tasks must not duplicate a check.
                if scenario == "launch-disabled" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                        self?.finish(["result": "disabled", "enabledBeforeLaunch": enabledBeforeLaunch, "started": owner.isStarted])
                    }
                }
                timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let owner = self.owner else { return }
                        if ["manual-only", "developer-auto-disabled"].contains(self.scenario),
                           case .available = owner.state,
                           owner.canCheckForUpdates {
                            let now = ProcessInfo.processInfo.systemUptime
                            if self.availableSince == nil { self.availableSince = now }
                            if now - self.availableSince! >= 2 {
                                self.finish([
                                    "result": "manual-required", "build": build,
                                    "legacyDownloadsDisabled": !UserDefaults.standard.bool(forKey: AppUpdater.PreferenceKey.legacyAutomaticDownloads),
                                    "preparedInstallation": owner.hasPendingInstallation
                                ])
                            }
                        } else if self.scenario == "launch-timeout" {
                            let now = ProcessInfo.processInfo.systemUptime
                            if owner.state == .failed(.checkTimeout), owner.canCheckForUpdates,
                               self.launchCheckTimedOutAt == nil {
                                self.launchCheckTimedOutAt = now
                            }
                            if let timedOutAt = self.launchCheckTimedOutAt,
                               now - timedOutAt >= 2, !self.manualRetryStarted {
                                // Staying open and repeating the launch callback must not retry.
                                owner.applicationDidLaunch()
                                self.manualRetryStarted = true
                                owner.checkNow()
                            }
                        } else if self.scenario == "launch-checks", case .available = owner.state, owner.canCheckForUpdates {
                            self.finish([
                                "result": "checked", "enabledBeforeLaunch": enabledBeforeLaunch,
                                "savedChoice": UserDefaults.standard.bool(forKey: AppUpdater.PreferenceKey.checksOnLaunch),
                                "timerEnabled": UserDefaults.standard.bool(forKey: AppUpdater.PreferenceKey.legacyAutomaticChecks),
                                "build": build
                            ])
                        }
                    }
                }
            } else {
                guard owner.authorizeUpdate() else { return }
                let standard = AutomatedFixtureUserDriver(
                    fail: { [weak self] error in
                        self?.finish(["result": "unexpected", "detail": error])
                    },
                    onReady: { [weak self] reply in
                        guard let self else { reply(.skip); return }
                        if ["cancel-install", "quit-before-install", "developer-auto-off-during-download"].contains(self.scenario) {
                            self.quitResult = ["result": "cancelled", "build": build]
                            if self.scenario == "developer-auto-off-during-download" {
                                self.quitResult?["requiredManualConfirmation"] = true
                            }
                            if self.scenario != "quit-before-install" { reply(.dismiss) }
                            NSApp.terminate(nil)
                        } else {
                            reply(.install)
                        }
                    },
                    onDownload: { [weak self] in
                        if self?.scenario == "developer-auto-off-during-download" {
                            self?.automaticUpdatesEnabled = false
                        }
                    },
                    onExtraction: { [weak self] in
                        if self?.scenario == "developer-auto-ready-conflict" {
                            self?.conflicts = [.benchmark]
                        }
                    }
                )
                let driver = GuardedUpdateUserDriver(standard: standard, owner: owner)
                let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: owner)
                self.updater = updater
                updater.automaticallyChecksForUpdates = false
                updater.automaticallyDownloadsUpdates = false
                try updater.start()
                updater.checkForUpdates()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 40) { [weak self] in
                self?.finish([
                    "result": "timeout", "state": "\(owner.state)",
                    "canCheck": owner.canCheckForUpdates
                ])
            }
        } catch {
            finish(["result": "fixture-error", "detail": error.localizedDescription])
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        owner?.applicationMayTerminate() == false ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard var result = quitResult else { return }
        result["preparedInstallation"] = owner?.hasPendingInstallation ?? false
        result["installationReserved"] = owner?.safety.isReserved ?? false
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: root.appendingPathComponent("result.json"))
        }
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
    let onReady: ((SPUUserUpdateChoice) -> Void) -> Void
    let onDownload: () -> Void
    let onExtraction: () -> Void
    init(
        fail: @escaping (String) -> Void,
        onReady: @escaping ((SPUUserUpdateChoice) -> Void) -> Void,
        onDownload: @escaping () -> Void,
        onExtraction: @escaping () -> Void
    ) {
        self.fail = fail
        self.onReady = onReady
        self.onDownload = onDownload
        self.onExtraction = onExtraction
    }
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
    func showDownloadInitiated(cancellation: @escaping () -> Void) { onDownload() }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { onExtraction() }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { onReady(reply) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}
