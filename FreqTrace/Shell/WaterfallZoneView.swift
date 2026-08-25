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
            peakCrosshair
            graphControlsCluster
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
            // Establish an @Observable dependency on the per-hop stream so the
            // tooltip re-renders as data scrolls under a *stationary* cursor
            // (user report: freq/level didn't update unless the mouse moved).
            // magnitudeDb() reads the renderer's own CPU mirror, which isn't
            // Observable, so without this touch SwiftUI never re-evaluates the
            // overlay between mouse moves. The RTA branch below already gets
            // this for free by reading pipeline.latestRTABars.
            _ = pipeline.latestMagnitudes.count
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

    // Peak crosshair (ticket #28): an always-on marker at the currently-
    // tracked peak frequency, so the eye can find the tracked bin on the
    // graph itself, not just read it in the numeric row. A vertical line at
    // the tracked frequency in both modes (the shared log-frequency x-axis);
    // in RTA, additionally a horizontal line at the tracked level, since
    // RTA's Y axis is dB -- the waterfall's Y is time, so there's no level
    // axis to mark there (vertical-only). Reads the same freezeGate-gated
    // pipeline.trackedFrequencyHz/LevelDb the hero numeric reads, so it
    // freezes with the display, hides on Stop/empty, and can never disagree
    // with the number (same value, no independent smoothing). Line color is
    // theme.text at a higher opacity than the axis gridlines (0.18) --
    // brighter than the grid in Dark, darker in Light (user request) -- so
    // it reads as a distinct marker without a new hue competing with the
    // color ramp or the anomaly-candidate emphasis. Label reuses the hover
    // tooltip's formatter. Non-interactive, so it never blocks the toggles.
    private var peakCrosshair: some View {
        GeometryReader { proxy in
            if pipeline.hasWaterfallData, let hz = pipeline.trackedFrequencyHz {
                let topInset: CGFloat = 12
                let bottomInset: CGFloat = 28
                let usableHeight = proxy.size.height - topInset - bottomInset
                let x = proxy.size.width * FrequencyAxis.normalizedPosition(forHz: hz)
                // Vertical frequency line (both modes), inset top/bottom to
                // match the axis label rows rather than running under them.
                Rectangle()
                    .fill(theme.text.opacity(0.55))
                    .frame(width: 1.5, height: max(usableHeight, 0))
                    .position(x: x, y: topInset + max(usableHeight, 0) / 2)
                // Horizontal level line (RTA only). Same -120…0dB normalized
                // mapping dbAxisLabels uses, so the line meets its own dB
                // gridline exactly. Dashed (vs. the solid vertical line) so it
                // doesn't read as another of RTA's solid white per-bar peak-
                // hold caps -- a dashed span is the conventional "reference
                // level" mark and stays legible even where it sits above/below
                // a bar top (the Tracked-Frequency level is a single loudest
                // bin, not the binned per-band bar, so the two legitimately
                // differ).
                if displayMode == .rta, usableHeight > 0,
                   let db = pipeline.trackedFrequencyLevelDb, db.isFinite {
                    let normalized = (Float(db) - MagnitudeScaling.floorDb)
                        / (MagnitudeScaling.ceilingDb - MagnitudeScaling.floorDb)
                    let clamped = min(max(normalized, 0), 1)
                    let y = topInset + usableHeight * CGFloat(1 - clamped)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                    .stroke(theme.text.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                // Hover-style label near the top of the line, clamped in-bounds.
                axisLabel(crosshairLabel(hz: hz, db: pipeline.trackedFrequencyLevelDb))
                    .position(
                        x: min(max(x, endpointLabelInset + 24), proxy.size.width - endpointLabelInset - 24),
                        y: topInset + 8
                    )
            }
        }
        .allowsHitTesting(false)
    }

    // Same content as the hover tooltip (hoverText), but fed the tracked
    // freq/level instead of the mouse position -- so the crosshair reads in
    // the same "2340 Hz  -18 dB" form the rest of the graph does.
    private func crosshairLabel(hz: Double, db: Double?) -> String {
        let freq = formattedHoverFrequency(hz)
        guard let db, db.isFinite else { return freq }
        return "\(freq)  \(Int(db.rounded())) dB"
    }

    // The graph zone's three display controls (ticket #30), consolidated
    // into one aligned top-right cluster: the Waterfall/RTA view toggle, the
    // banding-resolution picker, and the Octave/Decade frequency scale. They
    // were previously three separately-backgrounded pills stacked with
    // hardcoded per-control top offsets (10/50/86pt) and ragged left edges,
    // reading as three scattered objects; now one recessed panel, one
    // top-right anchor, consistent styling. All three affect both the
    // waterfall and RTA (view toggle switches which is shown; banding + scale
    // apply to both), so they belong together regardless of displayMode.
    // Compact form (user pick): the 7-way banding is a `1/12 ▾` dropdown
    // rather than 7 always-visible segments, matching the app's device/ISO
    // picker idiom and keeping the panel narrow over the waterfall; the two
    // 2-way toggles stay one-tap segments.
    private var graphControlsCluster: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 0) {
                        ForEach(GraphDisplayMode.allCases) { mode in
                            displayModeButton(mode)
                        }
                    }
                    bandingResolutionDropdown
                    HStack(spacing: 4) {
                        ForEach(FrequencyScale.allCases) { scale in
                            frequencyScaleButton(scale)
                        }
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.surfaceRaised.opacity(0.9))
                )
                .padding(10)
            }
            Spacer()
        }
    }

    // Banding-resolution picker as a dropdown (ticket #30 compact form) --
    // the same SwiftUI Menu idiom as the Input/Output Device and ISO-band
    // pickers, over RTABandingResolution.allCases, with a checkmark on the
    // active resolution. A leading "BANDS" caption names it (the two toggles
    // are self-labelling by their segment text; the dropdown value alone --
    // "1/12" -- isn't). Shared by RTA and the waterfall alike, same setting.
    private var bandingResolutionDropdown: some View {
        HStack(spacing: 6) {
            Text("BANDS")
                .font(.system(size: Typography.axisLabelSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.textDim)
            Menu {
                ForEach(RTABandingResolution.allCases) { resolution in
                    Button {
                        pipeline.bandingResolution = resolution
                    } label: {
                        if resolution == pipeline.bandingResolution {
                            Label(resolution.label, systemImage: "checkmark")
                        } else {
                            Text(resolution.label)
                        }
                    }
                }
            } label: {
                // Flat console pill (ticket #30 design pass), not the native
                // Menu bezel: the cluster's two toggles are flat accent-fill
                // segments, so a stock system pull-down beside them read as a
                // different control *material*. A recessed theme.surface pill
                // with a trailing chevron matches the segments' flatness while
                // still reading as "opens a list". .menuStyle(.button) +
                // .buttonStyle(.plain) render the custom label as-is (no
                // bezel); .menuIndicator(.hidden) drops Menu's own chevron so
                // only this trailing one shows, on the correct (right) side.
                HStack(spacing: 4) {
                    Text(pipeline.bandingResolution.label)
                        .font(.system(size: Typography.axisLabelSize, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.text)
                    Image(systemName: "chevron.down")
                        .font(.system(size: Typography.axisLabelSize - 2, weight: .semibold))
                        .foregroundStyle(theme.textDim)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.surface)
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func frequencyScaleButton(_ scale: FrequencyScale) -> some View {
        let isSelected = pipeline.frequencyScale == scale
        return Button {
            pipeline.frequencyScale = scale
        } label: {
            // Uppercased at the display site to match displayModeButton's
            // WATERFALL/RTA -- the two peer toggles sit adjacent in the #30
            // cluster, so their casing must agree (FrequencyScale.label stays
            // title-case for any other, non-toggle use).
            Text(scale.label.uppercased())
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
            // 10pt mono, matching frequencyScaleButton -- the whole cluster
            // speaks the graph's own axis-label type system (ticket #30
            // design pass), not a transplanted 12pt Controls-row fragment,
            // so it reads as one quiet element beside the frequency labels.
            Text(mode.rawValue.uppercased())
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

    // Empty-state affordance (ticket #22): with no data yet (stopped at
    // launch, or after Stop) the graph is otherwise an inert black void. A
    // quiet centered prompt invites the tech to act, over a thin static
    // strip of the waterfall's own color ramp so the app's identity shows
    // before data flows. Keyed on latestMagnitudes.isEmpty, so it's gone the
    // instant the first frame arrives and never overlaps live data; a frozen
    // display keeps its last frame (non-empty) so freezing never shows it.
    // Non-interactive, so it doesn't block the toggles or hover.
    private var emptyStateOverlay: some View {
        VStack(spacing: 22) {
            // The app's identity moment before data flows (design review). Was a
            // 220x6 hairline that read as an incidental loading bar; enlarged
            // into a real ramp swatch of the waterfall's own WaterfallColorMap
            // so the empty state carries the app's character instead of floating
            // in a void. A soft accent glow lifts it off the background.
            // Deliberately restrained -- no wordmark (the title bar already
            // names the app), no motion.
            spectralStrip
                .frame(width: 380, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: theme.accent.opacity(0.25), radius: 16, y: 0)
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
            .font(.system(size: Typography.controlSize + 2, weight: .medium))
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
            // Two line weights (issue #25): major reference lines (octave
            // centers, or a decade grid's 100/1k/10k) read boldest; the
            // decade scale's minor 2-9 lines recede. Gridlines/labels sit at
            // the true normalizedPosition -- no inset -- so they stay aligned
            // with the RTA bars, which position by the same mapping.
            ForEach(pipeline.frequencyScale.gridlines, id: \.hz) { line in
                let x = proxy.size.width * FrequencyAxis.normalizedPosition(forHz: line.hz)
                Rectangle()
                    .fill(theme.text.opacity(line.isMajor ? 0.18 : 0.08))
                    .frame(width: line.isMajor ? 1.5 : 1)
                    .position(x: x, y: proxy.size.height / 2)
                // The decade scale's extreme labels (20 at x~0, 20k at x~1)
                // would clip against this view's .clipped() edge -- same
                // symptom the time axis fixed. Nudge only the endpoint pills'
                // center inward (~half a pill width) so the number stays
                // readable, without moving the gridline (keeps bar alignment).
                axisLabel(line.label)
                    .position(x: min(max(x, endpointLabelInset), proxy.size.width - endpointLabelInset),
                              y: proxy.size.height - 12)
            }
        }
    }

    /// Horizontal half-pill margin used only to keep the first/last axis
    /// labels from clipping at the view edges (see frequencyAxisLabels).
    private let endpointLabelInset: CGFloat = 18

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
