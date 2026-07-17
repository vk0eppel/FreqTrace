//
//  AppShellView.swift
//  FreqTrace
//
//  The three-zone layout: Waterfall/RTA (dominant) -> Measured Data row ->
//  Controls row (two lines). See CLAUDE.md Frontend for the rationale
//  (everything visible on one screen, no tabs/panels/sheets).
//
//  Appearance Mode (ticket #10, ADR 0005): AppShellView is where
//  AppearanceSettings.mode actually becomes a Theme -- everything below
//  reads \.theme from the environment (see Theme.swift), so the toggle in
//  ControlsRowView only has to write one value here, not touch every view.
//

import AppKit
import SwiftUI

struct AppShellView: View {
    @State private var trackedFrequencyViewModel = AudioPipelineViewModel()
    @State private var appearanceSettings = AppearanceSettings()
    /// Bug fix history (user report: spacebar still typed into/erased the
    /// SPL Offset field): a hidden Button carrying .keyboardShortcut(.space)
    /// was tried first, with the button explicitly focused on appear to
    /// win the window's initial first-responder assignment away from
    /// NumericValueField -- didn't hold, since AppKit's own default-focus
    /// assignment on window-did-become-key can run after SwiftUI's
    /// onAppear and simply overwrite it back to the text field, a timing
    /// race rather than something this view controls. Replaced with an
    /// NSEvent monitor that checks the *actual* first responder at the
    /// moment the key is pressed -- that logic now lives in
    /// KeyboardShortcuts (shared with WaterfallZoneView's w/r shortcuts).
    @State private var spacebarMonitor: Any?
    /// Bug fix (user report: "if the user needs to enter a value somewhere,
    /// the focus get stuck there"): once a NumericValueField becomes first
    /// responder, standard AppKit behavior leaves it first responder
    /// indefinitely -- clicking a button still works (SwiftUI buttons
    /// handle their own click regardless of what else has focus), but
    /// clicking anywhere non-interactive (the waterfall, empty space) does
    /// nothing to release it, so spacebar kept being swallowed as a typed
    /// character long after the tech was done editing. This monitor
    /// resigns first responder on every mouse-down, *before* AppKit's own
    /// click handling runs (local monitors fire first, and the event is
    /// still returned unchanged so that handling proceeds normally
    /// afterward) -- a click landing back on the same field simply
    /// re-focuses it via AppKit's ordinary click-to-edit behavior, and a
    /// click anywhere else just leaves it resigned. No need to compute any
    /// field's frame or special-case which control was clicked.
    @State private var clickAwayMonitor: Any?

    private var theme: Theme { Theme(mode: appearanceSettings.mode) }

    var body: some View {
        VStack(spacing: 0) {
            WaterfallZoneView()
                .frame(minHeight: 340)
            MeasuredDataRowView()
            ControlsRowView()
        }
        .background(theme.bg)
        .frame(minWidth: LayoutMetrics.minWindowWidth, minHeight: LayoutMetrics.minWindowHeight)
        .environment(\.theme, theme)
        .environment(trackedFrequencyViewModel)
        .environment(appearanceSettings)
        .onAppear {
            installSpacebarShortcut()
            installClickAwayReset()
            resignInitialTextFieldFocus()
        }
        .onDisappear {
            removeSpacebarShortcut()
            removeClickAwayReset()
        }
    }

    // Bug fix (user report: "offset field is still focused at launch" --
    // the spacebar monitor above correctly leaves an *actively edited*
    // text field alone, but that's exactly the problem: AppKit hands the
    // SPL Offset field first-responder status by default on launch, before
    // the tech has clicked anything, so the monitor read that as "the tech
    // is editing" and let spacebar type into it instead of toggling
    // capture. Explicitly resigning first responder removes that unwanted
    // default focus outright, rather than trying to out-race it (see
    // spacebarMonitor's doc comment on why racing SwiftUI's own
    // @FocusState against it didn't work) -- dispatched to the next run
    // loop turn so it runs *after* AppKit's own initial-responder
    // assignment on window-did-become-key, which can happen after this
    // onAppear fires.
    private func resignInitialTextFieldFocus() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    private func installSpacebarShortcut() {
        guard spacebarMonitor == nil else { return }
        spacebarMonitor = KeyboardShortcuts.install([
            " ": { trackedFrequencyViewModel.toggleCapture() },
        ])
    }

    private func removeSpacebarShortcut() {
        KeyboardShortcuts.remove(spacebarMonitor)
        spacebarMonitor = nil
    }

    private func installClickAwayReset() {
        guard clickAwayMonitor == nil else { return }
        clickAwayMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if let window = NSApp.keyWindow, window.firstResponder is NSTextView {
                window.makeFirstResponder(nil)
            }
            return event
        }
    }

    private func removeClickAwayReset() {
        if let clickAwayMonitor {
            NSEvent.removeMonitor(clickAwayMonitor)
        }
        clickAwayMonitor = nil
    }
}

#Preview {
    AppShellView()
        .environment(\.theme, Theme(mode: .default))
}
