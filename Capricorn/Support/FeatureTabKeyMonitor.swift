// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct FeatureTabKeyMonitor: NSViewRepresentable {
    var onOpenSettings: () -> Void
    var onNext: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onOpenSettings: onOpenSettings,
            onNext: onNext
        )
    }

    func makeNSView(context: Context) -> FeatureTabKeyMonitorView {
        let view = FeatureTabKeyMonitorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: FeatureTabKeyMonitorView, context: Context) {
        context.coordinator.onNext = onNext
        context.coordinator.onOpenSettings = onOpenSettings
        context.coordinator.window = nsView.window
    }

    static func dismantleNSView(_ nsView: FeatureTabKeyMonitorView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    final class Coordinator {
        var onOpenSettings: () -> Void
        var onNext: () -> Void
        weak var window: NSWindow?
        private var monitor: Any?

        init(
            onOpenSettings: @escaping () -> Void,
            onNext: @escaping () -> Void
        ) {
            self.onOpenSettings = onOpenSettings
            self.onNext = onNext
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        deinit {
            invalidate()
        }

        func invalidate() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            let relevantModifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
            let hasDisqualifyingModifiers = relevantModifiers.contains(.control)
                || relevantModifiers.contains(.option)
                || relevantModifiers.contains(.command)

            if AppSettingsKeyRouter.matches(
                keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                hasDisqualifyingModifiers: hasDisqualifyingModifiers
            ) {
                onOpenSettings()
                return nil
            }

            guard AppFeatureTabKeyRouter.matches(
                keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                hasModifiers: !relevantModifiers.isEmpty
            ) else {
                return event
            }
            onNext()
            return nil
        }
    }
}

final class FeatureTabKeyMonitorView: NSView {
    weak var coordinator: FeatureTabKeyMonitor.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.window = window
    }
}
