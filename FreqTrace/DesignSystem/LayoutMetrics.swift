//
//  LayoutMetrics.swift
//  FreqTrace
//
//  Minimum window size is derived from the widest Controls row line at the
//  Typography scale, not picked arbitrarily -- see CLAUDE.md "Window".
//  Re-derive if the Controls row's contents change.
//

import CoreGraphics

enum LayoutMetrics {
    static let minWindowWidth: CGFloat = 1120
    static let minWindowHeight: CGFloat = 570
}
