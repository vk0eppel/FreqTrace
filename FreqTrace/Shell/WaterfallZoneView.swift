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
                MetalWaterfallView(
                    magnitudes: pipeline.latestMagnitudes, config: pipeline.config,
                    appearanceMode: theme.mode, fullScalePower: pipeline.fullScalePower
                )
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

    // Axis legibility (user report: "not visible enough"): each label now
    // sits on its own backdrop pill so it reads clearly against any
    // waterfall/RTA color underneath, rather than bare low-opacity text
    // that could disappear into similarly-colored pixels. A faint gridline
    // at full opacity-independent low alpha marks the exact position, not
    // just an approximate label placement.
    private var frequencyAxisLabels: some View {
        GeometryReader { proxy in
            ForEach(FrequencyAxis.labeledBands, id: \.hz) { band in
                let x = proxy.size.width * FrequencyAxis.normalizedPosition(forHz: band.hz)
                Rectangle()
                    .fill(theme.text.opacity(0.12))
                    .frame(width: 1)
                    .position(x: x, y: proxy.size.height / 2)
                axisLabel(band.label)
                    .position(x: x, y: proxy.size.height - 12)
            }
        }
    }

    // Inset top/bottom (user report: "first/last value mainly out of
    // screen"): the oldest ("-15s") and newest ("now") gridlines used to map
    // to y=0 and y=proxy.size.height exactly -- flush against the view's
    // own .clipped() edges, so roughly half of each label's pill was cut
    // off. bottomInset is larger than topInset so "now" also clears the
    // frequency axis's bottom label row instead of overlapping it.
    private var timeAxisLabels: some View {
        GeometryReader { proxy in
            let topInset: CGFloat = 12
            let bottomInset: CGFloat = 28
            let usableHeight = proxy.size.height - topInset - bottomInset
            ForEach(gridlines, id: \.secondsAgo) { gridline in
                let y = topInset + usableHeight * (1 - gridline.normalizedPosition)
                Rectangle()
                    .fill(theme.text.opacity(0.12))
                    .frame(height: 1)
                    .position(x: proxy.size.width / 2, y: y)
                axisLabel(gridline.secondsAgo == 0 ? "now" : "\u{2212}\(Int(gridline.secondsAgo))s")
                    .position(x: 26, y: y)
            }
        }
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Typography.axisLabelSize, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.text.opacity(0.9))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.bg.opacity(0.7))
            )
    }
}

#Preview {
    WaterfallZoneView()
        .environment(\.theme, Theme(mode: .dark))
        .environment(AudioPipelineViewModel())
        .frame(width: 900, height: 340)
}
