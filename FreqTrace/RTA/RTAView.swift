//
//  RTAView.swift
//  FreqTrace
//
//  Renders the live spectrum as bars (ticket #11, CLAUDE.md "RTA"): a
//  SwiftUI Canvas over RTABinning's normalized per-bar heights. Unlike the
//  waterfall's scrolling history, this is a single live frame -- no
//  history buffer, no Metal texture, just redrawn from `magnitudes` as it
//  changes. Not unit-tested (pure rendering glue over the already-tested
//  RTABinning), consistent with MetalWaterfallView.
//
//  Bar color: a single accent color (not the waterfall's magnitude-mapped
//  color ramp) -- standard RTA convention, and simpler to read as "one
//  live shape" at a glance versus the waterfall's per-pixel color coding,
//  which exists there to encode history that an RTA doesn't have.
//
//  Peak markers (ticket #12, CONTEXT.md "Peak"): a thin line per bar at
//  AudioPipelineViewModel.peakForRTABar(_:)'s held height, drawn above the
//  live bar. Peaks are updated in AudioPipelineViewModel.apply(_:), every
//  hop regardless of whether RTA is the visible view (found by code
//  review: updating them here instead, only reachable while this view is
//  mounted, silently paused peak accumulation whenever the waterfall was
//  shown instead -- Peak hold is supposed to be indefinite). RTAView only
//  reads the already-tracked peaks, never mutates view-model state itself.
//

import SwiftUI

