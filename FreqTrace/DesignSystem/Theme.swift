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

    // Stored, not computed (perf fix -- `sample` showed HexColor.rgb/
    // Color(hex:) hot on the main thread: every view reads these every
    // body evaluation, and the waterfall/RTA re-render at display rate, so
    // computed properties re-parsed the same hex strings thousands of
    // times per second). A Theme is only constructed on an appearance-mode
    // change, so parsing once here is effectively free.
    let bg: Color
    let surface: Color
    let surfaceRaised: Color
    let border: Color
    let borderSoft: Color
    let text: Color
    let textDim: Color
    let textFaint: Color
    let accent: Color
    let accentDim: Color
    let danger: Color
    let warn: Color

    init(mode: AppearanceMode) {
        self.mode = mode
        let tokens = DesignTokens.tokens(for: mode)
        self.bg = Color(hex: tokens.bg)
        self.surface = Color(hex: tokens.surface)
        self.surfaceRaised = Color(hex: tokens.surfaceRaised)
        self.border = Color(hex: tokens.border)
        self.borderSoft = Color(hex: tokens.borderSoft)
        self.text = Color(hex: tokens.text)
        self.textDim = Color(hex: tokens.textDim)
        self.textFaint = Color(hex: tokens.textFaint)
        self.accent = Color(hex: tokens.accent)
        self.accentDim = Color(hex: tokens.accentDim)
        self.danger = Color(hex: tokens.danger)
        self.warn = Color(hex: tokens.warn)
    }
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
