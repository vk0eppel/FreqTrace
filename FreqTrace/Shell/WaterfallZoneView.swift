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

import MetalKit
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
    /// Owned here rather than inside MetalWaterfallView's makeCoordinator()
    /// (hover tooltip feature) so hoverReadout(at:size:) can query the same
    /// instance's magnitudeDb(secondsAgo:hz:) that's writing the GPU
    /// texture -- constructed once on first appearance since MTLDevice
    /// creation/pipeline setup shouldn't repeat on every body evaluation.
    @State private var waterfallRenderer: WaterfallRenderer?
    /// Cursor position within the zone's own coordinate space, nil when the
    /// mouse isn't over it -- drives the hover tooltip below.
    @State private var hoverPoint: CGPoint?
    /// Keyboard shortcuts (user request: "w for Waterfall view, r for
    /// RTA") -- registered here rather than in AppShellView's monitor
    /// because displayMode is this view's own state; KeyboardShortcuts
    /// provides the shared guards (modifiers pass through, a focused text
    /// field wins), same as the spacebar Start/Stop shortcut.
    @State private var shortcutMonitor: Any?

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
                if let waterfallRenderer {
                    MetalWaterfallView(
                        renderer: waterfallRenderer,
                        appearanceMode: theme.mode,
                        isActive: pipeline.isCaptureActive && !pipeline.isFrozen
                    )
                }
                frequencyAxisLabels
                timeAxisLabels
            case .rta:
                RTAView()
                frequencyAxisLabels
                dbAxisLabels
            }
            if !pipeline.hasWaterfallData {
                emptyStateOverlay
            }
            hoverOverlay
            displayModeToggle
            bandingResolutionControl
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            guard shortcutMonitor == nil else { return }
            shortcutMonitor = KeyboardShortcuts.install([
                "w": { displayMode = .waterfall },
                "r": { displayMode = .rta },
            ])
        }
        .onDisappear {
            KeyboardShortcuts.remove(shortcutMonitor)
            shortcutMonitor = nil
        }
        .task(id: pipeline.config) {
            // Reactive, not just-once-in-onAppear (FFT size became
            // selectable, user request): WaterfallRenderer's GPU texture
            // dimensions are permanently fixed at init time (columnCount =
            // config.windowSize / 2), so a windowSize change needs a whole
            // new renderer + texture, not just a config update on the
            // existing one. .task(id:) re-runs whenever pipeline.config
            // (Equatable) changes, in addition to running once on first
            // appearance. Losing in-progress waterfall history when this
            // happens is expected, same as switching bandingResolution
            // already clears RTA bar peaks.
            guard let device = MTLCreateSystemDefaultDevice() else { return }
            let renderer = WaterfallRenderer(device: device, config: pipeline.config)
            waterfallRenderer = renderer
            // Feed hop frames straight to this renderer, outside SwiftUI (perf:
            // AudioPipelineViewModel.waterfallSink) -- re-registered here so a
            // renderer swap (FFT-size change) always points the sink at the
            // current renderer. Weak so a discarded renderer isn't retained.
            pipeline.waterfallSink = { [weak renderer] stepped, fullScalePower in
                renderer?.pushMagnitudes(stepped, fullScalePower: fullScalePower)
            }
        }
        .onDisappear { pipeline.waterfallSink = nil }
    }

    // Mouse-over exact-value readout (user request: "Mouse over waterfall
    // or rta should indicate the exact scale values") -- the axis
    // gridlines are necessarily coarse (fixed octave bands, 5dB steps), so
    // a tech pointing at an arbitrary spot gets the precise Hz + dB there
    // instead of eyeballing against the nearest label. Works live, no
    // Freeze required (confirmed with user) -- Freeze already gates
    // pipeline.latestMagnitudes/frozen waterfall rows upstream, so this
    // needs no special-casing either way.
    private var hoverOverlay: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverPoint = location
                    case .ended:
                        hoverPoint = nil
                    }
                }
            if let hoverPoint, let readout = hoverReadout(at: hoverPoint, size: proxy.size) {
                hoverTooltip(readout, near: hoverPoint, in: proxy.size)
            }
        }
    }

    private struct HoverReadout {
        let hz: Double
        /// nil when there's nothing to report yet at this point (e.g. a
        /// waterfall row not written yet) -- shown as frequency-only, no
        /// placeholder dash, matching how the rest of the app omits
        /// nothing-to-show state rather than faking a value.
        let db: Float?
    }

    private func hoverReadout(at point: CGPoint, size: CGSize) -> HoverReadout? {
        guard size.width > 0, size.height > 0 else { return nil }
        let hz = FrequencyAxis.hz(atNormalizedPosition: Double(point.x / size.width))

        switch displayMode {
        case .waterfall:
            guard let waterfallRenderer else { return HoverReadout(hz: hz, db: nil) }
            // Inverse of timeAxisLabels' own topInset/bottomInset mapping,
            // so the tooltip's time position matches the gridlines exactly.
            let topInset: CGFloat = 12
            let bottomInset: CGFloat = 28
            let usableHeight = size.height - topInset - bottomInset
            guard usableHeight > 0 else { return HoverReadout(hz: hz, db: nil) }
            let normalizedPosition = min(max(1 - Double((point.y - topInset) / usableHeight), 0), 1)
            let secondsAgo = normalizedPosition * historyDurationSeconds
            return HoverReadout(hz: hz, db: waterfallRenderer.magnitudeDb(secondsAgo: secondsAgo, hz: hz))
        case .rta:
            let barsPerOctave = pipeline.bandingResolution.rawValue
            // Reads the same cached per-hop bars RTAView now reads (perf
            // fix) instead of an independent third recomputation of
            // RTABinning.bars for the same hop's data.
            let bars = pipeline.latestRTABars
            guard !bars.isEmpty else { return HoverReadout(hz: hz, db: nil) }
            let edges = RTABinning.bandEdges(barsPerOctave: barsPerOctave, config: pipeline.config)
            guard let index = edges.firstIndex(where: { hz >= $0.lowerHz && hz <= $0.upperHz }) else {
                return HoverReadout(hz: hz, db: nil)
            }
            return HoverReadout(hz: hz, db: MagnitudeScaling.dB(fromNormalized: bars[index]))
        }
    }

    private func hoverTooltip(_ readout: HoverReadout, near point: CGPoint, in size: CGSize) -> some View {
        let width: CGFloat = 130
        let height: CGFloat = 20
        let x = min(max(point.x + 14 + width / 2, width / 2 + 4), size.width - width / 2 - 4)
        let y = min(max(point.y - 14, height / 2 + 4), size.height - height / 2 - 4)
        return axisLabel(hoverText(readout))
            .position(x: x, y: y)
            .allowsHitTesting(false)
    }

    private func hoverText(_ readout: HoverReadout) -> String {
        let freq = formattedHoverFrequency(readout.hz)
        guard let db = readout.db else { return freq }
        return "\(freq)  \(Int(db.rounded())) dB"
    }

    // Whole Hz below 1kHz, kHz above -- same convention
    // MeasuredDataRowView.formattedAnomalyFrequency already uses for
    // Anomaly Candidate rows.
    private func formattedHoverFrequency(_ hz: Double) -> String {
        hz >= 1000 ? String(format: "%.2f kHz", hz / 1000) : String(format: "%.0f Hz", hz)
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

    // Empty-state affordance (ticket #22): with no data yet (stopped at
    // launch, or after Stop) the graph is otherwise an inert black void. A
    // quiet centered prompt invites the tech to act, over a thin static
    // strip of the waterfall's own color ramp so the app's identity shows
    // before data flows. Keyed on latestMagnitudes.isEmpty, so it's gone the
    // instant the first frame arrives and never overlaps live data; a frozen
    // display keeps its last frame (non-empty) so freezing never shows it.
    // Non-interactive, so it doesn't block the toggles or hover.
    private var emptyStateOverlay: some View {
        VStack(spacing: 14) {
            spectralStrip
                .frame(width: 220, height: 6)
                .clipShape(Capsule())
                .opacity(0.85)
            // While a Start is in progress (between the press and the first
            // hop -- possibly a slow coreaudiod start) show "Starting…" so the
            // empty state reads as working, not idle. Otherwise the usual
            // affordance, naming both ways to start: the Start control and the
            // spacebar shortcut (KeyboardShortcuts: space = Start/Stop), so the
            // shortcut is discoverable from the empty state itself.
            Group {
                if pipeline.isCaptureStarting {
                    Text("Starting…")
                } else {
                    HStack(spacing: 6) {
                        Text("Press Start or")
                        keycap("Space")
                        Text("to measure")
                    }
                }
            }
            .font(.system(size: Typography.controlSize, weight: .medium))
            .foregroundStyle(theme.textDim)
        }
        .allowsHitTesting(false)
    }

    // A small keyboard-hint cap, styled like the Controls row's console
    // plates (raised fill, hairline border) so it reads as a key, not a
    // button.
    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: Typography.controlSize - 1, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )
            )
    }

    // The waterfall's own magnitude ramp (WaterfallColorMap, the single
    // source of truth the Metal shader mirrors) rendered as a horizontal
    // gradient -- theme-aware, matching whichever ramp the live waterfall
    // would use.
    private var spectralStrip: some View {
        let stops = theme.mode == .light ? WaterfallColorMap.light : WaterfallColorMap.dark
        return LinearGradient(
            stops: stops.map { stop in
                Gradient.Stop(
                    color: Color(.sRGB, red: Double(stop.rgb.x), green: Double(stop.rgb.y), blue: Double(stop.rgb.z)),
                    location: CGFloat(stop.position)
                )
            },
            startPoint: .leading,
            endPoint: .trailing
        )
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
    // here. Levels mirror RTABinning/MagnitudeScaling's -120…0dB normalized
    // range (the same range each bar's height is computed from), so a bar
    // reaching the "-20 dB" gridline really is -20dB. Same top/bottom inset
    // approach as timeAxisLabels, for the same reason (avoid clipping the
    // top label and colliding with the frequency axis's bottom row).
    private static let dbGridlineLevels: [Float] = [0, -20, -40, -60, -80, -100, -120]

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
