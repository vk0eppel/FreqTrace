//
//  WaterfallColorMap.swift
//  FreqTrace
//
//  The waterfall's magnitude -> color ramps (ticket #8): deliberately
//  multi-hue (magma/viridis-family), not the generic single-hue sequential
//  ramp -- see CLAUDE.md "Waterfall Color Maps" for why (a spectrogram's
//  wide dynamic range needs more perceptual steps than one hue carries),
//  and for the OKLCH monotonicity verification these exact stops passed.
//
//  Pure, hardware-independent -- this is the test seam. Waterfall.metal
//  reimplements the same stops/interpolation on the GPU side (a fragment
//  shader can't call back into Swift), so if the ramp ever changes, both
//  places need updating together.
//

import Foundation

enum WaterfallColorMap {
    struct Stop {
        let position: Float
        let rgb: SIMD3<Float>
    }

    /// CLAUDE.md "Waterfall Color Maps" -- Dark mode: silence -> loudest.
    static let dark: [Stop] = [
        Stop(position: 0.0, rgb: HexColor.rgb("#0b0d10")),
        Stop(position: 0.2, rgb: HexColor.rgb("#2b1150")),
        Stop(position: 0.4, rgb: HexColor.rgb("#7c1c62")),
        Stop(position: 0.6, rgb: HexColor.rgb("#c33b3a")),
        Stop(position: 0.8, rgb: HexColor.rgb("#e8752b")),
        Stop(position: 1.0, rgb: HexColor.rgb("#ffd166")),
    ]

    /// Piecewise-linear interpolation across `stops` at normalized
    /// magnitude `t` (clamped to [0,1]).
    static func color(for t: Float, in stops: [Stop] = dark) -> SIMD3<Float> {
        let clamped = min(max(t, 0), 1)
        for i in 0..<(stops.count - 1) {
            let a = stops[i]
            let b = stops[i + 1]
            guard clamped >= a.position && clamped <= b.position else { continue }
            // Return exact stop colors at exact stop positions rather than
            // computing a + (b-a)*1 or *0 -- float arithmetic doesn't
            // guarantee those round-trip to bit-identical results.
            if clamped == a.position { return a.rgb }
            if clamped == b.position { return b.rgb }
            let localT = (clamped - a.position) / (b.position - a.position)
            return a.rgb + (b.rgb - a.rgb) * localT
        }
        return stops.last!.rgb
    }
}
