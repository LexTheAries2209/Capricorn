// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

/// AppKit owns trackpad magnification and scrolling; SwiftUI still owns nodes,
/// selection, dragging and commands. Updating a selection never reapplies zoom.
struct TopologyMagnifyingScrollView<Content: View>: NSViewRepresentable {
    let documentSize: CGSize
    let fittingRect: CGRect
    let command: TopologyViewportCommand
    let onZoomChanged: (CGFloat) -> Void
    let nodeRegions: [TopologyNodeHitRegion]
    let onNodeClick: (String) -> Void
    let onNodeDrag: (String, CGSize) -> Void
    let onNodeDragEnded: () -> Void
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> TopologyNodeDragCoordinator { TopologyNodeDragCoordinator() }

    func makeNSView(context: Context) -> TopologyNativeScrollView {
        let scroll = TopologyNativeScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.allowsMagnification = true
        let document = NSHostingView(rootView: AnyView(content()))
        scroll.documentView = document
        context.coordinator.install(on: document)
        scroll.setAccessibilityIdentifier("topologyInteractiveViewport")
        return scroll
    }

    func updateNSView(_ scroll: TopologyNativeScrollView, context: Context) {
        (scroll.documentView as? NSHostingView<AnyView>)?.rootView = AnyView(content())
        if scroll.documentView?.frame.size != documentSize {
            scroll.documentView?.setFrameSize(documentSize)
        }
        if scroll.fittingRect != fittingRect, scroll.isFitted {
            scroll.pendingAction = .fit
        }
        scroll.fittingRect = fittingRect
        scroll.onZoomChanged = onZoomChanged
        context.coordinator.regions = nodeRegions
        context.coordinator.onClick = onNodeClick
        context.coordinator.onDrag = { [weak scroll] id, translation in
            scroll?.preserveManualViewport()
            onNodeDrag(id, translation)
        }
        context.coordinator.onEnd = onNodeDragEnded
        if scroll.lastCommand != command {
            if command.action == .fit { context.coordinator.cancelDrag() }
            scroll.lastCommand = command
            scroll.pendingAction = command.action
        }
        scroll.needsLayout = true
    }

    static func dismantleNSView(_ scroll: TopologyNativeScrollView, coordinator: TopologyNodeDragCoordinator) {
        scroll.onZoomChanged = nil
        coordinator.invalidate()
    }
}

final class TopologyNativeScrollView: NSScrollView {
    var fittingRect: CGRect = .zero
    var lastCommand: TopologyViewportCommand?
    var pendingAction: TopologyViewportCommand.Action?
    var onZoomChanged: ((CGFloat) -> Void)?
    private(set) var isFitted = true
    private var previousViewportSize: CGSize = .zero
    private var reportedZoom: CGFloat?

    var fittingScale: CGFloat {
        guard fittingRect.width > 0, fittingRect.height > 0 else { return 1 }
        return max(0.02, min(1, (contentSize.width - 24) / fittingRect.width,
                             (contentSize.height - 24) / fittingRect.height))
    }

    override func layout() {
        super.layout()
        guard contentSize.width > 24, contentSize.height > 24, !fittingRect.isEmpty else { return }
        let resized = previousViewportSize != contentSize
        previousViewportSize = contentSize
        let action = pendingAction
        pendingAction = nil
        // Keep automatic fitting live while the window resizes, but preserve
        // the user's chosen magnification after a pinch or zoom-button action.
        if let action {
            perform(action)
        } else if resized && isFitted {
            perform(.fit)
        } else if resized {
            updateZoomLimits()
            reportZoom()
        }
    }

    override func magnify(with event: NSEvent) {
        isFitted = false
        super.magnify(with: event)
        reportZoom()
    }

    func preserveManualViewport() {
        isFitted = false
    }

    func perform(_ action: TopologyViewportCommand.Action) {
        updateZoomLimits()
        switch action {
        case .fit:
            isFitted = true
            setMagnification(fittingScale, centeredAt: CGPoint(x: fittingRect.midX, y: fittingRect.midY))
            let visible = contentView.bounds.size
            contentView.scroll(to: CGPoint(x: fittingRect.midX - visible.width / 2,
                                           y: fittingRect.midY - visible.height / 2))
            reflectScrolledClipView(contentView)
        case .zoomIn, .zoomOut:
            isFitted = false
            let zoom = magnification / fittingScale
                + (action == .zoomIn ? TopologyZoomLimits.step : -TopologyZoomLimits.step)
            let target = min(maxMagnification, max(minMagnification, zoom * fittingScale))
            let visible = contentView.bounds
            setMagnification(target, centeredAt: CGPoint(x: visible.midX, y: visible.midY))
        }
        reportZoom()
    }

    private func updateZoomLimits() {
        let minimum = fittingScale * TopologyZoomLimits.minimum
        let maximum = fittingScale * TopologyZoomLimits.maximum
        // Either limit can move across the old range after a large resize.
        if maximum < minMagnification {
            minMagnification = minimum
            maxMagnification = maximum
        } else {
            maxMagnification = maximum
            minMagnification = minimum
        }
    }

    private func reportZoom() {
        let zoom = magnification / fittingScale
        guard reportedZoom != zoom else { return }
        reportedZoom = zoom
        // Native layout can run inside SwiftUI's update pass.
        DispatchQueue.main.async { [weak self] in self?.onZoomChanged?(zoom) }
    }
}
