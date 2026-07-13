//
//  RTABinning.swift
//  FreqTrace
//
//  Resamples a raw FFT magnitude spectrum into a fixed number of
//  log-frequency-spaced, normalized [0,1] bars for the RTA view (ticket
//  #11). Reuses FrequencyAxis (the waterfall's log-frequency mapping, so
//  the RTA reads consistently with the waterfall's x-axis) and
//  MagnitudeScaling (the waterfall's dB normalization). Pure -- this is the
//  test seam; RTAView (SwiftUI Canvas) is the untested rendering glue.
//
//  Bar count v1 default: CLAUDE.md flags "RTA resolution/band count" as
//  deferred ("revisit once RTA is actually being built"). No spec pins
//  this down, so 48 is a judgment call -- coarse enough to read at a
//  glance from a distance (CLAUDE.md's product goal), fine enough to
//  distinguish the labeled bands (100Hz-10kHz). Revisit if it's wrong.
//

import Foundation

enum RTABinning {
    static let defaultBarCount = 48

    /// Each bar takes the loudest bin within its log-frequency range
    /// (matching "highest level" semantics, not an average that could hide
    /// a narrow peak), normalized via MagnitudeScaling. Bars with no bins
    /// in range (audible range is coarser than a very high bar count near
    /// the low end) stay at 0 (silence).
    ///
    /// `fullScalePower` (bug fix): raw vDSP FFT power is NOT already on a
    /// [0,1]/dBFS scale -- a full-scale tone's raw power is on the order
    /// of 10^6-10^7 for a 4096-point window, not ~1.0 -- so it must be
    /// referenced against a calibrated full-scale power (the same
    /// synthetic-reference-tone technique FrequencyTracker.weightedLevelDb
    /// already uses for SPL) before MagnitudeScaling's -80/0dB floor/
    /// ceiling means anything. Without this, every bin reads far above the
    /// ceiling and clamps to 1.0 regardless of actual loudness -- reported
    /// by a user as every RTA bar pegged to max / the waterfall reading
    /// uniformly "too loud."
    static func bars(magnitudes: [Float], config: AnalysisConfig, barCount: Int = defaultBarCount, fullScalePower: Float) -> [Float] {
        guard barCount > 0, !magnitudes.isEmpty else { return [] }
        let safeFullScalePower = max(fullScalePower, .leastNormalMagnitude)

        let binHz = config.sampleRate / Double(config.windowSize)
        var peakPowerPerBar = [Float](repeating: 0, count: barCount)

        for bin in 1..<magnitudes.count {
            let hz = Double(bin) * binHz
            guard hz >= FrequencyAxis.minHz, hz <= FrequencyAxis.maxHz else { continue }
            let position = FrequencyAxis.normalizedPosition(forHz: hz)
            let barIndex = min(barCount - 1, Int(position * Double(barCount)))
            peakPowerPerBar[barIndex] = max(peakPowerPerBar[barIndex], magnitudes[bin])
        }

        return peakPowerPerBar.map { MagnitudeScaling.normalized(power: $0 / safeFullScalePower) }
    }
}
