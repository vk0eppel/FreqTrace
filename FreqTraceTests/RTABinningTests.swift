//
//  RTABinningTests.swift
//  FreqTraceTests
//
//  Exercises RTABinning.bars, the pure log-frequency bar-binning logic
//  behind the RTA view (ticket #11): resamples a raw FFT magnitude
//  spectrum (FrequencyTracker.spectrum(in:)'s output) into a fixed number
//  of log-frequency-spaced, normalized [0,1] bars, reusing FrequencyAxis
//  (log mapping) and MagnitudeScaling (dB normalization) -- both already
//  covered by WaterfallLogicTests.swift, so these tests focus on the
//  binning behavior itself, not re-testing the shared math.
//
//  Band count and positions are driven by `barsPerOctave`, anchored at
//  1kHz (user question: "what would be the best choice to stay aligned
//  with the standard 1/3-octave frequencies with any banding choice?") --
//  n=0 always lands exactly on 1kHz, so these tests compute expected bar
//  indices/counts via the same stepsDown/stepsUp formula RTABinning uses
//  internally, rather than a pre-1kHz-anchoring formula.
//

import Foundation
import Testing
@testable import FreqTrace

struct RTABinningTests {

    private let config = AnalysisConfig.default // 48kHz / 4096-window / 2048-hop

    /// Steps down from the 1kHz reference to FrequencyAxis.minHz, at
    /// `barsPerOctave` bands per octave -- also the array index of the
    /// bar centered exactly on 1kHz (n=0), since RTABinning's edges run
    /// from n=-stepsDown to n=+stepsUp.
    private func stepsDown(barsPerOctave: Int) -> Int {
        Int((log2(1000 / FrequencyAxis.minHz) * Double(barsPerOctave)).rounded())
    }

    private func stepsUp(barsPerOctave: Int) -> Int {
        Int((log2(FrequencyAxis.maxHz / 1000) * Double(barsPerOctave)).rounded())
    }

    /// Array index of the band nearest `hz`, at `barsPerOctave` bands per
    /// octave anchored at 1kHz.
    private func barIndex(forHz hz: Double, barsPerOctave: Int) -> Int {
        stepsDown(barsPerOctave: barsPerOctave) + Int((log2(hz / 1000) * Double(barsPerOctave)).rounded())
    }

    @Test func producesBarCountDerivedFromBarsPerOctave() {
        let magnitudes = [Float](repeating: 0, count: config.windowSize / 2)
        let barsPerOctave = 3

        let bars = RTABinning.bars(magnitudes: magnitudes, config: config, barsPerOctave: barsPerOctave, fullScalePower: 1.0)

        // 1/3 octave across 20Hz-20kHz: 31 bands (user report: "at 1/3 we
        // should have 31 bands"), not an arbitrary requested count --
        // `barsPerOctave` bands per octave anchored at 1kHz determines the
        // count, it isn't a direct input anymore.
        let expectedCount = stepsDown(barsPerOctave: barsPerOctave) + stepsUp(barsPerOctave: barsPerOctave) + 1
        #expect(expectedCount == 31)
        #expect(bars.count == expectedCount)
    }

    @Test func emptyMagnitudesProducesEmptyBars() {
        let bars = RTABinning.bars(magnitudes: [], config: config, barsPerOctave: 12, fullScalePower: 1.0)

        #expect(bars.isEmpty)
    }

    @Test func loudToneProducesAPeakInTheBarCenteredOn1kHz() {
        var magnitudes = [Float](repeating: 0, count: config.windowSize / 2)
        let binHz = config.sampleRate / Double(config.windowSize)
        let toneBin = Int(1000 / binHz) // 1kHz
        magnitudes[toneBin] = 1.0 // full-scale power

        let barsPerOctave = 12
        let bars = RTABinning.bars(magnitudes: magnitudes, config: config, barsPerOctave: barsPerOctave, fullScalePower: 1.0)

        // 1kHz (n=0) is always at array index stepsDown, regardless of
        // barsPerOctave -- the whole point of anchoring at 1kHz.
        let expectedBar = stepsDown(barsPerOctave: barsPerOctave)
        let loudestBar = bars.indices.max(by: { bars[$0] < bars[$1] })!

        #expect(loudestBar == expectedBar)
        #expect(bars[expectedBar] > 0.9) // near full-scale after normalization
    }

