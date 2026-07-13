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
    @State private var trackedFrequencyViewModel = AudioPipelineViewModel()

    var body: some View {
        VStack(spacing: 0) {
            WaterfallZoneView()
                .frame(minHeight: 340)
            MeasuredDataRowView()
            ControlsRowView()
        }
        .background(theme.bg)
        .frame(minWidth: LayoutMetrics.minWindowWidth, minHeight: LayoutMetrics.minWindowHeight)
        .environment(trackedFrequencyViewModel)
        .task {
            // System default input device only for now -- explicit Input
            // Device selection is ticket #4. Starts the shared capture ->
            // FFT -> tracking pipeline (ADR 0002) for the whole app shell.
            trackedFrequencyViewModel.start()
        }
    }
}

#Preview {
    AppShellView()
        .environment(\.theme, Theme(mode: .default))
}
