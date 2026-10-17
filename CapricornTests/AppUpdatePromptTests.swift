// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import XCTest
@testable import Capricorn

@MainActor
final class AppUpdatePromptTests: XCTestCase {
    func testCheckErrorAndResultReuseWindowWithoutMovingOrResizing() throws {
        let presenter = AppUpdatePromptController()
        var cancellations = 0
        presenter.show(prompt(checking: true)) { cancellations += 1 }
        let window = try XCTUnwrap(presenter.window)
        defer { window.performClose(nil) }
        let frame = window.frame
        var errorAcknowledgements = 0
        presenter.show(prompt(checking: false, detail: String(repeating: "Long error. ", count: 80))) {
            errorAcknowledgements += 1
            presenter.dismiss()
        }
        XCTAssertTrue(presenter.window === window)
        XCTAssertEqual(window.frame, frame)
        XCTAssertEqual(cancellations, 0, "Completing a check must not invoke its cancellation")
        presenter.dismissChecking()
        XCTAssertTrue(window.isVisible, "A result stays visible until acknowledged")
        var resultAcknowledgements = 0
        presenter.show(prompt(checking: false)) { resultAcknowledgements += 1 }
        XCTAssertEqual(errorAcknowledgements, 1, "Replacing a result must release Sparkle's callback")
        XCTAssertEqual(window.frame, frame)
        window.performClose(nil)
        window.performClose(nil)
        XCTAssertEqual(resultAcknowledgements, 1)
        XCTAssertFalse(window.isVisible)
    }

    func testClosingCheckCancelsOnceButProgrammaticDismissalDoesNot() throws {
        let presenter = AppUpdatePromptController()
        var cancellations = 0
        presenter.show(prompt(checking: true)) { cancellations += 1 }
        let window = try XCTUnwrap(presenter.window)
        window.performClose(nil)
        window.performClose(nil)
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
        window.performClose(nil)
        XCTAssertEqual(acknowledgements, 1)
    }

    private func prompt(checking: Bool, detail: String = "") -> AppUpdatePrompt {
        AppUpdatePrompt(
            windowTitle: "Software Update", title: checking ? "Checking for updates…" : "Update result",
            detail: detail, buttonTitle: checking ? "Cancel" : "OK", isChecking: checking,
            belongsToUpdateSession: true
        )
    }
}
