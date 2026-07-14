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

    /// Each bar takes the loudest bin within its log-frequency range,
    /// normalized via MagnitudeScaling ("highest level" semantics, not an
    /// average that could hide a narrow peak).
    ///
    /// Bar-centric, not bin-centric (bug fix -- user report: "under 63Hz
    /// we have only one per two RTA bar working"): below ~63Hz at the
    /// default config, the log-scaled bar width (as narrow as ~3Hz near
    /// 20Hz) is finer than the FFT's own bin resolution (~11.7Hz). Forward
    /// bin->bar mapping (iterate bins, place each into whichever bar its
    /// frequency falls in) then skips alternating bars entirely -- bins
    /// land in bars 1, 3, 5, 7... never 0, 2, 4, 6... -- leaving them
    /// silent forever regardless of actual signal, since nothing ever
    /// wrote to them. Iterating per BAR instead and looking up whichever
    /// bin(s) fall in its frequency range guarantees every bar gets a
    /// value: multiple bins in range (the common case higher up, where a
    /// bar spans many bins) still takes the loudest; zero bins in range
    /// (the low-frequency case) falls back to the single nearest bin
    /// rather than staying silent.
    ///
    /// `fullScalePower` (separate bug fix): raw vDSP FFT power is NOT
    /// already on a [0,1]/dBFS scale -- a full-scale tone's raw power is
    /// on the order of 10^6-10^7 for a 4096-point window, not ~1.0 -- so
    /// it must be referenced against a calibrated full-scale power (the
    /// same synthetic-reference-tone technique
    /// FrequencyTracker.weightedLevelDb already uses for SPL) before
    /// MagnitudeScaling's -80/0dB floor/ceiling means anything.
    static func bars(magnitudes: [Float], config: AnalysisConfig, barCount: Int = defaultBarCount, fullScalePower: Float) -> [Float] {
        guard barCount > 0, !magnitudes.isEmpty else { return [] }
        let safeFullScalePower = max(fullScalePower, .leastNormalMagnitude)

        let binHz = config.sampleRate / Double(config.windowSize)
        let maxBin = magnitudes.count - 1

        func nearestBin(toHz hz: Double) -> Int {
            min(max(1, Int((hz / binHz).rounded())), maxBin)
        }

        var powerPerBar = [Float](repeating: 0, count: barCount)
        for barIndex in 0..<barCount {
            let lowerHz = FrequencyAxis.hz(atNormalizedPosition: Double(barIndex) / Double(barCount))
            let upperHz = FrequencyAxis.hz(atNormalizedPosition: Double(barIndex + 1) / Double(barCount))
            let lowerBin = nearestBin(toHz: lowerHz)
            let upperBin = nearestBin(toHz: upperHz)

            if upperBin > lowerBin {
                var peak: Float = 0
                for bin in lowerBin...upperBin {
                    peak = max(peak, magnitudes[bin])
                }
                powerPerBar[barIndex] = peak
            } else {
                // Bar is narrower than one FFT bin -- no bin's frequency
                // falls strictly within its range, so fall back to the
                // single nearest bin (at the bar's midpoint) instead of
                // leaving it silent.
                powerPerBar[barIndex] = magnitudes[nearestBin(toHz: (lowerHz + upperHz) / 2)]
            }
        }

        return powerPerBar.map { MagnitudeScaling.normalized(power: $0 / safeFullScalePower) }
    }

    /// Same octave-banding math as `bars`, but for the waterfall (user
    /// request: "it should be the same for the waterfall") rather than the
    /// RTA -- the waterfall writes one texel per raw FFT bin instead of
    /// resampling to a fixed bar count (WaterfallRenderer.writeRow), so
    /// collapsing down to `barCount` values the way `bars` does isn't
    /// useful here. Instead, each bar's peak is expanded back out across
    /// every bin in its own range, producing a full bin-resolution array
    /// that's piecewise-flat ("stepped") per band instead of varying
    /// smoothly per bin -- the shader's linear filtering between adjacent
    /// texels only blurs at the ~1-texel-wide band edges, so this reads as
    /// genuine discrete bands, not a softened version of the raw spectrum.
    /// Still raw power, not normalized -- WaterfallRenderer.writeRow
    /// applies MagnitudeScaling itself, same as it always has.
    static func steppedMagnitudes(magnitudes: [Float], config: AnalysisConfig, barCount: Int) -> [Float] {
        guard barCount > 0, !magnitudes.isEmpty else { return magnitudes }

        let binHz = config.sampleRate / Double(config.windowSize)
        let maxBin = magnitudes.count - 1

        func nearestBin(toHz hz: Double) -> Int {
            min(max(1, Int((hz / binHz).rounded())), maxBin)
        }

        var stepped = magnitudes
        for barIndex in 0..<barCount {
            let lowerHz = FrequencyAxis.hz(atNormalizedPosition: Double(barIndex) / Double(barCount))
            let upperHz = FrequencyAxis.hz(atNormalizedPosition: Double(barIndex + 1) / Double(barCount))
            let lowerBin = nearestBin(toHz: lowerHz)
            let upperBin = nearestBin(toHz: upperHz)

            let peak: Float
            let fillRange: ClosedRange<Int>
            if upperBin > lowerBin {
                peak = magnitudes[lowerBin...upperBin].max() ?? 0
                fillRange = lowerBin...upperBin
            } else {
                // Bar narrower than one FFT bin -- same nearest-bin
                // fallback `bars` uses, just filling that single bin.
                let bin = nearestBin(toHz: (lowerHz + upperHz) / 2)
                peak = magnitudes[bin]
                fillRange = bin...bin
            }
            for bin in fillRange {
                stepped[bin] = peak
            }
        }
        return stepped
    }
}
