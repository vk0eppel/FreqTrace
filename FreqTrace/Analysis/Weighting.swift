//
//  Weighting.swift
//  FreqTrace
//
//  The single global Weighting setting (A/C/Z, default A) applied wherever
//  the app judges "loudest" -- currently the Tracked Frequency (see
//  CONTEXT.md "Weighting"). Gain curves are the standard IEC 61672 A/C
//  weighting formulas, normalized to 0 dB at 1 kHz; Z-weighting is flat
//  (unweighted), matching the CONTEXT.md definition.
//

import Foundation

// Plain Sendable value type -- opts out of this module's default @MainActor
// isolation so it can be referenced from AudioAnalysisPipeline's background
// actor and FrequencyTracker without hopping to the main actor.
nonisolated enum Weighting: String, CaseIterable, Identifiable, Sendable {
    case a = "A"
    case c = "C"
    case z = "Z"

    var id: String { rawValue }

    static let `default`: Weighting = .a

    /// Relative gain in dB at `frequency` (Hz). Callers convert to a linear
    /// multiplier to apply against FFT bin magnitudes.
    func gainDb(at frequency: Double) -> Double {
        guard frequency > 0 else { return -Double.infinity }
        switch self {
        case .z:
            return 0
        case .c:
            return Weighting.cWeightingDb(frequency)
        case .a:
            return Weighting.aWeightingDb(frequency)
        }
    }

    // IEC 61672 C-weighting, normalized so C(1000 Hz) == 0 dB.
    private static func cWeightingDb(_ f: Double) -> Double {
        let f2 = f * f
        let numerator = 12194.0 * 12194.0 * f2
        let denominator = (f2 + 20.6 * 20.6) * (f2 + 12194.0 * 12194.0)
        let rc = numerator / denominator
        return 20 * log10(rc) + 0.0619
    }

    // IEC 61672 A-weighting, normalized so A(1000 Hz) == 0 dB. A-weighting
    // rolls off low frequencies far more steeply than C -- this is what
    // makes the Weighting control actually change the Tracked Frequency
    // reading for program material where a loud low tone competes with a
    // quieter mid tone.
    private static func aWeightingDb(_ f: Double) -> Double {
        let f2 = f * f
        let f4 = f2 * f2
        let numerator = 12194.0 * 12194.0 * f4
        let denom1 = f2 + 20.6 * 20.6
        let denom2 = (f2 + 107.7 * 107.7).squareRoot() * (f2 + 737.9 * 737.9).squareRoot()
        let denom3 = f2 + 12194.0 * 12194.0
        let ra = numerator / (denom1 * denom2 * denom3)
        return 20 * log10(ra) + 2.00
    }
}
