//
//  MeasuredReading.swift
//  FreqTrace
//
//  A hero/secondary numeric readout split into its number and its unit
//  (ticket #24): the Measured Data row renders the number big and bright and
//  the unit smaller and dimmed, so the digits read first from a distance
//  (CLAUDE.md "readable from a distance"). Also carries the intentional
//  empty state (ticket #22): before a reading exists, `number` is an em dash
//  and `hasValue` is false, so the view can show a dimmed "— Hz" / "— dB"
//  rather than a bare floating dash that reads as broken.
//
//  Pure value type, nonisolated (CLAUDE.md Architecture Swift 6 isolation
//  convention) -- the formatting is the test seam; the view just styles it.
//

import Foundation

nonisolated struct MeasuredReading: Equatable {
    /// The numeric part only ("240", "-61"), or `placeholderNumber` when
    /// there's no reading yet.
    let number: String
    /// The unit suffix ("Hz", "dB"), always present -- shown even in the
    /// empty state so "— Hz" reads as "no reading yet", not a stray dash.
    let unit: String
    /// False in the empty state, so the view can dim the placeholder number.
    let hasValue: Bool

    /// Em dash -- the same placeholder the row used before the split.
    static let placeholderNumber = "\u{2014}"

    /// Tracked Frequency (hero). Whole Hz -- the tracker's parabolic sub-bin
    /// interpolation (FrequencyTracker.trackedFrequency) makes whole Hz an
    /// accurate, FFT-size-stable value rather than the bin grid's ceiling, so
    /// this rounds cleanly to whole Hz for a distance-legible readout.
    static func frequency(hz: Double?) -> MeasuredReading {
        guard let hz else {
            return MeasuredReading(number: placeholderNumber, unit: "Hz", hasValue: false)
        }
        return MeasuredReading(number: String(format: "%.0f", hz), unit: "Hz", hasValue: true)
    }

    /// SPL = raw dBFS + manual offset (ticket #6), rounded to a whole dB.
    static func spl(db: Double?, offset: Double) -> MeasuredReading {
        guard let db, db.isFinite else {
            return MeasuredReading(number: placeholderNumber, unit: "dB", hasValue: false)
        }
        return MeasuredReading(number: "\(Int((db + offset).rounded()))", unit: "dB", hasValue: true)
    }
}
