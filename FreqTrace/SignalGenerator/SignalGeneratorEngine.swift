//
//  SignalGeneratorEngine.swift
//  FreqTrace
//
//  AVAudioEngine glue for the Signal Generator (issue #9). Deliberately its
//  own AVAudioEngine instance, separate from the capture pipeline's (ADR
//  0002) -- this is playback/output, so it has no dependency on capture
//  being active and keeps running through a future Freeze/Stop on the
//  analysis side (see CONTEXT.md "Signal Generator On/Off").
//
//  Plays to the system default output device (AVAudioEngine's outputNode
//  targets the default device automatically on macOS when no output device
//  is explicitly assigned) -- an explicit Output Device selector is a
//  separate, later ticket per CLAUDE.md.
//
//  Not unit-tested directly -- it drives real audio hardware, which this
//  sandboxed environment cannot exercise. The pure math it wraps
//  (SignalGeneratorCore, SineOscillator, noise generators, Decibels) is
//  fully covered by SignalGeneratorCoreTests. Actually hearing the tone /
//  noise needs manual verification on a real Mac.
//

import AVFoundation
import Observation

@MainActor
@Observable
final class SignalGeneratorEngine {
    /// Signal Generator Level's editable range (CONTEXT.md: a numeric dB
    /// box, e.g. "-66dB"). -96dB is a conventional digital noise floor
    /// (16-bit dynamic range); 0dB is unity/full-scale, the loudest the
    /// generator can output. Not specified by issue #9 -- flagged in the
    /// report as a decision worth confirming for the domain docs.
    static let levelRangeDB: ClosedRange<Double> = -96...0
    static let defaultLevelDB: Double = -66

    var waveform: Waveform = .sine {
        didSet { syncRenderState() }
    }

    var levelDB: Double = SignalGeneratorEngine.defaultLevelDB {
        didSet { syncRenderState() }
    }

    private(set) var isOn: Bool = false
    private(set) var startupError: String?

    private let engine = AVAudioEngine()
    private let renderState: SignalGeneratorRenderState

    init() {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let effectiveSampleRate = sampleRate > 0 ? sampleRate : 48000
        renderState = SignalGeneratorRenderState(sampleRate: effectiveSampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: effectiveSampleRate, channels: 1)!
        let sourceNode = AVAudioSourceNode(format: format) { [renderState] isSilence, timestamp, frameCount, audioBufferList in
            renderState.render(
                isSilence: isSilence,
                timestamp: timestamp,
                frameCount: frameCount,
                audioBufferList: audioBufferList
            )
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.prepare()

        syncRenderState()
    }

    /// Explicit on/off per CONTEXT.md "Signal Generator On/Off" -- a real
    /// switch that actually starts/stops audible output, never a passive
    /// status indicator.
    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        guard on else {
            engine.stop()
            isOn = false
            return
        }
        do {
            try engine.start()
            isOn = true
            startupError = nil
        } catch {
            isOn = false
            startupError = error.localizedDescription
        }
    }

    private func syncRenderState() {
        let amplitude = Decibels.linearAmplitude(fromDecibels: levelDB)
        renderState.update(waveform: waveform, amplitude: amplitude)
    }
}
