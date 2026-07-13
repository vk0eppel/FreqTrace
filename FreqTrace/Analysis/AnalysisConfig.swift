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

    static let `default` = AnalysisConfig(sampleRate: 48_000, windowSize: 4096, hopSize: 2048)

    /// Frequency width of one FFT bin, i.e. the best-case resolution of the
    /// Tracked Frequency readout at this configuration.
    var binResolutionHz: Double {
        sampleRate / Double(windowSize)
    }
}
