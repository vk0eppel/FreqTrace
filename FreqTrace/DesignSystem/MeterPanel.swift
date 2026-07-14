//
//  MeterPanel.swift
//  FreqTrace
//
//  A lighter echo of the Controls row's console styling (ConsoleModule.swift)
//  for the Measured Data row -- deliberately NOT the same treatment. The
//  Measured Data blocks are read-only meters, not switches: there's no
//  selected state to show, so no LEDIndicator, and no shared fixed height --
//  Tracked Frequency stays the visual hero (CLAUDE.md "Typography scale"),
//  so forcing it into a small uniform box like a Controls row module would
//  flatten it to "just another module" and would compete with the Anomaly
//  Candidate severity glow. All this borrows is the recessed-panel feel: a
//  subtly sunken fill (theme.bg, already darker/grayer than the row's own
//  theme.surface in both Appearance Modes) with a soft hairline border.
//

import SwiftUI

private struct MeterPanel: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.borderSoft, lineWidth: 1)
            )
    }
}

extension View {
    func meterPanel() -> some View {
        modifier(MeterPanel())
    }
}
