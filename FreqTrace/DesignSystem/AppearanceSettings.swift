//
//  AppearanceSettings.swift
//  FreqTrace
//
//  Owns the manual Appearance Mode toggle (ticket #10, ADR 0005): a plain
//  @Observable holder, separate from AudioPipelineViewModel -- this is UI
//  chrome state, not audio pipeline state. AppShellView derives the
//  injected Theme from this; the View menu's Appearance items (FreqTraceApp)
//  write to it directly.
//
//  Persisted across launches (added when the selector moved from the
//  always-visible Controls row into the View menu): a visible toggle that
//  resets to Dark on relaunch is a shrug, but a menu setting that silently
//  forgets itself reads as broken.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppearanceSettings {
    private static let defaultsKey = "FreqTrace.appearanceMode"

    var mode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey)
        }
    }

    init() {
        mode = UserDefaults.standard.string(forKey: Self.defaultsKey)
            .flatMap { AppearanceMode(rawValue: $0) } ?? .default
    }
}
