//
//  AnalysisConfig.swift
//  FreqTrace
//
//  FFT parameters for the shared capture -> FFT -> tracking pipeline (see
//  CLAUDE.md "Architecture" / ADR 0002). Deliberately a value, not literals
//  scattered through the pipeline, so sample rate/window/hop can be made
//  user-configurable later without touching the DSP code itself.
//

import Foundation

// Plain Sendable value type -- opts out of this module's default @MainActor
// isolation so it can be constructed/read from AudioAnalysisPipeline's
// background actor and FrequencyTracker without hopping to the main actor.
nonisolated struct AnalysisConfig: Sendable, Equatable {
    /// Samples per second the FFT window/hop below are sized for. The
    /// capture side (MicrophoneCaptureEngine) reports the audio hardware's
    /// actual native rate, which may differ from this default.
    var sampleRate: Double

    /// FFT window size in samples. Must be a power of two.
    var windowSize: Int

    /// Samples advanced between consecutive FFT windows. Capped independently
    /// of windowSize (see FFTWindowSize.hopSize) so the pipeline's update
    /// cadence doesn't degrade as the window grows -- larger windows overlap
    /// more instead of updating slower.
    var hopSize: Int

    // Derived from FFTWindowSize.default (user request: FFT size became a
    // live-selectable setting, FFTWindowSize.swift) rather than duplicating
    // the numbers here separately -- single source of truth for the
    // pipeline's starting resolution. Window widened from the original 4096
    // (user request: low-frequency RTA bars near 40Hz at 1/12 octave were
    // narrower than the old ~11.7Hz bin width, so several adjacent bars
    // unavoidably shared one bin's value); hop is capped at 2048 samples
    // regardless of window size (see FFTWindowSize.hopSize) so update
    // cadence stays ~43ms at every resolution.
    static let `default` = FFTWindowSize.default.config(sampleRate: 48_000)

    /// Frequency width of one FFT bin, i.e. the best-case resolution of the
    /// Tracked Frequency readout at this configuration.
    var binResolutionHz: Double {
        sampleRate / Double(windowSize)
    }
}
