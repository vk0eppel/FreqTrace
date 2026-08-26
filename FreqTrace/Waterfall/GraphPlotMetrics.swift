//
//  GraphPlotMetrics.swift
//  FreqTrace
//
//  The shared vertical mapping for the graph zone's plots (#45). The
//  waterfall time axis, the RTA dB axis, the RTA bars, the combined-view
//  overlay curve, and the peak crosshair all map a normalized [0,1] level
//  (loud = 1) into the same inset band [topInset, height - bottomInset]. That
//  single mapping is what keeps the RTA reading at the *exact same vertical
//  position* whether it's drawn as standalone bars or as the overlay curve
//  (user report: the RTA "moved up and down" when toggling the waterfall,
//  because the bars used full canvas height while the curve/dB-axis were
//  inset) -- and it lines every one of them up with the dB gridlines.
//
//  The insets keep the top-most / bottom-most axis-label pills from clipping
//  against the view's own .clipped() edge and keep the bottom row clear of
//  the frequency-axis labels; bottomInset is larger than topInset for the
//  latter.
//
//  Pure math, nonisolated per the module convention -- read from RTAView's
//  Canvas, from WaterfallZoneView, and from non-main paths alike.
//

import CoreGraphics

nonisolated enum GraphPlotMetrics {
    static let topInset: CGFloat = 12
    static let bottomInset: CGFloat = 28

    /// The drawable band height once the top/bottom insets are removed.
    static func usableHeight(_ height: CGFloat) -> CGFloat {
        max(0, height - topInset - bottomInset)
    }

    /// Normalized [0,1] level (loud = 1) -> y within a plot of `height`, so
    /// 1 lands on `topInset` (the 0 dB gridline) and 0 on `height -
    /// bottomInset` (the -120 dB gridline / silence floor).
    static func y(forNormalized normalized: Float, height: CGFloat) -> CGFloat {
        let clamped = min(max(CGFloat(normalized), 0), 1)
        return topInset + usableHeight(height) * (1 - clamped)
    }
}
