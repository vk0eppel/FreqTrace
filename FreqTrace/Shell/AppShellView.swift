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
//  reads \.theme from the environment (see Theme.swift), so the View
//  menu's Appearance items only have to write one value, not touch every
//  view. AppearanceSettings itself is owned by FreqTraceApp (menu commands
//  live on the Scene, outside this view tree) and arrives via environment.
//

import AppKit
import SwiftUI

struct AppShellView: View {
    @State private var trackedFrequencyViewModel = AudioPipelineViewModel()
    @Environment(AppearanceSettings.self) private var appearanceSettings
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
    /// One-shot observer that clears AppKit's unwanted launch focus on the
    /// SPL Offset field (see `installInitialFocusReset`). Held so it can be
    /// torn down if it never fires.
    @State private var didBecomeKeyObserver: Any?

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
        .onAppear {
            installSpacebarShortcut()
            installClickAwayReset()
            installInitialFocusReset()
        }
        .onDisappear {
            removeSpacebarShortcut()
            removeClickAwayReset()
            removeInitialFocusReset()
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
    // @FocusState against it didn't work).
    //
    // Priority-inversion fix (Thread Performance Checker: "User-interactive
    // thread waiting on a lower QoS Default thread"): the resign used to run
    // from a bare `DispatchQueue.main.async` inside onAppear, i.e. on the
    // *cold-launch critical path*. There, makeFirstResponder synchronously
    // drives AppKit's text-input machinery (NSTextInputContext / input-method
    // services) as it warms up on a Default-QoS thread, so the main
    // (user-interactive) thread blocks on lower-QoS work. Triggering off
    // `didBecomeKey` instead means the window is fully key and the field
    // editor's text-input context is already warm, so resigning it is a
    // teardown that doesn't block on cold input-method init. Still dispatched
    // one run-loop turn later so it runs *after* AppKit's own
    // initial-responder assignment (which happens as the window becomes key).
    // One-shot: it removes itself after the first fire so a later app
    // reactivation (Cmd-Tab back) never steals focus from a field the tech is
    // actively editing. Guarded to only act when a text field actually holds
    // focus (same guard as clickAwayMonitor), so it's a no-op if nothing did.
    private func installInitialFocusReset() {
        guard didBecomeKeyObserver == nil else { return }
        var token: Any?
        // Deferred + guarded resign, one-shot: removes the observer the first
        // time it runs so a later app reactivation can't fire it. Guarding on
        // NSTextView means it only touches the responder chain once a field
        // actually holds focus -- so it never resigns cold (avoiding the
        // Default-QoS text-input init the inversion came from).
        let reset: () -> Void = {
            DispatchQueue.main.async {
                if let window = NSApp.keyWindow, window.firstResponder is NSTextView {
                    window.makeFirstResponder(nil)
                }
            }
            if let token {
                NotificationCenter.default.removeObserver(token)
            }
        }
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in reset() }
        didBecomeKeyObserver = token
        // Cover the race where the window already became key before this
        // observer registered (onAppear can run after window-did-become-key,
        // so the notification would already be missed): if it's key now, run
        // the same guarded resign directly. `reset()` then tears the observer
        // down, so it won't fire on a future Cmd-Tab return.
        if NSApp.keyWindow != nil {
            reset()
        }
    }

    private func removeInitialFocusReset() {
        if let didBecomeKeyObserver {
            NotificationCenter.default.removeObserver(didBecomeKeyObserver)
        }
        didBecomeKeyObserver = nil
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
        .environment(AppearanceSettings())
        .environment(\.theme, Theme(mode: .default))
}
