//
//  FreezeGate.swift
//  FreqTrace
//
//  Pure buffering seam behind Freeze (ticket #13, CONTEXT.md "Freeze"):
//  while frozen, values passed to receive(_:) are held silently instead of
//  being published to the UI; unfreezing releases only the most recently
//  held value immediately, giving an instant catch-up to live rather than a
//  replay of everything received while frozen. Deliberately generic and
//  independent of AudioPipelineViewModel/SwiftUI -- see
//  AudioPipelineViewModel for how a single FreezeGate<AnalysisResult> gates
//  all three published properties that update together from one hop.
//
nonisolated struct FreezeGate<Value> {
    private(set) var isFrozen = false
    private var heldValue: Value?

    /// Starts holding subsequently received values instead of passing them
    /// through. A no-op if already frozen.
    mutating func freeze() {
        isFrozen = true
    }

    /// Stops holding values and returns the most recently held one (if any)
    /// for immediate publication -- the "instant catch-up," not a replay of
    /// every value received while frozen. A no-op (returns nil) if already
    /// unfrozen.
    @discardableResult
    mutating func unfreeze() -> Value? {
        guard isFrozen else { return nil }
        isFrozen = false
        defer { heldValue = nil }
        return heldValue
    }

    /// Passes `value` straight through when not frozen. While frozen, holds
    /// it silently (overwriting any previously held value) and returns nil
    /// so the caller knows not to publish.
    mutating func receive(_ value: Value) -> Value? {
        guard isFrozen else { return value }
        heldValue = value
        return nil
    }
}
