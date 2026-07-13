//
//  MeasuredDataRowView.swift
//  FreqTrace
//
//  The Measured Data row: Tracked Frequency (hero, live-wired to
//  AudioPipelineViewModel per ticket #3), Anomaly Candidates, SPL.
//  Read-only, no controls (see CLAUDE.md Frontend). Anomaly Candidates/SPL
//  are still placeholders pending their own tickets.
//

import SwiftUI

struct MeasuredDataRowView: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPipelineViewModel.self) private var trackedFrequencyViewModel

    var body: some View {
        HStack(spacing: 0) {
            dataBlock(label: "TRACKED FREQUENCY") {
                heroValue(trackedFrequencyViewModel.formattedFrequency)
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
            .foregroundStyle(trackedFrequencyViewModel.trackedFrequencyHz == nil ? theme.textFaint : theme.text)
    }
}

#Preview {
    MeasuredDataRowView()
        .environment(\.theme, Theme(mode: .dark))
        .environment(AudioPipelineViewModel())
        .frame(width: 1120)
}
