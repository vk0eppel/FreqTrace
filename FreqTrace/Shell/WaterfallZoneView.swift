//
//  WaterfallZoneView.swift
//  FreqTrace
//
//  The dominant Waterfall/RTA zone. Real Metal rendering (ADR 0004, ticket
//  #8) with log-frequency axis labels along the bottom and time-axis
//  gridlines along the left, per CLAUDE.md "Primary view -- spectrogram/
//  waterfall". The RTA view and the Waterfall/RTA toggle (top-right of
//  this zone) are ticket #11, not added yet -- this ticket only builds the
//  real waterfall.
//

import SwiftUI

struct WaterfallZoneView: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPipelineViewModel.self) private var pipeline

    private var historyDurationSeconds: Double {
        WaterfallHistoryBuffer(config: pipeline.config).historyDurationSeconds
    }

    private var gridlines: [WaterfallHistoryBuffer.Gridline] {
        WaterfallHistoryBuffer.gridlines(historyDurationSeconds: historyDurationSeconds)
    }

    var body: some View {
        ZStack {
            MetalWaterfallView(magnitudes: pipeline.latestMagnitudes, config: pipeline.config)
            frequencyAxisLabels
            timeAxisLabels
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var frequencyAxisLabels: some View {
        GeometryReader { proxy in
            ForEach(FrequencyAxis.labeledBands, id: \.hz) { band in
                Text(band.label)
                    .font(.system(size: Typography.axisLabelSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.text.opacity(0.55))
                    .position(
                        x: proxy.size.width * FrequencyAxis.normalizedPosition(forHz: band.hz),
                        y: proxy.size.height - 10
                    )
            }
        }
    }

    private var timeAxisLabels: some View {
        GeometryReader { proxy in
            ForEach(gridlines, id: \.secondsAgo) { gridline in
                Text(gridline.secondsAgo == 0 ? "now" : "\u{2212}\(Int(gridline.secondsAgo))s")
                    .font(.system(size: Typography.axisLabelSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.text.opacity(0.55))
                    .position(
                        x: 22,
                        y: proxy.size.height * (1 - gridline.normalizedPosition)
                    )
            }
        }
    }
}

#Preview {
    WaterfallZoneView()
        .environment(\.theme, Theme(mode: .dark))
        .environment(AudioPipelineViewModel())
        .frame(width: 900, height: 340)
}
