//
//  PeakHoldTracker.swift
//  FreqTrace
//
//  Classic level-meter peak-hold (ticket #12, CONTEXT.md "Peak"): the
//  highest value seen per key since the last manual reset, indefinite --
//  never auto-expiring, never lowered by a quieter update. Generic over Key
//  so RTA bars (keyed by bar index), SPL, and the Tracked Frequency level
//  readout can share one implementation rather than three.
//
// Plain value type, nonisolated (like TimeAveragingBlender/AnomalyDetector):
// opts out of the module's default @MainActor isolation so its nonisolated
// unit tests compile in Swift 6 language mode.
nonisolated struct PeakHoldTracker<Key: Hashable> {
    private var peaks: [Key: Float] = [:]

    /// The held peak for `key`, or `nil` if it's never been updated (or was
    /// cleared by the last `reset()`).
    func peak(for key: Key) -> Float? {
        peaks[key]
    }

    /// Records a new reading. Only raises the held peak -- a lower value
    /// never lowers it (that's the entire point of a peak hold).
    mutating func update(_ value: Float, for key: Key) {
        peaks[key] = max(peaks[key] ?? -.greatestFiniteMagnitude, value)
    }

    /// The manual reset (AC: "A manual reset control clears all held
    /// peaks") -- the only way a held peak ever goes away.
    mutating func reset() {
        peaks.removeAll()
    }

    /// Clears only keys matching `predicate` -- for RTA bars specifically,
    /// whose index no longer means the same frequency once the bar count
    /// changes (banding resolution). Without this, a stale peak from a
    /// coarse layout could sit at the wrong index in a denser one,
    /// possibly forever (peaks only ever rise).
    mutating func removeAll(where predicate: (Key) -> Bool) {
        peaks = peaks.filter { !predicate($0.key) }
    }
}
