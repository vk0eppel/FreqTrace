//
//  FrequencyScale.swift
//  FreqTrace
//
//  Selectable frequency-axis label/gridline series (issue #25): the x-axis
//  mapping itself is a fixed continuous log scale (FrequencyAxis), so this
//  only chooses *which reference lines* are drawn on top of it -- it does
//  not touch the axis math, the Metal shader, or RTA bar positioning.
//
//  Octave (default) is the ISO/graphic-EQ series real live-sound techs
//  navigate by (31.5, 63, ... 16k). Decade is the REW/Smaart-style log
//  grid: bold lines at each decade (100, 1k, 10k) with fainter minor lines
//  at the 2-9 multiples between them, so every frequency still has a nearby
//  reference. Same shape as RTABandingResolution (CaseIterable/Identifiable
//  over a user-recognizable label); declaration order is UI order.
//
//  nonisolated: pure value type, see CLAUDE.md Architecture (Swift 6
//  isolation opt-out convention).
//

import Foundation

nonisolated enum FrequencyScale: String, CaseIterable, Identifiable {
    case octave
    case decade

    var id: String { rawValue }

    var label: String {
        switch self {
        case .octave: return "Octave"
        case .decade: return "Decade"
        }
    }

    /// The gridlines this scale draws, ascending. Octave reuses the existing
    /// ISO octave series (all major, single tier, keeping the fractional
    /// "31.5" label). Decade generates a log grid: every 2-9 multiple of each
    /// decade inside [minHz, maxHz], with the decade boundaries (mantissa 1:
    /// 100/1k/10k) flagged major.
    var gridlines: [FrequencyAxis.Gridline] {
        switch self {
        case .octave:
            return FrequencyAxis.labeledBands.map {
                FrequencyAxis.Gridline(hz: $0.hz, label: $0.label, isMajor: true)
            }
        case .decade:
            var lines: [FrequencyAxis.Gridline] = []
            for base in [10.0, 100.0, 1000.0, 10_000.0] {
                for mantissa in 1...9 {
                    let hz = base * Double(mantissa)
                    guard hz >= FrequencyAxis.minHz, hz <= FrequencyAxis.maxHz else { continue }
                    lines.append(FrequencyAxis.Gridline(hz: hz, label: FrequencyAxis.label(forHz: hz), isMajor: mantissa == 1))
                }
            }
            return lines
        }
    }
}
