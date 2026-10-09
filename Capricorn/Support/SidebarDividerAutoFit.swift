// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

enum SidebarAutoFitWidth {
    static let minimum: CGFloat = 260
    static let initial: CGFloat = 300
    static let defaultMaximum: CGFloat = 420
    static let minimumDetailWidth: CGFloat = 600
    static let coordinateSpace = "driveSidebar"
    // Text and SF Symbol subviews round fractional widths independently.
    static let pixelRoundingAllowance: CGFloat = 2

    static func preferred(rowWidths: [CGFloat], rowInset: CGFloat = 0) -> CGFloat {
        let contentWidth = rowWidths.filter { $0.isFinite && $0 > 0 }.max() ?? 0
        let inset = rowInset.isFinite ? max(0, rowInset) : 0
        return ceil(max(minimum, contentWidth + inset * 2 + pixelRoundingAllowance))
    }
}

struct DriveSidebarAvailableWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let width = nextValue()
        guard width.isFinite, width > 0 else { return }
        // Fit the narrowest usable row, including differing native row insets.
        value = value > 0 ? min(value, width) : width
    }
}

struct DriveSidebarViewportWidthPreferenceKey: PreferenceKey {
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
    var viewportWidth: CGFloat? = nil
    var onAutoFitChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            preferredWidth: preferredWidth,
            viewportWidth: viewportWidth,
            onAutoFitChanged: onAutoFitChanged
        )
    }

    func makeNSView(context: Context) -> SidebarDividerAutoFitView {
        let view = SidebarDividerAutoFitView()
        view.coordinator = context.coordinator
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ nsView: SidebarDividerAutoFitView, context: Context) {
        context.coordinator.onAutoFitChanged = onAutoFitChanged
        context.coordinator.update(preferredWidth: preferredWidth, viewportWidth: viewportWidth)
    }

    static func dismantleNSView(_ nsView: SidebarDividerAutoFitView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    @MainActor
    final class Coordinator {
        var preferredWidth: CGFloat
        var viewportWidth: CGFloat?
        private(set) var followsContentWidth = false
        var onAutoFitChanged: (Bool) -> Void
        weak var anchor: NSView?
        private var monitor: Any?
        private var pendingFit: Task<Void, Never>?

        init(
            preferredWidth: CGFloat,
            viewportWidth: CGFloat? = nil,
            onAutoFitChanged: @escaping (Bool) -> Void = { _ in }
        ) {
            self.preferredWidth = preferredWidth
            self.viewportWidth = viewportWidth
            self.onAutoFitChanged = onAutoFitChanged
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        isolated deinit {
            pendingFit?.cancel()
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func invalidate() {
            pendingFit?.cancel()
            pendingFit = nil
            followsContentWidth = false
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        func update(preferredWidth: CGFloat, viewportWidth: CGFloat?) {
            let contentChanged = self.preferredWidth != preferredWidth
            self.preferredWidth = preferredWidth
            self.viewportWidth = viewportWidth
            guard followsContentWidth, contentChanged else { return }
            pendingFit?.cancel()
            // Inventory and SMART enrichment can finish after the double-click.
            // Fit after SwiftUI applies the new measurements and column limits.
            pendingFit = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, self.followsContentWidth,
                      let anchor = self.anchor,
                      let splitView = self.sidebarSplitView(for: anchor) else { return }
                self.fit(splitView)
            }
        }

        func fittedWidth(sidebarWidth: CGFloat) -> CGFloat {
            // Split-view thickness also includes native navigation chrome
            // outside the measured SwiftUI list.
            let chromeWidth = viewportWidth.flatMap {
                $0.isFinite && $0 > 0 ? max(0, sidebarWidth - $0) : nil
            } ?? 0
            return preferredWidth + chromeWidth
        }

        func handle(_ event: NSEvent) -> NSEvent? {
            guard event.type == .leftMouseDown,
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
            guard event.clickCount == 2 else {
                // An ordinary divider press starts native manual sizing.
                followsContentWidth = false
                pendingFit?.cancel()
                onAutoFitChanged(false)
                return event
            }

            // Leave native dragging and collapse behavior alone; consume only
            // a double-click on this window's sidebar divider.
            followsContentWidth = true
            onAutoFitChanged(true)
            fit(splitView)
            return nil
        }

        private func fit(_ splitView: NSSplitView) {
            let sidebar = splitView.arrangedSubviews[0]
            let detail = splitView.arrangedSubviews[1]
            guard !sidebar.isHidden, !detail.isHidden,
                  sidebar.frame.width > 0, detail.frame.width > 0,
                  preferredWidth.isFinite, preferredWidth > 0 else { return }
            // SwiftUI can publish a zero detail minimum; keep that pane usable
            // when an unusually long identity exceeds the visible window.
            let detailMinimum = max(
                SidebarAutoFitWidth.minimumDetailWidth,
                (splitView.delegate as? NSSplitViewController)?
                    .splitViewItems[1].minimumThickness ?? 0
            )
            let visibleWidth = anchor?.window?.contentLayoutRect.width ?? splitView.bounds.width
            let maximumWidth = min(
                splitView.maxPossiblePositionOfDivider(at: 0),
                visibleWidth - detailMinimum - splitView.dividerThickness
            )
            guard maximumWidth > 0 else { return }
            let target = min(
                fittedWidth(sidebarWidth: sidebar.frame.width),
                maximumWidth
            )
            guard abs(sidebar.frame.width - target) >= 1 else { return }
            splitView.setPosition(target, ofDividerAt: 0)
            splitView.layoutSubtreeIfNeeded()
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
