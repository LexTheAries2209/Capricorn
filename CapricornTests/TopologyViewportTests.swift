// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import XCTest
@testable import Capricorn

final class TopologyViewportTests: XCTestCase {
    @MainActor
    func testNativeClickUsesCurrentNodeRegionsAndIgnoresBackgroundAndActiveDrag() {
        let coordinator = TopologyNodeDragCoordinator()
        let frame = CGRect(x: 100, y: 100, width: 200, height: 150)
        coordinator.regions = [.init(id: "computer", frame: frame), .init(id: "disk", frame: frame)]
        var selections: [String] = []
        coordinator.onClick = { selections.append($0) }
        coordinator.routeClick(at: CGPoint(x: 150, y: 150))
        coordinator.routeClick(at: .zero)
        XCTAssertEqual(selections, ["disk"])
        coordinator.regions = [.init(id: "computer", frame: frame)]
        coordinator.routeClick(at: CGPoint(x: 150, y: 150))
        XCTAssertEqual(selections, ["disk", "computer"])
        coordinator.route(state: .began, location: CGPoint(x: 150, y: 150), translation: .zero)
        coordinator.routeClick(at: CGPoint(x: 150, y: 150))
        XCTAssertEqual(selections, ["disk", "computer"])
        coordinator.cancelDrag()
        coordinator.routeClick(at: CGPoint(x: 150, y: 150))
        XCTAssertEqual(selections, ["disk", "computer", "computer"])
        coordinator.invalidate()
        coordinator.routeClick(at: CGPoint(x: 150, y: 150))
        XCTAssertEqual(selections.count, 3)
    }

    @MainActor
    func testClickWaitsForPanFailureAndBothRecognizersAreRemovedOnTeardown() throws {
        let coordinator = TopologyNodeDragCoordinator()
        let document = NSView()
        coordinator.install(on: document)
        let pan = try XCTUnwrap(document.gestureRecognizers.first { $0 is NSPanGestureRecognizer })
        let click = try XCTUnwrap(document.gestureRecognizers.first { $0 is NSClickGestureRecognizer })
        XCTAssertTrue(coordinator.gestureRecognizer(click, shouldRequireFailureOf: pan))
        XCTAssertFalse(coordinator.gestureRecognizer(pan, shouldRequireFailureOf: click))
        coordinator.invalidate()
        XCTAssertTrue(document.gestureRecognizers.isEmpty)
    }

    @MainActor
    func testNativeDragKeepsOriginalNodeWhileHitRegionsUpdate() {
        let coordinator = TopologyNodeDragCoordinator()
        coordinator.regions = [
            .init(id: "computer", frame: CGRect(x: 100, y: 100, width: 340, height: 280)),
            .init(id: "disk", frame: CGRect(x: 600, y: 100, width: 214, height: 140))
        ]
        var moves: [(String, CGSize)] = []
        var endings = 0
        coordinator.onDrag = { moves.append(($0, $1)) }
        coordinator.onEnd = { endings += 1 }
        XCTAssertNil(coordinator.nodeID(at: CGPoint(x: 50, y: 50), translation: .zero))
        coordinator.route(state: .began, location: CGPoint(x: 225, y: 205), translation: CGPoint(x: 25, y: 5))
        coordinator.regions = [] // SwiftUI updates the hosted node frames during dragging.
        coordinator.route(state: .changed, location: CGPoint(x: 500, y: 400), translation: CGPoint(x: 300, y: 200))
        coordinator.route(state: .ended, location: CGPoint(x: 510, y: 420), translation: CGPoint(x: 310, y: 220))
        XCTAssertEqual(moves.map(\.0), ["computer", "computer", "computer"])
        XCTAssertEqual(moves.last?.1, CGSize(width: 310, height: 220))
        XCTAssertEqual(endings, 1)
        coordinator.route(state: .changed, location: .zero, translation: .zero)
        XCTAssertEqual(moves.count, 3)
        coordinator.invalidate()
    }

    @MainActor
    func testNativeDragChoosesTopmostNodeAndCancelsOnReset() {
        let coordinator = TopologyNodeDragCoordinator()
        let frame = CGRect(x: 100, y: 100, width: 200, height: 150)
        coordinator.regions = [.init(id: "back", frame: frame), .init(id: "front", frame: frame)]
        XCTAssertEqual(coordinator.nodeID(at: CGPoint(x: 150, y: 150), translation: .zero), "front")
        var moves = 0
        coordinator.onDrag = { _, _ in moves += 1 }
        coordinator.route(state: .began, location: CGPoint(x: 150, y: 150), translation: .zero)
        coordinator.cancelDrag()
        coordinator.route(state: .changed, location: CGPoint(x: 200, y: 200), translation: CGPoint(x: 50, y: 50))
        XCTAssertEqual(moves, 1)
    }

