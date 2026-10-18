// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct DriveSidebarSelectionHighlight: NSViewRepresentable {
    func makeNSView(context: Context) -> DriveSidebarSelectionHighlightView {
        DriveSidebarSelectionHighlightView()
    }

    func updateNSView(_ nsView: DriveSidebarSelectionHighlightView, context: Context) {
        nsView.updateSelectionHighlight()
    }
}

final class DriveSidebarSelectionHighlightView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSelectionHighlight()
    }

    func updateSelectionHighlight() {
        // Wait until the row is attached to its native List table.
        DispatchQueue.main.async { [weak self] in
            var ancestor = self?.superview
            while let view = ancestor {
                if let table = view as? NSTableView {
                    // SwiftUI draws the neutral background; AppKit still owns selection.
                    if table.selectionHighlightStyle != .none {
                        table.selectionHighlightStyle = .none
                        table.needsDisplay = true
                    }
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
