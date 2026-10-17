// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import XCTest
@testable import Capricorn

@MainActor
final class AppUpdatePromptTests: XCTestCase {
    func testCheckErrorAndResultReuseNativeAlertAndKeepItsCenter() throws {
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
        XCTAssertTrue(presenter.window === window)
        XCTAssertEqual(window.frame.midX, center.x, accuracy: 1)
        XCTAssertEqual(window.frame.midY, center.y, accuracy: 1)
        XCTAssertEqual(cancellations, 0, "Completing a check must not invoke its cancellation")
        presenter.dismissChecking()
        XCTAssertTrue(window.isVisible, "A result stays visible until acknowledged")
        var resultAcknowledgements = 0
        presenter.show(prompt(checking: false)) { resultAcknowledgements += 1 }
        XCTAssertEqual(errorAcknowledgements, 1, "Replacing a result must release Sparkle's callback")
        XCTAssertEqual(window.frame.midX, center.x, accuracy: 1)
        XCTAssertEqual(window.frame.midY, center.y, accuracy: 1)
        presenter.alert?.buttons.first?.performClick(nil)
        presenter.alert?.buttons.first?.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        XCTAssertEqual(resultAcknowledgements, 1)
        XCTAssertFalse(window.isVisible)
    }

    func testCancelButtonRunsOnceButProgrammaticDismissalDoesNotCancel() throws {
        let presenter = AppUpdatePromptController()
        var cancellations = 0
        presenter.show(prompt(checking: true)) { cancellations += 1 }
        let window = try XCTUnwrap(presenter.window)
        presenter.alert?.buttons.first?.performClick(nil)
        presenter.alert?.buttons.first?.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
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
        presenter.alert?.buttons.first?.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        XCTAssertEqual(acknowledgements, 1)
    }

    func testChinesePromptBreaksAtSentencesWithoutBreakingVersionsOrURLs() {
        let text = "Capricorn 2.10.2 无法更新。请打开 https://github.com/LexTheAries2209/Capricorn。稍后重试！"
        XCTAssertEqual(
            AppUpdatePromptText.paragraphs(text),
            "Capricorn 2.10.2 无法更新。\n请打开 https://github.com/LexTheAries2209/Capricorn。\n稍后重试！"
        )
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
        presenter.show(prompt(checking: false, detail: "无法下载更新。请检查网络或查看 Releases。")) {}
        XCTAssertEqual(presenter.alert?.informativeText, "无法下载更新。\n请检查网络或查看 Releases。")
    }

    private func prompt(checking: Bool, detail: String = "") -> AppUpdatePrompt {
        AppUpdatePrompt(
            windowTitle: "Software Update", title: checking ? "Checking for updates…" : "Update result",
            detail: detail, buttonTitle: checking ? "Cancel" : "OK", isChecking: checking,
            belongsToUpdateSession: true
        )
    }
}
