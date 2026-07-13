//
//  WaterfallZoneView.swift
//  FreqTrace
//
//  The dominant Waterfall/RTA zone. Real Metal rendering (ADR 0004, ticket
//  #8) with log-frequency axis labels along the bottom and time-axis
//  gridlines along the left, per CLAUDE.md "Primary view -- spectrogram/
//  waterfall". RTA (ticket #11, CLAUDE.md "RTA") is a second, mutually
//  exclusive rendering of the same live pipeline.latestMagnitudes stream --
//  switching the toggle never touches capture/start/stop, only which view
//  reads the already-flowing data, so both views stay live regardless of
//  which is shown (the AC's "without interrupting the underlying data
//  stream"). The toggle lives in this zone's top-right corner, not the
//  Controls row (CONTEXT.md "Controls row": "it's about that view
//  specifically").
//

import SwiftUI

enum GraphDisplayMode: String, CaseIterable, Identifiable {
    case waterfall = "Waterfall"
    case rta = "RTA"

    var id: String { rawValue }
}

struct WaterfallZoneView: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPipelineViewModel.self) private var pipeline
    @State private var displayMode: GraphDisplayMode = .waterfall

    private var historyDurationSeconds: Double {
        WaterfallHistoryBuffer(config: pipeline.config).historyDurationSeconds
    }

    private var gridlines: [WaterfallHistoryBuffer.Gridline] {
        WaterfallHistoryBuffer.gridlines(historyDurationSeconds: historyDurationSeconds)
    }

    var body: some View {
        ZStack {
            switch displayMode {
            case .waterfall:
                MetalWaterfallView(magnitudes: pipeline.latestMagnitudes, config: pipeline.config, appearanceMode: theme.mode)
                frequencyAxisLabels
                timeAxisLabels
            case .rta:
                RTAView()
                frequencyAxisLabels
            }
            displayModeToggle
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var displayModeToggle: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 0) {
                    ForEach(GraphDisplayMode.allCases) { mode in
                        displayModeButton(mode)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.surfaceRaised.opacity(0.9))
                )
                .padding(10)
            }
            Spacer()
        }
    }

    private func displayModeButton(_ mode: GraphDisplayMode) -> some View {
        let isSelected = displayMode == mode
        return Button {
            displayMode = mode
        } label: {
            Text(mode.rawValue.uppercased())
                .font(.system(size: Typography.controlSize, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? theme.bg : theme.textDim)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? theme.accent : Color.clear)
                )
        }
        .buttonStyle(.plain)
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
