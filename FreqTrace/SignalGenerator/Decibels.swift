//
//  Decibels.swift
//  FreqTrace
//
//  dBFS <-> linear-amplitude conversion for the Signal Generator's Level
//  control (see CONTEXT.md "Signal Generator Level" -- a directly-editable
//  numeric dB box, e.g. "-66dB", not a slider). 0 dB == amplitude 1.0
//  (unity gain / full scale).
//

import Foundation

enum Decibels {
    /// Converts a dBFS value to a linear amplitude multiplier (0 dB -> 1.0).
    static func linearAmplitude(fromDecibels db: Double) -> Double {
        pow(10, db / 20)
    }

    /// Inverse of `linearAmplitude(fromDecibels:)`. `amplitude` of 0 maps to
    /// -infinity; callers displaying silence should special-case that rather
    /// than showing "-inf dB".
    static func decibels(fromLinearAmplitude amplitude: Double) -> Double {
        20 * log10(amplitude)
    }
}
