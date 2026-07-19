//
//  KeyboardShortcuts.swift
//  FreqTrace
//
//  Shared plumbing for the app's plain-key shortcuts (user request: space
//  = Start/Stop, w = Waterfall, r = RTA). One NSEvent local monitor per
//  registering view, all sharing the same two guards:
//
//  - Modifier keys pass through untouched, so Cmd+W still closes the
//    window and other system chords keep working.
//  - A focused text field wins: if the current first responder is an
//    NSTextView (a NumericValueField mid-edit uses the shared field
//    editor, which is one), the keystroke is delivered as typed text
//    instead of firing a shortcut. This checks the *actual* first
//    responder at the moment the key lands rather than any SwiftUI-side
//    focus state -- see AppShellView's spacebarMonitor history for why
//    racing @FocusState against AppKit's own focus assignment didn't work.
//
//  Keys are matched by the typed character (`charactersIgnoringModifiers`),
//  not the physical key code -- key codes name QWERTY positions, so
//  code-based matching would put "w" on a different physical key for
//  techs on AZERTY or other layouts.
//

import AppKit

enum KeyboardShortcuts {
    /// Named keys for shortcuts whose typed "character" is a non-printing
    /// function-key scalar rather than a writable string literal (the arrow
    /// keys, used for the Signal Generator's frequency/level -- user
    /// request). Matched by character like every other shortcut, so they
    /// stay layout-independent.
    static let leftArrow = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    static let rightArrow = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    static let upArrow = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    static let downArrow = String(UnicodeScalar(NSDownArrowFunctionKey)!)

    /// Modifiers whose presence means "this is a chord, not a plain-key
    /// shortcut" -- so it passes through untouched (Cmd+W still closes the
    /// window, Shift/Cmd+arrow reach the system). Deliberately NOT the full
    /// `.deviceIndependentFlagsMask`: the arrow keys always report
    /// `.function` + `.numericPad`, which are in that mask, so checking it
    /// would treat every arrow as modified and none of the arrow shortcuts
    /// would ever fire. Caps Lock is likewise excluded, so shortcuts keep
    /// working with it on.
    private static let chordModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    /// Installs a local keyDown monitor firing `actions[key]` for plain
    /// (unmodified) keypresses. Returns the monitor token; the caller owns
    /// it and must pass it to `remove(_:)` when its view disappears.
    static func install(_ actions: [String: @MainActor () -> Void]) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(chordModifiers).isEmpty,
                  let key = event.charactersIgnoringModifiers?.lowercased(),
                  let action = actions[key] else {
                return event
            }
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                return event
            }
            action()
            return nil
        }
    }

    static func remove(_ monitor: Any?) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