struct RTAView: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPipelineViewModel.self) private var pipeline
    /// Smoothed bar heights, eased continuously toward
    /// `pipeline.latestRTABars` rather than snapping the instant a new hop
    /// lands (stutter fix, part 2 of 2 -- part 1 is FFTWindowSize.hopSize's
    /// cap, the actual root cause: the data rate itself degraded to ~6
    /// spectra/second at large FFT windows, which no display smoothing can
    /// hide). With the data arriving at a healthy >= ~23Hz at every window
    /// size, this layer's remaining job is small: TimelineView(.animation)
    /// redraws at display rate instead of only when a hop lands, and
    /// advanceSmoothing gives bars fast-meter-style ballistics that absorb
    /// the measured +-50ms burstiness of MainActor hop delivery (the same
    /// irregular-delivery pattern diagnosed on the waterfall -- see
    /// WaterfallRenderer.displayedRowPosition).
    @State private var displayedBars: [Float] = []
    @State private var lastTickDate: Date?

    /// True once the eased bars have fully caught up with the latest hop's
    /// targets -- used to pause the TimelineView below (perf fix, user
    /// report: "the RTA seems to consume more CPU"): an .animation
    /// schedule otherwise ticks at full display rate (120Hz on ProMotion)
    /// forever, re-rendering the Canvas even when every bar already sits
    /// exactly on target (frozen display, capture stopped, or simply the
    /// ~5 display frames between hops after ballistics converge). Reading
    /// pipeline.latestRTABars here means Observation re-evaluates body --
    /// and thus un-pauses -- the moment the next hop lands.
    private var isConverged: Bool {
        displayedBars == pipeline.latestRTABars
    }

    var body: some View {
        // minimumInterval 1/60: the ballistics span ~100ms (see
        // advanceSmoothing), so 60Hz is comfortably smooth for meter bars
        // -- ticking at a ProMotion display's native 120Hz just doubled
        // the redraw work for motion no faster than a real meter's.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: isConverged)) { timeline in
            Canvas { context, size in
                let barsPerOctave = pipeline.bandingResolution.rawValue
                guard !displayedBars.isEmpty else { return }

                // Positioned by each bar's actual (1kHz-anchored) frequency
                // range via FrequencyAxis, not by array index (bug fix --
                // user report: "the rta bars and x axis scale are clearly
                // off (even at 1k)") -- index no longer maps 1:1 to
                // log-frequency position now that bar count comes from
                // independently rounding the octave steps up/down from
                // 1kHz, so evenly dividing the canvas by index drifted out
                // of sync with the x-axis labels, which position by true
                // frequency.
                let positions = RTABarPositionCache.positions(barsPerOctave: barsPerOctave, config: pipeline.config)

                if barsPerOctave <= 0 {
                    // None/narrowband: ~one bar per FFT bin (thousands).
                    // Drawing that many individual rounded-rect fills +
                    // per-bar peak strokes every frame pegged the CPU at
                    // ~150% (user report). Collapse it to a single filled
                    // spectrum envelope + one peak polyline -- two draw calls
                    // instead of thousands, and the continuous curve real
                    // narrowband analyzers draw anyway.
                    drawNarrowband(context: context, size: size, positions: positions)
                } else {
                    drawBars(context: context, size: size, positions: positions)
                }
            }
            .onChange(of: timeline.date, initial: true) { _, newDate in
                advanceSmoothing(to: newDate)
            }
        }
    }

    /// Octave/fractional-octave rendering: discrete rounded-rect bars with a
    /// per-bar peak cap. Bar counts here are modest (<=~180 at 1/48 octave),
    /// so per-bar draw calls are fine.
    private func drawBars(context: GraphicsContext, size: CGSize, positions: [RTABarPositionCache.BarPosition]) {
        let gap: CGFloat = 2
        for (index, normalized) in displayedBars.enumerated() {
            guard index < positions.count else { break }
            let position = positions[index]
            let xStart = position.start * size.width
            let xEnd = position.end * size.width
            let barWidth = max(1, xEnd - xStart - gap)
            let barHeight = size.height * CGFloat(normalized)
            let rect = CGRect(x: xStart, y: size.height - barHeight, width: barWidth, height: barHeight)
            let path = Path(roundedRect: rect, cornerSize: CGSize(width: 2, height: 2))
            context.fill(path, with: .color(theme.accent))

            if let peak = pipeline.peakForRTABar(index) {
                let peakY = size.height - size.height * CGFloat(peak)
                var peakLine = Path()
                peakLine.move(to: CGPoint(x: xStart, y: peakY))
                peakLine.addLine(to: CGPoint(x: xStart + barWidth, y: peakY))
                context.stroke(peakLine, with: .color(theme.text), lineWidth: 2)
            }
        }
    }

    /// None/narrowband rendering: one bar per FFT bin (thousands), drawn as a
    /// single filled envelope through each bar's center plus one stroked
    /// held-peak polyline -- two draw submissions total, versus thousands of
    /// per-bar fills/strokes that saturated the CPU. The peak line breaks
    /// into separate subpaths across any bars that have no recorded peak yet.
    private func drawNarrowband(context: GraphicsContext, size: CGSize, positions: [RTABarPositionCache.BarPosition]) {
        let count = min(displayedBars.count, positions.count)
        guard count > 0 else { return }
        func centerX(_ i: Int) -> CGFloat { CGFloat((positions[i].start + positions[i].end) / 2) * size.width }
        func topY(_ v: Float) -> CGFloat { size.height - size.height * CGFloat(v) }

        var envelope = Path()
        envelope.move(to: CGPoint(x: centerX(0), y: size.height))
        for i in 0..<count {
            envelope.addLine(to: CGPoint(x: centerX(i), y: topY(displayedBars[i])))
        }
        envelope.addLine(to: CGPoint(x: centerX(count - 1), y: size.height))
        envelope.closeSubpath()
        context.fill(envelope, with: .color(theme.accent))

        var peakPath = Path()
        var penDown = false
        for i in 0..<count {
            if let peak = pipeline.peakForRTABar(i) {
                let point = CGPoint(x: centerX(i), y: topY(peak))
                if penDown { peakPath.addLine(to: point) } else { peakPath.move(to: point); penDown = true }
            } else {
                penDown = false
            }
        }
        context.stroke(peakPath, with: .color(theme.text), lineWidth: 1)
    }

    // Reads AudioPipelineViewModel's cached per-hop bars (perf fix) rather
    // than recomputing RTABinning.bars itself -- apply(_:) already scans
    // the same magnitudes for peak tracking every hop, and
    // bandingResolution's didSet keeps this in sync immediately on a
    // resolution change, so it's never stale here.
    private func advanceSmoothing(to now: Date) {
        let targets = pipeline.latestRTABars

        // A bar-count change (banding resolution switch) means index no
        // longer refers to the same frequency range -- snap straight to
        // the new targets rather than interpolating between two
        // differently-shaped arrays.
        guard displayedBars.count == targets.count else {
            displayedBars = targets
            lastTickDate = now
            return
        }

        // Already on target: write no state at all (a @State write, even
        // of an equal value, invalidates the view and re-renders the
        // Canvas). Together with `isConverged` pausing the TimelineView,
        // this is what actually stops the idle-redraw treadmill.
        guard displayedBars != targets else { return }

        guard let lastTickDate else {
            self.lastTickDate = now
            return
        }
        let dt = now.timeIntervalSince(lastTickDate)
        self.lastTickDate = now
        guard dt > 0 else { return }

        // Full 0...1 swing in ~100ms -- comparable to a real meter's Fast
        // ballistics, so the RTA reads as live rather than damped, while
        // still spanning ~2 hop intervals (~43ms each, every FFT size --
        // FFTWindowSize.hopSize's cap) so the measured +-50ms burstiness
        // of hop delivery is absorbed as continuous motion instead of
        // rendered as stutter.
        let maxDeltaPerSecond: Float = 10
        let maxStep = Float(dt) * maxDeltaPerSecond
        for index in displayedBars.indices {
            let diff = targets[index] - displayedBars[index]
            if abs(diff) <= maxStep {
                displayedBars[index] = targets[index]
            } else {
                displayedBars[index] += diff > 0 ? maxStep : -maxStep
            }
        }
    }
}

