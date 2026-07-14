//
//  WaterfallHistoryBuffer.swift
//  FreqTrace
//
//  Bookkeeping for the waterfall's scrolling history (ticket #8): which
//  circular texture row a new frame should land in, the scroll-offset
//  value the shader uses for wraparound sampling, and the time-axis
//  gridline positions. Pure, hardware-independent -- this is the test seam.
//  The actual GPU texture write (WaterfallRenderer) uses the row index this
//  produces but isn't itself unit-testable.
//
//  Row count is derived from AnalysisConfig (hop duration) and a target
//  history duration, not hardcoded, matching CLAUDE.md's "~10-20s default
//  scroll history" and the project's general preference for derived-not-
//  arbitrary constants (see LayoutMetrics for another example).
//

import Foundation

struct WaterfallHistoryBuffer {
    let rowCount: Int
    let columnCount: Int
    let historyDurationSeconds: Double

    private(set) var writeIndex: Int = 0

    init(config: AnalysisConfig, targetHistoryDurationSeconds: Double = 15) {
        columnCount = config.windowSize / 2
        let hopDurationSeconds = Double(config.hopSize) / config.sampleRate
        rowCount = max(1, Int((targetHistoryDurationSeconds / hopDurationSeconds).rounded(.up)))
        historyDurationSeconds = Double(rowCount) * hopDurationSeconds
    }

    /// The texture row a new frame should be written to; advances the
    /// write cursor. Wraps within [0, rowCount) -- older rows are
    /// overwritten as history scrolls, which is the whole point of a
    /// circular buffer.
    mutating func nextRowIndex() -> Int {
        let row = writeIndex % rowCount
        writeIndex += 1
        return row
    }

    /// Normalized [0,1] scroll offset for the shader's wraparound sampling:
    /// the fragment shader adds this to a pixel's base row coordinate
    /// (mod 1, via a repeat-addressing sampler) so the newest row always
    /// renders at the bottom and older rows scroll upward as writeIndex
    /// advances -- see CLAUDE.md "Scroll direction: new data enters at the
    /// bottom, scrolls up."
    var scrollOffset: Float {
        Float(writeIndex % rowCount) / Float(rowCount)
    }

    /// Inverse of the row bookkeeping above (hover tooltip feature): which
    /// texture row holds the frame from `secondsAgo` seconds ago. writeIndex
    /// - 1 is the most recently written row ("now"); stepping back by whole
    /// hops and wrapping within [0, rowCount) mirrors nextRowIndex()'s own
    /// circular-buffer math. Clamped to the buffer's own history -- callers
    /// asking for a time further back than historyDurationSeconds get the
    /// oldest row still held, not an out-of-range index.
    func rowIndex(secondsAgo: Double) -> Int {
        Self.rowIndex(secondsAgo: secondsAgo, writeIndex: writeIndex, rowCount: rowCount, historyDurationSeconds: historyDurationSeconds)
    }

    /// Static variant of `rowIndex(secondsAgo:)` taking `writeIndex` as a
    /// parameter rather than reading `self`: WaterfallRenderer's hover
    /// query runs on a different thread than the one mutating `writeIndex`
    /// (see its header comment on pendingMagnitudes' cross-thread handoff),
    /// so it snapshots writeIndex under its own lock and calls this instead
    /// of touching a live WaterfallHistoryBuffer instance from that thread.
    static func rowIndex(secondsAgo: Double, writeIndex: Int, rowCount: Int, historyDurationSeconds: Double) -> Int {
        guard rowCount > 0 else { return 0 }
        let hopDurationSeconds = historyDurationSeconds / Double(rowCount)
        let maxHopsAgo = rowCount - 1
        let hopsAgo = min(max(Int((secondsAgo / hopDurationSeconds).rounded()), 0), maxHopsAgo)
        return ((writeIndex - 1 - hopsAgo) % rowCount + rowCount) % rowCount
    }

    struct Gridline {
        let secondsAgo: Double
        let normalizedPosition: Double
    }

    /// Time-axis gridlines from "now" (0s, bottom) up to
    /// `historyDurationSeconds`, every `intervalSeconds` -- see CLAUDE.md
    /// "Time axis: explicit labeled gridlines (e.g. every 5s)."
    static func gridlines(historyDurationSeconds: Double, intervalSeconds: Double = 5) -> [Gridline] {
        var result: [Gridline] = []
        var t = 0.0
        while t <= historyDurationSeconds {
            result.append(Gridline(secondsAgo: t, normalizedPosition: t / historyDurationSeconds))
            t += intervalSeconds
        }
        return result
    }
}