    func testDraggingUsesCumulativeGestureDeltaAndPreservesOtherNodes() {
        let base = StorageTopologyRadialLayout(
            positions: ["computer": CGPoint(x: 200, y: 100), "disk": CGPoint(x: 500, y: 100)],
            size: CGSize(width: 700, height: 300)
        )
        var placement = TopologyNodePlacement()
        let initial = placement.layout(from: base)
        let nodeSize = CGSize(width: 214, height: 140)
        placement.drag("disk", translation: CGSize(width: 50, height: -10),
                       basePosition: base.positions["disk"]!, nodeSize: nodeSize, documentSize: initial.size)
        placement.drag("disk", translation: CGSize(width: 75, height: -20),
                       basePosition: base.positions["disk"]!, nodeSize: nodeSize, documentSize: initial.size)
        XCTAssertEqual(placement.offsets["disk"], CGSize(width: 75, height: -20))
        placement.endDrag()
        placement.drag("disk", translation: CGSize(width: 25, height: 30),
                       basePosition: base.positions["disk"]!, nodeSize: nodeSize, documentSize: initial.size)
        let moved = placement.layout(from: base)
        XCTAssertEqual(moved.positions["computer"], initial.positions["computer"])
        XCTAssertEqual(moved.positions["disk"], CGPoint(x: 1400, y: 910))
        placement.reset()
        XCTAssertTrue(placement.offsets.isEmpty)
        XCTAssertEqual(placement.layout(from: base).positions, initial.positions)
        placement.drag("disk", translation: CGSize(width: 5, height: 5),
                       basePosition: base.positions["disk"]!, nodeSize: nodeSize, documentSize: initial.size)
        XCTAssertEqual(placement.offsets["disk"], CGSize(width: 5, height: 5))
    }

    func testDraggedNodeStaysReachableAtAllCanvasEdges() {
        var placement = TopologyNodePlacement()
        let base = StorageTopologyRadialLayout(positions: ["disk": CGPoint(x: 100, y: 100)],
                                              size: CGSize(width: 300, height: 200))
        let size = CGSize(width: 214, height: 140)
        let document = placement.layout(from: base).size
        for delta in [CGSize(width: -100_000, height: -100_000),
                      CGSize(width: 100_000, height: 100_000)] {
            placement.drag("disk", translation: delta, basePosition: base.positions["disk"]!,
                           nodeSize: size, documentSize: document)
            let point = placement.layout(from: base).positions["disk"]!
            XCTAssertGreaterThanOrEqual(point.x - size.width / 2, 24)
            XCTAssertGreaterThanOrEqual(point.y - size.height / 2, 24)
            XCTAssertLessThanOrEqual(point.x + size.width / 2, document.width - 24)
            XCTAssertLessThanOrEqual(point.y + size.height / 2, document.height - 24)
            placement.endDrag()
        }
    }

    @MainActor
    func testNativeZoomAndFitRestoreScaleAndCenter() {
        let scroll = TopologyNativeScrollView(frame: CGRect(x: 0, y: 0, width: 800, height: 460))
        scroll.documentView = NSView(frame: CGRect(x: 0, y: 0, width: 3200, height: 1800))
        scroll.allowsMagnification = true
        scroll.fittingRect = CGRect(x: 800, y: 600, width: 1500, height: 500)
        scroll.perform(.fit)
        let fitted = scroll.magnification
        XCTAssertTrue(scroll.isFitted)
        XCTAssertEqual(fitted, scroll.fittingScale, accuracy: 0.001)
        XCTAssertEqual(scroll.contentView.bounds.midX, scroll.fittingRect.midX, accuracy: 1)
        XCTAssertEqual(scroll.contentView.bounds.midY, scroll.fittingRect.midY, accuracy: 1)
        scroll.perform(.zoomIn)
        XCTAssertFalse(scroll.isFitted)
        XCTAssertGreaterThan(scroll.magnification, fitted)
        scroll.perform(.zoomOut)
        XCTAssertEqual(scroll.magnification, fitted, accuracy: 0.001)
        scroll.contentView.scroll(to: CGPoint(x: 100, y: 100))
        scroll.perform(.fit)
        XCTAssertTrue(scroll.isFitted)
        XCTAssertEqual(scroll.contentView.bounds.midX, scroll.fittingRect.midX, accuracy: 1)
        XCTAssertEqual(scroll.contentView.bounds.midY, scroll.fittingRect.midY, accuracy: 1)
    }

    @MainActor
    func testZoomLimitsAndResizingInAutomaticFitMode() {
        let scroll = TopologyNativeScrollView(frame: CGRect(x: 0, y: 0, width: 800, height: 460))
        scroll.documentView = NSView(frame: CGRect(x: 0, y: 0, width: 3200, height: 1800))
        scroll.fittingRect = CGRect(x: 800, y: 600, width: 1500, height: 500)
        scroll.perform(.fit)
        for _ in 0..<100 { scroll.perform(.zoomIn) }
        XCTAssertEqual(scroll.magnification / scroll.fittingScale, 8, accuracy: 0.001)
        for _ in 0..<100 { scroll.perform(.zoomOut) }
        XCTAssertEqual(scroll.magnification / scroll.fittingScale, 0.6, accuracy: 0.001)
        scroll.perform(.fit)
        scroll.setFrameSize(CGSize(width: 500, height: 300))
        scroll.layoutSubtreeIfNeeded()
        XCTAssertTrue(scroll.isFitted)
        XCTAssertEqual(scroll.magnification, scroll.fittingScale, accuracy: 0.001)
        scroll.setFrameSize(CGSize(width: 80, height: 80))
        scroll.layoutSubtreeIfNeeded()
        scroll.setFrameSize(CGSize(width: 1200, height: 700))
        scroll.layoutSubtreeIfNeeded()
        XCTAssertEqual(scroll.magnification, scroll.fittingScale, accuracy: 0.001)
    }
}
