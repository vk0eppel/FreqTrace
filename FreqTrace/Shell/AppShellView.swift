//
//  AppShellView.swift
//  FreqTrace
//
//  The three-zone layout: Waterfall/RTA (dominant) -> Measured Data row ->
//  Controls row (two lines). See CLAUDE.md Frontend for the rationale
//  (everything visible on one screen, no tabs/panels/sheets).
//

import SwiftUI

struct AppShellView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            WaterfallZoneView()
                .frame(minHeight: 340)
            MeasuredDataRowView()
            ControlsRowView()
        }
        .background(theme.bg)
        .frame(minWidth: LayoutMetrics.minWindowWidth, minHeight: LayoutMetrics.minWindowHeight)
    }
}

#Preview {
    AppShellView()
        .environment(\.theme, Theme(mode: .default))
}
