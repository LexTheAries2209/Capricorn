// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

enum TopologyZoomLimits {
    static let minimum: CGFloat = 0.6
    static let maximum: CGFloat = 8
    static let step: CGFloat = 0.2
}

struct TopologyViewportCommand: Equatable {
    enum Action { case fit, zoomIn, zoomOut }
    var action: Action = .fit
    private(set) var revision = 0

    mutating func request(_ action: Action) {
        self.action = action
        revision += 1
    }
}

private struct TopologyResetRevisionKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct TopologyZoomInRevisionKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct TopologyZoomOutRevisionKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var topologyResetRevision: Int {
        get { self[TopologyResetRevisionKey.self] }
        set { self[TopologyResetRevisionKey.self] = newValue }
    }

    var topologyZoomInRevision: Int {
        get { self[TopologyZoomInRevisionKey.self] }
        set { self[TopologyZoomInRevisionKey.self] = newValue }
    }

    var topologyZoomOutRevision: Int {
        get { self[TopologyZoomOutRevisionKey.self] }
        set { self[TopologyZoomOutRevisionKey.self] = newValue }
    }
}
