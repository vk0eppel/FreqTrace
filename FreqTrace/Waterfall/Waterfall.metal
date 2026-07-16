//
//  Waterfall.metal
//  FreqTrace
//
//  Renders the scrolling spectrogram (ticket #8, ADR 0004) from a linear-
//  frequency-bin texture (one row per FFT hop, R32Float normalized
//  magnitude). Both the log-frequency axis remap and the magnitude->color
//  mapping happen here per-pixel rather than being precomputed on the CPU
//  -- resampling ~2000 columns x ~350 rows per frame on the CPU would be
//  far more expensive than doing it once per screen pixel on the GPU.
//
//  The color ramps below must match FreqTrace/Waterfall/WaterfallColorMap.swift's
//  `dark`/`light` stops exactly -- MSL can't call back into Swift, so if
//  either ramp changes (see CLAUDE.md "Waterfall Color Maps"), both places
//  need updating together. isLightMode (ticket #10) selects which ramp
//  waterfallColor samples from.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Full-screen quad via a triangle strip -- no vertex buffer needed.
vertex VertexOut waterfall_vertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[4] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1)
    };
    // uv.y = 0 at the bottom (screen-space "now"), 1 at the top (oldest) --
    // matches CLAUDE.md "new data enters at the bottom, scrolls up."
    constexpr float2 uvs[4] = {
        float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1)
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0, 1);
    out.uv = uvs[vertexID];
    return out;
}

struct WaterfallUniforms {
    /// Continuous, smoothly-eased position (in fractional row units) of the
    /// newest row (ticket #15, user report: "scroll ... stops sometimes and
    /// then updates", then "still lagging"/"regularly repeated, 2-3 times a
    /// second"). Two earlier approaches tried to *predict* when the next
    /// hop would land (from a fixed theoretical duration, then a measured
    /// one); real hop delivery turned out to arrive in a repeating
    /// deterministic pattern (not jitter around a mean), which any
    /// prediction guesses wrong on every single hop -- freezing when it
    /// undershoots, snapping forward when it overshoots. WaterfallRenderer.
    /// displayedRowPosition instead continuously eases toward whichever row
    /// is *actually* newest, never predicting the future, so every frame
    /// produces genuine smooth motion at the cost of a small constant
    /// (not jittery) display lag.
    float newestRowContinuous;
    /// Matches WaterfallRenderer.draw's `maxLagRows` -- reserved as extra
    /// guard margin below so the seam-avoidance window's far edge never
    /// reaches into rows the circular buffer has already overwritten (bug
    /// fix, user report: "the line on top ... is back and bigger than
    /// before" -- displayRowSpan below used to assume newestRowContinuous
    /// *was* the true newest row; once it started lagging behind by design,
    /// the window's far edge started reading already-overwritten rows).
    float maxLagRows;
    float rowCount;
    float minHz;
    float maxHz;
    float binResolutionHz;
    float columnCount;
    float isLightMode;
};

constant float3 kDarkColorStops[6] = {
    float3(0x0b, 0x0d, 0x10) / 255.0, // silence
    float3(0x2b, 0x11, 0x50) / 255.0,
    float3(0x7c, 0x1c, 0x62) / 255.0,
    float3(0xc3, 0x3b, 0x3a) / 255.0,
    float3(0xe8, 0x75, 0x2b) / 255.0,
    float3(0xff, 0xd1, 0x66) / 255.0, // loudest
};
constant float3 kLightColorStops[6] = {
    float3(0xf4, 0xf5, 0xf6) / 255.0, // silence
    float3(0xbc, 0xd6, 0xf2) / 255.0,
    float3(0x6f, 0x9f, 0xe0) / 255.0,
    float3(0x39, 0x59, 0x9e) / 255.0,
    float3(0x5a, 0x2e, 0x6b) / 255.0,
    float3(0x2a, 0x0e, 0x33) / 255.0, // loudest
};
constant float kColorStopPositions[6] = { 0.0, 0.2, 0.4, 0.6, 0.8, 1.0 };

