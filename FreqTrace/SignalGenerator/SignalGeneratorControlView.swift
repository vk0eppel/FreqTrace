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

            SignalGeneratorLevelField(levelDB: $engine.levelDB)

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

/// The directly-editable numeric dB level box (CONTEXT.md "Signal Generator
/// Level") -- explicitly not a slider. Shows "-66dB"-style formatting while
/// unfocused; while the tech is typing, the raw text is left alone so
/// mid-edit reformatting doesn't fight their cursor.
private struct SignalGeneratorLevelField: View {
    @Environment(\.theme) private var theme
    @Binding var levelDB: Double
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Level", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .frame(width: 64)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(theme.border)
            }
            .focused($isFocused)
            .onAppear { text = Self.formatted(levelDB) }
            .onChange(of: levelDB) { _, newValue in
                if !isFocused { text = Self.formatted(newValue) }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onSubmit { commit() }
    }

    private func commit() {
        let digits = text.filter { $0.isNumber || $0 == "-" || $0 == "." }
        if let parsed = Double(digits) {
            levelDB = min(max(parsed, SignalGeneratorEngine.levelRangeDB.lowerBound), SignalGeneratorEngine.levelRangeDB.upperBound)
        }
        text = Self.formatted(levelDB)
    }

    private static func formatted(_ db: Double) -> String {
        "\(Int(db.rounded()))dB"
    }
}

#Preview {
    SignalGeneratorControlView(engine: SignalGeneratorEngine())
        .environment(\.theme, Theme(mode: .dark))
        .padding()
        .background(Theme(mode: .dark).surfaceRaised)
}
