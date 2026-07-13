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
            let bars = RTABinning.bars(magnitudes: pipeline.latestMagnitudes, config: pipeline.config)
            guard !bars.isEmpty else { return }

            let barCount = bars.count
            let gap: CGFloat = 2
            let barWidth = (size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)

            for (index, normalized) in bars.enumerated() {
                let barHeight = size.height * CGFloat(normalized)
                let x = CGFloat(index) * (barWidth + gap)
                let rect = CGRect(x: x, y: size.height - barHeight, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerSize: CGSize(width: 2, height: 2))
                context.fill(path, with: .color(theme.accent))

                if let peak = pipeline.peakForRTABar(index) {
                    let peakY = size.height - size.height * CGFloat(peak)
                    var peakLine = Path()
                    peakLine.move(to: CGPoint(x: x, y: peakY))
                    peakLine.addLine(to: CGPoint(x: x + barWidth, y: peakY))
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