static float3 waterfallColor(float t, bool isLightMode) {
    t = clamp(t, 0.0, 1.0);
    for (int i = 0; i < 5; i++) {
        float a = kColorStopPositions[i];
        float b = kColorStopPositions[i + 1];
        if (t >= a && t <= b) {
            float localT = (b > a) ? (t - a) / (b - a) : 0.0;
            return isLightMode
                ? mix(kLightColorStops[i], kLightColorStops[i + 1], localT)
                : mix(kDarkColorStops[i], kDarkColorStops[i + 1], localT);
        }
    }
    return isLightMode ? kLightColorStops[5] : kDarkColorStops[5];
}

fragment float4 waterfall_fragment(VertexOut in [[stage_in]],
                                    texture2d<float, access::sample> spectrumTexture [[texture(0)]],
                                    constant WaterfallUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, s_address::clamp_to_edge, t_address::clamp_to_edge, filter::linear);

    // Log-frequency remap: screen-space in.uv.x (0=20Hz, 1=20kHz) -> the
    // linear FFT bin column that frequency actually lives in. Matches
    // FrequencyAxis.hz(atNormalizedPosition:) on the Swift side.
    float freq = uniforms.minHz * pow(uniforms.maxHz / uniforms.minHz, in.uv.x);
    float binIndex = freq / uniforms.binResolutionHz;
    float texU = clamp(binIndex / uniforms.columnCount, 0.0, 1.0);

    // Scrolling (ticket #15 rewrite -- bug fix, user report: "a thin
    // horizontal strip of waterfall color content ... flickers at the very
    // top edge"). The old scheme sampled the texture's time axis as one
    // full loop of the circular buffer (`fract((1-uv.y)+scrollOffset)`),
    // which forces uv.y=0 ("now") and uv.y=1 ("oldest") to resolve to the
    // exact same interpolation point -- and that point always landed
    // exactly on a texel boundary, so linear filtering blended the
    // brand-new row 50/50 with the unrelated row from ~15s ago every single
    // frame. Fixed by walking backward from the newest row (uniforms.
    // newestRowContinuous, itself a smoothly-eased float -- see
    // WaterfallRenderer.displayedRowPosition) by up to displayRowSpan row
    // units, which never wraps back onto the newest row itself, so there's
    // no seam to blend across at all.
    float rowCount = max(uniforms.rowCount, 1.0);
    float displayRowSpan = max(rowCount - 1.0 - max(uniforms.maxLagRows, 0.0), 1.0);
    float rowFloat = clamp(
        uniforms.newestRowContinuous - in.uv.y * displayRowSpan,
        uniforms.newestRowContinuous - displayRowSpan,
        uniforms.newestRowContinuous
    );
    float rowFloorF = floor(rowFloat);
    float frac = rowFloat - rowFloorF;

    int rowCountI = int(rowCount);
    int rowNear = ((int(rowFloorF) % rowCountI) + rowCountI) % rowCountI;
    int rowFar = (((int(rowFloorF) - 1) % rowCountI) + rowCountI) % rowCountI;

    // Sampled at each row's exact texel center so the hardware sampler
    // contributes zero weight from its vertical neighbor -- linear
    // filtering still applies normally on the U (frequency) axis. Note
    // rowFar can reference a not-yet-written (or wrapped-onto-newest) row
    // right at rowFloat's extremes, but frac lands at exactly 0 there, so
    // it always carries zero weight in the mix below.
    float2 uvNear = float2(texU, (float(rowNear) + 0.5) / rowCount);
    float2 uvFar = float2(texU, (float(rowFar) + 0.5) / rowCount);
    float mNear = spectrumTexture.sample(s, uvNear).r;
    float mFar = spectrumTexture.sample(s, uvFar).r;
    float magnitude = mix(mNear, mFar, frac);

    return float4(waterfallColor(magnitude, uniforms.isLightMode > 0.5), 1.0);
}
