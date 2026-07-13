//
//  WaterfallZoneView.swift
//  FreqTrace
//
//  Placeholder for the dominant Waterfall/RTA zone. Real Metal rendering
//  (ADR 0004) and the RTA toggle land in later tickets; this establishes
//  the zone's position and sizing in the shell.
//

import SwiftUI

struct WaterfallZoneView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.surface
            Text("Waterfall / RTA")
                .font(.system(size: Typography.controlSize, weight: .medium))
                .foregroundStyle(theme.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WaterfallZoneView()
        .environment(\.theme, Theme(mode: .dark))
        .frame(width: 900, height: 340)
}
