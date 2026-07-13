//
//  NumericValueField.swift
//  FreqTrace
//
//  A directly-editable numeric value box (e.g. "-66dB", "1000Hz") --
//  explicitly not a slider. Originally DBValueField (ticket #9), built for
//  the Signal Generator's Level field (CONTEXT.md "Signal Generator
//  Level") and the SPL meter's offset field (ticket #6, CONTEXT.md "SPL
//  Offset") -- both call for the exact same interaction. Generalized here
//  (ticket #14) with a pluggable `format` closure so the Signal
//  Generator's free Hz frequency field (CONTEXT.md "ISO Band") reuses the
//  same component rather than a near-duplicate being built for a second
//  unit. Shows formatted text while unfocused; while the tech is typing,
//  the raw text is left alone so mid-edit reformatting doesn't fight their
//  cursor.
//

import SwiftUI

struct NumericValueField: View {
    @Environment(\.theme) private var theme
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Formats the committed value for display while unfocused. Defaults
    /// to the original dB box's "-66dB" style.
    var format: (Double) -> String = { "\(Int($0.rounded()))dB" }
    var width: CGFloat = 64
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("value", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(theme.border)
            }
            .focused($isFocused)
            .onAppear { text = format(value) }
            .onChange(of: value) { _, newValue in
                if !isFocused { text = format(newValue) }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onSubmit { commit() }
    }

    private func commit() {
        let digits = text.filter { $0.isNumber || $0 == "-" || $0 == "." }
        if let parsed = Double(digits) {
            value = min(max(parsed, range.lowerBound), range.upperBound)
        }
        text = format(value)
    }
}

#Preview {
    @Previewable @State var value: Double = -66
    NumericValueField(value: $value, range: -96...0)
        .environment(\.theme, Theme(mode: .dark))
        .padding()
        .background(Theme(mode: .dark).surfaceRaised)
}
