//
//  FrequencyAxis.swift
//  FreqTrace
//
//  Log-frequency axis mapping for the waterfall (ticket #8): the display's
//  x-axis is log-scaled 20Hz-20kHz, labeled at meaningful bands rather than
//  raw FFT bin numbers (see CLAUDE.md "Primary view -- spectrogram/
//  waterfall"). Pure, hardware-independent -- this is the test seam; the
//  Metal shader (Waterfall.metal) reimplements the same log formula on the
//  GPU side to remap a linear-bin texture per-pixel, since a Swift-side
//  per-pixel resample would be far more CPU work than doing it once in the
//  fragment shader.
//

import Foundation

enum FrequencyAxis {
    static let minHz: Double = 20
    static let maxHz: Double = 20_000

    /// Maps a frequency (Hz) to a normalized [0,1] position on the log
    /// axis, clamped to [minHz, maxHz].
    static func normalizedPosition(forHz hz: Double) -> Double {
        let clamped = min(max(hz, minHz), maxHz)
        return log(clamped / minHz) / log(maxHz / minHz)
    }

    /// Inverse of normalizedPosition(forHz:), clamped to [0,1].
    static func hz(atNormalizedPosition position: Double) -> Double {
        let clamped = min(max(position, 0), 1)
        return minHz * pow(maxHz / minHz, clamped)
    }

    struct Band {
        let hz: Double
        let label: String
    }

    /// Standard octave-band series, 20Hz-20kHz (revised from ticket #8's
    /// original coarser set per user request): "labeled at meaningful
    /// bands, not raw FFT bins," now matching the octave spacing real
    /// analyzers use.
    static let labeledBands: [Band] = [
        Band(hz: 31.5, label: "31.5"),
        Band(hz: 63, label: "63"),
        Band(hz: 125, label: "125"),
        Band(hz: 250, label: "250"),
        Band(hz: 500, label: "500"),
        Band(hz: 1000, label: "1k"),
        Band(hz: 2000, label: "2k"),
        Band(hz: 4000, label: "4k"),
        Band(hz: 8000, label: "8k"),
        Band(hz: 16_000, label: "16k"),
    ]
}
