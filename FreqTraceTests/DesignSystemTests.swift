//
//  DesignSystemTests.swift
//  FreqTraceTests
//

import CoreGraphics
import Testing
@testable import FreqTrace

struct DesignTokensTests {

    @Test func darkTokensMatchSpec() {
        let dark = DesignTokens.dark
        #expect(dark.bg == "#0b0d10")
        #expect(dark.surface == "#14171b")
        #expect(dark.text == "#e8ecef")
        #expect(dark.textFaint == "#7a8189")
        #expect(dark.accent == "#ffb84d")
        #expect(dark.danger == "#ff5a5a")
        #expect(dark.warn == "#ffcf5c")
        #expect(dark.border == "#262b31")
        #expect(dark.borderSoft == "#1e2227")
        #expect(dark.surfaceRaised == "#1b1f24")
    }

    @Test func lightTokensMatchSpec() {
        let light = DesignTokens.light
        #expect(light.bg == "#f4f5f6")
        #expect(light.surface == "#ffffff")
        #expect(light.text == "#14171b")
        #expect(light.textFaint == "#5c6167")
        #expect(light.accent == "#8f4d00")
        #expect(light.danger == "#c62f2f")
        #expect(light.warn == "#6e4e00")
        #expect(light.border == "#d7dbdf")
        #expect(light.borderSoft == "#e3e6e9")
        #expect(light.surfaceRaised == "#f7f8f9")
    }

    @Test func lightModeIsNotANaiveInversionOfDark() {
        // Regression guard for the bug caught during design review: an
        // earlier naive-inverted draft measured *worse* contrast than Dark
        // on these three tokens. Light must never regress back to those
        // failing values.
        let light = DesignTokens.light
        #expect(light.accent != "#c9770a")
        #expect(light.warn != "#a8790a")
        #expect(light.textFaint != "#9aa0a7")
    }

    @Test func tokensForModeReturnsCorrectSet() {
        #expect(DesignTokens.tokens(for: .dark).bg == DesignTokens.dark.bg)
        #expect(DesignTokens.tokens(for: .light).bg == DesignTokens.light.bg)
    }

    @Test func defaultAppearanceModeIsDark() {
        #expect(AppearanceMode.default == .dark)
    }
}

struct TypographyTests {

    @Test func scaleMatchesSpec() {
        #expect(Typography.heroSize == 64)
        #expect(Typography.secondarySize == 32)
        #expect(Typography.tertiarySize == 20)
        #expect(Typography.captionSize == 11)
        #expect(Typography.controlSize == 12)
        #expect(Typography.axisLabelSize == 10)
    }

    @Test func trackedFrequencyIsTheDeliberateVisualHero() {
        // Tracked Frequency (heroSize) must stay strictly larger than SPL
        // (secondarySize) and the Anomaly Candidate rows (tertiarySize) --
        // this hierarchy was a deliberate product decision, not incidental.
        #expect(Typography.heroSize > Typography.secondarySize)
        #expect(Typography.secondarySize > Typography.tertiarySize)
    }
}

struct LayoutMetricsTests {

    // 1280 is a measured value, not the wireframe-era 1120 estimate -- see
    // LayoutMetrics' header comment for the measurement method (screenshots
    // at candidate widths with capture running). If this test fails because
    // LayoutMetrics changed, re-measure; don't just update the number here.
    @Test func minimumWindowSizeMatchesDerivedEstimate() {
        #expect(LayoutMetrics.minWindowWidth == 1280)
        #expect(LayoutMetrics.minWindowHeight == 660)
    }
}
