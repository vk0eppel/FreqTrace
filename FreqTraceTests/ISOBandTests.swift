//
//  ISOBandTests.swift
//  FreqTraceTests
//
//  Exercises the pure ISO 1/3-octave center-frequency stepping behind the
//  Signal Generator's sine frequency control (ticket #14, CONTEXT.md "ISO
//  Band"). Expected values are literal, independently-sourced standard
//  ISO 266 R10 1/3-octave centers (the same series used by graphic EQ
//  fader spacing), not derived from ISOBand.centers itself.
//

import Testing
@testable import FreqTrace

struct ISOBandTests {

    @Test func steppingUpFromAnExactCenterLandsOnTheAdjacentCenter() {
        #expect(ISOBand.stepUp(from: 1000) == 1250)
    }

    @Test func steppingDownFromAnExactCenterLandsOnTheAdjacentCenter() {
        #expect(ISOBand.stepDown(from: 1000) == 800)
    }

    @Test func steppingUpFromAnOffGridFrequencyLandsOnTheNearestCenterAboveItNotAHopOfTwo() {
        // 45 Hz sits between the standard 40 Hz and 50 Hz centers (entered
        // via the free Hz field) -- stepping up must land on 50, not skip
        // to 63.
        #expect(ISOBand.stepUp(from: 45) == 50)
    }

    @Test func steppingDownFromAnOffGridFrequencyLandsOnTheNearestCenterBelowItNotAHopOfTwo() {
        // Same off-grid frequency, opposite direction: must land on 40, not
        // skip down to 31.5.
        #expect(ISOBand.stepDown(from: 45) == 40)
    }

    @Test func steppingUpAtTheHighestCenterClampsInsteadOfGoingOutOfRange() {
        #expect(ISOBand.stepUp(from: 20000) == 20000)
    }

    @Test func steppingUpAboveTheHighestCenterClampsToTheHighestCenter() {
        #expect(ISOBand.stepUp(from: 25000) == 20000)
    }

    @Test func steppingDownAtTheLowestCenterClampsInsteadOfGoingOutOfRange() {
        #expect(ISOBand.stepDown(from: 25) == 25)
    }

    @Test func steppingDownBelowTheLowestCenterClampsToTheLowestCenter() {
        #expect(ISOBand.stepDown(from: 10) == 25)
    }

    @Test func centersSeriesMatchesTheKnownISO266R10StandardValues() {
        // Independent literal source-of-truth for the full series, not
        // derived the same way the implementation builds `centers`.
        let known: [Double] = [
            25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200,
            250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000,
            2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
        ]
        #expect(ISOBand.centers == known)
    }
}
