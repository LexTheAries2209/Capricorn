// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ObjectiveC
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
    private static var initialColumnWidthsKey: UInt8 = 0

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
                    self?.configureInitialColumnWidths(in: table)
                    return
                }
                ancestor = view.superview
            }
        }
    }

    func configureInitialColumnWidths(in table: NSTableView) {
        guard let idColumn = table.tableColumns.first,
              let sourceColumn = table.tableColumns.last,
              idColumn !== sourceColumn else { return }

        // Allow the narrower default even when the original source width was at its minimum.
        sourceColumn.minWidth = 70
        guard objc_getAssociatedObject(table, &Self.initialColumnWidthsKey) == nil else { return }
        objc_setAssociatedObject(table, &Self.initialColumnWidthsKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // Keep the marker on the table because scrolling can recreate the first cell's bridge.
        let transferredWidth = max(0, min(
            sourceColumn.width * 0.3,
            sourceColumn.width - sourceColumn.minWidth,
            idColumn.maxWidth - idColumn.width
        ))
        sourceColumn.width -= transferredWidth
        idColumn.width += transferredWidth

        if table.tableColumns.count > 2 {
            let nameColumn = table.tableColumns[1]
            // Transfer the name column's initial width without changing the table's total width.
            let nameTransferredWidth = max(0, min(
                nameColumn.width * 0.15,
                nameColumn.width - nameColumn.minWidth,
                idColumn.maxWidth - idColumn.width
            ))
            nameColumn.width -= nameTransferredWidth
            idColumn.width += nameTransferredWidth
        }
        table.tile()
    }
}
