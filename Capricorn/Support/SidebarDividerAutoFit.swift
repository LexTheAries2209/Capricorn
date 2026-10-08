// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

enum SidebarAutoFitWidth {
    static let minimum: CGFloat = 260
    static let initial: CGFloat = 300
    static let defaultMaximum: CGFloat = 420
    static let coordinateSpace = "driveSidebar"

    static func preferred(rowWidths: [CGFloat], rowInset: CGFloat = 0) -> CGFloat {
        let contentWidth = rowWidths.filter { $0.isFinite && $0 > 0 }.max() ?? 0
        let inset = rowInset.isFinite ? max(0, rowInset) : 0
        return ceil(max(minimum, contentWidth + inset * 2))
    }
}

struct DriveSidebarInsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct DriveSidebarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

struct SidebarDividerAutoFit: NSViewRepresentable {
    let preferredWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(preferredWidth: preferredWidth)
    }

    func makeNSView(context: Context) -> SidebarDividerAutoFitView {
        let view = SidebarDividerAutoFitView()
        view.coordinator = context.coordinator
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ nsView: SidebarDividerAutoFitView, context: Context) {
        context.coordinator.preferredWidth = preferredWidth
    }

    static func dismantleNSView(_ nsView: SidebarDividerAutoFitView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    @MainActor
    final class Coordinator {
        var preferredWidth: CGFloat
        weak var anchor: NSView?
        private var monitor: Any?

        init(preferredWidth: CGFloat) {
            self.preferredWidth = preferredWidth
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        isolated deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func invalidate() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        func handle(_ event: NSEvent) -> NSEvent? {
            guard event.type == .leftMouseDown, event.clickCount == 2,
                  let anchor, let window = anchor.window, event.window === window,
                  let splitView = sidebarSplitView(for: anchor),
                  preferredWidth.isFinite, preferredWidth > 0 else {
                return event
            }
            let sidebar = splitView.arrangedSubviews[0]
            let detail = splitView.arrangedSubviews[1]
            guard !sidebar.isHidden, !detail.isHidden,
                  sidebar.frame.width > 0, detail.frame.width > 0 else {
                return event
            }
            let divider = CGRect(
                x: sidebar.frame.maxX,
                y: splitView.bounds.minY,
                width: max(splitView.dividerThickness, detail.frame.minX - sidebar.frame.maxX),
                height: splitView.bounds.height
            ).insetBy(dx: -3, dy: 0)
            guard divider.contains(splitView.convert(event.locationInWindow, from: nil)) else {
                return event
            }

            // Leave native dragging and collapse behavior alone; consume only
            // a double-click on this window's sidebar divider.
            splitView.setPosition(preferredWidth, ofDividerAt: 0)
            splitView.layoutSubtreeIfNeeded()
            return nil
        }

        private func sidebarSplitView(for anchor: NSView) -> NSSplitView? {
            var ancestor = anchor.superview
            while let view = ancestor {
                if let splitView = view as? NSSplitView,
                   splitView.isVertical, splitView.arrangedSubviews.count >= 2,
                   anchor.isDescendant(of: splitView.arrangedSubviews[0]) {
                    return splitView
                }
                ancestor = view.superview
            }
            return nil
        }
    }
}

final class SidebarDividerAutoFitView: NSView {
    weak var coordinator: SidebarDividerAutoFit.Coordinator?
}
