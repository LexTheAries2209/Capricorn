// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct FeatureTabKeyMonitor: NSViewRepresentable {
    var isEnabled: Bool
    var onNext: () -> Void
    var onPrevious: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onNext: onNext, onPrevious: onPrevious)
    }

    func makeNSView(context: Context) -> FeatureTabKeyMonitorView {
        let view = FeatureTabKeyMonitorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: FeatureTabKeyMonitorView, context: Context) {
        context.coordinator.onNext = onNext
        context.coordinator.onPrevious = onPrevious
        context.coordinator.isEnabled = isEnabled
        context.coordinator.window = nsView.window
    }

    static func dismantleNSView(_ nsView: FeatureTabKeyMonitorView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    final class Coordinator {
        var isEnabled: Bool
        var onNext: () -> Void
        var onPrevious: () -> Void
        weak var window: NSWindow?
        private var monitor: Any?

        init(isEnabled: Bool, onNext: @escaping () -> Void, onPrevious: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onNext = onNext
            self.onPrevious = onPrevious
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
            guard isEnabled, let window, event.window === window else { return event }
            let relevantModifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
            let hasDisqualifyingModifiers = relevantModifiers.contains(.control)
                || relevantModifiers.contains(.option)
                || relevantModifiers.contains(.command)

            guard let action = AppFeatureTabKeyRouter.action(
                keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                hasShift: relevantModifiers.contains(.shift),
                hasDisqualifyingModifiers: hasDisqualifyingModifiers
            ) else {
                return event
            }

            switch action {
            case .next:
                onNext()
            case .previous:
                onPrevious()
            }
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
