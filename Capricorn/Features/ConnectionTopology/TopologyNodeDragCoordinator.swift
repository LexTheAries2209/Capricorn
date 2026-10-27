// SPDX-License-Identifier: GPL-3.0-only
import AppKit

struct TopologyNodeHitRegion {
    let id: String
    let frame: CGRect
}

/// Keep the pan recognizer on the stable hosting view while SwiftUI redraws
/// node positions. Replacing hosted content must not cancel an active drag.
final class TopologyNodeDragCoordinator: NSObject, NSGestureRecognizerDelegate {
    var regions: [TopologyNodeHitRegion] = []
    var onDrag: ((String, CGSize) -> Void)?
    var onEnd: (() -> Void)?
    private weak var document: NSView?
    private var recognizer: NSPanGestureRecognizer?
    private var activeID: String?
    private var cancelling = false

    func install(on document: NSView) {
        self.document = document
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.buttonMask = 1
        pan.delegate = self
        document.addGestureRecognizer(pan)
        recognizer = pan
    }

    func invalidate() {
        onDrag = nil
        onEnd = nil
        if let recognizer { document?.removeGestureRecognizer(recognizer) }
        recognizer?.delegate = nil
        recognizer = nil
        activeID = nil
    }

    func cancelDrag() {
        cancelling = true
        activeID = nil
        recognizer?.isEnabled = false
        recognizer?.isEnabled = true
        cancelling = false
    }

    func nodeID(at location: CGPoint, translation: CGPoint) -> String? {
        let start = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
        return regions.reversed().first { $0.frame.contains(start) }?.id
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? NSPanGestureRecognizer, let point = coordinates(for: pan) else { return false }
        return nodeID(at: point.location, translation: point.translation) != nil
    }

    @objc private func handlePan(_ pan: NSPanGestureRecognizer) {
        guard !cancelling, let point = coordinates(for: pan) else { return }
        route(state: pan.state, location: point.location, translation: point.translation)
    }

    private func coordinates(for pan: NSPanGestureRecognizer) -> (location: CGPoint, translation: CGPoint)? {
        guard let document else { return nil }
        var location = pan.location(in: document)
        var translation = pan.translation(in: document)
        // SwiftUI's node positions always use a top-left origin.
        if !document.isFlipped {
            location.y = document.bounds.height - location.y
            translation.y = -translation.y
        }
        return (location, translation)
    }

    func route(state: NSGestureRecognizer.State, location: CGPoint, translation: CGPoint) {
        switch state {
        case .began:
            activeID = nodeID(at: location, translation: translation)
            if let activeID { onDrag?(activeID, CGSize(width: translation.x, height: translation.y)) }
        case .changed:
            if let activeID { onDrag?(activeID, CGSize(width: translation.x, height: translation.y)) }
        case .ended:
            if let activeID { onDrag?(activeID, CGSize(width: translation.x, height: translation.y)) }
            activeID = nil
            onEnd?()
        case .cancelled, .failed:
            activeID = nil
            onEnd?()
        default:
            break
        }
    }
}
