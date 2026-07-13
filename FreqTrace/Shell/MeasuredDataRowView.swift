//
//  MeasuredDataRowView.swift
//  FreqTrace
//
//  Placeholder for the Measured Data row: Tracked Frequency (hero),
//  Anomaly Candidates, SPL. Read-only, no controls (see CLAUDE.md Frontend).
//  Real live values land in later tickets; this establishes the row's
//  structure, sizing, and typography hierarchy.
//

import SwiftUI

struct MeasuredDataRowView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            dataBlock(label: "TRACKED FREQUENCY") {
                heroValue("—")
            }
            divider
            dataBlock(label: "ANOMALY CANDIDATES") {
                Text("—")
                    .font(.system(size: Typography.tertiarySize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            divider
            dataBlock(label: "SPL") {
                Text("—")
                    .font(.system(size: Typography.secondarySize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textFaint)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(theme.surface)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.borderSoft)
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dataBlock(label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: Typography.captionSize, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.textFaint)
            value()
        }
        .padding(.horizontal, 24)
    }

    private func heroValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Typography.heroSize, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.textFaint)
    }
}

#Preview {
    MeasuredDataRowView()
        .environment(\.theme, Theme(mode: .dark))
        .frame(width: 1120)
}
