// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import XCTest
@testable import Capricorn

@MainActor
final class AppUpdatePromptTests: XCTestCase {
    func testCheckErrorAndResultUseFreshNativeAlertsAndKeepTheirCenter() throws {
        let presenter = AppUpdatePromptController()
        var cancellations = 0
        presenter.show(prompt(checking: true)) { cancellations += 1 }
        let window = try XCTUnwrap(presenter.window)
        defer { presenter.dismiss() }
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        XCTAssertEqual(presenter.alert?.alertStyle, .informational)
        var errorAcknowledgements = 0
        presenter.show(prompt(checking: false, detail: String(repeating: "Long error. ", count: 8))) {
            errorAcknowledgements += 1
            presenter.dismiss()
        }
        let errorWindow = try XCTUnwrap(presenter.window)
        XCTAssertFalse(errorWindow === window)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(errorWindow.frame.midX, center.x, accuracy: 1)
        XCTAssertEqual(errorWindow.frame.midY, center.y, accuracy: 1)
        XCTAssertFalse(Self.containsProgressIndicator(in: errorWindow.contentView))
        XCTAssertEqual(cancellations, 0, "Completing a check must not invoke its cancellation")
        presenter.dismissChecking()
        XCTAssertTrue(errorWindow.isVisible, "A result stays visible until acknowledged")
        var resultAcknowledgements = 0
        presenter.show(prompt(checking: false)) { resultAcknowledgements += 1 }
        XCTAssertEqual(errorAcknowledgements, 1, "Replacing a result must release Sparkle's callback")
        XCTAssertEqual(presenter.window!.frame.midX, center.x, accuracy: 1)
        XCTAssertEqual(presenter.window!.frame.midY, center.y, accuracy: 1)
        respondToModalAlert(presenter)
        XCTAssertEqual(resultAcknowledgements, 1)
        XCTAssertFalse(presenter.window!.isVisible)
    }

    func testCancelButtonRunsOnceButProgrammaticDismissalDoesNotCancel() throws {
        let presenter = AppUpdatePromptController()
        var cancellations = 0
        presenter.show(prompt(checking: true)) { cancellations += 1 }
        let window = try XCTUnwrap(presenter.window)
        respondToModalAlert(presenter)
        XCTAssertEqual(cancellations, 1)
        presenter.show(prompt(checking: true)) { cancellations += 1 }
        presenter.dismissChecking()
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(cancellations, 1)
    }

    func testAbortedSessionDismissesResultAndAcknowledgesOnlyOnce() throws {
        let presenter = AppUpdatePromptController()
        var acknowledgements = 0
        presenter.show(prompt(checking: false)) { acknowledgements += 1 }
        let window = try XCTUnwrap(presenter.window)
        presenter.dismissUpdateSession()
        presenter.dismissUpdateSession()
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(acknowledgements, 1)
    }

    func testSessionTeardownLeavesAppOwnedConflictWarningVisible() throws {
        let presenter = AppUpdatePromptController()
        var acknowledgements = 0
        presenter.show(AppUpdatePrompt(
            windowTitle: "Software Update", title: "Update blocked", detail: "Benchmark",
            buttonTitle: "OK", isChecking: false, belongsToUpdateSession: false
        )) { acknowledgements += 1 }
        let window = try XCTUnwrap(presenter.window)
        presenter.dismissUpdateSession()
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(acknowledgements, 0)
        respondToModalAlert(presenter)
        XCTAssertEqual(acknowledgements, 1)
    }

