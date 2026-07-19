//
//  FreqTraceApp.swift
//  FreqTrace
//
//  Created by Victor Koeppel on 13/07/2026.
//

import SwiftUI

@main
struct FreqTraceApp: App {
    /// Owned here, not by AppShellView (moved when the Appearance selector
    /// left the Controls row for the View menu, ADR 0005 addendum): menu
    /// commands live on the Scene, outside the view tree, so the state
    /// they write must be owned at the App level and injected down.
    @State private var appearanceSettings = AppearanceSettings()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(appearanceSettings)
                .environment(\.theme, Theme(mode: .default))
        }
        .windowResizability(.contentMinSize)
        .commands {
            // View menu > Appearance (ADR 0005 addendum): still the manual,
            // venue-driven Dark/Light choice -- deliberately NOT tied to the
            // macOS system appearance, which tracks the user's global
            // preference/schedule rather than the lighting at the FOH
            // position. Demoted from the always-visible Controls row: this
            // is a set-once-per-venue setting, not a mid-show control, so
            // it doesn't earn permanent screen space.
            CommandGroup(after: .toolbar) {
                Divider()
                ForEach(AppearanceMode.allCases) { mode in
                    Toggle(mode.rawValue, isOn: Binding(
                        get: { appearanceSettings.mode == mode },
                        set: { isOn in if isOn { appearanceSettings.mode = mode } }
                    ))
                    .keyboardShortcut(mode == .dark ? "d" : "l", modifiers: [.command, .shift])
                }
            }
        }
    }
}
