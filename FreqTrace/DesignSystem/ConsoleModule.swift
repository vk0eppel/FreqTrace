//
//  ConsoleModule.swift
//  FreqTrace
//
//  Console-styled treatment for the Controls row (design pass, user
//  request): each functional group reads as a channel-strip module let
//  into the row -- a recessed plate (theme.surface inset against the row's
//  own theme.surfaceRaised background) rather than a flat toolbar segment.
//  A toggle's selected state is shown by a small lit LED next to its label
//  instead of filling the whole control with the accent color -- the same
//  "one lit indicator = one active state" language a real mixing console
//  uses, reused identically across Weighting, Time Avg, Freeze, Appearance,
//  and the Signal Generator waveform picker so it reads as one system
//  rather than a repainted button. Stop/Start passes `color: theme.danger`
//  for a tally-light reading ("capture is running") instead of the shared
//  amber "selected" language, since that's a running-state indicator, not
//  a passing preference.
//

import SwiftUI

struct LEDIndicator: View {
    @Environment(\.theme) private var theme
    let isLit: Bool
    var color: Color?

    var body: some View {
        let lit = color ?? theme.accent
        Circle()
            .fill(isLit ? lit : theme.textFaint.opacity(0.4))
            .frame(width: 6, height: 6)
            .shadow(color: isLit ? lit.opacity(0.8) : .clear, radius: isLit ? 3 : 0)
    }
}

/// Fixed rather than content-sized, so every module reads as the same
/// height regardless of what it holds -- a plain LED+label row and the
/// Signal Generator cluster (numeric dB box, toggle switch) have different
/// intrinsic heights, which left plates visibly uneven (user report).
private let consoleModuleHeight: CGFloat = 36

private struct ConsolePlate: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .frame(height: consoleModuleHeight)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func consolePlate() -> some View {
        modifier(ConsolePlate())
    }
}
