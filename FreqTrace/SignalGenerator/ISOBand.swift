//
//  ISOBand.swift
//  FreqTrace
//
//  Pure ISO 1/3-octave center-frequency stepping for the Signal Generator's
//  sine frequency control (ticket #14, CONTEXT.md "ISO Band"): step buttons
//  jump to the next/previous standard center, matching graphic EQ fader
//  spacing. Independent of AVAudioEngine/SwiftUI -- see ISOBandTests.
//

import Foundation

enum ISOBand {
    /// The standard ISO 266 R10 1/3-octave center frequencies from 25 Hz to
    /// 20 kHz (CONTEXT.md "ISO Band": "25, 31.5, 40, 50 Hz... matching
    /// graphic EQ fader spacing").
    static let centers: [Double] = [
        25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200,
        250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000,
        2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ]

    /// The next standard center strictly above `frequency`, or the highest
    /// center if already at/above it (clamps rather than going out of
    /// range).
    static func stepUp(from frequency: Double) -> Double {
        centers.first(where: { $0 > frequency }) ?? centers.last!
    }

    /// The previous standard center strictly below `frequency`, or the
    /// lowest center if already at/below it (clamps rather than going out
    /// of range).
    static func stepDown(from frequency: Double) -> Double {
        centers.last(where: { $0 < frequency }) ?? centers.first!
    }
}
