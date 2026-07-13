//
//  WaterfallLogicTests.swift
//  FreqTraceTests
//
//  Exercises the pure, hardware/GPU-independent half of the waterfall
//  (ticket #8): log-frequency axis mapping, the color ramp, magnitude
//  scaling, and history-buffer bookkeeping. The Metal rendering itself
//  (WaterfallRenderer, Waterfall.metal) is not unit-testable -- verified
//  visually instead (see the ticket's implementation notes).
//

import Testing
@testable import FreqTrace

struct HexColorTests {

    @Test func parsesKnownValues() {
        #expect(HexColor.rgb("#0b0d10") == SIMD3<Float>(0x0b, 0x0d, 0x10) / 255)
        #expect(HexColor.rgb("#ffffff") == SIMD3<Float>(1, 1, 1))
        #expect(HexColor.rgb("#000000") == SIMD3<Float>(0, 0, 0))
    }

    @Test func toleratesMissingHashPrefix() {
        #expect(HexColor.rgb("ffd166") == HexColor.rgb("#ffd166"))
    }
}

struct FrequencyAxisTests {

    @Test func endpointsMapToZeroAndOne() {
        #expect(FrequencyAxis.normalizedPosition(forHz: FrequencyAxis.minHz) == 0)
        #expect(FrequencyAxis.normalizedPosition(forHz: FrequencyAxis.maxHz) == 1)
    }

    @Test func clampsOutOfRangeFrequencies() {
        #expect(FrequencyAxis.normalizedPosition(forHz: 1) == 0)
        #expect(FrequencyAxis.normalizedPosition(forHz: 100_000) == 1)
    }

    @Test func isMonotonicIncreasing() {
        let positions = [50.0, 100, 500, 1000, 5000, 15000].map(FrequencyAxis.normalizedPosition(forHz:))
        #expect(positions == positions.sorted())
    }

    @Test func hzAndPositionRoundTrip() {
        for hz in [50.0, 220, 1000, 4400, 12000] {
            let position = FrequencyAxis.normalizedPosition(forHz: hz)
            let roundTripped = FrequencyAxis.hz(atNormalizedPosition: position)
            #expect(abs(roundTripped - hz) / hz < 0.001)
        }
    }

    @Test func labeledBandsMatchTheSpec() {
        // Standard octave-band series, 20Hz-20kHz (user-requested
        // revision, superseding ticket #8's original coarser set).
        let labels = FrequencyAxis.labeledBands.map(\.label)
        #expect(labels == ["31.5", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"])
    }

    @Test func labeledBandsAreInAscendingOrder() {
        let hz = FrequencyAxis.labeledBands.map(\.hz)
        #expect(hz == hz.sorted())
    }
}

struct WaterfallColorMapTests {

    @Test func endpointsMatchCLAUDEMdExactly() {
        // CLAUDE.md "Waterfall Color Maps", Dark mode: silence -> loudest.
        #expect(WaterfallColorMap.color(for: 0) == HexColor.rgb("#0b0d10"))
        #expect(WaterfallColorMap.color(for: 1) == HexColor.rgb("#ffd166"))
    }

    @Test func exactStopsMatchTheirDocumentedHex() {
        #expect(WaterfallColorMap.color(for: 0.2) == HexColor.rgb("#2b1150"))
        #expect(WaterfallColorMap.color(for: 0.4) == HexColor.rgb("#7c1c62"))
        #expect(WaterfallColorMap.color(for: 0.6) == HexColor.rgb("#c33b3a"))
        #expect(WaterfallColorMap.color(for: 0.8) == HexColor.rgb("#e8752b"))
    }

    @Test func interpolatesBetweenStopsRatherThanSteppingAbruptly() {
        let quarter = WaterfallColorMap.color(for: 0.1)
        let stop0 = HexColor.rgb("#0b0d10")
        let stop1 = HexColor.rgb("#2b1150")
        #expect(quarter != stop0 && quarter != stop1)
        // Halfway between 0 and 0.2 -> each component should sit between
        // the two stops' corresponding components.
        for i in 0..<3 {
            let lo = min(stop0[i], stop1[i])
            let hi = max(stop0[i], stop1[i])
            #expect(quarter[i] >= lo && quarter[i] <= hi)
        }
    }

