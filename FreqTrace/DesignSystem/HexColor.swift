//
//  HexColor.swift
//  FreqTrace
//
//  Shared hex-string -> RGB parsing, factored out so Theme's SwiftUI Color
//  conversion and the waterfall's SIMD3<Float>-based color ramp (which
//  can't depend on SwiftUI) don't each reimplement the same parsing.
//

import Foundation

// nonisolated: pure value type, see CLAUDE.md Architecture (Swift 6 isolation opt-out convention).
nonisolated enum HexColor {
    /// Parses a "#rrggbb" or "rrggbb" string into normalized [0,1] RGB
    /// components. A malformed token is a build-time bug, not a runtime
    /// condition to degrade gracefully from -- fails loudly.
    static func rgb(_ hex: String) -> SIMD3<Float> {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }
        var value: UInt64 = 0
        precondition(
            sanitized.count == 6 && Scanner(string: sanitized).scanHexInt64(&value),
            "Invalid hex color: \"\(hex)\""
        )
        let r = Float((value >> 16) & 0xFF) / 255
        let g = Float((value >> 8) & 0xFF) / 255
        let b = Float(value & 0xFF) / 255
        return SIMD3(r, g, b)
    }
}
