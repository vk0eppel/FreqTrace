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

    func makeCoordinator() -> WaterfallRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return WaterfallRenderer(device: device, config: config)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.preferredFramesPerSecond = 30
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator?.setAppearanceMode(appearanceMode)
        guard !magnitudes.isEmpty else { return }
        let stepped = RTABinning.steppedMagnitudes(magnitudes: magnitudes, config: config, barsPerOctave: bandingResolution.rawValue)
        context.coordinator?.pushMagnitudes(stepped, fullScalePower: fullScalePower)
    }
}