/// Memoizes each banding resolution's normalized bar x-positions (perf
/// fix, same user report as `isConverged`): RTABinning.bandEdges plus two
/// FrequencyAxis.normalizedPosition log10 calls per bar were recomputed
/// inside the Canvas on every redraw, though they depend only on
/// barsPerOctave -- at 1/48 octave that was ~1000 log evaluations per
/// frame. At most a handful of resolutions ever get cached, so the cache
/// is never evicted.
@MainActor
private enum RTABarPositionCache {
    struct BarPosition {
        let start: CGFloat
        let end: CGFloat
    }

    // Keyed by config too, not just barsPerOctave: the None (raw per-bin)
    // case's positions depend on the FFT bin grid, so they'd go stale across
    // an FFT-size change if cached by resolution alone. Octave resolutions
    // ignore config in bandEdges, so their entry is still effectively one per
    // resolution.
    private struct Key: Hashable {
        let barsPerOctave: Int
        let windowSize: Int
        let sampleRate: Double
    }
    private static var cache: [Key: [BarPosition]] = [:]

    static func positions(barsPerOctave: Int, config: AnalysisConfig) -> [BarPosition] {
        let key = Key(barsPerOctave: barsPerOctave, windowSize: config.windowSize, sampleRate: config.sampleRate)
        if let cached = cache[key] { return cached }
        let positions = RTABinning.bandEdges(barsPerOctave: barsPerOctave, config: config).map { edge in
            BarPosition(
                start: CGFloat(FrequencyAxis.normalizedPosition(forHz: edge.lowerHz)),
                end: CGFloat(FrequencyAxis.normalizedPosition(forHz: edge.upperHz))
            )
        }
        cache[key] = positions
        return positions
    }
}

#Preview {
    RTAView()
        .environment(\.theme, Theme(mode: .dark))
        .environment(AudioPipelineViewModel())
        .frame(width: 900, height: 340)
        .background(Color.black)
}
