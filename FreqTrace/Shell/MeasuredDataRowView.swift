//
//  MeasuredDataRowView.swift
//  FreqTrace
//
//  The Measured Data row: Tracked Frequency (hero, live-wired to
//  AudioPipelineViewModel per ticket #3), Anomaly Candidates (live per
//  ticket #5), SPL (live per ticket #6, moved here from the Controls row
//  so the SPL Offset control sits with the reading it affects). Peak
//  markers (ticket #12, CONTEXT.md "Peak") show alongside Tracked
//  Frequency's and SPL's live values -- never appearing at all until a
//  peak has actually been recorded, no placeholder dash.
//
//  Anomaly Candidates (CONTEXT.md, "Measured Data row"): top 2-3 ranked by
//  severity, shows nothing at all (not even a dash) when there are zero --
//  the caption label always shows (like every other block's label), only
//  the value area is genuinely empty. Severity is a compound visual signal
//  (stripe height/glow, frequency-number size, text-color intensity), not
//  a single color dot; the highest-severity row pulses, respecting
//  accessibilityReduceMotion.
//

import SwiftUI

struct MeasuredDataRowView: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPipelineViewModel.self) private var trackedFrequencyViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highestSeverityPulse = false

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
                if !trackedFrequencyViewModel.anomalyCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(trackedFrequencyViewModel.anomalyCandidates.enumerated()), id: \.element.id) { rank, candidate in
                            anomalyRow(candidate, rank: rank)
                        }
                    }
                }
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

    // Compound severity signal (rank 0 = highest): text size, color
    // intensity, and a left stripe's height/glow all scale together --
    // never color alone (CLAUDE.md "Severity is weighted, not just
    // colored"). Only rank 0 gets the slow pulsing glow.
    private func anomalyRow(_ candidate: AnomalyCandidate, rank: Int) -> some View {
        let isHighest = rank == 0
        let fontSize: CGFloat = rank == 0 ? 22 : (rank == 1 ? 18 : 15)
        let colorOpacity: Double = rank == 0 ? 1.0 : (rank == 1 ? 0.75 : 0.55)
        let stripeHeight: CGFloat = rank == 0 ? 20 : (rank == 1 ? 14 : 10)

        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.danger)
                .frame(width: 4, height: stripeHeight)
                .shadow(
                    color: isHighest ? theme.danger.opacity(highestSeverityPulse ? 0.9 : 0.35) : .clear,
                    radius: isHighest ? 6 : 0
                )
            Text(formattedAnomalyFrequency(candidate.frequencyHz))
                .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.danger.opacity(colorOpacity))
        }
        .onAppear {
            guard isHighest, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                highestSeverityPulse = true
            }
        }
    }

    private func formattedAnomalyFrequency(_ hz: Double) -> String {
        hz >= 1000 ? String(format: "%.2f kHz", hz / 1000) : String(format: "%.0f Hz", hz)
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
