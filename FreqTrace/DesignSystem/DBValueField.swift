//
//  DBValueField.swift
//  FreqTrace
//
//  A directly-editable numeric dB value box (e.g. "-66dB") -- explicitly
//  not a slider. Shared by the Signal Generator's Level field (ticket #9,
//  CONTEXT.md "Signal Generator Level") and the SPL meter's offset field
//  (ticket #6, CONTEXT.md "SPL Offset") -- both call for the exact same
//  interaction, extracted here after the second real call site showed up
//  rather than duplicated a second time. Shows formatted text while
//  unfocused; while the tech is typing, the raw text is left alone so
//  mid-edit reformatting doesn't fight their cursor.
//

import SwiftUI

struct DBValueField: View {
    @Environment(\.theme) private var theme
    @Binding var value: Double
    let range: ClosedRange<Double>
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("dB", text: $text)
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
            .onAppear { text = Self.formatted(value) }
            .onChange(of: value) { _, newValue in
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
            value = min(max(parsed, range.lowerBound), range.upperBound)
        }
        text = Self.formatted(value)
    }

    private static func formatted(_ db: Double) -> String {
        "\(Int(db.rounded()))dB"
    }
}

#Preview {
    @Previewable @State var value: Double = -66
    DBValueField(value: $value, range: -96...0)
        .environment(\.theme, Theme(mode: .dark))
        .padding()
        .background(Theme(mode: .dark).surfaceRaised)
}
