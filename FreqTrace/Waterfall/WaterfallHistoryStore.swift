//
//  WaterfallHistoryStore.swift
//  FreqTrace
//
//  CPU-side mirror of the waterfall's GPU texture rows (hover tooltip
//  feature): WaterfallRenderer.writeRow already computes a normalized
//  [0,1] row per hop before writing it into the Metal texture, but
//  previously discarded that array immediately after -- there was no way
//  to answer "what's the value at this historical point" for a mouseover
//  readout. This is a plain circular buffer of those rows, indexed the
//  same way WaterfallHistoryBuffer indexes GPU texture rows, so a hover
//  query can look up any point still within the scroll history. Pure,
//  no Metal dependency -- this is the test seam, same role
//  WaterfallHistoryBuffer/MagnitudeScaling already play.
//

import Foundation

struct WaterfallHistoryStore {
    private var rows: [[Float]]
    let columnCount: Int

    init(rowCount: Int, columnCount: Int) {
        self.columnCount = columnCount
        rows = Array(repeating: [], count: max(0, rowCount))
    }

    mutating func write(row: Int, values: [Float]) {
        guard rows.indices.contains(row) else { return }
        rows[row] = values
    }

    /// Normalized [0,1] value at `row`/`column`, or nil if either index is
    /// out of range or that row hasn't been written yet.
    func value(row: Int, column: Int) -> Float? {
        guard rows.indices.contains(row), column >= 0, column < columnCount else { return nil }
        let values = rows[row]
        guard values.indices.contains(column) else { return nil }
        return values[column]
    }
}
