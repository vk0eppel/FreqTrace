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
//  denser than 1/1 octave, not the reverse. `rawValue` is passed straight
//  into RTABinning.bars/steppedMagnitudes as `barsPerOctave` -- there's no
//  separate total-bar-count to compute here, since RTABinning's 1kHz-
//  anchored band grid derives the actual count itself (user question:
//  "what would be the best choice to stay aligned with the standard 1/3-
//  octave frequencies with any banding choice?" -- anchoring at 1kHz
//  rather than at minHz/maxHz).
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
}