    @Test func silentSpectrumProducesBarsAtTheFloor() {
        let magnitudes = [Float](repeating: 0, count: config.windowSize / 2)

        let bars = RTABinning.bars(magnitudes: magnitudes, config: config, barsPerOctave: 12, fullScalePower: 1.0)

        #expect(bars.allSatisfy { $0 == 0 })
    }

    // Regression test for a real bug: raw vDSP FFT power is NOT already
    // normalized to a [0,1]/dBFS scale (a full-scale tone's raw power is
    // on the order of 10^6-10^7 for this window size, not ~1.0) --
    // without dividing by a full-scale reference first, MagnitudeScaling's
    // -80/0dB floor/ceiling clamped virtually everything to the ceiling,
    // pegging every bar to max regardless of actual loudness (reported by
    // the user as "RTA is out of window" / "everything looks too high").
    @Test func rawUnnormalizedVDSPScalePowerIsCorrectlyReferencedAgainstFullScalePower() {
        // A realistic full-scale-tone raw power magnitude for a 4096-point
        // FFT (order of magnitude only -- the exact vDSP constant doesn't
        // matter, what matters is it's nowhere near 1.0).
        let realisticFullScaleRawPower: Float = 4_000_000
        var loudMagnitudes = [Float](repeating: 0, count: config.windowSize / 2)
        var quietMagnitudes = [Float](repeating: 0, count: config.windowSize / 2)
        let binHz = config.sampleRate / Double(config.windowSize)
        let toneBin = Int(1000 / binHz)
        loudMagnitudes[toneBin] = realisticFullScaleRawPower
        // -12dB half-amplitude-squared-ish quieter tone (power, not
        // amplitude, so -12dB power ~ a quarter of the full-scale power).
        quietMagnitudes[toneBin] = realisticFullScaleRawPower * Float(pow(10, -12.0 / 10.0))

        let barsPerOctave = 12
        let loudBars = RTABinning.bars(
            magnitudes: loudMagnitudes, config: config, barsPerOctave: barsPerOctave, fullScalePower: realisticFullScaleRawPower
        )
        let quietBars = RTABinning.bars(
            magnitudes: quietMagnitudes, config: config, barsPerOctave: barsPerOctave, fullScalePower: realisticFullScaleRawPower
        )
        let bin = stepsDown(barsPerOctave: barsPerOctave) // 1kHz (n=0)

        // Both must NOT simply peg to 1.0 -- the quieter tone should read
        // meaningfully lower than the loud one, proving the raw power was
        // actually referenced against fullScalePower before normalizing.
        #expect(loudBars[bin] > 0.9)
        #expect(quietBars[bin] < loudBars[bin])
        #expect(quietBars[bin] > 0.0)
    }

    // Regression test for a real bug (user report: "under 63Hz we have
    // only one per two RTA bar working"): below ~63Hz at the default
    // config, the log-scaled bar width (as narrow as ~3Hz near 20Hz) is
    // finer than the FFT's own bin resolution (~11.7Hz) -- forward
    // bin->bar mapping then skips alternating bars entirely (bins land in
    // bars 1,3,5,7... never 0,2,4,6...), leaving them silent forever
    // regardless of actual signal.
    @Test func lowFrequencyBarsAllReceiveEnergyEvenWhenCoarserThanBinResolution() {
        // Uniform non-silent energy across every bin -- if any bar in the
        // sub-63Hz region stays exactly at the floor, that bar never got a
        // bin mapped to it.
        let magnitudes = [Float](repeating: 1000, count: config.windowSize / 2)
        let barsPerOctave = 12

        let bars = RTABinning.bars(magnitudes: magnitudes, config: config, barsPerOctave: barsPerOctave, fullScalePower: 1000)

        let cutoffBar = barIndex(forHz: 63, barsPerOctave: barsPerOctave)
        for bar in 0...cutoffBar {
            #expect(bars[bar] > 0, "bar \(bar) (below 63Hz) should not be silent")
        }
    }
}
