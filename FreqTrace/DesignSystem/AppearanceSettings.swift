//
//  AppearanceSettings.swift
//  FreqTrace
//
//  Owns the manual Appearance Mode toggle (ticket #10, ADR 0005): a plain
//  @Observable holder, separate from AudioPipelineViewModel -- this is UI
//  chrome state, not audio pipeline state. AppShellView derives the
//  injected Theme from this; ControlsRowView's Appearance control writes
//  to it directly.
//

import Observation

@MainActor
@Observable
final class AppearanceSettings {
    var mode: AppearanceMode = .default
}
