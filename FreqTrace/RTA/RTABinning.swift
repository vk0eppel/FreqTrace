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

import Foundation
import os

// Pure math, nonisolated: opts out of the module's default @MainActor
// isolation (Swift 6) -- called from nonisolated unit tests and from
// non-main render/binning paths alike.
nonisolated enum RTABinning {
    static let defaultBarsPerOctave = 12

    /// Memoizes bandEdges(barsPerOctave:) (perf fix -- user request "reduce
    /// CPU charge"): it's pure and only ever changes when the user picks a
    /// different RTABandingResolution, but was recomputed with fresh array
    /// allocations on every single hop from three separate call sites --
    /// AudioPipelineViewModel.apply's continuous peak tracking, RTAView's
    /// per-frame Canvas render, and WaterfallZoneView's hover overlay --
    /// none of which share a common caller. A lock-guarded cache (same
    /// OSAllocatedUnfairLock pattern WaterfallRenderer already uses for
    /// cross-thread state) rather than a plain static var, since this enum
    /// has no actor isolation of its own and its callers span multiple
    /// actors/threads. Stays small -- at most one entry per
    /// RTABandingResolution case, since minHz/maxHz/referenceHz are
    /// effectively constant in practice.
    private struct BandEdgesCacheKey: Hashable {
        let barsPerOctave: Int
        let minHz: Double
        let maxHz: Double
        let referenceHz: Double
    }
    private static let bandEdgesCache = OSAllocatedUnfairLock<[BandEdgesCacheKey: [(lowerHz: Double, upperHz: Double)]]>(initialState: [:])

    /// Band edges for `barsPerOctave` bands per octave, anchored at 1kHz
    /// (user question: "what would be the best choice to stay aligned with
    /// the standard 1/3-octave frequencies with any banding choice?").
    /// Centers are `referenceHz * 2^(n / barsPerOctave)` for integer n, so
    /// n=0 always lands exactly on 1kHz regardless of `barsPerOctave`, and
    /// every coarser resolution's centers are an exact subset of every
    /// finer one's (1/3 = 2/6 = 4/12 = 8/24 = 16/48 octave) -- switching
    /// resolution only adds/removes bands between the existing ones, never
    /// shifts them, the same nesting property real graphic EQs/analyzers
    /// have. This reproduces the standard 1/3-octave preferred-frequency
    /// series almost exactly (2^(1/3) is a hair off the true decimal
    /// preferred-number ratio 10^(1/10), close enough to round to the same
    /// nominal labels). 20Hz/20kHz become approximate nominal endpoints
    /// rather than exact centers as a result -- same as the real standard's
    /// own nominal "20Hz" band, which is ~19.95Hz in the exact math. (An
    /// earlier version centered exactly on minHz/maxHz instead by dividing
    /// the whole range into equal slices, but that meant 1kHz almost never
    /// landed on a center and every resolution had its own independent,
    /// non-nesting grid -- user report: "shouldn't we have a bar centered
    /// exactly around 1k? it seems off".)
    ///
    /// Not private -- RTAView needs each bar's real (lowerHz, upperHz) to
    /// draw it at its true FrequencyAxis position (bug fix -- user report:
    /// "the rta bars and x axis scale are clearly off (even at 1k)": array
    /// index no longer maps 1:1 to log-frequency position the way it did
    /// under the old equal-slice scheme, since bar count here comes from
    /// independently rounding the steps up and down from 1kHz).
    static func bandEdges(barsPerOctave: Int, minHz: Double = FrequencyAxis.minHz, maxHz: Double = FrequencyAxis.maxHz, referenceHz: Double = 1000) -> [(lowerHz: Double, upperHz: Double)] {
        guard barsPerOctave > 0 else { return [] }
        let key = BandEdgesCacheKey(barsPerOctave: barsPerOctave, minHz: minHz, maxHz: maxHz, referenceHz: referenceHz)
        if let cached = bandEdgesCache.withLock({ $0[key] }) { return cached }

        let step = 1.0 / Double(barsPerOctave)
        let stepsDown = Int((log2(referenceHz / minHz) * Double(barsPerOctave)).rounded())
        let stepsUp = Int((log2(maxHz / referenceHz) * Double(barsPerOctave)).rounded())
        let edges = (-stepsDown...stepsUp).map { n -> (lowerHz: Double, upperHz: Double) in
            let center = referenceHz * pow(2, Double(n) * step)
            return (center * pow(2, -step / 2), center * pow(2, step / 2))
        }

        bandEdgesCache.withLock { $0[key] = edges }
        return edges
    }

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
    static func bars(magnitudes: [Float], config: AnalysisConfig, barsPerOctave: Int = defaultBarsPerOctave, fullScalePower: Float) -> [Float] {
        guard barsPerOctave > 0, !magnitudes.isEmpty else { return [] }
        let safeFullScalePower = max(fullScalePower, .leastNormalMagnitude)

        let binHz = config.sampleRate / Double(config.windowSize)
        let maxBin = magnitudes.count - 1

        func nearestBin(toHz hz: Double) -> Int {
            min(max(1, Int((hz / binHz).rounded())), maxBin)
        }

        let edges = bandEdges(barsPerOctave: barsPerOctave)
        var powerPerBar = [Float](repeating: 0, count: edges.count)
        for (barIndex, edge) in edges.enumerated() {
            let lowerBin = nearestBin(toHz: edge.lowerHz)
            let upperBin = nearestBin(toHz: edge.upperHz)

            if upperBin > lowerBin {
                var peak: Float = 0
                for bin in lowerBin...upperBin {
                    peak = max(peak, magnitudes[bin])
                }
                powerPerBar[barIndex] = peak
            } else {
                // Bar is narrower than one FFT bin -- no bin's frequency
                // falls strictly within its range, so fall back to the
                // single nearest bin (at the bar's center) instead of
                // leaving it silent.
                powerPerBar[barIndex] = magnitudes[nearestBin(toHz: (edge.lowerHz + edge.upperHz) / 2)]
            }
        }

        return powerPerBar.map { MagnitudeScaling.normalized(power: $0 / safeFullScalePower) }
    }

    /// Same octave-banding math as `bars`, but for the waterfall (user
    /// request: "it should be the same for the waterfall") rather than the
    /// RTA -- the waterfall writes one texel per raw FFT bin instead of
    /// resampling to a fixed bar count (WaterfallRenderer.writeRow), so
    /// collapsing down to a bar array the way `bars` does isn't useful
    /// here. Instead, each bar's peak is expanded back out across every
    /// bin in its own range, producing a full bin-resolution array that's
    /// piecewise-flat ("stepped") per band instead of varying smoothly per
    /// bin -- the shader's linear filtering between adjacent texels only
    /// blurs at the ~1-texel-wide band edges, so this reads as genuine
    /// discrete bands, not a softened version of the raw spectrum. Still
    /// raw power, not normalized -- WaterfallRenderer.writeRow applies
    /// MagnitudeScaling itself, same as it always has.
    static func steppedMagnitudes(magnitudes: [Float], config: AnalysisConfig, barsPerOctave: Int) -> [Float] {
        guard barsPerOctave > 0, !magnitudes.isEmpty else { return magnitudes }

        let binHz = config.sampleRate / Double(config.windowSize)
        let maxBin = magnitudes.count - 1

        func nearestBin(toHz hz: Double) -> Int {
            min(max(1, Int((hz / binHz).rounded())), maxBin)
        }

        let edges = bandEdges(barsPerOctave: barsPerOctave)
        var stepped = magnitudes
        for edge in edges {
            let lowerBin = nearestBin(toHz: edge.lowerHz)
            let upperBin = nearestBin(toHz: edge.upperHz)

            let peak: Float
            let fillRange: ClosedRange<Int>
            if upperBin > lowerBin {
                peak = magnitudes[lowerBin...upperBin].max() ?? 0
                fillRange = lowerBin...upperBin
            } else {
                // Bar narrower than one FFT bin -- same nearest-bin
                // fallback `bars` uses, just filling that single bin.
                let bin = nearestBin(toHz: (edge.lowerHz + edge.upperHz) / 2)
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
