// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct SmartAttributesTableScrollConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> SmartAttributesTableScrollConfigurationView {
        SmartAttributesTableScrollConfigurationView()
    }

    func updateNSView(_ nsView: SmartAttributesTableScrollConfigurationView, context: Context) {
        nsView.configureTable()
    }
}

final class SmartAttributesTableScrollConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTable()
    }

    func configureTable() {
        // Wait for the first cell to join SwiftUI's native table hierarchy.
        DispatchQueue.main.async { [weak self] in
            var ancestor = self?.superview
            while let view = ancestor {
                if let table = view as? NSTableView, let scroll = table.enclosingScrollView {
                    // Grow the document on column resize instead of squeezing trailing columns.
                    table.columnAutoresizingStyle = .noColumnAutoresizing
                    scroll.hasHorizontalScroller = true
                    scroll.autohidesScrollers = false
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
