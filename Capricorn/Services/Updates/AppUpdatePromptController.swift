// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NaturalLanguage

struct AppUpdatePrompt: Equatable {
    let windowTitle: String
    let title: String
    let detail: String
    let buttonTitle: String
    let isChecking: Bool
    let belongsToUpdateSession: Bool
}

@MainActor
protocol AppUpdatePromptPresenting: AnyObject {
    func show(_ prompt: AppUpdatePrompt, action: @escaping () -> Void)
    func dismissUpdateSession()
    func dismissChecking()
    func showInFocus() -> Bool
}

enum AppUpdatePromptText {
    static func paragraphs(_ text: String) -> String {
        guard text.range(of: #"\p{Han}"#, options: .regularExpression) != nil else { return text }
        // Preserve explicit paragraphs and lists while recognizing real sentence boundaries.
        return text.components(separatedBy: "\n").map { paragraph in
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = paragraph
            tokenizer.setLanguage(.simplifiedChinese)
            let sentences = tokenizer.tokens(for: paragraph.startIndex..<paragraph.endIndex).map {
                String(paragraph[$0]).trimmingCharacters(in: .whitespaces)
            }
            return sentences.isEmpty ? paragraph : sentences.joined(separator: "\n")
        }.joined(separator: "\n")
    }
}

/// Reuse the original system alert, preserving its center as native layout adapts to the message.
@MainActor
final class AppUpdatePromptController: NSObject, AppUpdatePromptPresenting {
    private var prompt: AppUpdatePrompt?
    private var response: (() -> Void)?
    private var progressAccessory: NSView?
    private var progressIndicator: NSProgressIndicator?
    private var modalSession: NSApplication.ModalSession?
    private var modalPoll: Timer?
    private var isPollingModalSession = false
    private(set) var alert: NSAlert?
    var window: NSWindow? { alert?.window }

    func show(_ prompt: AppUpdatePrompt, action: @escaping () -> Void) {
        pollModalSession()
        let previousCenter = window.flatMap { $0.isVisible ? NSPoint(x: $0.frame.midX, y: $0.frame.midY) : nil }
        // A replaced result must still acknowledge Sparkle; a completed check must not cancel it.
        let previousResponse = self.prompt?.isChecking == false ? response : nil
        response = nil
        previousResponse?()
        if alert == nil { makeAlert() }
        guard let alert, let window else { return }
        self.prompt = prompt
        response = action
        alert.messageText = prompt.title
        alert.informativeText = AppUpdatePromptText.paragraphs(prompt.detail)
        alert.buttons[0].title = prompt.buttonTitle
        alert.accessoryView = prompt.isChecking ? progressAccessory : nil
        if prompt.isChecking {
            progressIndicator?.startAnimation(nil)
        } else {
            progressIndicator?.stopAnimation(nil)
        }
        alert.layout()
        let button = alert.buttons[0]
        button.keyEquivalent = prompt.isChecking ? "\u{1b}" : "\r"
        window.title = prompt.windowTitle
        position(window, center: previousCenter)
        window.makeKeyAndOrderFront(nil)
        if modalSession == nil {
            // A nonblocking modal session keeps NSAlert's reserved button actions intact.
            modalSession = NSApp.beginModalSession(for: window)
            let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                MainActor.assumeIsolated { self.pollModalSession() }
            }
            modalPoll = timer
            RunLoop.main.add(timer, forMode: .common)
            pollModalSession()
        }
    }

    func dismissChecking() {
        guard prompt?.isChecking == true else { return }
        hide()
    }

    func dismiss() {
        let acknowledgement = prompt?.isChecking == false ? response : nil
        hide()
        acknowledgement?()
    }

    func dismissUpdateSession() {
        guard prompt?.belongsToUpdateSession == true else { return }
        dismiss()
    }

    func showInFocus() -> Bool {
        guard let window, window.isVisible else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    private func pollModalSession() {
        guard let modalSession, !isPollingModalSession else { return }
        isPollingModalSession = true
        defer { isPollingModalSession = false }
        if NSApp.runModalSession(modalSession) != .continue { respond() }
    }

    private func respond() {
        let action = response
        hide()
        action?()
    }

    private func hide() {
        response = nil
        prompt = nil
        modalPoll?.invalidate()
        modalPoll = nil
        if let modalSession {
            NSApp.endModalSession(modalSession)
            self.modalSession = nil
        }
        progressIndicator?.stopAnimation(nil)
        window?.orderOut(nil)
    }

    private func makeAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApplication.shared.applicationIconImage
        alert.addButton(withTitle: "")
        let window = alert.window
        window.identifier = NSUserInterfaceItemIdentifier("appUpdatePrompt")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 20))
        let indicator = NSProgressIndicator(frame: NSRect(x: 106, y: 2, width: 16, height: 16))
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isIndeterminate = true
        accessory.addSubview(indicator)
        progressAccessory = accessory
        progressIndicator = indicator
        self.alert = alert
    }

    private func position(_ window: NSWindow, center: NSPoint?) {
        let owner = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }.first { $0 !== window }
        let visible = (owner?.screen ?? window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let anchor = owner?.frame ?? visible
        let center = center ?? NSPoint(x: anchor.midX, y: anchor.midY)
        let size = window.frame.size
        let origin = NSPoint(
            x: min(max(center.x - size.width / 2, visible.minX), visible.maxX - size.width),
            y: min(max(center.y - size.height / 2, visible.minY), visible.maxY - size.height)
        )
        window.setFrameOrigin(origin)
    }
}
