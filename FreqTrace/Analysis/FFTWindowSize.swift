//
//  FFTWindowSize.swift
//  FreqTrace
//
//  Selectable FFT window size (user request: "make the FFT size
//  selectable" -- follow-up to widening the fixed default 4096->8192 to
//  fix low-frequency RTA bars near 40Hz all reading the same bin). Same
//  shape as RTABandingResolution (RTA/RTABandingResolution.swift):
//  CaseIterable/Identifiable over the raw value real techs would
//  recognize, not an opaque index. Larger windows mean finer frequency
//  resolution (narrower bins) at the cost of coarser time resolution
//  (longer hop, laggier updates) -- a tradeoff a tech might want to dial
//  differently per situation (finer resolution hunting a low-frequency
//  ring vs. faster response for fast-moving material), the same way
//  RTABandingResolution and Time Averaging are already selectable rather
//  than fixed.
//

import Foundation

// Bug fix (user report: "the highest value just freeze" -- diagnosis showed
// it wasn't actually specific to the highest value; a synthetic pipeline
// harness reproduced hangs/erratic hop delivery across most sizes). This
// module defaults new types to @MainActor isolation, but AnalysisConfig.
// default below calls FFTWindowSize.default.config(sampleRate:) from a
// nonisolated context -- without opting out here the same way
// AnalysisConfig itself already does ("so it can be constructed/read from
// AudioAnalysisPipeline's background actor and FrequencyTracker without
// hopping to the main actor"), that was a real actor-isolation violation,
// silently downgraded to a warning today ("this is an error in the Swift 6
// language mode") rather than a hard compile error -- exactly the kind of
// undefined cross-actor access that produces intermittent hangs.
nonisolated enum FFTWindowSize: Int, CaseIterable, Identifiable {
    case n1024 = 1024
    case n2048 = 2048
    case n4096 = 4096
    case n8192 = 8192
    case n16384 = 16384

    var id: Int { rawValue }
    var windowSize: Int { rawValue }
    /// 50% overlap at every size, matching AnalysisConfig's own convention.
    var hopSize: Int { rawValue / 2 }
    var label: String { String(rawValue) }

    static let `default`: FFTWindowSize = .n8192

    func config(sampleRate: Double) -> AnalysisConfig {
        AnalysisConfig(sampleRate: sampleRate, windowSize: windowSize, hopSize: hopSize)
    }
}
