//
//  SignalGeneratorControlView.swift
//  FreqTrace
//
//  The Signal Generator cluster on the right of Controls row Line 1 (see
//  CLAUDE.md Frontend, CONTEXT.md "Signal Generator Level" / "Signal
//  Generator On/Off"): waveform picker, numeric dB level box, explicit
//  on/off switch. Output Device is deliberately excluded here -- it's a
//  separate control on Line 2, and this ticket (#9) plays to the system
//  default output device only.
//

import SwiftUI

struct SignalGeneratorControlView: View {
    @Environment(\.theme) private var theme
    @Bindable var engine: SignalGeneratorEngine

    var body: some View {
        HStack(spacing: 12) {
            Picker("Waveform", selection: $engine.waveform) {
                ForEach(Waveform.allCases) { waveform in
                    Text(waveform.displayName).tag(waveform)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 148)

            DBValueField(value: $engine.levelDB, range: SignalGeneratorEngine.levelRangeDB)

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
        .padding(.horizontal, 18)
    }
}

#Preview {
    SignalGeneratorControlView(engine: SignalGeneratorEngine())
        .environment(\.theme, Theme(mode: .dark))
        .padding()
        .background(Theme(mode: .dark).surfaceRaised)
}
