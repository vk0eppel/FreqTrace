//
//  TimeAveraging.swift
//  FreqTrace
//
//  Post-FFT frame-blending (ticket #7, CONTEXT.md "Time Averaging"): an
//  exponential moving average over consecutive magnitude spectra, feeding
//  Tracked Frequency (+ its level), SPL, and the waterfall/RTA display --
//  everything except the Anomaly Candidate detector, which reads the raw,
//  unblended spectrum (ADR 0001: a building ring must be caught fast, not
//  smoothed away). Never touches FrequencyTracker's FFT setup (AC: "does not
//  change FFT frequency resolution/window size").
//
//  Fast/Slow are real *time constants* (125 ms / 1 s), not raw per-frame
//  weights (user request). The per-hop EMA weight is derived from the target
//  time constant and the actual hop duration -- w = 1 - exp(-Δt/τ) -- so the
//  smoothing is the same wall-clock time at every FFT size. A raw per-frame
//  weight would not be: the hop rate changes with FFT size (hopSize =
//  min(windowSize/2, 2048)), so the same weight converged ~4x faster at 1024
//  than at 4096. NB the FFT window itself integrates over windowSize/sampleRate
//  (341 ms at 16384) -- that's separate inherent smoothing this filter sits on
//  top of; the 125 ms/1 s govern the blender stage only.
//

import Foundation

// Plain value types -- opt out of this module's default @MainActor
// isolation (like Weighting/AnalysisConfig) so AudioAnalysisPipeline's
// background actor can call blend(_:preset:hopDuration:) directly; leaving
// them implicitly MainActor-isolated was a Swift 6 language-mode error
// waiting to happen (warned in Swift 5 mode).
// Declaration order is UI order (the Controls row iterates allCases):
// None -> Fast -> Slow, least to most smoothing.
nonisolated enum TimeAveragingPreset: String, CaseIterable, Identifiable {
    case none = "None"
    case fast = "Fast"
    case slow = "Slow"

    var id: String { rawValue }

    /// The smoothing time constant (seconds): the wall-clock time the EMA
    /// takes to cover ~63% of a step, independent of FFT size / hop rate.
    /// 125 ms (Fast) / 1 s (Slow) match IEC 61672's SPL-meter Fast/Slow
    /// (see docs/research/fast-slow-time-weighting.md). `nil` for None --
    /// no time averaging at all, each frame replaces the last (REW's
    /// "Live/None"), the most responsive setting.
    fileprivate var timeConstantSeconds: Double? {
        switch self {
        case .none: nil
        case .fast: 0.125
        case .slow: 1.0
        }
    }

    /// Per-hop weight for the newest frame, derived from the time constant
    /// and the actual hop duration via the zero-order-hold discretization of
    /// a first-order low-pass (w = 1 - exp(-Δt/τ)) -- so the effective time
    /// constant is τ regardless of how often hops arrive. None returns 1.0
    /// (pure passthrough: the new frame fully replaces the previous).
    fileprivate func newFrameWeight(hopDuration: Double) -> Float {
        guard let timeConstantSeconds else { return 1.0 }
        return Float(1 - exp(-hopDuration / timeConstantSeconds))
    }
}

nonisolated struct TimeAveragingBlender {
    private var previous: [Float]?

    /// Blends `magnitudes` against the previously blended frame. `hopDuration`
    /// (seconds between hops) turns the preset's time constant into the
    /// per-hop EMA weight, so the smoothing is FFT-size-independent. The very
    /// first call (no previous frame) always passes through unchanged --
    /// there's nothing to lag behind yet.
    mutating func blend(_ magnitudes: [Float], preset: TimeAveragingPreset, hopDuration: Double) -> [Float] {
        guard let previous, previous.count == magnitudes.count else {
            self.previous = magnitudes
            return magnitudes
        }
        let weight = preset.newFrameWeight(hopDuration: hopDuration)
        let blended = zip(previous, magnitudes).map { weight * $1 + (1 - weight) * $0 }
        self.previous = blended
        return blended
    }
}
