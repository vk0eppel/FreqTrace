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
                    appearanceMode: theme.mode, fullScalePower: pipeline.fullScalePower,
                    bandingResolution: pipeline.bandingResolution
                )
                frequencyAxisLabels
                timeAxisLabels
            case .rta:
                RTAView()
                frequencyAxisLabels
                dbAxisLabels
            }
            displayModeToggle
            bandingResolutionControl
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

    // Octave-banding resolution (user request: "relative to octaves, from
    // 48 per octave to 1 per octave," then "the same for the waterfall" --
    // one shared setting for both views, confirmed with user, not an
    // independent control per view). Lives here in the graph zone rather
    // than the Controls row, same reasoning CLAUDE.md already gives for
    // the Waterfall/RTA toggle itself living here; shown regardless of
    // displayMode since it now affects both.
    private var bandingResolutionControl: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    ForEach(RTABandingResolution.allCases) { resolution in
                        bandingResolutionButton(resolution)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.surfaceRaised.opacity(0.9))
                )
                .padding(.trailing, 10)
            }
            .padding(.top, 50)
            Spacer()
        }
    }

    private func bandingResolutionButton(_ resolution: RTABandingResolution) -> some View {
        let isSelected = pipeline.bandingResolution == resolution
        return Button {
            pipeline.bandingResolution = resolution
        } label: {
            Text(resolution.label)
                .font(.system(size: Typography.axisLabelSize, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .foregroundStyle(isSelected ? theme.bg : theme.textDim)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? theme.accent : Color.clear)
                )
        }
        .buttonStyle(.plain)
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

    // RTA's Y axis (user report: "RTA should have a visible y axis scale
    // too") -- RTA has no time history (a single live frame), so unlike the
    // waterfall this side of the graph is otherwise unused, and the same
    // left-edge position timeAxisLabels uses for the waterfall is free
    // here. Levels mirror RTABinning/MagnitudeScaling's -80…0dB normalized
    // range (the same range each bar's height is computed from), so a bar
    // reaching the "-20 dB" gridline really is -20dB. Same top/bottom inset
    // approach as timeAxisLabels, for the same reason (avoid clipping the
    // top label and colliding with the frequency axis's bottom row).
    private static let dbGridlineLevels: [Float] = [0, -20, -40, -60, -80]

    private var dbAxisLabels: some View {
        GeometryReader { proxy in
            let topInset: CGFloat = 12
            let bottomInset: CGFloat = 28
            let usableHeight = proxy.size.height - topInset - bottomInset
            ForEach(Self.dbGridlineLevels, id: \.self) { db in
                let normalized = (db - MagnitudeScaling.floorDb) / (MagnitudeScaling.ceilingDb - MagnitudeScaling.floorDb)
                let y = topInset + usableHeight * (1 - CGFloat(normalized))
                Rectangle()
                    .fill(theme.text.opacity(0.12))
                    .frame(height: 1)
                    .position(x: proxy.size.width / 2, y: y)
                axisLabel("\(Int(db)) dB")
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
