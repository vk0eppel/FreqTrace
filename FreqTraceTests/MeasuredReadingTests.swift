//
//  MeasuredReadingTests.swift
//  FreqTraceTests
//
//  The number/unit split + empty-state placeholder behind the Measured Data
//  row's hero readings (tickets #24 and #22): the view styles the number and
//  unit separately, so this is where the formatting is pinned.
//

import Testing
@testable import FreqTrace

struct MeasuredReadingTests {

    @Test func frequencySplitsNumberFromUnitAsWholeHz() {
        let reading = MeasuredReading.frequency(hz: 240.4)
        #expect(reading.number == "240")   // whole Hz, rounded
        #expect(reading.unit == "Hz")
        #expect(reading.hasValue)
    }

    @Test func frequencyWithoutAValueIsAUnitBearingPlaceholder() {
        let reading = MeasuredReading.frequency(hz: nil)
        #expect(reading.number == MeasuredReading.placeholderNumber)
        #expect(reading.unit == "Hz")       // unit kept so it reads "— Hz"
        #expect(!reading.hasValue)
    }

    @Test func splAppliesOffsetAndSplitsUnit() {
        let reading = MeasuredReading.spl(db: -61.2, offset: 0)
        #expect(reading.number == "-61")
        #expect(reading.unit == "dB")
        #expect(reading.hasValue)
    }

    @Test func splAddsTheOffsetBeforeRounding() {
        let reading = MeasuredReading.spl(db: -61, offset: 10)
        #expect(reading.number == "-51")
    }

    @Test func splWithoutAValueIsAUnitBearingPlaceholder() {
        let reading = MeasuredReading.spl(db: nil, offset: 0)
        #expect(reading.number == MeasuredReading.placeholderNumber)
        #expect(reading.unit == "dB")
        #expect(!reading.hasValue)
    }

    @Test func splRejectsNonFiniteAsPlaceholder() {
        let reading = MeasuredReading.spl(db: .infinity, offset: 0)
        #expect(!reading.hasValue)
        #expect(reading.number == MeasuredReading.placeholderNumber)
    }
}
