//
//  SignalGeneratorControlView.swift
//  FreqTrace
//
//  The Signal Generator cluster on the right of Controls row Line 1 (see
//  CLAUDE.md Frontend, CONTEXT.md "Signal Generator Level" / "Signal
//  Generator On/Off"): waveform picker, sine frequency control (ticket #14,
//  CONTEXT.md "ISO Band"), numeric dB level box, explicit on/off switch.
//  Output Device is deliberately excluded here -- it's a separate control
//  on Line 2 (see ControlsRowView).
//
//  The frequency control (ISO Band step buttons + free Hz field) only
//  applies to the sine waveform -- pink/white noise have no single
//  frequency to set (CONTEXT.md "ISO Band") -- so it's hidden entirely
//  rather than merely disabled when a noise waveform is selected, keeping
//  the cluster's width stable rather than showing a dead control.
//

import SwiftUI

struct SignalGeneratorControlView: View {
    @Environment(\.theme) private var theme
    @Bindable var engine: SignalGeneratorEngine

    var body: some View {
        HStack(spacing: 12) {
            waveformControl

            if engine.waveform == .sine {
                sineFrequencyControl
            }

            // Narrower than NumericValueField's default width (64pt, sized
            // for other fields' wider ranges) -- levelRangeDB tops out at
            // "-96dB" (5 chars), so the box only needs to fit that (user
            // report: box was wider than the value it holds).
            NumericValueField(value: $engine.levelDB, range: SignalGeneratorEngine.levelRangeDB, width: 46)

            // Native Toggle per CONTEXT.md -- a real, explicit switch, not
            // a passive status dot: flipping it must actually start/stop
            // audible output.
            Toggle("Signal Generator On", isOn: Binding(
                get: { engine.isOn },
                set: { engine.setOn($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(theme.accent)
        }
        .font(.system(size: Typography.controlSize, weight: .medium))
        .foregroundStyle(theme.text)
        .consolePlate()
    }

    // Waveform picker (ticket #9): rendered as its own row of lit-LED
    // buttons rather than a native segmented control, matching the same
    // "one lit indicator = one active state" language used by every other
    // toggle in the Controls row (see ConsoleModule.swift).
    private var waveformControl: some View {
        HStack(spacing: 10) {
            ForEach(Waveform.allCases) { waveform in
                waveformButton(waveform)
            }
        }
    }

    private func waveformButton(_ waveform: Waveform) -> some View {
        let isSelected = engine.waveform == waveform
        return Button {
            engine.waveform = waveform
        } label: {
            HStack(spacing: 4) {
                LEDIndicator(isLit: isSelected)
                Text(waveform.displayName.uppercased())
                    .font(.system(size: Typography.controlSize, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.text : theme.textDim)
            }
        }
        .buttonStyle(.plain)
    }

    // Sine frequency control (ticket #14, CONTEXT.md "ISO Band"): step
    // buttons jump to the next/previous standard ISO 1/3-octave center
    // (the primary interaction, matching graphic EQ fader spacing); the
    // numeric Hz field is the fallback for an exact custom value, including
    // landing off-grid between two centers.
    private var sineFrequencyControl: some View {
        HStack(spacing: 4) {
            stepButton(systemName: "chevron.left") { engine.stepSineFrequencyDown() }

            NumericValueField(
                value: $engine.sineFrequencyHz,
                range: SignalGeneratorEngine.sineFrequencyRangeHz,
                format: Self.formattedHz,
                width: 60
            )

            stepButton(systemName: "chevron.right") { engine.stepSineFrequencyUp() }
        }
    }

    private func stepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: Typography.controlSize, weight: .semibold))
                .foregroundStyle(theme.textDim)
                .frame(width: 18, height: 22)
        }
        .buttonStyle(.plain)
    }

    /// "1000Hz" / "31.5Hz"-style formatting -- ISO Band centers are mostly
    /// whole numbers but a few (31.5, 315, 3150...) carry one decimal, so
    /// trailing ".0" is trimmed rather than always showing a fixed number
    /// of decimal places.
    // nonisolated: passed as NumericValueField's `format` closure, which
    // isn't main-actor-bound -- pure string formatting anyway (Swift 6
    // language-mode error otherwise).
    private nonisolated static func formattedHz(_ hz: Double) -> String {
        let rounded = (hz * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded))Hz"
        }
        return String(format: "%.1fHz", rounded)
    }
}

#Preview {
    SignalGeneratorControlView(engine: SignalGeneratorEngine())
        .environment(\.theme, Theme(mode: .dark))
        .padding()
        .background(Theme(mode: .dark).surfaceRaised)
}
