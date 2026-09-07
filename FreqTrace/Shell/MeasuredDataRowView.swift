//
//  MeasuredDataRowView.swift
//  FreqTrace
//
//  The Measured Data row: Tracked Frequency (hero, live-wired to
//  AudioPipelineViewModel per ticket #3), Anomaly Candidates (live per
//  ticket #5), and two SPL meters -- SPL (A) and SPL (C) (live per ticket
//  #6; both weightings shown at once, neither following the global
//  Weighting -- CONTEXT.md "SPL"). A single shared SPL Offset strip spans
//  beneath both SPL panels (one offset for both meters), moved here from the
//  Controls row so it's with the readings it affects. Peak markers (ticket #12,
//  CONTEXT.md "Peak") show alongside each SPL meter's live value -- never
//  appearing at all until a peak has actually been recorded, no placeholder
//  dash.
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
            // Input clip/headroom meter (user request): a VU-style vertical
            // meter as the leftmost block, before Tracked Frequency -- a
            // measured value, so it lives with the readouts, not the Controls
            // row. Reads the true input sample peak (dBFS/clip), distinct from
            // the SPL meters' spectral energy.
            dataBlock(label: "INPUT") {
                InputLevelMeter()
            }
            dataBlock(label: "TRACKED FREQUENCY") {
                VStack(alignment: .leading, spacing: 2) {
                    readingValue(
                        trackedFrequencyViewModel.trackedFrequencyReading,
                        numberSize: Typography.heroSize,
                        referenceNumber: "24000"
                    )
                    // Live level in a fixed-width trailing box (widest
                    // "-100 dB" reserved, real value overlaid trailing-
                    // aligned) so the "dB" unit stays anchored and only the
                    // leading digits shift -- same as the hero/SPL
                    // readingValue (user request: "the dB.. part does not
                    // move each time the level changes"). No PEAK here: the
                    // tracked frequency wanders, so a held peak of its level
                    // isn't anchored to any one frequency -- this readout is
                    // deliberately instantaneous (Peak reconsideration).
                    Text("-100 dB")
                        .font(.system(size: trackedLevelSize, weight: .medium, design: .monospaced))
                        .hidden()
                        .overlay(alignment: .trailing) {
                            if let level = trackedFrequencyViewModel.formattedTrackedFrequencyLevel {
                                Text(level)
                                    .font(.system(size: trackedLevelSize, weight: .medium, design: .monospaced))
                                    .foregroundStyle(theme.text)
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
            // Two independent SPL meters, A- and C-weighted, shown side by
            // side (CONTEXT.md "SPL") -- neither follows the global Weighting.
            splGroup
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(theme.surface)
    }

    // The two SPL meters as one group: the A and C panels side by side, with
    // a single slim OFFSET strip spanning beneath both (the offset is shared,
    // so it belongs to neither panel alone -- user request). The group sits
    // in the outer top-aligned row like any other block; the strip makes it a
    // little taller than the others, which only trims the flexible waterfall
    // above by a few pt (the data row sizes to content).
    private var splGroup: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                splBlock(
                    label: "SPL (A)",
                    reading: trackedFrequencyViewModel.splReadingA,
                    peak: trackedFrequencyViewModel.formattedSPLPeakA
                )
                splBlock(
                    label: "SPL (C)",
                    reading: trackedFrequencyViewModel.splReadingC,
                    peak: trackedFrequencyViewModel.formattedSPLPeakC
                )
            }
            // The two panels flex to fill whatever height is left above the
            // strip, so the whole group is exactly one block tall (matching
            // Tracked Frequency) rather than a block + an extra strip line
            // below it (user report: the group was taller than Tracked
            // Frequency / the offset sat alone on a new line). The SPL panels
            // had ~44pt of unused vertical space at the full block height
            // anyway, so absorbing the strip here costs the meters nothing.
            splOffsetStrip
        }
        .frame(height: Self.dataBlockOuterHeight)
        .fixedSize(horizontal: true, vertical: false)
    }

    // One SPL meter block: the weighted reading (hero) and its held PEAK.
    // Unlike the fixed-112pt dataBlock, this fills the height its container
    // gives it (maxHeight: .infinity) so splGroup can split one block's worth
    // of height between the two panels and the shared offset strip. Same
    // caption + recessed meterPanel treatment as the other blocks otherwise.
    private func splBlock(label: String, reading: MeasuredReading, peak: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: Typography.captionSize, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.textFaint)
            readingValue(reading, numberSize: Typography.secondarySize, referenceNumber: "-100")
            fixedHeight(reference: peakLabelReference) {
                if let peak {
                    peakLabel(peak)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .meterPanel()
    }

    // The shared SPL Offset strip (CONTEXT.md "SPL Offset"): a bare-bones
    // manual numeric field, no calibration workflow -- ADR 0003. One offset
    // applies to both meters (a physical calibration is one system gain), so
    // it spans under both panels rather than sitting inside one of them.
    // Recessed to match the meter panels above it, and full-width across the
    // pair so it reads as belonging to the SPL meters as a whole. Displayed
    // level = raw dBFS + this offset (see AudioPipelineViewModel.splReadingA/C).
    private var splOffsetStrip: some View {
        HStack(spacing: 8) {
            Text("SPL OFFSET")
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
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .center)
        .meterPanel()
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

    /// Width+height reference for the optional Peak label line (both SPL
    /// meters) -- rendered hidden to reserve layout size; the exact text never
    /// shows. Must be at least as wide as the widest real peak string so the
    /// value isn't clipped: the weighted unit "dB(A)"/"dB(C)" makes
    /// "PEAK -100 dB(A)" the widest case (a bare "PEAK -100 dB" reference
    /// truncated the live "PEAK -8 dB(A)" to "PEAK -8 dB(…" -- user report).
    private var peakLabelReference: some View {
        Text("PEAK -100 dB(A)")
            .font(.system(size: Typography.subCaptionSize, weight: .medium, design: .monospaced))
    }

    /// The live level reads a little larger than PEAK (user request) so the
    /// current value stands out over the held peak beside it.
    private var trackedLevelSize: CGFloat { 14 }

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
    /// The full outer height of a Measured Data block: content + the 12pt
    /// vertical padding on each side dataBlock applies before meterPanel.
    /// splGroup pins itself to this so the two SPL panels + shared offset
    /// strip together are exactly one block tall, not taller.
    private static let dataBlockOuterHeight: CGFloat = dataBlockContentHeight + 24

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
