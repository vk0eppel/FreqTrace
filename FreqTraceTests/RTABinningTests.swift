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

import Testing
@testable import FreqTrace

struct RTABinningTests {

    private let config = AnalysisConfig.default // 48kHz / 4096-window / 2048-hop

    @Test func producesExactlyBarCountBars() {
        let magnitudes = [Float](repeating: 0, count: config.windowSize / 2)

        let bars = RTABinning.bars(magnitudes: magnitudes, config: config, barCount: 32)

        #expect(bars.count == 32)
    }

    @Test func emptyMagnitudesProducesEmptyBars() {
        let bars = RTABinning.bars(magnitudes: [], config: config, barCount: 32)

        #expect(bars.isEmpty)
    }

    @Test func loudToneProducesAPeakInTheBarMatchingItsLogFrequencyPosition() {
        var magnitudes = [Float](repeating: 0, count: config.windowSize / 2)
        let binHz = config.sampleRate / Double(config.windowSize)
        let toneBin = Int(1000 / binHz) // 1kHz
        magnitudes[toneBin] = 1.0 // full-scale power

        let barCount = 48
        let bars = RTABinning.bars(magnitudes: magnitudes, config: config, barCount: barCount)

        let expectedBar = min(barCount - 1, Int(FrequencyAxis.normalizedPosition(forHz: 1000) * Double(barCount)))
        let loudestBar = bars.indices.max(by: { bars[$0] < bars[$1] })!

        #expect(loudestBar == expectedBar)
        #expect(bars[expectedBar] > 0.9) // near full-scale after normalization
    }

    @Test func silentSpectrumProducesBarsAtTheFloor() {
        let magnitudes = [Float](repeating: 0, count: config.windowSize / 2)

        let bars = RTABinning.bars(magnitudes: magnitudes, config: config, barCount: 32)

        #expect(bars.allSatisfy { $0 == 0 })
    }
}
