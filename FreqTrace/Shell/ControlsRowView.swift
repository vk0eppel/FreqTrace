//
//  ControlsRowView.swift
//  FreqTrace
//
//  Two-line Controls row (see CLAUDE.md Frontend):
//  Line 1 -- Weighting (live, ticket #3), Time Averaging (live, ticket #7),
//  Peak reset (live, ticket #12), Freeze/Stop (live, ticket #13), Signal
//  Generator (live, ticket #9, sine frequency control added ticket #14).
//  SPL Offset lives in the Measured Data row's SPL block instead (ticket
//  #6), alongside the
//  reading it offsets, not here. Line 2 -- Input Device (live, ticket #4),
//  Appearance Mode (live, ticket #10, center), Output Device (live, ticket
//  #14). Remaining groups are still placeholders pending their own
//  tickets.
//

import SwiftUI

struct ControlsRowView: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPipelineViewModel.self) private var trackedFrequencyViewModel
    @Environment(AppearanceSettings.self) private var appearanceSettings
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
        HStack(spacing: 8) {
            weightingControl
            timeAveragingControl
            peakResetControl
            freezeStopControl
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
            appearanceControl
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    // Appearance Mode (ticket #10, ADR 0005): a manual Dark/Light toggle,
    // deliberately independent of the macOS system appearance setting --
    // Dark (default) for dim venues, high-contrast Light for direct
    // sunlight. Writes straight to AppearanceSettings.mode, which
    // AppShellView turns into the injected Theme every view reads.
    private var appearanceControl: some View {
        HStack(spacing: 10) {
            Text("APPEARANCE")
                .font(.system(size: Typography.controlSize, weight: .medium))
                .foregroundStyle(theme.textDim)
            ForEach(AppearanceMode.allCases) { mode in
                appearanceButton(mode)
            }
        }
        .consolePlate()
    }

    private func appearanceButton(_ mode: AppearanceMode) -> some View {
        let isSelected = appearanceSettings.mode == mode
        return Button {
            appearanceSettings.mode = mode
        } label: {
            HStack(spacing: 4) {
                LEDIndicator(isLit: isSelected)
                Text(mode.rawValue.uppercased())
                    .font(.system(size: Typography.controlSize, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.text : theme.textDim)
            }
        }
        .buttonStyle(.plain)
    }

    // The Input Device control (ticket #4, CONTEXT.md "Input Device"): a
    // picker over Core Audio's currently available input devices, plus an
    // unmistakable disconnected indicator when the active device
    // disappears mid-use (ADR 0006 -- never a silent fallback). Selecting a
    // device here, including from the disconnected state, re-points the
    // live pipeline and persists the choice as the new default.
    private var inputDeviceControl: some View {
        let isDisconnected: Bool = {
            if case .disconnected = trackedFrequencyViewModel.connectionState { return true }
            return false
        }()
        return HStack(spacing: 6) {
            LEDIndicator(isLit: true, color: isDisconnected ? theme.danger : nil)
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

            if isDisconnected {
                Text("DISCONNECTED")
                    .font(.system(size: Typography.controlSize, weight: .semibold))
                    .foregroundStyle(theme.danger)
            }
        }
        .consolePlate()
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
        let isDisconnected: Bool = {
            if case .disconnected = signalGenerator.connectionState { return true }
            return false
        }()
        return HStack(spacing: 6) {
            if isDisconnected {
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
            LEDIndicator(isLit: true, color: isDisconnected ? theme.danger : nil)
        }
        .consolePlate()
    }

    private var selectedOutputDeviceName: String {
        guard let id = signalGenerator.selectedOutputDeviceID,
              let device = signalGenerator.availableOutputDevices.first(where: { $0.id == id }) else {
            return "No Output Device"
        }
        return device.name
    }

    // Time Averaging (ticket #7, CONTEXT.md "Time Averaging"): Fast/Slow
    // preset controlling how quickly Tracked Frequency responds to level
    // changes -- post-FFT frame-blending, never changes FFT window
    // size/resolution.
    private var timeAveragingControl: some View {
        HStack(spacing: 10) {
            Text("TIME AVG")
                .font(.system(size: Typography.controlSize, weight: .medium))
                .foregroundStyle(theme.textDim)
            ForEach(TimeAveragingPreset.allCases) { preset in
                timeAveragingButton(preset)
            }
        }
        .consolePlate()
    }

    private func timeAveragingButton(_ preset: TimeAveragingPreset) -> some View {
        let isSelected = trackedFrequencyViewModel.timeAveraging == preset
        return Button {
            trackedFrequencyViewModel.timeAveraging = preset
        } label: {
            HStack(spacing: 4) {
                LEDIndicator(isLit: isSelected)
                Text(preset.rawValue.uppercased())
                    .font(.system(size: Typography.controlSize, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.text : theme.textDim)
            }
        }
        .buttonStyle(.plain)
    }

    // Peak reset (ticket #12, CONTEXT.md "Peak"): the only manual control
    // Peak has -- clears every held peak (RTA bars, SPL, Tracked Frequency
    // level) at once. Peak itself has no on/off state of its own; the
    // markers just always show once a value has been recorded.
    private var peakResetControl: some View {
        Button {
            trackedFrequencyViewModel.resetPeaks()
        } label: {
            Text("PEAK RESET")
                .font(.system(size: Typography.controlSize, weight: .semibold))
                .foregroundStyle(theme.textDim)
        }
        .buttonStyle(.plain)
        .consolePlate()
    }

    // Freeze + Stop (ticket #13, CONTEXT.md "Freeze" / "Stop"): two
    // independent controls, deliberately not one. Freeze toggles on/off in
    // place (pipeline keeps running underneath -- see
    // AudioPipelineViewModel.toggleFreeze for the instant-catch-up
    // behavior). Stop halts capture and swaps its own label to "Start"
    // (user report: reads as a Stop/Start toggle, not Stop/Resume), which
    // re-initializes capture against the currently-selected Input Device
    // rather than picking a new one.
    private var freezeStopControl: some View {
        HStack(spacing: 14) {
            freezeButton
            stopButton
        }
        .consolePlate()
    }

    private var freezeButton: some View {
        let isFrozen = trackedFrequencyViewModel.isFrozen
        return Button {
            trackedFrequencyViewModel.toggleFreeze()
        } label: {
            HStack(spacing: 4) {
                LEDIndicator(isLit: isFrozen)
                Text("FREEZE")
                    .font(.system(size: Typography.controlSize, weight: .semibold))
                    .foregroundStyle(isFrozen ? theme.text : theme.textDim)
            }
        }
        .buttonStyle(.plain)
    }

    // Stop/Start's LED reads as a tally light (lit red while capture is
    // actively running), not the shared amber "selected" language every
    // other toggle in this row uses -- this is an engine-running state, not
    // a passing preference.
    private var stopButton: some View {
        let isActive = trackedFrequencyViewModel.isCaptureActive
        return Button {
            if isActive {
                trackedFrequencyViewModel.stop()
            } else {
                trackedFrequencyViewModel.resumeCapture()
            }
        } label: {
            HStack(spacing: 4) {
                LEDIndicator(isLit: isActive, color: theme.danger)
                Text(isActive ? "STOP" : "START")
                    .font(.system(size: Typography.controlSize, weight: .semibold))
                    .foregroundStyle(isActive ? theme.danger : theme.textDim)
            }
        }
        .buttonStyle(.plain)
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
        HStack(spacing: 10) {
            Text("WEIGHTING")
                .font(.system(size: Typography.controlSize, weight: .medium))
                .foregroundStyle(theme.textDim)
            ForEach(Weighting.allCases) { option in
                weightingButton(option)
            }
        }
        .consolePlate()
    }

    private func weightingButton(_ option: Weighting) -> some View {
        let isSelected = trackedFrequencyViewModel.weighting == option
        return Button {
            trackedFrequencyViewModel.weighting = option
        } label: {
            HStack(spacing: 4) {
                LEDIndicator(isLit: isSelected)
                Text(option.rawValue)
                    .font(.system(size: Typography.controlSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? theme.text : theme.textDim)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ControlsRowView()
        .environment(\.theme, Theme(mode: .dark))
        .environment(AudioPipelineViewModel())
        .environment(AppearanceSettings())
        .frame(width: 1120)
}
