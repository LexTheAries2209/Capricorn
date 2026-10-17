// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    enum PreferenceKey {
        static let checksOnLaunch = "checksForUpdatesOnLaunch"
        static let legacyAutomaticChecks = "SUEnableAutomaticChecks"
        static let legacyAutomaticDownloads = "SUAutomaticallyUpdate"
        static let lastCheck = "SULastCheckTime"
    }

    private(set) var state: AppUpdaterState = .idle
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var lastCheckedAt: Date?
    private(set) var downloadProgress: Double?
    private(set) var hasPendingInstallation = false
    private(set) var isStarted = false
    let nativeLanguage: AppLanguage
    let safety: AppUpdateSafetyGate
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var userDriver: GuardedUpdateUserDriver?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let language: () -> AppLanguage
    @ObservationIgnored private let hostBundle: Bundle
    @ObservationIgnored private let allowsStartup: Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let automaticUpdatesEnabled: () -> Bool
    @ObservationIgnored private let presentAlert: ((String, String) -> Void)?
    @ObservationIgnored private let promptPresenter: any AppUpdatePromptPresenting
    @ObservationIgnored private var hasAttemptedStart = false
    @ObservationIgnored private var postponedRelaunch: (() -> Void)?
    @ObservationIgnored private var hasHandledApplicationLaunch = false
    @ObservationIgnored private var launchCheckDeadline: (id: UUID, timer: Timer)?
    @ObservationIgnored private var cancelPreparedInstallation: (() -> Void)?
    @ObservationIgnored private var quitsAfterCancellingUpdate = false
    @ObservationIgnored private var isCancellingPreparedInstallation = false
    @ObservationIgnored private let finishRequestedQuit: @MainActor () -> Void

    init(
        safety: AppUpdateSafetyGate,
        language: @escaping () -> AppLanguage,
        hostBundle: Bundle = .main,
        allowsStartup: Bool = ApplicationRuntime.allowsAutomaticStartupTasks,
        defaults: UserDefaults = .standard,
        presentAlert: ((String, String) -> Void)? = nil,
        promptPresenter: (any AppUpdatePromptPresenting)? = nil,
        finishRequestedQuit: (@MainActor () -> Void)? = nil,
        automaticUpdatesEnabled: @escaping () -> Bool = { false }
    ) {
        self.safety = safety
        self.language = language
        nativeLanguage = language()
        self.hostBundle = hostBundle
        self.allowsStartup = allowsStartup
        self.defaults = defaults
        self.automaticUpdatesEnabled = automaticUpdatesEnabled
        // Read saved choices before creating Sparkle, including in Debug and with an invalid feed.
        automaticallyChecksForUpdates = defaults.object(forKey: PreferenceKey.checksOnLaunch) as? Bool
            ?? defaults.object(forKey: PreferenceKey.legacyAutomaticChecks) as? Bool ?? false
        // Retire old opt-ins before Sparkle reads its preferences.
        defaults.set(false, forKey: PreferenceKey.legacyAutomaticDownloads)
        lastCheckedAt = defaults.object(forKey: PreferenceKey.lastCheck) as? Date
        self.presentAlert = presentAlert
        self.promptPresenter = promptPresenter ?? AppUpdatePromptController()
        self.finishRequestedQuit = finishRequestedQuit ?? { NSApp.terminate(nil) }
        super.init()
    }

    func start() {
        guard allowsStartup, !hasAttemptedStart else { return }
        hasAttemptedStart = true
        do {
            _ = try AppUpdateConfiguration(
                info: hostBundle.infoDictionary ?? [:],
                allowsLocalTestFeed: hostBundle.bundleIdentifier == "lex.Capricorn.UpdateFixture"
            )
            let standard = SPUStandardUserDriver(hostBundle: hostBundle, delegate: self)
            let driver = GuardedUpdateUserDriver(standard: standard, owner: self)
            let updater = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle, userDriver: driver, delegate: self)
            userDriver = driver
            self.updater = updater
            // Migrate consent before disabling Sparkle's independent timer. Only the app schedules checks.
            defaults.set(automaticallyChecksForUpdates, forKey: PreferenceKey.checksOnLaunch)
            updater.automaticallyChecksForUpdates = false
            // App-owned consent drives the user-driver flow. Keep Sparkle's
            // separate preference and native opt-in checkbox disabled.
            updater.automaticallyDownloadsUpdates = false
            try updater.start()
            isStarted = true
            observations = [
                updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.synchronizeSettings() }
                },
                updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.synchronizeSettings() }
                }
            ]
            synchronizeSettings()
        } catch {
            state = .failed(.configuration)
        }
    }

    func applicationDidLaunch() {
        guard !hasHandledApplicationLaunch else { return }
        hasHandledApplicationLaunch = true
        guard allowsStartup, automaticallyChecksForUpdates, authorizeUpdate() else { return }
        start()
        guard let updater, isStarted, updater.canCheckForUpdates else { return }
        let checkID = UUID()
        let deadline = Timer(timeInterval: 15, repeats: false) { [weak self, weak updater] _ in
            MainActor.assumeIsolated {
                guard let self, let updater else { return }
                self.expireLaunchCheck(updater, id: checkID)
            }
        }
        launchCheckDeadline = (checkID, deadline)
        RunLoop.main.add(deadline, forMode: .common)
        RunLoop.main.add(deadline, forMode: .modalPanel)
        updater.checkForUpdatesInBackground()
    }

    func checkNow() {
        guard authorizeUpdate() else { return }
        if let resume = postponedRelaunch {
            guard authorizeUpdate(installing: true) else { return }
            postponedRelaunch = nil
            resume()
            return
        }
        start()
        guard let updater, isStarted else {
            showIssue(.configuration)
            return
        }
        guard updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        defaults.set(enabled, forKey: PreferenceKey.checksOnLaunch)
        automaticallyChecksForUpdates = enabled
    }

    var allowsAutomaticUpdateInstallation: Bool {
        automaticUpdatesEnabled()
    }

    func conflictsDidChange() {
        guard !safety.isReserved else { return }
        do {
            try safety.check()
            if case .blocked = state { state = .idle }
        } catch {
            guard userDriver?.cancelDownload != nil || updater?.sessionInProgress == true || hasPendingInstallation else { return }
            userDriver?.cancelActiveDownload()
            userDriver?.cancelActiveCheck()
            if let blocked = error as? AppUpdateBlockedError, state == .blocked(blocked.conflicts) { return }
            reportBlocked(error)
        }
    }

    @discardableResult
    func authorizeUpdate(installing: Bool = false) -> Bool {
        do {
            if installing {
                try safety.beginInstallation()
            } else {
                try safety.check()
            }
            return true
        } catch {
            reportBlocked(error)
            return false
        }
    }

    func applicationMayTerminate() -> Bool {
        guard !quitsAfterCancellingUpdate else { return false }
        if (hasPendingInstallation && !safety.isReserved) || isCancellingPreparedInstallation {
            // A prepared Sparkle installer watches for process termination. Cancel it
            // and wait for the update cycle to finish before honoring an ordinary quit.
            quitsAfterCancellingUpdate = true
            cancelPreparedInstallation?()
            return false
        }
        guard hasPendingInstallation || safety.isReserved else { return true }
        return authorizeUpdate(installing: true)
    }

    func registerPreparedInstallationCancellation(_ cancellation: @escaping () -> Void) -> Bool {
        if quitsAfterCancellingUpdate {
            cancellation()
            return false
        }
        cancelPreparedInstallation = cancellation
        return true
    }

    func clearPreparedInstallationCancellation() {
        cancelPreparedInstallation = nil
    }

    func didCancelPreparedInstallation() {
        markPendingInstallation(false)
        isCancellingPreparedInstallation = true
        switch state {
        case .blocked, .failed, .available: break
        default: transition(to: .idle)
        }
    }

    func markPendingInstallation(_ pending: Bool) {
        hasPendingInstallation = pending
        if !pending {
            clearPreparedInstallationCancellation()
            postponedRelaunch = nil
            safety.endInstallation()
        }
    }

    func transition(to state: AppUpdaterState) {
        if state != .checking { finishLaunchCheckDeadline() }
        self.state = state
    }

    private func finishLaunchCheckDeadline() {
        launchCheckDeadline?.timer.invalidate()
        launchCheckDeadline = nil
    }

    private func expireLaunchCheck(_ expiredUpdater: SPUUpdater, id: UUID) {
        guard updater === expiredUpdater, launchCheckDeadline?.id == id else { return }
        finishLaunchCheckDeadline()
        // Finding a result, downloading, and installing end the deadline before this point.
        switch state {
        case .idle, .checking, .blocked: break
        default: return
        }
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        promptPresenter.dismissChecking()
        userDriver?.invalidate()
        userDriver = nil
        // Sparkle aborts its driver and cancels the downloader in SPUUpdater.dealloc.
        // The timer holds only a weak reference, so the retired updater can be released.
        updater = nil
        isStarted = false
        hasAttemptedStart = false
        canCheckForUpdates = true
        let checkedAt = Date()
        lastCheckedAt = checkedAt
        defaults.set(checkedAt, forKey: PreferenceKey.lastCheck)
        if case .blocked = state { return }
        state = .failed(.checkTimeout)
    }

    func receivedDownloadProgress(_ progress: Double?) {
        downloadProgress = progress.map { min(1, max(0, $0)) }
    }

    func showCheckingPrompt(cancellation: @escaping () -> Void) {
        promptPresenter.show(AppUpdatePrompt(
            windowTitle: language().t("Software Update"),
            title: language().t("Checking for updates…"),
            detail: "", buttonTitle: language().t("Cancel"), isChecking: true, belongsToUpdateSession: true
        ), action: cancellation)
    }

    func dismissCheckingPrompt() {
        promptPresenter.dismissChecking()
    }

    func dismissPrompt() {
        promptPresenter.dismissUpdateSession()
    }

    func showPromptInFocus() -> Bool {
        promptPresenter.showInFocus()
    }

    func showCheckResult(_ error: Error, acknowledgement: @escaping () -> Void) {
        if case .blocked = state {
            acknowledgement()
            return
        }
        state = .upToDate
        let error = error as NSError
        showAlert(
            title: language() == .simplifiedChinese
                ? language().t("Updated to the latest version") : error.localizedDescription,
            detail: error.localizedRecoverySuggestion ?? language().t("You are up to date."),
            acknowledgement: acknowledgement, belongsToUpdateSession: true
        )
    }

    func showIssue(
        _ issue: AppUpdateIssue, acknowledgement: @escaping () -> Void = {},
        belongsToUpdateSession: Bool = false
    ) {
        state = .failed(issue)
        showAlert(title: language().t("Update unavailable"), detail: language().t(issue.rawValue),
                  acknowledgement: acknowledgement, belongsToUpdateSession: belongsToUpdateSession)
    }

    func handleError(_ error: Error, showingAlert: Bool, acknowledgement: @escaping () -> Void = {}) {
        let nsError = error as NSError
        if nsError.domain == "lex.Capricorn.UpdateBlocked" {
            acknowledgement()
            return
        }
        if (nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue)
            || (nsError.domain == SUSparkleErrorDomain && nsError.code == Int(SUError.installationCanceledError.rawValue)) {
            markPendingInstallation(false)
            acknowledgement()
            if case .blocked = state { return }
            state = .idle
            return
        }
        markPendingInstallation(false)
        if case .blocked = state {
            acknowledgement()
            return
        }
        let issue = Self.issue(for: nsError)
        if showingAlert {
            showIssue(issue, acknowledgement: acknowledgement, belongsToUpdateSession: true)
        } else {
            state = .failed(issue)
            acknowledgement()
        }
    }

    static func issue(for error: NSError, depth: Int = 0) -> AppUpdateIssue {
        guard depth < 8 else { return .installation }
        var children = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] ?? []
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { children.append(underlying) }
        let underlyingIssues = children.map { issue(for: $0, depth: depth + 1) }
        if underlyingIssues.contains(.signature) { return .signature }
        if error.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: error.code) {
            case .badServerResponse, .resourceUnavailable, .fileDoesNotExist: return .download
            default: return .network
            }
        }
        guard error.domain == SUSparkleErrorDomain else {
            return underlyingIssues.first(where: { $0 != .installation }) ?? .installation
        }
        switch SUError(rawValue: OSStatus(error.code)) {
        case .signatureError, .validationError, .insufficientSigningError: return .signature
        case .appcastError, .appcastParseError, .resumeAppcastError: return .feed
        // Sparkle also uses downloadError for HTTP failures, without a structured status code.
        case .downloadError: return underlyingIssues.first(where: { $0 != .installation }) ?? .download
        case .invalidFeedURLError, .insecureFeedURLError, .invalidUpdaterError,
             .invalidHostVersionError, .invalidHostBundleIdentifierError, .noPublicDSAFoundError:
            return .configuration
        default: return underlyingIssues.first(where: { $0 != .installation }) ?? .installation
        }
    }

    private func reportBlocked(_ error: Error) {
        if let blocked = error as? AppUpdateBlockedError {
            state = .blocked(blocked.conflicts)
            let tasks = blocked.conflicts.map { language().t($0.rawValue) }.joined(separator: "\n")
            showAlert(
                title: language().t("Update blocked"),
                detail: language().t("Finish or stop these tasks, then try updating again:") + "\n\n" + tasks
            )
        } else {
            showIssue(.save)
        }
    }

    private func showAlert(
        title: String, detail: String, acknowledgement: @escaping () -> Void = {},
        belongsToUpdateSession: Bool = false
    ) {
        if let presentAlert {
            presentAlert(title, detail)
            acknowledgement()
            return
        }
        promptPresenter.show(AppUpdatePrompt(
            windowTitle: language().t("Software Update"), title: title, detail: detail,
            buttonTitle: language().t("OK"), isChecking: false, belongsToUpdateSession: belongsToUpdateSession
        ), action: acknowledgement)
    }

    private func synchronizeSettings() {
        guard let updater else { return }
        canCheckForUpdates = updater.canCheckForUpdates
        lastCheckedAt = updater.lastUpdateCheckDate
    }

    // Launch checks and user-initiated updates share the same task guards.
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard authorizeUpdate() else { throw blockedNSError() }
        state = .checking
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard authorizeUpdate() else { throw blockedNSError() }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        finishLaunchCheckDeadline()
        state = .available(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        finishLaunchCheckDeadline()
        if case .blocked = state {
            synchronizeSettings()
            return
        }
        state = .upToDate
        synchronizeSettings()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        defer {
            finishLaunchCheckDeadline()
            isCancellingPreparedInstallation = false
            if quitsAfterCancellingUpdate {
                quitsAfterCancellingUpdate = false
                markPendingInstallation(false)
                let finishQuit = finishRequestedQuit
                Task { @MainActor in finishQuit() }
            }
        }
        synchronizeSettings()
        if let error {
            let nsError = error as NSError
            if nsError.domain == "lex.Capricorn.UpdateBlocked" { return }
            if nsError.domain == SUSparkleErrorDomain,
               [SUError.noUpdateError.rawValue, SUError.installationCanceledError.rawValue].contains(OSStatus(nsError.code)) {
                if nsError.code == Int(SUError.installationCanceledError.rawValue) {
                    markPendingInstallation(false)
                    if state != .upToDate { state = .idle }
                }
                return
            }
            handleError(error, showingAlert: false)
        }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard authorizeUpdate(installing: true) else {
            // Only an explicit Check for Updates action may retry this handler.
            postponedRelaunch = installHandler
            return true
        }
        return false
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        []
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { self.state = .available(update.displayVersionString) }
    }

    private func blockedNSError() -> NSError {
        NSError(domain: "lex.Capricorn.UpdateBlocked", code: 1, userInfo: [
            NSLocalizedDescriptionKey: language().t("Update blocked")
        ])
    }
}
