// SPDX-License-Identifier: GPL-3.0-only
import Sparkle
import XCTest
@testable import Capricorn

@MainActor
final class AppUpdaterTests: XCTestCase {
    func testApplicationBundleContainsStrictSignedUpdateConfiguration() throws {
        let info = try XCTUnwrap(Bundle(for: AppUpdater.self).infoDictionary)
        let configuration = try AppUpdateConfiguration(info: info)
        XCTAssertEqual(configuration.feedURL.scheme, "https")
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info["SUSignedFeedFailureExpirationInterval"] as? Int, 0)
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
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

    func testPendingQuitInstallationIsBlockedAndDoesNotReserve() {
        var conflicts: [AppUpdateConflict] = [.workload]
        let gate = AppUpdateSafetyGate(conflicts: { conflicts })
        let updater = AppUpdater(safety: gate, language: { .english }, allowsStartup: false, presentAlert: { _, _ in })
        updater.markPendingInstallation(true)
        XCTAssertFalse(updater.applicationMayTerminate())
        XCTAssertFalse(gate.isReserved)
        conflicts = []
        XCTAssertFalse(gate.isReserved)
        XCTAssertTrue(updater.applicationMayTerminate())
        XCTAssertTrue(gate.isReserved)
        updater.markPendingInstallation(false)
        XCTAssertFalse(gate.isReserved)
    }

    func testNewConflictWithPreparedAutomaticUpdatePresentsWarningOnce() {
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
}

@MainActor
private final class RecordingUpdateUserDriver: NSObject, SPUUserDriver {
    var readyReply: ((SPUUserUpdateChoice) -> Void)?
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {}
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {}
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {}
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
