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

/// MTKView that pauses its render loop while its window is fully occluded
/// (bug fix -- user report: "app freezes after sample rate change to 44.1",
/// which turned out to be unrelated to sample rate: diagnosed via `sample`
/// of the "frozen" process, whose main thread was spending ~40% of its time
/// parked in CAMetalLayer nextDrawable 1s-timeout semaphore waits with the
/// GPU idle). When another window fully covers this one (the user was in
/// Audio MIDI Setup), the compositor stops consuming presented drawables,
/// the layer's drawable pool never recycles, and a continuously-drawing
/// MTKView (isPaused = false) then blocks the main thread ~1s per draw call
/// waiting for a drawable that can only free up once the window is visible
/// again -- indistinguishable from a hard freeze, recovering only after an
/// event backlog drains. Pausing on occlusion sidesteps the whole class:
/// no drawables are requested while nothing would display them anyway.
/// Un-pausing needs no catch-up logic -- WaterfallRenderer.draw always
/// renders current state, and the scroll position is wall-clock-derived.
final class OcclusionPausingMTKView: MTKView {
    /// nonisolated(unsafe): deinit is nonisolated in Swift 6 and may not
    /// touch main-actor state, but this token is only ever written on the
    /// main actor (viewDidMoveToWindow) and read once more in deinit,
    /// after which nothing can race it -- removing an observer token from
    /// any thread is documented-safe for NotificationCenter.
    private nonisolated(unsafe) var occlusionObserver: (any NSObjectProtocol)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        guard let window else { return }
        updatePauseState(for: window)
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue (specified above), so hopping to
            // the main actor is a formality the compiler can't see through.
            // The notification itself is deliberately not touched: passing
            // a non-Sendable Notification into the isolated closure is a
            // Swift 6 error, and `self.window` is the same window anyway
            // (the observer is registered filtered to it, and re-registered
            // whenever the view changes windows).
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                self.updatePauseState(for: window)
            }
        }
    }

    private func updatePauseState(for window: NSWindow) {
        isPaused = !window.occlusionState.contains(.visible)
    }

    deinit {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }
}

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
        let view = OcclusionPausingMTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = renderer
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        // Bumped from 30 (ticket #15, fluid-scroll fix): fractionalRow
        // interpolation (WaterfallRenderer.draw) only looks as smooth as it
        // has draw calls to interpolate across within one hop period -- at
        // 30fps and an ~85ms hop, that was only ~2-3 samples, still visibly
        // steppy. 60fps roughly doubles that headroom.
        view.preferredFramesPerSecond = 60
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
