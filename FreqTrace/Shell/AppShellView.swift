//
//  AppShellView.swift
//  FreqTrace
//
//  The three-zone layout: Waterfall/RTA (dominant) -> Measured Data row ->
//  Controls row (two lines). See CLAUDE.md Frontend for the rationale
//  (everything visible on one screen, no tabs/panels/sheets).
//
//  Appearance Mode (ticket #10, ADR 0005): AppShellView is where
//  AppearanceSettings.mode actually becomes a Theme -- everything below
//  reads \.theme from the environment (see Theme.swift), so the toggle in
//  ControlsRowView only has to write one value here, not touch every view.
//

import SwiftUI

struct AppShellView: View {
    @State private var trackedFrequencyViewModel = AudioPipelineViewModel()
    @State private var appearanceSettings = AppearanceSettings()

    private var theme: Theme { Theme(mode: appearanceSettings.mode) }

    var body: some View {
        VStack(spacing: 0) {
            WaterfallZoneView()
                .frame(minHeight: 340)
            MeasuredDataRowView()
            ControlsRowView()
        }
        .background(theme.bg)
        .frame(minWidth: LayoutMetrics.minWindowWidth, minHeight: LayoutMetrics.minWindowHeight)
        .environment(\.theme, theme)
        .environment(trackedFrequencyViewModel)
        .environment(appearanceSettings)
    }
}

#Preview {
    AppShellView()
        .environment(\.theme, Theme(mode: .default))
}
