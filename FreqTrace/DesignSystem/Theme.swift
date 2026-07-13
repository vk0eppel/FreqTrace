//
//  Theme.swift
//  FreqTrace
//
//  Converts DesignTokens (hex strings, unit-testable) into SwiftUI Colors,
//  and exposes them via the environment so every view reads from one place.
//  The environment seam exists now so the future Appearance Mode toggle
//  ticket only has to change what's written here, not every consuming view.
//
//  Hex parsing itself lives in HexColor (a plain SIMD3<Float>, no SwiftUI
//  dependency) so the waterfall's color ramp can share it without pulling
//  in SwiftUI.
//

import SwiftUI

extension Color {
    init(hex: String) {
        let rgb = HexColor.rgb(hex)
        self.init(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
    }
}

struct Theme {
    let mode: AppearanceMode
    private let tokens: ColorTokens

    init(mode: AppearanceMode) {
        self.mode = mode
        self.tokens = DesignTokens.tokens(for: mode)
    }

    var bg: Color { Color(hex: tokens.bg) }
    var surface: Color { Color(hex: tokens.surface) }
    var surfaceRaised: Color { Color(hex: tokens.surfaceRaised) }
    var border: Color { Color(hex: tokens.border) }
    var borderSoft: Color { Color(hex: tokens.borderSoft) }
    var text: Color { Color(hex: tokens.text) }
    var textDim: Color { Color(hex: tokens.textDim) }
    var textFaint: Color { Color(hex: tokens.textFaint) }
    var accent: Color { Color(hex: tokens.accent) }
    var accentDim: Color { Color(hex: tokens.accentDim) }
    var danger: Color { Color(hex: tokens.danger) }
    var warn: Color { Color(hex: tokens.warn) }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(mode: .default)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
