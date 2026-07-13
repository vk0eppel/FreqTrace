//
//  Typography.swift
//  FreqTrace
//
//  Scale from CLAUDE.md's "Typography scale" table. Tracked Frequency
//  (heroSize) is the deliberate visual hero of the app -- see
//  TrackedFrequencyIsTheDeliberateVisualHero test.
//

import CoreGraphics

enum Typography {
    static let heroSize: CGFloat = 64        // Tracked Frequency
    static let secondarySize: CGFloat = 32   // SPL
    static let tertiarySize: CGFloat = 20    // Anomaly Candidate rows
    static let captionSize: CGFloat = 11     // Section captions
    static let controlSize: CGFloat = 12     // Controls row
    static let axisLabelSize: CGFloat = 10   // Waterfall axis labels
    static let subCaptionSize: CGFloat = 11  // Data sub-captions
}
