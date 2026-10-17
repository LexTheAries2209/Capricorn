// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private(set) var state: AppUpdaterState = .idle
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var automaticallyDownloadsUpdates = false
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
    @ObservationIgnored private let presentAlert: ((String, String) -> Void)?
    @ObservationIgnored private var isShowingAlert = false
    @ObservationIgnored private var hasAttemptedStart = false
    @ObservationIgnored private var postponedRelaunch: (() -> Void)?

    init(
        safety: AppUpdateSafetyGate,
        language: @escaping () -> AppLanguage,
        hostBundle: Bundle = .main,
        allowsStartup: Bool = ApplicationRuntime.allowsAutomaticStartupTasks,
        presentAlert: ((String, String) -> Void)? = nil
    ) {
        self.safety = safety
        self.language = language
        nativeLanguage = language()
        self.hostBundle = hostBundle
        self.allowsStartup = allowsStartup
        self.presentAlert = presentAlert
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
            try updater.start()
            isStarted = true
            observations = [
                updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.synchronizeSettings() }
                },
                updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.synchronizeSettings() }
                },
                updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.synchronizeSettings() }
                }
            ]
            synchronizeSettings()
        } catch {
            state = .failed(.configuration)
        }
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
        updater?.automaticallyChecksForUpdates = enabled
        synchronizeSettings()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updater?.automaticallyDownloadsUpdates = enabled
        synchronizeSettings()
    }

    func conflictsDidChange() {
        guard !safety.isReserved else { return }
        do {
            try safety.check()
            if case .blocked = state { state = .idle }
        } catch {
            guard userDriver?.cancelDownload != nil || updater?.sessionInProgress == true || hasPendingInstallation else { return }
            userDriver?.cancelActiveDownload()
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
        guard hasPendingInstallation || safety.isReserved else { return true }
        return authorizeUpdate(installing: true)
    }

    func markPendingInstallation(_ pending: Bool) {
        hasPendingInstallation = pending
        if !pending {
            postponedRelaunch = nil
            safety.endInstallation()
        }
    }

    func transition(to state: AppUpdaterState) {
        self.state = state
    }

    func receivedDownloadProgress(_ progress: Double?) {
        downloadProgress = progress.map { min(1, max(0, $0)) }
    }

    func showIssue(_ issue: AppUpdateIssue) {
        state = .failed(issue)
        showAlert(title: language().t("Update unavailable"), detail: language().t(issue.rawValue))
    }

    func handleError(_ error: Error, showingAlert: Bool) {
        let nsError = error as NSError
        if nsError.domain == "lex.Capricorn.UpdateBlocked" { return }
        if (nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue)
            || (nsError.domain == SUSparkleErrorDomain && nsError.code == Int(SUError.installationCanceledError.rawValue)) {
            markPendingInstallation(false)
            if case .blocked = state { return }
            state = .idle
            return
        }
        let issue = Self.issue(for: nsError)
        markPendingInstallation(false)
        if showingAlert {
            showIssue(issue)
        } else if case .blocked = state {
            return
        } else {
            state = .failed(issue)
        }
    }

    static func issue(for error: NSError, depth: Int = 0) -> AppUpdateIssue {
        guard depth < 8 else { return .installation }
        var children = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] ?? []
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { children.append(underlying) }
        let underlyingIssues = children.map { issue(for: $0, depth: depth + 1) }
        if underlyingIssues.contains(.signature) { return .signature }
        if error.domain == NSURLErrorDomain { return .network }
        guard error.domain == SUSparkleErrorDomain else {
            return underlyingIssues.first(where: { $0 != .installation }) ?? .installation
        }
        switch SUError(rawValue: OSStatus(error.code)) {
        case .signatureError, .validationError, .insufficientSigningError: return .signature
        case .appcastError, .appcastParseError, .resumeAppcastError: return .feed
        case .downloadError: return .network
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

    private func showAlert(title: String, detail: String) {
        if let presentAlert {
            presentAlert(title, detail)
            return
        }
        guard !isShowingAlert else { return }
        isShowingAlert = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: language().t("OK"))
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil {
            alert.beginSheetModal(for: window) { [weak self] _ in self?.isShowingAlert = false }
        } else {
            alert.runModal()
            isShowingAlert = false
        }
    }

    private func synchronizeSettings() {
        guard let updater else { return }
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        lastCheckedAt = updater.lastUpdateCheckDate
    }

    // Sparkle calls these for scheduled checks too, including background downloads.
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard authorizeUpdate() else { throw blockedNSError() }
        state = .checking
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard authorizeUpdate() else { throw blockedNSError() }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        state = .available(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        state = .upToDate
        synchronizeSettings()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
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

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        hasPendingInstallation = true
        _ = authorizeUpdate()
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
