// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Observation
import SwiftUI

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

@MainActor
@Observable
private final class AppUpdatePromptModel {
    var prompt: AppUpdatePrompt?
    @ObservationIgnored var action: (() -> Void)?
}

/// Sparkle callbacks update one window without changing its size or position.
@MainActor
final class AppUpdatePromptController: NSObject, AppUpdatePromptPresenting, NSWindowDelegate {
    fileprivate static let windowSize = NSSize(width: 263, height: 202)
    fileprivate static let contentSize = NSWindow.contentRect(
        forFrameRect: NSRect(origin: .zero, size: windowSize), styleMask: [.titled, .closable]
    ).size
    private let model = AppUpdatePromptModel()
    private var response: (() -> Void)?
    private(set) var window: NSWindow?

    func show(_ prompt: AppUpdatePrompt, action: @escaping () -> Void) {
        let wasVisible = window?.isVisible == true
        // A replaced result must still acknowledge Sparkle; a completed check must not cancel it.
        let previousResponse = model.prompt?.isChecking == false ? response : nil
        response = nil
        previousResponse?()
        if window == nil { makeWindow() }
        guard let window else { return }
        model.prompt = prompt
        response = action
        window.title = prompt.windowTitle
        if !wasVisible { position(window) }
        window.makeKeyAndOrderFront(nil)
    }

    func dismissChecking() {
        guard model.prompt?.isChecking == true else { return }
        hide()
    }

    func dismiss() {
        let acknowledgement = model.prompt?.isChecking == false ? response : nil
        hide()
        acknowledgement?()
    }

    func dismissUpdateSession() {
        guard model.prompt?.belongsToUpdateSession == true else { return }
        dismiss()
    }

    func showInFocus() -> Bool {
        guard let window, window.isVisible else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        respond()
        return false
    }

    private func respond() {
        let action = response
        hide()
        action?()
    }

    private func hide() {
        response = nil
        model.prompt = nil
        window?.orderOut(nil)
    }

    private func makeWindow() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("appUpdatePrompt")
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.contentViewController = NSHostingController(rootView: AppUpdatePromptView(model: model))
        // Include window chrome in the old alert's outer dimensions.
        window.setFrame(NSRect(origin: .zero, size: Self.windowSize), display: false)
        window.delegate = self
        model.action = { [weak self] in self?.respond() }
        self.window = window
    }

    private func position(_ window: NSWindow) {
        let owner = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }.first { $0 !== window }
        let visible = (owner?.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let anchor = owner?.frame ?? visible
        let size = window.frame.size
        let origin = NSPoint(
            x: min(max(anchor.midX - size.width / 2, visible.minX), visible.maxX - size.width),
            y: min(max(anchor.midY - size.height / 2, visible.minY), visible.maxY - size.height)
        )
        window.setFrameOrigin(origin)
    }
}

private struct AppUpdatePromptView: View {
    let model: AppUpdatePromptModel

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            if let prompt = model.prompt {
                Text(prompt.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .accessibilityIdentifier("appUpdatePromptTitle")

                Group {
                    if prompt.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        ViewThatFits(in: .vertical) {
                            detailText(prompt.detail)
                            ScrollView { detailText(prompt.detail) }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                .frame(height: 42)

                if prompt.isChecking {
                    actionButton(prompt.buttonTitle)
                        .keyboardShortcut(.cancelAction)
                } else {
                    actionButton(prompt.buttonTitle)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(8)
        .frame(width: AppUpdatePromptController.contentSize.width, height: AppUpdatePromptController.contentSize.height)
        .background(.regularMaterial)
    }

    private func actionButton(_ title: String) -> some View {
        Button(action: { model.action?() }) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .frame(height: 26)
        .accessibilityIdentifier("appUpdatePromptAction")
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}
