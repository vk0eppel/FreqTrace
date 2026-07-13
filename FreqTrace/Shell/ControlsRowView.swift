//
//  ControlsRowView.swift
//  FreqTrace
//
//  Two-line Controls row (see CLAUDE.md Frontend):
//  Line 1 -- Weighting (live, ticket #3), Time Averaging, Peak/Freeze/Stop,
//  Signal Generator (live, ticket #9, sine frequency control added ticket
//  #14). SPL Offset lives in the Measured Data row's SPL block instead
//  (ticket #6), alongside the reading it offsets, not here. Line 2 --
//  Input Device (live, ticket #4), Appearance Mode (center), Output Device
//  (live, ticket #14). Remaining groups are still placeholders pending
//  their own tickets.
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
            inputDeviceControl
                .frame(maxWidth: .infinity, alignment: .leading)
            outputDeviceControl
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .overlay {
            placeholderGroup("Appearance")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    // The Input Device control (ticket #4, CONTEXT.md "Input Device"): a
    // picker over Core Audio's currently available input devices, plus an
    // unmistakable disconnected indicator when the active device
    // disappears mid-use (ADR 0006 -- never a silent fallback). Selecting a
    // device here, including from the disconnected state, re-points the
    // live pipeline and persists the choice as the new default.
    private var inputDeviceControl: some View {
        HStack(spacing: 6) {
            Text("INPUT")
                .font(.system(size: Typography.controlSize, weight: .medium))
                .foregroundStyle(theme.textDim)

            Menu {
                ForEach(trackedFrequencyViewModel.availableInputDevices) { device in
                    Button(device.name) {
                        trackedFrequencyViewModel.selectInputDevice(id: device.id)
                    }
                }
            } label: {
                Text(selectedInputDeviceName)
                    .font(.system(size: Typography.controlSize, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize()

            if case .disconnected = trackedFrequencyViewModel.connectionState {
                Text("DISCONNECTED")
                    .font(.system(size: Typography.controlSize, weight: .semibold))
                    .foregroundStyle(theme.danger)
            }
        }
        .padding(.horizontal, 18)
    }

    private var selectedInputDeviceName: String {
        guard let id = trackedFrequencyViewModel.selectedInputDeviceID,
              let device = trackedFrequencyViewModel.availableInputDevices.first(where: { $0.id == id }) else {
            return "No Input Device"
        }
        return device.name
    }

    // The Output Device control (ticket #14, CONTEXT.md "Output Device"):
    // same shape as the Input Device control above, but for the Signal
    // Generator's own AVAudioEngine/device selection -- independent of the
    // Input Device picker (own AudioDeviceEnumerator scope, own
    // AudioDeviceSelector resolution, own persisted choice). Same
    // disconnect behavior (ADR 0006): the disconnected indicator appears
    // rather than silently falling back to another output.
    private var outputDeviceControl: some View {
        HStack(spacing: 6) {
            if case .disconnected = signalGenerator.connectionState {
                Text("DISCONNECTED")
                    .font(.system(size: Typography.controlSize, weight: .semibold))
                    .foregroundStyle(theme.danger)
            }

            Menu {
                ForEach(signalGenerator.availableOutputDevices) { device in
                    Button(device.name) {
                        signalGenerator.selectOutputDevice(id: device.id)
                    }
                }
            } label: {
                Text(selectedOutputDeviceName)
                    .font(.system(size: Typography.controlSize, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize()

            Text("OUTPUT")
                .font(.system(size: Typography.controlSize, weight: .medium))
                .foregroundStyle(theme.textDim)
        }
        .padding(.horizontal, 18)
    }

    private var selectedOutputDeviceName: String {
        guard let id = signalGenerator.selectedOutputDeviceID,
              let device = signalGenerator.availableOutputDevices.first(where: { $0.id == id }) else {
            return "No Output Device"
        }
        return device.name
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
}

#Preview {
    ControlsRowView()
        .environment(\.theme, Theme(mode: .dark))
        .environment(AudioPipelineViewModel())
        .frame(width: 1120)
}
