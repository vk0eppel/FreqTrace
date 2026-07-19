//
//  ControlsRowView.swift
//  FreqTrace
//
//  Two-line Controls row (see CLAUDE.md Frontend):
//  Line 1 -- Weighting (ticket #3), FFT Size, Time Averaging (ticket #7),
//  Peak reset (ticket #12), Freeze/Stop (ticket #13) -- purely
//  analysis/view controls. Line 2 -- Input Device (ticket #4, left), and
//  the Signal Generator cluster (ticket #9, sine frequency control ticket
//  #14) directly left of the Output Device (ticket #14) it plays through.
//  SPL Offset lives in the Measured Data row's SPL block instead (ticket
//  #6), alongside the reading it offsets, not here. Appearance Mode moved
//  to the View menu (ADR 0005 addendum).
//

import SwiftUI

struct ControlsRowView: View {
    @Environment(\.theme) private var theme
    @Environment(AudioPipelineViewModel.self) private var trackedFrequencyViewModel
    @State private var signalGenerator = SignalGeneratorEngine()
    /// Signal Generator keyboard shortcuts (user request): left/right arrows
    /// step the sine frequency (ISO Band down/up), up/down arrows nudge the
    /// output level +/-1 dB. Registered here rather than in AppShellView's
    /// monitor because the generator engine is this view's own state;
    /// KeyboardShortcuts supplies the shared guards (a focused text field
    /// wins -- so arrows edit the Level/Hz/Offset fields normally while one
    /// is being typed into -- and real chords pass through), same as the
    /// space/w/r shortcuts.
    @State private var generatorShortcutMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            line1
            Rectangle()
                .fill(theme.borderSoft)
                .frame(height: 1)
            line2
        }
        .background(theme.surfaceRaised)
        .onAppear {
            guard generatorShortcutMonitor == nil else { return }
            generatorShortcutMonitor = KeyboardShortcuts.install([
                // Frequency stepping is meaningful only for the sine waveform
                // (the UI hides the frequency control for pink/white noise) --
                // arrows are a no-op there, matching the hidden control.
                KeyboardShortcuts.leftArrow: {
                    if signalGenerator.waveform == .sine { signalGenerator.stepSineFrequencyDown() }
                },
                KeyboardShortcuts.rightArrow: {
                    if signalGenerator.waveform == .sine { signalGenerator.stepSineFrequencyUp() }
                },
                KeyboardShortcuts.upArrow: { signalGenerator.stepLevelUp() },
                KeyboardShortcuts.downArrow: { signalGenerator.stepLevelDown() },
            ])
        }
        .onDisappear {
            KeyboardShortcuts.remove(generatorShortcutMonitor)
            generatorShortcutMonitor = nil
        }
    }

    private var line1: some View {
        HStack(spacing: 8) {
            weightingControl
            fftWindowSizeControl
            timeAveragingControl
            peakResetControl
            freezeStopControl
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    // Line 2 is Input Device (left) / Signal Generator + Output Device
    // (right). The generator cluster moved down from Line 1's right side
    // (user request), landing directly left of the Output Device it plays
    // through -- the generator and its output routing now read as one
    // group, and Line 1 is purely analysis/view controls. The Appearance
    // selector that used to sit centered here moved to the View menu (ADR
    // 0005 addendum).
    private var line2: some View {
        HStack(spacing: 8) {
            inputDeviceControl
            Spacer(minLength: 0)
            SignalGeneratorControlView(engine: signalGenerator)
            outputDeviceControl
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
        let isDisconnected: Bool = {
            if case .disconnected = trackedFrequencyViewModel.connectionState { return true }
            return false
        }()
        // "CAPTURE UNAVAILABLE" (see AudioPipelineViewModel.isCaptureStalled):
        // capture is supposed to be running but the audio stack has stopped
        // delivering and the first watchdog restart didn't cure it --
        // distinct from DISCONNECTED (device gone from the system), which
        // takes priority since it's the more specific diagnosis. Same red
        // treatment as DISCONNECTED: both mean "this reading is dead."
        let isStalled = trackedFrequencyViewModel.isCaptureActive
            && trackedFrequencyViewModel.isCaptureStalled
        // "STARTING…" (amber, in-progress -- not a dead-reading red): shown
        // while a Start attempt is between pressing Start and the first hop,
        // so a slow coreaudiod start reads as "working on it," not a hang.
        let isStarting = trackedFrequencyViewModel.isCaptureStarting
        return HStack(spacing: 6) {
            LEDIndicator(isLit: true, color: isDisconnected || isStalled || trackedFrequencyViewModel.isMicAccessDenied ? theme.danger : (isStarting ? theme.warn : nil))
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
                Text(inputDeviceLabel.text)
                    .font(.system(size: Typography.controlSize, weight: .medium))
                    .foregroundStyle(inputDeviceLabel.color)
                    .lineLimit(1)
            }
            .fixedSize()

            // The device's hardware operating format (user request:
            // "indicate sample rate and bit depth near the input device")
            // -- dimmed data sub-caption, hidden while disconnected (the
            // format of a device that's gone is stale information, and the
            // DISCONNECTED indicator needs the room).
            if !isDisconnected, let format = trackedFrequencyViewModel.selectedInputDeviceFormat {
                Text(format.displayString)
                    .font(.system(size: Typography.subCaptionSize).monospacedDigit())
                    .foregroundStyle(theme.textFaint)
            }

            // Priority: DISCONNECTED (device gone -- the most specific
            // diagnosis) > MIC ACCESS DENIED (device present, OS forbids
            // capture; recovery is System Settings + Start) > CAPTURE
            // UNAVAILABLE (running but stalled). Denied and stalled can't
            // overlap in practice (denied means capture never started),
            // but the explicit ordering keeps the plate single-message.
            if isDisconnected {
                Text("DISCONNECTED")
                    .font(.system(size: Typography.controlSize, weight: .semibold))
                    .foregroundStyle(theme.danger)
            } else if trackedFrequencyViewModel.isMicAccessDenied {
                Text("MIC ACCESS DENIED")
                    .font(.system(size: Typography.controlSize, weight: .semibold))
                    .foregroundStyle(theme.danger)
            } else if isStalled {
                Text("CAPTURE UNAVAILABLE")
                    .font(.system(size: Typography.controlSize, weight: .semibold))
                    .foregroundStyle(theme.danger)
            } else if isStarting {
                // Below the three failure messages (a genuine failure mid-start
                // should win), amber not red: this is in-progress, not dead.
                Text("STARTING…")
                    .font(.system(size: Typography.controlSize, weight: .semibold))
                    .foregroundStyle(theme.warn)
            }
        }
        .consolePlate()
    }

    // Input Device plate label (ticket #23): while stopped, previews the
    // device a Start would capture from (dimmed) instead of the old alarming
    // "No Input Device"; only a genuine no-device / disconnected state shows
    // the honest empty message. See InputDevicePlateLabel.
    private var inputDeviceLabel: (text: String, color: Color) {
        switch trackedFrequencyViewModel.inputDevicePlateLabel {
        case .active(let name): return (name, theme.text)
        case .preview(let name): return (name, theme.textDim)
        case .unavailable: return ("No input device", theme.textFaint)
        }
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
            trackedFrequencyViewModel.toggleCapture()
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

    // FFT Size (user request, FFTWindowSize.swift): the frequency-vs-time
    // resolution tradeoff, made selectable rather than a fixed default --
    // finer resolution for hunting a low-frequency ring, faster response
    // for fast-moving material. A global, pipeline-wide setting like
    // Weighting/Time Averaging (not per-view, unlike bandingResolution's
    // placement in the graph zone), so it lives here in Line 1 too.
    // Changing it restarts capture under the hood if it was running (see
    // AudioPipelineViewModel.applyFFTWindowSizeChange) -- a heavier control
    // than Weighting/Time Averaging's simple hot-swap, but reads/writes the
    // same way from this view.
    private var fftWindowSizeControl: some View {
        HStack(spacing: 10) {
            Text("FFT SIZE")
                .font(.system(size: Typography.controlSize, weight: .medium))
                .foregroundStyle(theme.textDim)
            ForEach(FFTWindowSize.allCases) { option in
                fftWindowSizeButton(option)
            }
        }
        .consolePlate()
    }

    private func fftWindowSizeButton(_ option: FFTWindowSize) -> some View {
        let isSelected = trackedFrequencyViewModel.fftWindowSize == option
        return Button {
            trackedFrequencyViewModel.fftWindowSize = option
        } label: {
            HStack(spacing: 4) {
                LEDIndicator(isLit: isSelected)
                Text(option.label)
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
        .frame(width: 1120)
}
