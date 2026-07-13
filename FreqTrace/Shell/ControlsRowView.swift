//
//  ControlsRowView.swift
//  FreqTrace
//
//  Placeholder for the two-line Controls row (see CLAUDE.md Frontend):
//  Line 1 -- Weighting, Time Averaging, Peak/Freeze/Stop, Signal Generator.
//  Line 2 -- Input Device (left), Appearance Mode (center), Output Device
//  (right). Real controls land in later tickets; this establishes the
//  two-line structure and grouping so nothing needs to be re-laid-out later.
//

import SwiftUI

struct ControlsRowView: View {
    @Environment(\.theme) private var theme

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
            placeholderGroup("Weighting")
            placeholderGroup("Time Avg")
            placeholderGroup("Peak / Freeze / Stop")
            Spacer(minLength: 0)
            placeholderGroup("Signal Generator")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    private var line2: some View {
        HStack(spacing: 0) {
            placeholderGroup("Input Device")
            Spacer(minLength: 0)
            placeholderGroup("Appearance")
            Spacer(minLength: 0)
            placeholderGroup("Output Device")
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
}

#Preview {
    ControlsRowView()
        .environment(\.theme, Theme(mode: .dark))
        .frame(width: 1120)
}
