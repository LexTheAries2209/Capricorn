// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct FeatureTabKeyMonitor: NSViewRepresentable {
    var onOpenSettings: () -> Void
    var onNext: () -> Void
    var onOpenTopology: () -> Void
    var onResetTopology: () -> Bool = { false }
    var onZoomInTopology: () -> Bool = { false }
    var onZoomOutTopology: () -> Bool = { false }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onOpenSettings: onOpenSettings,
            onNext: onNext,
            onOpenTopology: onOpenTopology,
            onResetTopology: onResetTopology,
            onZoomInTopology: onZoomInTopology,
            onZoomOutTopology: onZoomOutTopology
        )
    }

    func makeNSView(context: Context) -> FeatureTabKeyMonitorView {
        let view = FeatureTabKeyMonitorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: FeatureTabKeyMonitorView, context: Context) {
        context.coordinator.onNext = onNext
        context.coordinator.onOpenTopology = onOpenTopology
        context.coordinator.onOpenSettings = onOpenSettings
        context.coordinator.onResetTopology = onResetTopology
        context.coordinator.onZoomInTopology = onZoomInTopology
        context.coordinator.onZoomOutTopology = onZoomOutTopology
        context.coordinator.window = nsView.window
    }

    static func dismantleNSView(_ nsView: FeatureTabKeyMonitorView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    @MainActor
    final class Coordinator {
        var onOpenSettings: () -> Void
        var onNext: () -> Void
        var onOpenTopology: () -> Void
        var onResetTopology: () -> Bool
        var onZoomInTopology: () -> Bool
        var onZoomOutTopology: () -> Bool
        weak var window: NSWindow?
        private var monitor: Any?

        init(
            onOpenSettings: @escaping () -> Void,
            onNext: @escaping () -> Void,
            onOpenTopology: @escaping () -> Void,
            onResetTopology: @escaping () -> Bool = { false },
            onZoomInTopology: @escaping () -> Bool = { false },
            onZoomOutTopology: @escaping () -> Bool = { false }
        ) {
            self.onOpenSettings = onOpenSettings
            self.onNext = onNext
            self.onOpenTopology = onOpenTopology
            self.onResetTopology = onResetTopology
            self.onZoomInTopology = onZoomInTopology
            self.onZoomOutTopology = onZoomOutTopology
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        isolated deinit {
            invalidate()
        }

        func invalidate() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        func handle(_ event: NSEvent) -> NSEvent? {
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

            if AppFeatureTabKeyRouter.matchesTopology(
                keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                hasModifiers: !relevantModifiers.isEmpty,
                isEditingText: isEditingText
            ) {
                onOpenTopology()
                return nil
            }

            if AppFeatureTabKeyRouter.matchesTopologyReset(
                keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                hasModifiers: !relevantModifiers.isEmpty,
                isEditingText: isEditingText
            ), onResetTopology() {
                return nil
            }

            if AppFeatureTabKeyRouter.matchesTopologyZoomIn(
                keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                hasShift: relevantModifiers.contains(.shift),
                hasDisqualifyingModifiers: hasDisqualifyingModifiers,
                isEditingText: isEditingText
            ), onZoomInTopology() {
                return nil
            }

            if AppFeatureTabKeyRouter.matchesTopologyZoomOut(
                keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                hasShift: relevantModifiers.contains(.shift),
                hasDisqualifyingModifiers: hasDisqualifyingModifiers,
                isEditingText: isEditingText
            ), onZoomOutTopology() {
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

        private var isEditingText: Bool {
            guard let responder = window?.firstResponder else { return false }
            if let editor = responder as? NSTextView {
                return editor.isEditable || editor.hasMarkedText()
            }
            return (responder as? NSTextField)?.isEditable == true
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