    @Test func clampsOutOfRangeInput() {
        #expect(WaterfallColorMap.color(for: -1) == WaterfallColorMap.color(for: 0))
        #expect(WaterfallColorMap.color(for: 2) == WaterfallColorMap.color(for: 1))
    }

    @Test func lightRampEndpointsAndStopsMatchCLAUDEMdExactly() {
        // CLAUDE.md "Waterfall Color Maps", Light mode: silence -> loudest
        // (ticket #10). Lightness *decreases* -- loudest is near-black.
        #expect(WaterfallColorMap.color(for: 0, in: WaterfallColorMap.light) == HexColor.rgb("#f4f5f6"))
        #expect(WaterfallColorMap.color(for: 1, in: WaterfallColorMap.light) == HexColor.rgb("#2a0e33"))
        #expect(WaterfallColorMap.color(for: 0.2, in: WaterfallColorMap.light) == HexColor.rgb("#bcd6f2"))
        #expect(WaterfallColorMap.color(for: 0.4, in: WaterfallColorMap.light) == HexColor.rgb("#6f9fe0"))
        #expect(WaterfallColorMap.color(for: 0.6, in: WaterfallColorMap.light) == HexColor.rgb("#39599e"))
        #expect(WaterfallColorMap.color(for: 0.8, in: WaterfallColorMap.light) == HexColor.rgb("#5a2e6b"))
    }
}

struct MagnitudeScalingTests {

    @Test func fullScalePowerNormalizesToOne() {
        #expect(abs(MagnitudeScaling.normalized(power: 1.0) - 1.0) < 0.001)
    }

    @Test func silenceNormalizesToZero() {
        #expect(MagnitudeScaling.normalized(power: 0) == 0)
    }

    @Test func isMonotonicWithLoudness() {
        let quiet = MagnitudeScaling.normalized(power: 0.001)
        let mid = MagnitudeScaling.normalized(power: 0.1)
        let loud = MagnitudeScaling.normalized(power: 1.0)
        #expect(quiet < mid && mid < loud)
    }

    @Test func clampsAboveFullScale() {
        // A power > 1.0 (e.g. a very hot signal) must not exceed the [0,1]
        // range the color map expects.
        #expect(MagnitudeScaling.normalized(power: 100) == 1.0)
    }
}

struct WaterfallHistoryBufferTests {

    @Test func historyDurationLandsInTheSpeccedTenToTwentySecondRange() {
        // Ticket #8: "~10-20s default scroll history."
        let buffer = WaterfallHistoryBuffer(config: .default)
        #expect(buffer.historyDurationSeconds >= 10)
        #expect(buffer.historyDurationSeconds <= 20)
    }

    @Test func columnCountMatchesHalfTheFFTWindow() {
        let buffer = WaterfallHistoryBuffer(config: .default)
        #expect(buffer.columnCount == AnalysisConfig.default.windowSize / 2)
    }

    @Test func nextRowIndexCyclesWithinRowCount() {
        var buffer = WaterfallHistoryBuffer(config: .default)
        var seen = Set<Int>()
        for _ in 0..<(buffer.rowCount * 2) {
            let row = buffer.nextRowIndex()
            #expect(row >= 0 && row < buffer.rowCount)
            seen.insert(row)
        }
        // After more than a full cycle, every row index should have been
        // used at least once.
        #expect(seen.count == buffer.rowCount)
    }

    @Test func scrollOffsetAdvancesAsRowsAreWritten() {
        var buffer = WaterfallHistoryBuffer(config: .default)
        let initial = buffer.scrollOffset
        _ = buffer.nextRowIndex()
        #expect(buffer.scrollOffset != initial)
    }

    @Test func gridlinesIncludeNowAndStayWithinHistory() {
        let gridlines = WaterfallHistoryBuffer.gridlines(historyDurationSeconds: 15, intervalSeconds: 5)
        #expect(gridlines.first?.secondsAgo == 0)
        #expect(gridlines.allSatisfy { $0.secondsAgo <= 15 })
        #expect(gridlines.map(\.secondsAgo) == [0, 5, 10, 15])
    }

    @Test func gridlineNormalizedPositionsAreFractionOfHistory() {
        let gridlines = WaterfallHistoryBuffer.gridlines(historyDurationSeconds: 20, intervalSeconds: 5)
        #expect(gridlines.map(\.normalizedPosition) == [0, 0.25, 0.5, 0.75, 1.0])
    }
}