    func testRunningCheckTransitionsToResultWithoutStaleSpinnerOrModalSession() throws {
        let presenter = AppUpdatePromptController()
        defer { presenter.dismiss() }
        var cancellations = 0
        var acknowledgements = 0
        for _ in 0..<2 {
            presenter.show(prompt(checking: true)) { cancellations += 1 }
            let checkingWindow = try XCTUnwrap(presenter.window)
            XCTAssertTrue(Self.containsProgressIndicator(in: checkingWindow.contentView))
            let resultPrompt = prompt(checking: false, detail: "Capricorn 2.10.2 是当前的最新版本。")
            let transition = Timer(timeInterval: 0.02, repeats: false) { _ in
                MainActor.assumeIsolated {
                    XCTAssertTrue(NSApp.modalWindow === checkingWindow)
                    presenter.show(resultPrompt) {
                        acknowledgements += 1
                    }
                    XCTAssertFalse(checkingWindow.isVisible)
                    XCTAssertFalse(Self.containsProgressIndicator(in: presenter.window?.contentView))
                }
            }
            RunLoop.main.add(transition, forMode: .modalPanel)
            respondToModalAlert(presenter, delay: 0.05)
            XCTAssertFalse(presenter.window!.isVisible)
            XCTAssertNil(NSApp.modalWindow)
        }
        XCTAssertEqual(cancellations, 0)
        XCTAssertEqual(acknowledgements, 2)
    }

    func testChinesePromptBreaksAtSentencesWithoutBreakingVersionsOrURLs() {
        let text = "Capricorn 2.10.2 无法更新。请打开 https://github.com/LexTheAries2209/Capricorn。稍后重试！"
        XCTAssertEqual(
            AppUpdatePromptText.paragraphs(text),
            "Capricorn 2.10.2 无法更新。\n请打开 https://github.com/LexTheAries2209/Capricorn。\n稍后重试！"
        )
        XCTAssertEqual(
            AppUpdatePromptText.displayText(text),
            "Capricorn 2.10.2 无法更新\n请打开 https://github.com/LexTheAries2209/Capricorn\n稍后重试"
        )
        XCTAssertEqual(AppUpdatePromptText.displayText("https://example.com/update!"), "https://example.com/update!")
    }

    func testSentenceBreaksPreserveExistingParagraphsAndTaskLists() {
        XCTAssertEqual(
            AppUpdatePromptText.paragraphs("更新被阻止。请先停止任务。\n\n测速\nSMART 自检"),
            "更新被阻止。\n请先停止任务。\n\n测速\nSMART 自检"
        )
        let english = "Unable to download updates. Check your network or Releases."
        XCTAssertEqual(AppUpdatePromptText.paragraphs(english), english)
    }

    func testNativeAlertReceivesSentenceFormattedText() {
        let presenter = AppUpdatePromptController()
        defer { presenter.dismiss() }
        presenter.show(AppUpdatePrompt(
            windowTitle: "软件更新", title: "暂时无法更新！",
            detail: "无法下载更新。请检查网络或查看 Releases。",
            buttonTitle: "好", isChecking: false, belongsToUpdateSession: true
        )) {}
        XCTAssertEqual(presenter.alert?.messageText, "暂时无法更新")
        XCTAssertEqual(presenter.alert?.informativeText, "无法下载更新\n请检查网络或查看 Releases")
    }

    private func prompt(checking: Bool, detail: String = "") -> AppUpdatePrompt {
        AppUpdatePrompt(
            windowTitle: "Software Update", title: checking ? "Checking for updates…" : "Update result",
            detail: detail, buttonTitle: checking ? "Cancel" : "OK", isChecking: checking,
            belongsToUpdateSession: true
        )
    }

    private static func containsProgressIndicator(in view: NSView?) -> Bool {
        guard let view else { return false }
        return view is NSProgressIndicator || view.subviews.contains { containsProgressIndicator(in: $0) }
    }

    private func respondToModalAlert(_ presenter: AppUpdatePromptController, delay: TimeInterval = 0.02) {
        var didRespond = false
        let responseTimer = Timer(timeInterval: delay, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard NSApp.modalWindow === presenter.window else { return }
                timer.invalidate()
                presenter.alert?.buttons.first?.performClick(nil)
                didRespond = true
            }
        }
        let watchdog = Timer(timeInterval: 1, repeats: false) { _ in
            MainActor.assumeIsolated {
                XCTFail("Native alert did not finish its modal session")
                presenter.dismiss()
            }
        }
        RunLoop.main.add(responseTimer, forMode: .modalPanel)
        RunLoop.main.add(watchdog, forMode: .common)
        RunLoop.main.add(watchdog, forMode: .modalPanel)
        defer {
            responseTimer.invalidate()
            watchdog.invalidate()
        }
        let deadline = Date().addingTimeInterval(1)
        while !didRespond, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(didRespond)
    }
}
