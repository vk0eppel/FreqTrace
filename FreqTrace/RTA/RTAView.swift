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

    var body: some View {
        TimelineView(.animation) { timeline in
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
                let edges = RTABinning.bandEdges(barsPerOctave: barsPerOctave)
                let gap: CGFloat = 2

                for (index, normalized) in displayedBars.enumerated() {
                    guard index < edges.count else { break }
                    let edge = edges[index]
                    let xStart = CGFloat(FrequencyAxis.normalizedPosition(forHz: edge.lowerHz)) * size.width
                    let xEnd = CGFloat(FrequencyAxis.normalizedPosition(forHz: edge.upperHz)) * size.width
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
            .onChange(of: timeline.date, initial: true) { _, newDate in
                advanceSmoothing(to: newDate)
            }
        }
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

#Preview {
    RTAView()
        .environment(\.theme, Theme(mode: .dark))
        .environment(AudioPipelineViewModel())
        .frame(width: 900, height: 340)
        .background(Color.black)
}
