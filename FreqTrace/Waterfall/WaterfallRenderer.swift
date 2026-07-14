//
//  WaterfallRenderer.swift
//  FreqTrace
//
//  MTKViewDelegate driving the scrolling spectrogram (ticket #8, ADR 0004).
//  Owns the GPU texture (one row per FFT hop, circular buffer via
//  WaterfallHistoryBuffer's row bookkeeping) and issues the draw call each
//  frame using Waterfall.metal. Not unit-testable -- the pure logic it
//  builds on (FrequencyAxis, WaterfallColorMap, MagnitudeScaling,
//  WaterfallHistoryBuffer) is tested in isolation; this class is verified
//  visually (see the ticket's implementation notes for how).
//
//  New magnitude frames arrive via pushMagnitudes(_:), called from the main
//  actor (MetalWaterfallView.updateNSView, driven by AudioPipelineViewModel).
//  draw(in:) is called by MTKView's internal render loop, which is not
//  guaranteed to be the main thread -- pendingMagnitudes is guarded by a
//  lock rather than assumed to be main-actor-isolated, matching the
//  producer/consumer pattern SignalGeneratorRenderState (ticket #9) uses
//  for the same kind of cross-thread real-time handoff.
//

import MetalKit
import os

private struct WaterfallUniforms {
    var scrollOffset: Float
    var minHz: Float
    var maxHz: Float
    var binResolutionHz: Float
    var columnCount: Float
    /// Ticket #10: 0 = Dark ramp, 1 = Light ramp -- matches
    /// Waterfall.metal's `waterfallColor` branch.
    var isLightMode: Float
}

