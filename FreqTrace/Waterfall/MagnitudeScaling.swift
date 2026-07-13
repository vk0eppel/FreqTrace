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
    static let floorDb: Float = -80
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
    static func normalized(power: Float, floorDb: Float = floorDb, ceilingDb: Float = ceilingDb) -> Float {
        let clamped = min(max(decibels(power: power), floorDb), ceilingDb)
        return (clamped - floorDb) / (ceilingDb - floorDb)
    }
}
