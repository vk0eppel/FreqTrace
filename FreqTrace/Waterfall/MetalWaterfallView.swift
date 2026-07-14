//
//  MetalWaterfallView.swift
//  FreqTrace
//
//  NSViewRepresentable wrapping the MTKView that renders the waterfall
//  (ticket #8, ADR 0004). Renders continuously at a modest fixed frame
//  rate independent of the pipeline's own ~23Hz hop cadence -- new data
//  just gets picked up by whichever draw call comes next, decoupling
//  "how often SwiftUI observes a change" from "how smooth the animation
//  looks" (see the ticket's "sustains a smooth frame rate" criterion).
//

import MetalKit
import SwiftUI

struct MetalWaterfallView: NSViewRepresentable {
    /// Owned by WaterfallZoneView, not created here (hover tooltip feature):
    /// WaterfallZoneView needs the same renderer instance to query
    /// magnitudeDb(secondsAgo:hz:) for its hover overlay, which isn't
    /// possible if this view's own makeCoordinator() is the only thing
    /// that ever constructs one.
    let renderer: WaterfallRenderer
    let magnitudes: [Float]
    let config: AnalysisConfig
    /// Ticket #10: selects which of WaterfallColorMap's ramps the GPU
    /// fragment shader samples from.
    var appearanceMode: AppearanceMode = .default
    /// Bug fix: raw vDSP power isn't already on a [0,1]/dBFS scale --
    /// WaterfallRenderer.writeRow divides by this before applying
    /// MagnitudeScaling's dB floor/ceiling. See FrequencyTracker.fullScalePower.
    var fullScalePower: Float = 1
    /// Octave-banding resolution (user request: "the same for the
    /// waterfall" as RTA's selectable bars-per-octave) -- pre-bins
    /// `magnitudes` into piecewise-flat bands before writing to the GPU
    /// texture, reusing RTABinning's bar-centric logic (RTABinning.swift's
    /// `steppedMagnitudes`) rather than resampling to a smaller texture, so
    /// none of the Metal-side remap math or texture sizing needs to change.
    var bandingResolution: RTABandingResolution = .oneOverTwelve

    // No Coordinator: makeCoordinator() only ever runs once for the MTKView's
    // lifetime, so caching `renderer` there (as this used to) left the
    // MTKView's delegate permanently pinned to whichever WaterfallRenderer
    // existed on first appearance -- WaterfallZoneView rebuilds `renderer`
    // with a new GPU texture/columnCount/binResolutionHz whenever FFT window
    // size changes (its `.task(id: pipeline.config)`), but updateNSView kept
    // pushing freshly-sized magnitude frames into the *old*, differently-
    // sized renderer, which silently mis-mapped bins to the wrong frequency
    // (e.g. a real 1kHz peak reading as 2kHz/4kHz as window size grew -- bug
    // report: "1kHz sig gen reads 2k on waterfall at 8192, 4k at 16384").
    // Always reading `renderer` (this struct's own property, fresh on every
    // SwiftUI re-render) instead of `context.coordinator` keeps the MTKView
    // wired to whichever renderer WaterfallZoneView currently owns.
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = renderer
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.preferredFramesPerSecond = 30
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Re-assigned every update (cheap, idempotent when unchanged) so a
        // renderer swap takes effect immediately rather than waiting on
        // some other coordinator lifecycle event.
        nsView.delegate = renderer
        renderer.setAppearanceMode(appearanceMode)
        guard !magnitudes.isEmpty else { return }
        let stepped = RTABinning.steppedMagnitudes(magnitudes: magnitudes, config: config, barsPerOctave: bandingResolution.rawValue)
        renderer.pushMagnitudes(stepped, fullScalePower: fullScalePower)
    }
}