final class WaterfallRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let texture: MTLTexture
    private let config: AnalysisConfig

    private let lock = OSAllocatedUnfairLock<(magnitudes: [Float], fullScalePower: Float)?>(initialState: nil)
    private var historyBuffer: WaterfallHistoryBuffer
    /// CPU-side mirror of the GPU texture rows (hover tooltip feature): the
    /// GPU texture itself can't cheaply be read back per-pixel from the
    /// hover gesture's thread, so writeRow also stores its already-computed
    /// `normalized` array here, under the same kind of cross-thread lock
    /// pendingMagnitudes uses -- writes happen from draw(in:)'s thread,
    /// reads happen from magnitudeDb(secondsAgo:hz:), called from the main
    /// actor's hover handling.
    private let historyLock: OSAllocatedUnfairLock<(store: WaterfallHistoryStore, writeIndex: Int)>
    private let historyRowCount: Int
    private let historyDurationSeconds: Double
    /// Ticket #10: written from the main actor (MetalWaterfallView.
    /// updateNSView), read from draw(in:) (not guaranteed main thread) --
    /// an OSAllocatedUnfairLock-guarded flag, same cross-thread handoff
    /// pattern as pendingMagnitudes.
    private let appearanceModeLock = OSAllocatedUnfairLock<AppearanceMode>(initialState: .default)

    init?(device: MTLDevice, config: AnalysisConfig) {
        guard let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "waterfall_vertex"),
              let fragmentFunction = library.makeFunction(name: "waterfall_fragment") else {
            return nil
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        let historyBuffer = WaterfallHistoryBuffer(config: config)
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: historyBuffer.columnCount,
            height: historyBuffer.rowCount,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]
        textureDescriptor.storageMode = .managed

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor),
              let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.texture = texture
        self.config = config
        self.historyBuffer = historyBuffer
        self.historyRowCount = historyBuffer.rowCount
        self.historyDurationSeconds = historyBuffer.historyDurationSeconds
        self.historyLock = OSAllocatedUnfairLock(initialState: (
            store: WaterfallHistoryStore(rowCount: historyBuffer.rowCount, columnCount: historyBuffer.columnCount),
            writeIndex: 0
        ))
    }

    /// Real-time-safe-ish (a lock, not lock-free, but the critical section
    /// is a single pointer swap): called from the main actor whenever the
    /// pipeline publishes a new spectrum frame. `fullScalePower` travels
    /// alongside its magnitudes (bug fix) -- raw vDSP power isn't already
    /// on a [0,1]/dBFS scale, so writeRow must divide by this reference
    /// before applying MagnitudeScaling's dB floor/ceiling, the same
    /// self-calibration technique already used for SPL.
    func pushMagnitudes(_ magnitudes: [Float], fullScalePower: Float) {
        lock.withLock { $0 = (magnitudes, fullScalePower) }
    }

    /// Ticket #10: called whenever AppearanceSettings.mode changes.
    func setAppearanceMode(_ mode: AppearanceMode) {
        appearanceModeLock.withLock { $0 = mode }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        if let pushed = lock.withLock({ pending in
            defer { pending = nil }
            return pending
        }) {
            writeRow(pushed.magnitudes, fullScalePower: pushed.fullScalePower)
        }

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let isLightMode = appearanceModeLock.withLock { $0 == .light }
        var uniforms = WaterfallUniforms(
            scrollOffset: historyBuffer.scrollOffset,
            minHz: Float(FrequencyAxis.minHz),
            maxHz: Float(FrequencyAxis.maxHz),
            binResolutionHz: Float(config.binResolutionHz),
            columnCount: Float(historyBuffer.columnCount),
            isLightMode: isLightMode ? 1 : 0
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WaterfallUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func writeRow(_ magnitudes: [Float], fullScalePower: Float) {
        let row = historyBuffer.nextRowIndex()
        let safeFullScalePower = max(fullScalePower, .leastNormalMagnitude)
        var normalized = magnitudes.map { MagnitudeScaling.normalized(power: $0 / safeFullScalePower) }

        // Defensive: keep the buffer we hand to Metal exactly columnCount
        // long so region width / bytesPerRow / buffer length all agree,
        // even if a caller ever supplies a differently-sized spectrum.
        if normalized.count < historyBuffer.columnCount {
            normalized.append(contentsOf: repeatElement(0, count: historyBuffer.columnCount - normalized.count))
        } else if normalized.count > historyBuffer.columnCount {
            normalized.removeLast(normalized.count - historyBuffer.columnCount)
        }

        let region = MTLRegionMake2D(0, row, historyBuffer.columnCount, 1)
        normalized.withUnsafeBytes { pointer in
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: pointer.baseAddress!,
                bytesPerRow: historyBuffer.columnCount * MemoryLayout<Float>.stride
            )
        }

        let writeIndex = historyBuffer.writeIndex
        historyLock.withLock { state in
            state.store.write(row: row, values: normalized)
            state.writeIndex = writeIndex
        }
    }

    /// Hover tooltip query (main actor, called from WaterfallZoneView's
    /// hover handling -- a different thread than writeRow's, hence the
    /// lock): the dB level at `hz` in the frame from `secondsAgo` seconds
    /// ago, or nil if that row hasn't been written yet. `hz` is converted
    /// to a column using the same linear bin-Hz formula RTABinning uses
    /// (config.sampleRate/windowSize) -- texture columns are raw FFT bins,
    /// not log-frequency-spaced; the log remap only happens per-pixel in
    /// the fragment shader.
    func magnitudeDb(secondsAgo: Double, hz: Double) -> Float? {
        let binHz = config.sampleRate / Double(config.windowSize)
        let column = min(max(Int((hz / binHz).rounded()), 0), historyBuffer.columnCount - 1)
        return historyLock.withLock { state in
            let row = WaterfallHistoryBuffer.rowIndex(
                secondsAgo: secondsAgo,
                writeIndex: state.writeIndex,
                rowCount: historyRowCount,
                historyDurationSeconds: historyDurationSeconds
            )
            guard let normalized = state.store.value(row: row, column: column) else { return nil }
            return MagnitudeScaling.dB(fromNormalized: normalized)
        }
    }
}
