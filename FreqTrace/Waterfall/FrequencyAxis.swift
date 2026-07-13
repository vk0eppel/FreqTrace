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

    /// The bands CLAUDE.md specifies: "labeled at meaningful bands (100,
    /// 200, 500, 1k, 2k, 5k, 10k), not raw FFT bins."
    static let labeledBands: [Band] = [
        Band(hz: 100, label: "100"),
        Band(hz: 200, label: "200"),
        Band(hz: 500, label: "500"),
        Band(hz: 1000, label: "1k"),
        Band(hz: 2000, label: "2k"),
        Band(hz: 5000, label: "5k"),
        Band(hz: 10_000, label: "10k"),
    ]
}
