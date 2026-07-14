//
//  MagnitudeScaling.swift
//  FreqTrace
//
//  Converts a raw FFT power magnitude (FrequencyTracker.spectrum(in:)'s
//  output, unbounded and non-linear) into the normalized [0,1] range
//  WaterfallColorMap expects. Pure -- this is the test seam.
//

import Foundation

enum MagnitudeScaling {
    // -120dB (user request, was -80dB) -- matches decibels(power:)'s own
    // 1e-12 floor (10*log10(1e-12) = -120dB exactly), so true silence
    // clamps at the same point normalized(power:) does, rather than the
    // decibels floor sitting below where normalization actually clips.
    static let floorDb: Float = -120
    static let ceilingDb: Float = 0

    /// Power magnitude -> decibels (10*log10, since vDSP_zvmags' output is
    /// already power/amplitude^2, not amplitude). Floored well below
    /// floorDb to avoid -infinity for exact silence.
    static func decibels(power: Float) -> Float {
        10 * log10(max(power, 1e-12))
    }

    /// Power magnitude -> normalized [0,1], clamped between `floorDb` and
    /// `ceilingDb`. 0 is silence (or below the noise floor); 1 is full
    /// scale or louder.
    static func normalized(power: Float, floorDb: Float = Self.floorDb, ceilingDb: Float = Self.ceilingDb) -> Float {
        let clamped = min(max(decibels(power: power), floorDb), ceilingDb)
        return (clamped - floorDb) / (ceilingDb - floorDb)
    }

    /// Inverse of `normalized(power:)` (hover tooltip feature): recovers a
    /// dB value from a stored [0,1] value. This reconstructs dB relative to
    /// whatever `fullScalePower` the original normalization divided by
    /// (i.e. dBFS), not raw unreferenced power -- same caveat as
    /// `normalized(power:)` itself.
    static func dB(fromNormalized normalized: Float, floorDb: Float = Self.floorDb, ceilingDb: Float = Self.ceilingDb) -> Float {
        floorDb + normalized * (ceilingDb - floorDb)
    }
}
