// SPDX-License-Identifier: GPL-3.0-only
import Sparkle
import XCTest
@testable import Capricorn

@MainActor
final class AppUpdaterTests: XCTestCase {
    func testApplicationBundleSupportsNativeUpdateWindowLanguages() throws {
        let host = Bundle(for: AppUpdater.self)
        // The host's supported languages also constrain Sparkle's native windows.
        for language in AppLanguage.allCases {
            let preferred = Bundle.preferredLocalizations(
                from: host.localizations, forPreferences: [language.rawValue]
            )
            XCTAssertEqual(preferred.first, language.rawValue)
        }
    }

    func testApplicationBundleContainsStrictSignedUpdateConfiguration() throws {
        let info = try XCTUnwrap(Bundle(for: AppUpdater.self).infoDictionary)
        let configuration = try AppUpdateConfiguration(info: info)
        XCTAssertEqual(configuration.feedURL.scheme, "https")
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info["SUSignedFeedFailureExpirationInterval"] as? Int, 0)
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, false)
        XCTAssertEqual(info["SUAllowsAutomaticUpdates"] as? Bool, false)
        XCTAssertNil(info["SUScheduledCheckInterval"])
        let build = try XCTUnwrap(info["CFBundleVersion"] as? String)
        XCTAssertNotNil(build.range(of: #"^[0-9]{4}$"#, options: .regularExpression))
        XCTAssertGreaterThan(try XCTUnwrap(Int(build)), 0)
    }

    func testRetiredDriverCannotOverwriteTimeoutDuringManualRetry() {
        let presenter = RecordingUpdatePromptPresenter()
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
            allowsStartup: false, promptPresenter: presenter
        )
        let standard = RecordingUpdateUserDriver()
        let driver = GuardedUpdateUserDriver(standard: standard, owner: updater)
        var cancellations = 0
        driver.showUserInitiatedUpdateCheck { cancellations += 1 }
        driver.invalidate()
        updater.transition(to: .failed(.checkTimeout))
        var acknowledgements = 0
        driver.cancelActiveCheck()
        driver.dismissUpdateInstallation()
        driver.showUpdaterError(URLError(.cancelled)) { acknowledgements += 1 }
        driver.showUpdateNotFoundWithError(URLError(.cancelled)) { acknowledgements += 1 }
        XCTAssertEqual(updater.state, .failed(.checkTimeout))
        XCTAssertEqual(cancellations, 0)
        XCTAssertEqual(acknowledgements, 2)
        XCTAssertEqual(standard.resultWindows, 0)
    }

    func testSavedLaunchCheckChoiceLoadsAndPersistsWithoutStartingSparkle() throws {
        let suite = "CapricornTests.updateChoices.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let makeUpdater = {
            AppUpdater(safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
                       allowsStartup: false, defaults: defaults)
        }
        let updater = makeUpdater()
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        updater.setAutomaticallyChecksForUpdates(true)
        let previousCheck = Date()
        defaults.set(previousCheck, forKey: AppUpdater.PreferenceKey.lastCheck)

        let reopened = makeUpdater()
        XCTAssertTrue(reopened.automaticallyChecksForUpdates)
        XCTAssertEqual(reopened.lastCheckedAt, previousCheck)
        XCTAssertFalse(reopened.isStarted)
        reopened.applicationDidLaunch()
        XCTAssertFalse(reopened.isStarted, "Test startup isolation must still prevent network requests")

        reopened.setAutomaticallyChecksForUpdates(false)
        XCTAssertFalse(makeUpdater().automaticallyChecksForUpdates)
    }

    func testLegacyAutomaticDownloadsAreDisabledBeforeStartingSparkle() throws {
        let suite = "CapricornTests.retiredAutomaticDownloads.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AppUpdater.PreferenceKey.checksOnLaunch)
        defaults.set(true, forKey: AppUpdater.PreferenceKey.legacyAutomaticDownloads)
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
            allowsStartup: false, defaults: defaults
        )
        XCTAssertFalse(defaults.bool(forKey: AppUpdater.PreferenceKey.legacyAutomaticDownloads))
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
        XCTAssertFalse(updater.isStarted)
    }

    func testAutomaticInstallationRequiresDeveloperConsentAndTracksChanges() throws {
        let suite = "CapricornTests.developerAutomaticUpdates.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AppUpdater.PreferenceKey.legacyAutomaticDownloads)
        let preferences = AppPreferences(defaults: defaults)
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
            allowsStartup: false, defaults: defaults,
            automaticUpdatesEnabled: { preferences.allowsAutomaticUpdateInstallation }
        )
        XCTAssertFalse(updater.allowsAutomaticUpdateInstallation, "Legacy Sparkle consent is not developer consent")
        preferences.automaticallyDownloadsAndInstallsUpdates = true
        XCTAssertFalse(updater.allowsAutomaticUpdateInstallation)
        preferences.enablesDeveloperOptions = true
        XCTAssertTrue(updater.allowsAutomaticUpdateInstallation)
        preferences.enablesDeveloperOptions = false
        XCTAssertFalse(updater.allowsAutomaticUpdateInstallation)
        preferences.enablesDeveloperOptions = true
        XCTAssertTrue(updater.allowsAutomaticUpdateInstallation)
        preferences.resetAllSettings()
        XCTAssertFalse(updater.allowsAutomaticUpdateInstallation)
        XCTAssertFalse(updater.isStarted, "Changing consent must not start a network request")
    }

    func testLegacyAutomaticCheckConsentIsPreservedAndNewChoiceTakesPriority() throws {
        let suite = "CapricornTests.updateConsent.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for legacyConsent in [true, false] {
            defaults.removeObject(forKey: AppUpdater.PreferenceKey.checksOnLaunch)
            defaults.set(legacyConsent, forKey: AppUpdater.PreferenceKey.legacyAutomaticChecks)
            let updater = AppUpdater(
                safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
                allowsStartup: false, defaults: defaults
            )
            XCTAssertEqual(updater.automaticallyChecksForUpdates, legacyConsent)
            updater.setAutomaticallyChecksForUpdates(!legacyConsent)
            let reopened = AppUpdater(
                safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
                allowsStartup: false, defaults: defaults
            )
            XCTAssertEqual(reopened.automaticallyChecksForUpdates, !legacyConsent)
        }
    }

    func testLaunchCheckWithConflictWarnsOnlyOnceAndDoesNotRetryWhenTasksFinish() throws {
        let suite = "CapricornTests.updateLaunchConflict.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AppUpdater.PreferenceKey.checksOnLaunch)
        var conflicts: [AppUpdateConflict] = [.benchmark]
        var alerts = 0
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { conflicts }), language: { .english },
            allowsStartup: true, defaults: defaults, presentAlert: { _, _ in alerts += 1 }
        )
        updater.applicationDidLaunch()
        updater.applicationDidLaunch()
        XCTAssertEqual(alerts, 1)
        XCTAssertEqual(updater.state, .blocked([.benchmark]))
        conflicts = []
        updater.applicationDidLaunch()
        XCTAssertFalse(updater.isStarted)
    }

    func testDisabledLaunchDoesNotStartUpdaterAndManualCheckRemainsAvailable() throws {
        let suite = "CapricornTests.updateLaunchDisabled.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var alerts = 0
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [.workload] }), language: { .english },
            allowsStartup: true, defaults: defaults, presentAlert: { _, _ in alerts += 1 }
        )
        updater.applicationDidLaunch()
        XCTAssertFalse(updater.isStarted)
        XCTAssertEqual(alerts, 0)
        updater.checkNow()
        XCTAssertEqual(alerts, 1)
        XCTAssertEqual(updater.state, .blocked([.workload]))
    }

    func testResetAllSettingsClearsLaunchCheckAndDownloadChoices() throws {
        let suite = "CapricornTests.updateReset.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
            allowsStartup: false, defaults: defaults
        )
        updater.setAutomaticallyChecksForUpdates(true)
        defaults.set(true, forKey: AppUpdater.PreferenceKey.legacyAutomaticDownloads)
        AppPreferences(defaults: defaults).resetAllSettings()
        let reopened = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
            allowsStartup: false, defaults: defaults
        )
        XCTAssertFalse(reopened.automaticallyChecksForUpdates)
        XCTAssertFalse(defaults.bool(forKey: AppUpdater.PreferenceKey.legacyAutomaticDownloads))
    }

    func testConfigurationRejectsInsecureFeedsAndInvalidKeys() throws {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        for feed in ["http://example.com/appcast.xml", "file:///tmp/appcast.xml", "https://user:pass@example.com/appcast.xml"] {
            XCTAssertThrowsError(try AppUpdateConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": key]))
        }
        XCTAssertThrowsError(try AppUpdateConfiguration(info: ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "bad"]))
        XCTAssertThrowsError(try AppUpdateConfiguration(info: ["SUFeedURL": "http://127.0.0.1:8765/appcast.xml", "SUPublicEDKey": key]))
        let local = try AppUpdateConfiguration(
            info: ["SUFeedURL": "http://127.0.0.1:8765/appcast.xml", "SUPublicEDKey": key],
            allowsLocalTestFeed: true
        )
        XCTAssertEqual(local.feedURL.host, "127.0.0.1")
    }

    func testManualCheckPresentsLocalizedConflictBeforeStartingUpdater() {
        var alerts: [String] = []
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [.benchmark, .selfTest] }),
            language: { .simplifiedChinese }, allowsStartup: false,
            presentAlert: { title, body in alerts.append(title + body) }
        )
        updater.checkNow()
        XCTAssertFalse(updater.isStarted)
        XCTAssertEqual(updater.state, .blocked([.benchmark, .selfTest]))
        XCTAssertEqual(alerts.count, 1)
        XCTAssertTrue(alerts[0].contains("更新已阻止"))
        XCTAssertTrue(alerts[0].contains("SMART 自检"))
    }

    func testOrdinaryQuitCancelsPreparedUpdateAndWaitsWithoutReserving() {
        var conflicts: [AppUpdateConflict] = [.workload]
        let gate = AppUpdateSafetyGate(conflicts: { conflicts })
        let updater = AppUpdater(safety: gate, language: { .english }, allowsStartup: false, presentAlert: { _, _ in })
        updater.markPendingInstallation(true)
        var cancellations = 0
        XCTAssertTrue(updater.registerPreparedInstallationCancellation { cancellations += 1 })
        XCTAssertFalse(updater.applicationMayTerminate())
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(gate.isReserved)
        conflicts = []
        XCTAssertFalse(gate.isReserved)
        XCTAssertFalse(updater.applicationMayTerminate())
        XCTAssertEqual(cancellations, 1)
        updater.markPendingInstallation(false)
        XCTAssertFalse(gate.isReserved)
    }

    func testNewConflictWithPreparedManualUpdatePresentsWarningOnce() {
        var conflicts: [AppUpdateConflict] = []
        var alertCount = 0
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { conflicts }),
            language: { .english }, allowsStartup: false,
            presentAlert: { _, _ in alertCount += 1 }
        )
        updater.markPendingInstallation(true)
        conflicts = [.selfTest]
        updater.conflictsDidChange()
        updater.conflictsDidChange()
        XCTAssertEqual(alertCount, 1)
        XCTAssertEqual(updater.state, .blocked([.selfTest]))
        XCTAssertFalse(updater.applicationMayTerminate())
        conflicts = []
        updater.conflictsDidChange()
        XCTAssertEqual(updater.state, .idle)
        XCTAssertFalse(updater.safety.isReserved)
    }

    func testReadyDialogRechecksForConflictsAtReplyAndCancelsPreparedInstall() {
        var conflicts: [AppUpdateConflict] = []
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { conflicts }),
            language: { .english }, allowsStartup: false, presentAlert: { _, _ in }
        )
        let standard = RecordingUpdateUserDriver()
        let driver = GuardedUpdateUserDriver(standard: standard, owner: updater)
        updater.markPendingInstallation(true)
        var receivedChoice: SPUUserUpdateChoice?
        driver.showReady(toInstallAndRelaunch: { receivedChoice = $0 })
        XCTAssertNotNil(standard.readyReply)
        conflicts = [.firstAid]
        standard.readyReply?(.install)
        XCTAssertEqual(receivedChoice, .skip)
        XCTAssertFalse(updater.hasPendingInstallation)
        XCTAssertFalse(updater.safety.isReserved)
        XCTAssertEqual(updater.state, .blocked([.firstAid]))
    }

    func testSaveFailureBlocksReadyDialogReply() {
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [] }, save: { throw CocoaError(.fileWriteNoPermission) }),
            language: { .english }, allowsStartup: false, presentAlert: { _, _ in }
        )
        let standard = RecordingUpdateUserDriver()
        let driver = GuardedUpdateUserDriver(standard: standard, owner: updater)
        var receivedChoice: SPUUserUpdateChoice?
        driver.showReady(toInstallAndRelaunch: { receivedChoice = $0 })
        standard.readyReply?(.install)
        XCTAssertEqual(receivedChoice, .skip)
        XCTAssertEqual(updater.state, .failed(.save))
        XCTAssertFalse(updater.safety.isReserved)
    }

    func testDismissingReadyDialogCancelsInsteadOfInstallingOnQuit() {
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
            allowsStartup: false
        )
        let standard = RecordingUpdateUserDriver()
        let driver = GuardedUpdateUserDriver(standard: standard, owner: updater)
        updater.markPendingInstallation(true)
        var receivedChoice: SPUUserUpdateChoice?
        driver.showReady(toInstallAndRelaunch: { receivedChoice = $0 })
        standard.readyReply?(.dismiss)
        XCTAssertEqual(receivedChoice, .skip)
        XCTAssertFalse(updater.hasPendingInstallation)
        XCTAssertFalse(updater.safety.isReserved)
    }

    func testQuitAtReadyDialogCancelsExactlyOnceAndFinishesAfterUpdateCycle() async {
        var finishedQuits = 0
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
            allowsStartup: false, finishRequestedQuit: { finishedQuits += 1 }
        )
        let standard = RecordingUpdateUserDriver()
        let driver = GuardedUpdateUserDriver(standard: standard, owner: updater)
        updater.markPendingInstallation(true)
        var choices: [SPUUserUpdateChoice] = []
        driver.showReady(toInstallAndRelaunch: { choices.append($0) })
        XCTAssertFalse(updater.applicationMayTerminate())
        XCTAssertEqual(choices, [.skip])
        XCTAssertFalse(updater.applicationMayTerminate())
        XCTAssertEqual(finishedQuits, 0)
        standard.readyReply?(.install)
        XCTAssertEqual(choices, [.skip], "A late confirmation must not start installation")
        let sparkler = SPUUpdater(
            hostBundle: .main, applicationBundle: .main, userDriver: standard, delegate: nil
        )
        updater.updater(sparkler, didFinishUpdateCycleFor: .updates, error: nil)
        let quitFinished = await AsyncTestWaiter.wait { finishedQuits == 1 }
        XCTAssertTrue(quitFinished)
        XCTAssertTrue(updater.applicationMayTerminate())
        XCTAssertFalse(updater.safety.isReserved)
    }

    func testExplicitReadyConfirmationReservesAndSavesBeforeTerminating() {
        var saves = 0
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [] }, save: { saves += 1 }),
            language: { .english }, allowsStartup: false
        )
        let standard = RecordingUpdateUserDriver()
        let driver = GuardedUpdateUserDriver(standard: standard, owner: updater)
        updater.markPendingInstallation(true)
        var choice: SPUUserUpdateChoice?
        driver.showReady(toInstallAndRelaunch: { choice = $0 })
        standard.readyReply?(.install)
        XCTAssertEqual(choice, .install)
        XCTAssertEqual(saves, 1)
        XCTAssertTrue(updater.safety.isReserved)
        XCTAssertTrue(updater.applicationMayTerminate())
        updater.markPendingInstallation(false)
    }

    func testSignatureErrorsHaveSpecificRecoveryAndNetworkErrorsRemainDistinct() {
        XCTAssertEqual(AppUpdater.issue(for: NSError(domain: SUSparkleErrorDomain, code: Int(SUError.signatureError.rawValue))), .signature)
        XCTAssertEqual(AppUpdater.issue(for: URLError(.notConnectedToInternet) as NSError), .network)
        XCTAssertEqual(AppUpdater.issue(for: NSError(domain: SUSparkleErrorDomain, code: Int(SUError.appcastParseError.rawValue))), .feed)
        let nested = NSError(
            domain: SUSparkleErrorDomain, code: Int(SUError.installationError.rawValue),
            userInfo: [NSUnderlyingErrorKey: NSError(
                domain: SUSparkleErrorDomain, code: Int(SUError.unarchivingError.rawValue),
                userInfo: [NSUnderlyingErrorKey: NSError(domain: SUSparkleErrorDomain, code: Int(SUError.signatureError.rawValue))]
            )]
        )
        XCTAssertEqual(AppUpdater.issue(for: nested), .signature)
    }

    func testDownloadFailuresDistinguishServerResponsesFromConnectionFailures() {
        // The real Sparkle downloader wraps HTTP failures using this domain/code.
        let httpFailure = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.downloadError.rawValue))
        XCTAssertEqual(AppUpdater.issue(for: httpFailure), .download)
        XCTAssertEqual(AppUpdater.issue(for: URLError(.badServerResponse) as NSError), .download)
        XCTAssertEqual(AppUpdater.issue(for: URLError(.resourceUnavailable) as NSError), .download)

        for code in [URLError.timedOut, .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet] {
            let transportFailure = NSError(
                domain: SUSparkleErrorDomain, code: Int(SUError.downloadError.rawValue),
                userInfo: [NSUnderlyingErrorKey: NSError(
                    domain: SUSparkleErrorDomain, code: Int(SUError.downloadError.rawValue),
                    userInfo: [NSUnderlyingErrorKey: URLError(code)]
                )]
            )
            XCTAssertEqual(AppUpdater.issue(for: transportFailure), .network)
        }
    }

    func testDownloadFailurePresentsLocalizedRecoveryWithoutClaimingConnectionFailed() {
        var detail = ""
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [] }),
            language: { .simplifiedChinese }, allowsStartup: false,
            presentAlert: { _, body in detail = body }
        )
        updater.handleError(
            NSError(domain: SUSparkleErrorDomain, code: Int(SUError.downloadError.rawValue)),
            showingAlert: true
        )
        XCTAssertEqual(updater.state, .failed(.download))
        XCTAssertEqual(detail, "无法下载更新。请检查网络或查看 Releases。")
        XCTAssertFalse(detail.contains("无法连接"))
    }

    func testManualCheckAndResultUseSharedPresenterWithoutOpeningSparkleWindows() {
        let presenter = RecordingUpdatePromptPresenter()
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .simplifiedChinese },
            allowsStartup: false, promptPresenter: presenter
        )
        let standard = RecordingUpdateUserDriver()
        let driver = GuardedUpdateUserDriver(standard: standard, owner: updater)
        var cancellations = 0
        driver.showUserInitiatedUpdateCheck { cancellations += 1 }
        XCTAssertEqual(presenter.prompt?.title, "正在检查更新…")
        XCTAssertEqual(presenter.prompt?.buttonTitle, "取消")
        XCTAssertEqual(presenter.prompt?.windowTitle, "软件更新")
        XCTAssertTrue(presenter.prompt?.isChecking == true)
        XCTAssertEqual(standard.checkingWindows, 0)

        var acknowledgements = 0
        driver.showUpdateNotFoundWithError(NSError(
            domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue),
            userInfo: [
                NSLocalizedDescriptionKey: "您使用的就是最新版！",
                NSLocalizedRecoverySuggestionErrorKey: "Capricorn 2.10.2 是当前的最新版本。"
            ]
        )) { acknowledgements += 1 }
        XCTAssertEqual(presenter.prompt?.title, "您已经更新至最新版本")
        XCTAssertEqual(presenter.prompt?.detail, "Capricorn 2.10.2 是当前的最新版本。")
        XCTAssertEqual(presenter.prompt?.buttonTitle, "好")
        XCTAssertFalse(presenter.prompt?.isChecking == true)
        XCTAssertEqual(standard.resultWindows, 0)
        XCTAssertEqual(cancellations, 0)
        XCTAssertEqual(acknowledgements, 0)
        XCTAssertNotNil(presenter.prompt, "A result waits for the user's acknowledgement")
        presenter.respond()
        XCTAssertEqual(acknowledgements, 1)
        driver.dismissUpdateInstallation()
        XCTAssertNil(presenter.prompt)
        XCTAssertEqual(acknowledgements, 1)
    }

    func testCheckCancellationRunsOnceAndResetsCheckingState() {
        let presenter = RecordingUpdatePromptPresenter()
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { [] }), language: { .english },
            allowsStartup: false, promptPresenter: presenter
        )
        let driver = GuardedUpdateUserDriver(standard: RecordingUpdateUserDriver(), owner: updater)
        var cancellations = 0
        driver.showUserInitiatedUpdateCheck { cancellations += 1 }
        presenter.respond()
        driver.cancelActiveCheck()
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(updater.state, .idle)
        XCTAssertNil(driver.cancelCheck)
    }

    func testErrorsAndConflictsUseSharedPresenterAndPreserveBlockedResult() {
        let presenter = RecordingUpdatePromptPresenter()
        var conflicts: [AppUpdateConflict] = []
        let updater = AppUpdater(
            safety: AppUpdateSafetyGate(conflicts: { conflicts }), language: { .simplifiedChinese },
            allowsStartup: false, promptPresenter: presenter
        )
        let driver = GuardedUpdateUserDriver(standard: RecordingUpdateUserDriver(), owner: updater)
        driver.showUserInitiatedUpdateCheck {}
        var acknowledgements = 0
        driver.showUpdaterError(URLError(.notConnectedToInternet)) { acknowledgements += 1 }
        XCTAssertEqual(presenter.prompt?.title, "暂时无法更新")
        XCTAssertEqual(presenter.prompt?.windowTitle, "软件更新")
        XCTAssertFalse(presenter.prompt?.isChecking == true)
        XCTAssertEqual(acknowledgements, 0)
        presenter.respond()
        XCTAssertEqual(acknowledgements, 1)

        conflicts = [.benchmark]
        XCTAssertFalse(updater.authorizeUpdate())
        let blockedPrompt = presenter.prompt
        driver.showUpdateNotFoundWithError(NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))) {
            acknowledgements += 1
        }
        XCTAssertEqual(presenter.prompt, blockedPrompt, "A late result must not overwrite the conflict warning")
        XCTAssertEqual(updater.state, .blocked([.benchmark]))
        XCTAssertEqual(acknowledgements, 2)
        driver.dismissUpdateInstallation()
        XCTAssertEqual(presenter.prompt, blockedPrompt, "Sparkle must not close an app-owned conflict warning")
    }
}

@MainActor
private final class RecordingUpdatePromptPresenter: AppUpdatePromptPresenting {
    var prompt: AppUpdatePrompt?
    var action: (() -> Void)?
    func show(_ prompt: AppUpdatePrompt, action: @escaping () -> Void) {
        self.prompt = prompt
        self.action = action
    }
    func dismissChecking() {
        if prompt?.isChecking == true {
            prompt = nil
            action = nil
        }
    }
    func dismissUpdateSession() {
        guard prompt?.belongsToUpdateSession == true else { return }
        if prompt?.isChecking == true {
            dismissChecking()
        } else {
            respond()
        }
    }
    func showInFocus() -> Bool { prompt != nil }
    func respond() {
        let response = action
        action = nil
        prompt = nil
        response?()
    }
}

@MainActor
private final class RecordingUpdateUserDriver: NSObject, SPUUserDriver {
    var readyReply: ((SPUUserUpdateChoice) -> Void)?
    var checkingWindows = 0
    var resultWindows = 0
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {}
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { checkingWindows += 1 }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {}
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { resultWindows += 1 }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {}
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { readyReply = reply }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {}
    func dismissUpdateInstallation() {}
}
