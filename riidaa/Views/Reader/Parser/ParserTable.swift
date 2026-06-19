//
//  ParserTable.swift
//  riidaa
//
//  Created by Pierre on 2025/06/20.
//

import SwiftUI

/// Renders a structured-content `<table>` as an actual grid.
///
/// The decoder keeps tables as a `.container` whose `tag == "table"`; its data nests
/// `thead`/`tbody`/`tfoot`/`tr` containers, and each `<td>`/`<th>` becomes a `.table` cell.
/// We walk that structure back into rows of cells and lay them out with `Grid`.
struct ParserTable: View {

    let container: StructuredContentContainer

    var body: some View {
        let rows = ParserTable.rows(from: container.data)
        if rows.isEmpty {
            EmptyView()
        } else {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                            DetailedView(structuredContent: cell.data)
                                .gridCellColumns(max(1, cell.cols))
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Collects table rows. Recurses through `thead`/`tbody`/`tfoot` wrappers and arrays,
    /// returning one `[StructuredContentTable]` (a row of cells) per `<tr>`.
    static func rows(from content: StructuredContent) -> [[StructuredContentTable]] {
        switch content {
        case .array(let blocks):
            return blocks.flatMap { $0.flatMap { rows(from: $0) } }
        case .container(let c):
            if c.tag == "tr" {
                return [cells(from: c.data)]
            }
            return rows(from: c.data)
        default:
            return []
        }
    }

    /// Collects the cells (`<td>`/`<th>`, decoded as `.table`) inside a single `<tr>`.
    static func cells(from content: StructuredContent) -> [StructuredContentTable] {
        switch content {
        case .array(let blocks):
            return blocks.flatMap { $0.flatMap { cells(from: $0) } }
        case .table(let cell):
            return [cell]
        case .container(let c):
            return cells(from: c.data)
        default:
            return []
        }
    }
}
