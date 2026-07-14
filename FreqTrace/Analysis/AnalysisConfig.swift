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

    /// Samples advanced between consecutive FFT windows (50% overlap at the
    /// default window size).
    var hopSize: Int

    // Derived from FFTWindowSize.default (user request: FFT size became a
    // live-selectable setting, FFTWindowSize.swift) rather than duplicating
    // "8192/4096" here separately -- single source of truth for the
    // pipeline's starting resolution. Widened from the original 4096/2048
    // (user request: low-frequency RTA bars near 40Hz at 1/12 octave were
    // narrower than the old ~11.7Hz bin width, so several adjacent bars
    // unavoidably shared one bin's value). 8192/4096 halves bin width to
    // ~5.9Hz while preserving the 50% overlap, at the cost of roughly
    // doubling hop latency -- see AnomalyDetector's sustainFrameCount(for:),
    // which was hardcoded against the old hop duration and had to be made
    // duration-derived to compensate.
    static let `default` = FFTWindowSize.default.config(sampleRate: 48_000)

    /// Frequency width of one FFT bin, i.e. the best-case resolution of the
    /// Tracked Frequency readout at this configuration.
    var binResolutionHz: Double {
        sampleRate / Double(windowSize)
    }
}
