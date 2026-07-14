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

    var body: some View {
        Canvas { context, size in
            let barsPerOctave = pipeline.bandingResolution.rawValue
            // Reads AudioPipelineViewModel's cached per-hop bars (perf fix)
            // rather than recomputing RTABinning.bars itself -- apply(_:)
            // already scans the same magnitudes for peak tracking every hop,
            // and bandingResolution's didSet keeps this in sync immediately
            // on a resolution change, so it's never stale here.
            let bars = pipeline.latestRTABars
            guard !bars.isEmpty else { return }

            // Positioned by each bar's actual (1kHz-anchored) frequency
            // range via FrequencyAxis, not by array index (bug fix -- user
            // report: "the rta bars and x axis scale are clearly off (even
            // at 1k)") -- index no longer maps 1:1 to log-frequency
            // position now that bar count comes from independently
            // rounding the octave steps up/down from 1kHz, so evenly
            // dividing the canvas by index drifted out of sync with the
            // x-axis labels, which position by true frequency.
            let edges = RTABinning.bandEdges(barsPerOctave: barsPerOctave)
            let gap: CGFloat = 2

            for (index, normalized) in bars.enumerated() {
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
    }
}

#Preview {
    RTAView()
        .environment(\.theme, Theme(mode: .dark))
        .environment(AudioPipelineViewModel())
        .frame(width: 900, height: 340)
        .background(Color.black)
}
