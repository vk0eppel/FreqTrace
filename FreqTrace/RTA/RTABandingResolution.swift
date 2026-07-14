//
//  RTABandingResolution.swift
//  FreqTrace
//
//  Selectable bar/band density (user request: "this value should be
//  relative to octaves, from 48 per octave to 1 per octave", then "the
//  same for the waterfall" -- shared by both RTA, replacing RTABinning's
//  previous fixed 48-total-bars default, and the waterfall, which pre-bins
//  its magnitudes into the same bands before writing to its GPU texture
//  (see RTABinning.steppedMagnitudes) rather than resampling to a smaller
//  texture. Uses the standard octave-fraction vernacular real analyzers use
//  ("1/3 octave", "1/12 octave", ...) rather than a raw bar count, since
//  that's the vocabulary a live sound tech already knows. `rawValue` is
//  bars-per-octave, so higher is finer resolution -- 1/48 octave is far
//  denser than 1/1 octave, not the reverse.
//

import Foundation

enum RTABandingResolution: Int, CaseIterable, Identifiable {
    case oneOverOne = 1
    case oneOverThree = 3
    case oneOverSix = 6
    case oneOverTwelve = 12
    case oneOverTwentyFour = 24
    case oneOverFortyEight = 48

    var id: Int { rawValue }

    var label: String { "1/\(rawValue)" }

    /// Total bar count across the full log-frequency range (~9.97 octaves
    /// at the default 20Hz-20kHz `FrequencyAxis` range), rounded to the
    /// nearest whole bar. RTABinning is bar-centric (see its own header
    /// comment), so any bar count -- from a coarse 10 bars at 1/1 octave up
    /// to a dense ~478 at 1/48 -- already falls back to the nearest FFT bin
    /// when a bar is narrower than the FFT's own bin resolution.
    func barCount(minHz: Double = FrequencyAxis.minHz, maxHz: Double = FrequencyAxis.maxHz) -> Int {
        let octaves = log2(maxHz / minHz)
        return max(1, Int((octaves * Double(rawValue)).rounded()))
    }
}
