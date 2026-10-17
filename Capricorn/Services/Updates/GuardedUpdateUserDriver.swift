// SPDX-License-Identifier: GPL-3.0-only
import Sparkle

/// Use one app-owned check/result prompt and keep Sparkle's update UI and installer.
/// The updater delegate alone cannot veto all resume/installation paths.
@MainActor
final class GuardedUpdateUserDriver: NSObject, SPUUserDriver {
    private let standard: SPUUserDriver
    private weak var owner: AppUpdater?
    private(set) var cancelDownload: (() -> Void)?
    private(set) var cancelCheck: (() -> Void)?
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0

    init(standard: SPUUserDriver, owner: AppUpdater) {
        self.standard = standard
        self.owner = owner
    }

    func cancelActiveDownload() {
        let cancellation = cancelDownload
        cancelDownload = nil
        cancellation?()
    }

    func cancelActiveCheck() {
        let cancellation = cancelCheck
        cancelCheck = nil
        owner?.dismissCheckingPrompt()
        if owner?.state == .checking { owner?.transition(to: .idle) }
        cancellation?()
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standard.show(request) { response in
            reply(SUUpdatePermissionResponse(
                automaticUpdateChecks: response.automaticUpdateChecks,
                automaticUpdateDownloading: response.automaticUpdateDownloading,
                sendSystemProfile: false
            ))
        }
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        owner?.transition(to: .checking)
        cancelCheck = cancellation
        if let owner {
            owner.showCheckingPrompt { [weak self] in self?.cancelActiveCheck() }
        } else {
            standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
        }
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancelCheck = nil
        owner?.dismissCheckingPrompt()
        // A prepared installer may survive the previous app process.
        if state.stage == .installing { owner?.markPendingInstallation(true) }
        guard owner?.authorizeUpdate() == true else {
            if state.stage == .installing { owner?.markPendingInstallation(false) }
            reply(state.stage == .installing ? .skip : .dismiss)
            return
        }
        standard.showUpdateFound(with: appcastItem, state: state) { [weak self] choice in
            guard let self else { reply(.dismiss); return }
            if choice == .install,
               self.owner?.authorizeUpdate(installing: state.stage == .installing) != true {
                if state.stage == .installing { self.owner?.markPendingInstallation(false) }
                reply(state.stage == .installing ? .skip : .dismiss)
            } else {
                if choice == .skip { self.owner?.markPendingInstallation(false) }
                reply(choice)
            }
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        standard.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        cancelCheck = nil
        if let owner {
            owner.showCheckResult(error, acknowledgement: acknowledgement)
        } else {
            standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
        }
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        cancelCheck = nil
        standard.dismissUpdateInstallation()
        if let owner {
            owner.handleError(error, showingAlert: true, acknowledgement: acknowledgement)
        } else {
            acknowledgement()
        }
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
        cancelDownload = cancellation
        owner?.transition(to: .downloading)
        owner?.receivedDownloadProgress(nil)
        standard.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
        standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength = receivedLength.addingReportingOverflow(length).partialValue
        owner?.receivedDownloadProgress(expectedLength > 0 ? Double(receivedLength) / Double(expectedLength) : nil)
        standard.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        cancelDownload = nil
        owner?.markPendingInstallation(true)
        owner?.transition(to: .extracting)
        standard.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        standard.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard owner?.authorizeUpdate() == true else {
            owner?.markPendingInstallation(false)
            reply(.skip)
            return
        }
        owner?.transition(to: .readyToInstall)
        standard.showReady(toInstallAndRelaunch: { [weak self] choice in
            guard let self else { reply(.skip); return }
            if choice == .install && self.owner?.authorizeUpdate(installing: true) != true {
                self.owner?.markPendingInstallation(false)
                reply(.skip)
            } else {
                if choice == .skip { self.owner?.markPendingInstallation(false) }
                reply(choice)
            }
        })
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        owner?.transition(to: .installing)
        standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated) { [weak self] in
            guard self?.owner?.authorizeUpdate(installing: true) == true else { return }
            retryTerminatingApplication()
        }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        owner?.markPendingInstallation(false)
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func dismissUpdateInstallation() {
        cancelDownload = nil
        cancelCheck = nil
        owner?.dismissPrompt()
        standard.dismissUpdateInstallation()
        if owner?.hasPendingInstallation == false { owner?.safety.endInstallation() }
    }

    func showUpdateInFocus() {
        if owner?.showPromptInFocus() == true { return }
        standard.showUpdateInFocus?()
    }
}
