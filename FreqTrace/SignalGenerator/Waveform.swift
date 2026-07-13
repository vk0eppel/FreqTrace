//
//  Waveform.swift
//  FreqTrace
//
//  The three waveforms the Signal Generator can emit (issue #9). No sweeps
//  in v1 -- see CLAUDE.md's Signal Generator bullet.
//

import Foundation

enum Waveform: String, CaseIterable, Identifiable {
    case sine
    case pinkNoise
    case whiteNoise

    var id: String { rawValue }

    /// Short label for the waveform picker in the Controls row.
    var displayName: String {
        switch self {
        case .sine: "Sine"
        case .pinkNoise: "Pink"
        case .whiteNoise: "White"
        }
    }
}
