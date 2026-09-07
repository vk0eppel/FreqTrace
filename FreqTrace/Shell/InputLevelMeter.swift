//
//  InputLevelMeter.swift
//  FreqTrace
//
//  The input clip/headroom watchdog (user request), rendered as the content of
//  the leftmost INPUT block in the Measured Data row (before Tracked
//  Frequency) as a VU-style **vertical** meter. It's a measured value, so it
//  belongs with the readouts, not the Controls row; it answers the one thing
//  the SPL(A)/SPL(C) meters don't: is the mic/interface input clipping, or too
//  quiet to measure? -- gain staging, not acoustics.
//
//  So it reads a TRUE time-domain sample peak (AnalysisResult.inputPeakDbFS --
//  max|sample| per hop, 0 dBFS = full scale), NOT the FFT-summed SPL level
//  (that's spectral energy, useless as a clip indicator). Three signals: a
//  live zone-colored column filling bottom->top (accent=normal, warn=hot,
//  danger=clip zone), a held-peak tick + dBFS number (worst case since PEAK
//  RESET), and a latching CLIP flag -- so a transient clip the tech didn't see
//  stays flagged (isInputClipping reads the held peak, cleared by PEAK RESET).
//
//  Renders only the meter content; MeasuredDataRowView wraps it in the shared
//  dataBlock (caption + recessed meterPanel) so it matches the other blocks.
//

import SwiftUI

struct InputLevelMeter: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPipelineViewModel.self) private var viewModel

    /// Displayed dBFS span: -60 (empty, bottom) .. 0 (full scale, top). Below
    /// -60 reads empty.
    private static let minDb: Double = -60
    private static let maxDb: Double = 0
    /// Zone boundaries: below hotDb is normal (accent), hotDb..clipDb is hot
    /// (warn), at/above clipDb is the clip zone (danger). clipDb matches the
    /// latching threshold so the column going red and the CLIP flag agree.
    private static let hotDb: Double = -6
    private var clipDb: Double { Double(AudioPipelineViewModel.inputClipThresholdDbFS) }

    private let barWidth: CGFloat = 14
    private let numberFont: Font = .system(size: 22, weight: .semibold, design: .monospaced)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            meterBar
            // Value beside the bar (user request) so the column spans the full
            // block height instead of sharing it with a number stacked under.
            VStack(alignment: .leading, spacing: 2) {
                // Fixed width (widest "-60" reserved, live value overlaid
                // leading-aligned) so the block doesn't change width as the
                // number's digit count changes ("-4" vs "-16") -- which shifted
                // every block after it (user report).
                Text("-60")
                    .font(numberFont)
                    .hidden()
                    .overlay(alignment: .leading) {
                        Text(levelNumber)
                            .font(numberFont)
                            .foregroundStyle(viewModel.isInputClipping ? theme.danger : theme.text)
                    }
                Text("dBFS")
                    .font(.system(size: Typography.subCaptionSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.textDim)
                // Reserved so the CLIP tag appearing doesn't shift the layout.
                Text("CLIP")
                    .font(.system(size: Typography.subCaptionSize, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.danger)
                    .opacity(viewModel.isInputClipping ? 1 : 0)
                    .padding(.top, 2)
            }
        }
        // Fill the block height so the bar can span it (maxHeight only -- NOT
        // maxWidth, which would make the block greedily wide and fight the
        // flexible Anomaly block).
        .frame(maxHeight: .infinity)
        // Tap the meter to reset its own held peak/clip latch (user request) --
        // a localized convenience; contentShape makes the whole area (bar +
        // value + gaps) tappable, not just the opaque pixels.
        .contentShape(Rectangle())
        .onTapGesture { viewModel.resetInputPeak() }
    }

    private var meterBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: w / 2).fill(theme.bg)

                // Live column, filling bottom-up, colored by the current zone.
                if let live = viewModel.inputPeakDbFS, live > Self.minDb {
                    RoundedRectangle(cornerRadius: w / 2)
                        .fill(zoneColor(live))
                        // At least w tall so a very low level is a visible nub.
                        .frame(height: max(w, fraction(live) * h))
                }

                RoundedRectangle(cornerRadius: w / 2).strokeBorder(theme.border, lineWidth: 1)
            }
            // Peak-hold tick: brightest horizontal mark at the highest level seen.
            .overlay(alignment: .bottom) {
                if let peak = viewModel.inputPeakHoldDbFS, Double(peak) > Self.minDb {
                    Rectangle()
                        .fill(theme.text)
                        .frame(height: 2)
                        .padding(.bottom, min(h - 2, fraction(Double(peak)) * h))
                }
            }
        }
        // Fill whatever height the block gives (what makes the VU column
        // tall -- user request), at a fixed width.
        .frame(maxHeight: .infinity)
        .frame(width: barWidth)
    }

    /// 0..1 position of `db` across the displayed span (0 = bottom, 1 = top).
    private func fraction(_ db: Double) -> CGFloat {
        let clamped = min(Self.maxDb, max(Self.minDb, db))
        return CGFloat((clamped - Self.minDb) / (Self.maxDb - Self.minDb))
    }

    private func zoneColor(_ db: Double) -> Color {
        if db >= clipDb { return theme.danger }
        if db >= Self.hotDb { return theme.warn }
        return theme.accent
    }

    /// The LIVE input level (dBFS) number beside the bar -- matches the bar's
    /// fill (both are the current per-hop sample peak), so it reflects the
    /// signal playing right now. The held peak stays visible as the bar's tick
    /// (and drives the CLIP latch); showing the *held peak* as the number
    /// instead read as "stuck/wrong" once an earlier louder signal had pushed
    /// the hold up while a quieter tone was playing (user report: "−2 dBFS for
    /// a −16 dB sine"). "—" before any level is read. The "dBFS" unit renders
    /// on its own line beside the bar.
    private var levelNumber: String {
        guard let live = viewModel.inputPeakDbFS, live.isFinite, live > Self.minDb else {
            return "—"
        }
        return "\(Int(live.rounded()))"
    }
}
