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

/// Present native alerts with their own modal lifecycle, preserving the center between states.
@MainActor
final class AppUpdatePromptController: NSObject, AppUpdatePromptPresenting {
    private var prompt: AppUpdatePrompt?
    private var response: (() -> Void)?
    private var runningAlert: NSAlert?
    private var presentationScheduled = false
    private(set) var alert: NSAlert?
    var window: NSWindow? { alert?.window }

    func show(_ prompt: AppUpdatePrompt, action: @escaping () -> Void) {
        let previousCenter = window.flatMap { $0.isVisible ? NSPoint(x: $0.frame.midX, y: $0.frame.midY) : nil }
        // A replaced result must still acknowledge Sparkle; a completed check must not cancel it.
        let previousResponse = self.prompt?.isChecking == false ? response : nil
        hide()
        previousResponse?()
        // NSAlert can retain an accessory's view hierarchy after accessoryView becomes nil.
        let alert = makeAlert(prompt)
        self.alert = alert
        let window = alert.window
        self.prompt = prompt
        response = action
        alert.layout()
        position(window, center: previousCenter)
        window.makeKeyAndOrderFront(nil)
        schedulePresentation()
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

    private func schedulePresentation() {
        guard prompt != nil, runningAlert == nil, !presentationScheduled else { return }
        presentationScheduled = true
        RunLoop.main.perform(inModes: [.common, .modalPanel]) { [weak self] in
            MainActor.assumeIsolated { self?.runPresentation() }
        }
    }

    private func runPresentation() {
        presentationScheduled = false
        guard runningAlert == nil, prompt != nil, let alert else { return }
        runningAlert = alert
        // NSAlert owns event routing and its reserved button actions. Polling an
        // NSApplication modal session alone does not handle real mouse clicks reliably.
        alert.runModal()
        runningAlert = nil
        if self.alert === alert, prompt != nil { respond() }
        // A replacement waits for the old modal loop to unwind before entering its own.
        schedulePresentation()
    }

    private func respond() {
        let action = response
        hide()
        action?()
    }

    private func hide() {
        response = nil
        prompt = nil
        if let runningAlert, NSApp.modalWindow === runningAlert.window {
            NSApp.abortModal()
            // A network/timer callback can finish while AppKit is waiting for an
            // event. Wake that wait so the old modal loop exits before replacement.
            if let event = NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: runningAlert.window.windowNumber, context: nil,
                subtype: 0, data1: 0, data2: 0
            ) {
                NSApp.postEvent(event, atStart: true)
            }
        }
        alert?.accessoryView?.subviews.compactMap { $0 as? NSProgressIndicator }.forEach {
            $0.stopAnimation(nil)
        }
        alert?.accessoryView?.removeFromSuperview()
        alert?.accessoryView = nil
        window?.orderOut(nil)
    }

    private func makeAlert(_ prompt: AppUpdatePrompt) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApplication.shared.applicationIconImage
        alert.messageText = prompt.title
        alert.informativeText = AppUpdatePromptText.paragraphs(prompt.detail)
        alert.addButton(withTitle: prompt.buttonTitle)
        alert.buttons[0].keyEquivalent = prompt.isChecking ? "\u{1b}" : "\r"
        let window = alert.window
        window.title = prompt.windowTitle
        window.identifier = NSUserInterfaceItemIdentifier("appUpdatePrompt")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        if prompt.isChecking {
            let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 20))
            let indicator = NSProgressIndicator(frame: NSRect(x: 106, y: 2, width: 16, height: 16))
            indicator.style = .spinning
            indicator.controlSize = .small
            indicator.isIndeterminate = true
            accessory.addSubview(indicator)
            alert.accessoryView = accessory
            indicator.startAnimation(nil)
        }
        return alert
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
