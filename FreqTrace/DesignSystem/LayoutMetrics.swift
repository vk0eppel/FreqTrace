//
//  LayoutMetrics.swift
//  FreqTrace
//
//  Minimum window size is derived from the widest Controls row line at the
//  Typography scale, not picked arbitrarily -- see CLAUDE.md "Window".
//  Re-derive if the Controls row's contents change.
//
//  Width was re-measured empirically (screenshots at candidate widths with
//  capture *running*, so the Input plate carries a real device name + the
//  sample-rate/bit-depth sub-caption -- the stopped state's "No Input
//  Device" is ~150pt narrower and understates the need): Line 2 (input
//  plate + generator cluster + output plate) is the binding line since the
//  generator moved down; clean at 1250, waveform labels wrap at 1200.
//  1280 = measured threshold + margin for longer device names. The old
//  1120 estimate predated the FFT Size plate and was observably too small.
//

import CoreGraphics

// nonisolated: pure value type, see CLAUDE.md Architecture (Swift 6 isolation opt-out convention).
nonisolated enum LayoutMetrics {
    static let minWindowWidth: CGFloat = 1280
    static let minWindowHeight: CGFloat = 660
}
