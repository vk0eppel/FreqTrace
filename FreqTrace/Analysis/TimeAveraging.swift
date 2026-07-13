//
//  TimeAveraging.swift
//  FreqTrace
//
//  Post-FFT frame-blending (ticket #7, CONTEXT.md "Time Averaging"): an
//  exponential moving average over consecutive magnitude spectra, applied
//  only to the spectrum Tracked Frequency's argmax reads -- never to
//  spectrum(in:)'s output (the waterfall/RTA/SPL all need the true,
//  unblended measurement), and never touching FrequencyTracker's FFT setup
//  (AC: "does not change FFT frequency resolution/window size").
//

enum TimeAveragingPreset: String, CaseIterable, Identifiable {
    case fast = "Fast"
    case slow = "Slow"

    var id: String { rawValue }

    /// Exponential-blend weight given to the newest frame. 1.0 (Fast) is
    /// effectively no smoothing -- each frame fully replaces the last, the
    /// fastest possible response. The Slow value (0.15) is a judgment
    /// call -- CONTEXT.md specifies Fast/Slow as presets, not a tunable
    /// time-constant, but doesn't pin down the exact smoothing factor;
    /// chosen to visibly lag a stepped test input (the AC) without being
    /// so slow it reads as broken.
    fileprivate var newFrameWeight: Float {
        switch self {
        case .fast: 1.0
        case .slow: 0.15
        }
    }
}

struct TimeAveragingBlender {
    private var previous: [Float]?

    /// Blends `magnitudes` against the previously blended frame. The very
    /// first call (no previous frame) always passes through unchanged --
    /// there's nothing to lag behind yet.
    mutating func blend(_ magnitudes: [Float], preset: TimeAveragingPreset) -> [Float] {
        guard let previous, previous.count == magnitudes.count else {
            self.previous = magnitudes
            return magnitudes
        }
        let weight = preset.newFrameWeight
        let blended = zip(previous, magnitudes).map { weight * $1 + (1 - weight) * $0 }
        self.previous = blended
        return blended
    }
}
