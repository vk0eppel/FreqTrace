//
//  ControlsRowView.swift
//  FreqTrace
//
//  Two-line Controls row (see CLAUDE.md Frontend):
//  Line 1 -- Weighting (live, ticket #3), SPL Offset (live, ticket #6),
//  Time Averaging, Peak/Freeze/Stop, Signal Generator (live, ticket #9).
//  Line 2 -- Input Device (left), Appearance Mode (center), Output Device
//  (right). Remaining groups are still placeholders pending their own
//  tickets.
//

import SwiftUI

struct ControlsRowView: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPipelineViewModel.self) private var trackedFrequencyViewModel
    @State private var signalGenerator = SignalGeneratorEngine()

    var body: some View {
        VStack(spacing: 0) {
            line1
            Rectangle()
                .fill(theme.borderSoft)
                .frame(height: 1)
            line2
        }
        .background(theme.surfaceRaised)
    }

    private var line1: some View {
        HStack(spacing: 0) {
            weightingControl
            splOffsetControl
            placeholderGroup("Time Avg")
            placeholderGroup("Peak / Freeze / Stop")
            Spacer(minLength: 0)
            SignalGeneratorControlView(engine: signalGenerator)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    private var line2: some View {
        // True three-way split (not a double-Spacer, which only centers
        // "Appearance" when the left/right content happen to be equal
        // width) -- side groups get equal flexible width via .frame, and
        // "Appearance" is centered as an overlay independent of their content.
        HStack(spacing: 0) {
            placeholderGroup("Input Device")
                .frame(maxWidth: .infinity, alignment: .leading)
            placeholderGroup("Output Device")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .overlay {
            placeholderGroup("Appearance")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    private func placeholderGroup(_ label: String) -> some View {
        Text(label)
            .font(.system(size: Typography.controlSize, weight: .medium))
            .foregroundStyle(theme.textDim)
            .padding(.horizontal, 18)
    }

    // The Weighting control (CONTEXT.md "Weighting"): a single global A/C/Z
    // setting, default A. Selecting a value here changes which frequency
    // reads as loudest in the Tracked Frequency readout.
    private var weightingControl: some View {
        HStack(spacing: 6) {
            Text("WEIGHTING")
                .font(.system(size: Typography.controlSize, weight: .medium))
                .foregroundStyle(theme.textDim)
            ForEach(Weighting.allCases) { option in
                weightingButton(option)
            }
        }
        .padding(.horizontal, 18)
    }

    private func weightingButton(_ option: Weighting) -> some View {
        let isSelected = trackedFrequencyViewModel.weighting == option
        return Button {
            trackedFrequencyViewModel.weighting = option
        } label: {
            Text(option.rawValue)
                .font(.system(size: Typography.controlSize, weight: .semibold, design: .monospaced))
                .frame(width: 22, height: 22)
                .foregroundStyle(isSelected ? theme.bg : theme.textDim)
                .background(Circle().fill(isSelected ? theme.accent : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // The SPL Offset control (CONTEXT.md "SPL Offset"): a bare-bones
    // manual numeric field, no calibration workflow -- ADR 0003. Displayed
    // = raw dBFS + this offset (see AudioPipelineViewModel.formattedSPL).
    private var splOffsetControl: some View {
        HStack(spacing: 6) {
            Text("SPL OFFSET")
                .font(.system(size: Typography.controlSize, weight: .medium))
                .foregroundStyle(theme.textDim)
            DBValueField(
                value: Binding(
                    get: { trackedFrequencyViewModel.splOffsetDb },
                    set: { trackedFrequencyViewModel.splOffsetDb = $0 }
                ),
                range: AudioPipelineViewModel.splOffsetRangeDB
            )
        }
        .padding(.horizontal, 18)
    }
}

#Preview {
    ControlsRowView()
        .environment(\.theme, Theme(mode: .dark))
        .environment(AudioPipelineViewModel())
        .frame(width: 1120)
}
