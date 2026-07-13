//
//  MeasuredDataRowView.swift
//  FreqTrace
//
//  The Measured Data row: Tracked Frequency (hero, live-wired to
//  AudioPipelineViewModel per ticket #3), Anomaly Candidates, SPL (live per
//  ticket #6, moved here from the Controls row so the SPL Offset control
//  sits with the reading it affects). Anomaly Candidates is still a
//  placeholder pending its own ticket. Peak markers (ticket #12,
//  CONTEXT.md "Peak") show alongside Tracked Frequency's and SPL's live
//  values -- never appearing at all until a peak has actually been
//  recorded, no placeholder dash.
//

import SwiftUI

struct MeasuredDataRowView: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPipelineViewModel.self) private var trackedFrequencyViewModel

    var body: some View {
        HStack(spacing: 0) {
            dataBlock(label: "TRACKED FREQUENCY") {
                VStack(alignment: .leading, spacing: 2) {
                    heroValue(trackedFrequencyViewModel.formattedFrequency)
                    if let peak = trackedFrequencyViewModel.formattedTrackedFrequencyLevelPeak {
                        peakLabel(peak)
                    }
                }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(trackedFrequencyViewModel.formattedSPL)
                        .font(.system(size: Typography.secondarySize, weight: .semibold, design: .monospaced))
                        .foregroundStyle(trackedFrequencyViewModel.splDb == nil ? theme.textFaint : theme.text)
                    if let peak = trackedFrequencyViewModel.formattedSPLPeak {
                        peakLabel(peak)
                    }
                    splOffsetControl
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(theme.surface)
    }

    // The SPL Offset control (CONTEXT.md "SPL Offset"): a bare-bones manual
    // numeric field, no calibration workflow -- ADR 0003. Lives with the SPL
    // reading it offsets, rather than in the Controls row, since it's
    // scoped to this one readout. Displayed = raw dBFS + this offset (see
    // AudioPipelineViewModel.formattedSPL).
    private var splOffsetControl: some View {
        HStack(spacing: 6) {
            Text("OFFSET")
                .font(.system(size: Typography.subCaptionSize, weight: .regular))
                .foregroundStyle(theme.textFaint)
            NumericValueField(
                value: Binding(
                    get: { trackedFrequencyViewModel.splOffsetDb },
                    set: { trackedFrequencyViewModel.splOffsetDb = $0 }
                ),
                range: AudioPipelineViewModel.splOffsetRangeDb
            )
        }
    }

    private func peakLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Typography.subCaptionSize, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.textDim)
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
