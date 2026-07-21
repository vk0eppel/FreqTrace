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
//  Fixed-width numeric readouts (user report: "space is moving when the
//  frequency changes"): Tracked Frequency and SPL's digit count varies
//  ("340 Hz" vs "12000 Hz"), which shifted every block after them since
//  none had a fixed width. Fixed via the standard SwiftUI trick -- an
//  invisible reference string at the widest plausible value reserves the
//  layout width; the real (shorter-or-equal) value overlays on top,
//  trailing-aligned (user report: "the Hz part is moving" -- left-aligning
//  the overlay left the unit suffix drifting as digit count changed),
//  without affecting the container's size.
//
//  Fixed-height blocks, top-aligned (user report: "should always stay at
//  the same height, on top of their line"): the three blocks used to sit
//  in a plain HStack (default center alignment) with each block's own
//  height determined by its optional content (a Peak label that may or
//  may not be showing, 0-3 Anomaly Candidate rows) -- so blocks visibly
//  resized and re-centered as that content came and went. Every optional
//  region below now reserves its maximum plausible height via the same
//  hidden-reference-overlay trick fixedWidth already established
//  (fixedHeight, vertical instead of horizontal), and the row's HStack is
//  explicitly top-aligned.
//

import SwiftUI

struct MeasuredDataRowView: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPipelineViewModel.self) private var trackedFrequencyViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highestSeverityPulse = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            dataBlock(label: "TRACKED FREQUENCY") {
                VStack(alignment: .leading, spacing: 2) {
                    readingValue(
                        trackedFrequencyViewModel.trackedFrequencyReading,
                        numberSize: Typography.heroSize,
                        referenceNumber: "24000"
                    )
                    fixedHeight(reference: peakLabelReference) {
                        if let peak = trackedFrequencyViewModel.formattedTrackedFrequencyLevelPeak {
                            peakLabel(peak)
                        }
                    }
                }
            }
            dataBlock(label: "ANOMALY CANDIDATES") {
                fixedHeight(reference: anomalyCandidatesReference) {
                    if !trackedFrequencyViewModel.anomalyCandidates.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(trackedFrequencyViewModel.anomalyCandidates.enumerated()), id: \.element.id) { rank, candidate in
                                anomalyRow(candidate, rank: rank)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            dataBlock(label: "SPL") {
                VStack(alignment: .leading, spacing: 4) {
                    readingValue(
                        trackedFrequencyViewModel.splReading,
                        numberSize: Typography.secondarySize,
                        referenceNumber: "-100"
                    )
                    fixedHeight(reference: peakLabelReference) {
                        if let peak = trackedFrequencyViewModel.formattedSPLPeak {
                            peakLabel(peak)
                        }
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .onAppear {
            guard isHighest, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                highestSeverityPulse = true
            }
        }
    }

    private func formattedAnomalyFrequency(_ hz: Double) -> String {
        // Whole Hz, no kHz abbreviation -- reads the same way as the Tracked
        // Frequency hero (MeasuredReading.frequency), e.g. "16250 Hz" not
        // "16.25 kHz" (user request), so the two readouts are directly
        // comparable at a glance.
        String(format: "%.0f Hz", hz)
    }

    private func peakLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Typography.subCaptionSize, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.textDim)
    }

    /// Height reference for the optional Peak label line (shared by
    /// Tracked Frequency and SPL) -- any non-empty string at the same font
    /// reserves the correct line height; the exact text never renders.
    private var peakLabelReference: some View {
        Text("PEAK -100 dB")
            .font(.system(size: Typography.subCaptionSize, weight: .medium, design: .monospaced))
    }

    /// Height reference for the Anomaly Candidates area -- three rows at
    /// each rank's real font size/spacing, so the block always reserves
    /// room for the maximum 2-3 rows (CONTEXT.md "Measured Data row")
    /// regardless of how many are currently showing. Plain Text, not
    /// anomalyRow(_:rank:) itself -- reusing that would attach a second
    /// onAppear to a hidden view and could kick off a redundant pulse
    /// animation for no visible row.
    private var anomalyCandidatesReference: some View {
        // 5 digits ("00000 Hz") reserves width up to Nyquist (24000 Hz),
        // matching the Tracked Frequency reference -- a 4-digit reference made
        // 5-digit candidates like "16250 Hz" wrap (user report).
        VStack(alignment: .leading, spacing: 6) {
            Text("00000 Hz").font(.system(size: 22, weight: .semibold, design: .monospaced))
            Text("00000 Hz").font(.system(size: 18, weight: .semibold, design: .monospaced))
            Text("00000 Hz").font(.system(size: 15, weight: .semibold, design: .monospaced))
        }
    }

    /// Reserves layout height for `reference` (rendered invisibly) so
    /// optional/variable-count content never resizes its block as it
    /// comes and goes (user report: "should always stay at the same
    /// height, on top of their line") -- `content` overlays on top,
    /// top-left-anchored, at its own natural size.
    private func fixedHeight(reference: some View, @ViewBuilder content: () -> some View) -> some View {
        reference
            .hidden()
            .overlay(alignment: .topLeading) { content() }
    }

    // Fixed content height (user report: "the boxes height should be
    // fixed") -- sized to the tallest block (Tracked Frequency: its caption
    // + the 64pt hero digits + the Peak line), so all three meter panels
    // match regardless of how much a given block's value actually needs.
    private static let dataBlockContentHeight: CGFloat = 112

    @ViewBuilder
    private func dataBlock(label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: Typography.captionSize, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.textFaint)
            value()
        }
        .frame(height: Self.dataBlockContentHeight, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .meterPanel()
    }

    /// A hero/secondary numeric readout: the number big and bright, the unit
    /// smaller and dimmed so the digits read first from a distance (ticket
    /// #24), with a unit-bearing "— Hz"/"— dB" placeholder in the empty state
    /// (ticket #22). `referenceNumber` is the widest plausible number (e.g.
    /// "24000" covers Nyquist at 48kHz, "-100" the SPL range) -- rendered
    /// invisibly with the same unit to reserve layout width, so a shorter
    /// live value never shifts anything after it and the unit stays anchored
    /// on the right, only the leading digits shifting (user reports: "space
    /// is moving when the frequency changes" / "the Hz part is moving").
    private func readingValue(_ reading: MeasuredReading, numberSize: CGFloat, referenceNumber: String) -> some View {
        // Unit ~0.42x the number and baseline-aligned -- large enough to read,
        // small enough that the digits clearly dominate.
        let unitSize = (numberSize * 0.42).rounded()
        let numberFont = Font.system(size: numberSize, weight: .semibold, design: .monospaced)
        let unitFont = Font.system(size: unitSize, weight: .medium, design: .monospaced)
        let spacing = unitSize * 0.3

        return HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Text(referenceNumber).font(numberFont)
            Text(reading.unit).font(unitFont)
        }
        .hidden()
        .overlay(alignment: .trailing) {
            HStack(alignment: .firstTextBaseline, spacing: spacing) {
                Text(reading.number)
                    .font(numberFont)
                    .foregroundStyle(reading.hasValue ? theme.text : theme.textFaint)
                Text(reading.unit)
                    .font(unitFont)
                    .foregroundStyle(theme.textDim)
            }
        }
    }
}

#Preview {
    MeasuredDataRowView()
        .environment(\.theme, Theme(mode: .dark))
        .environment(AudioPipelineViewModel())
        .frame(width: 1120)
}
