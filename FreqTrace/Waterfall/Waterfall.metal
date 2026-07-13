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
//  The color ramp below must match FreqTrace/Waterfall/WaterfallColorMap.swift's
//  `dark` stops exactly -- MSL can't call back into Swift, so if the ramp
//  changes (see CLAUDE.md "Waterfall Color Maps"), both places need
//  updating together.
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
    float scrollOffset;
    float minHz;
    float maxHz;
    float binResolutionHz;
    float columnCount;
};

constant float3 kColorStops[6] = {
    float3(0x0b, 0x0d, 0x10) / 255.0, // silence
    float3(0x2b, 0x11, 0x50) / 255.0,
    float3(0x7c, 0x1c, 0x62) / 255.0,
    float3(0xc3, 0x3b, 0x3a) / 255.0,
    float3(0xe8, 0x75, 0x2b) / 255.0,
    float3(0xff, 0xd1, 0x66) / 255.0, // loudest
};
constant float kColorStopPositions[6] = { 0.0, 0.2, 0.4, 0.6, 0.8, 1.0 };

static float3 waterfallColor(float t) {
    t = clamp(t, 0.0, 1.0);
    for (int i = 0; i < 5; i++) {
        float a = kColorStopPositions[i];
        float b = kColorStopPositions[i + 1];
        if (t >= a && t <= b) {
            float localT = (b > a) ? (t - a) / (b - a) : 0.0;
            return mix(kColorStops[i], kColorStops[i + 1], localT);
        }
    }
    return kColorStops[5];
}

fragment float4 waterfall_fragment(VertexOut in [[stage_in]],
                                    texture2d<float, access::sample> spectrumTexture [[texture(0)]],
                                    constant WaterfallUniforms &uniforms [[buffer(0)]]) {
    // u (frequency axis) clamps at the edges; v (time axis) wraps, since
    // the texture is a circular buffer of history rows -- one sampler,
    // different address modes per axis.
    constexpr sampler s(coord::normalized, s_address::clamp_to_edge, t_address::repeat, filter::linear);

    // Log-frequency remap: screen-space in.uv.x (0=20Hz, 1=20kHz) -> the
    // linear FFT bin column that frequency actually lives in. Matches
    // FrequencyAxis.hz(atNormalizedPosition:) on the Swift side.
    float freq = uniforms.minHz * pow(uniforms.maxHz / uniforms.minHz, in.uv.x);
    float binIndex = freq / uniforms.binResolutionHz;
    float texU = clamp(binIndex / uniforms.columnCount, 0.0, 1.0);

    // Scrolling: see WaterfallHistoryBuffer.scrollOffset's doc comment for
    // the derivation -- a fixed texture row's content moves toward
    // increasing v (upward) as scrollOffset advances over time.
    float texV = fract((1.0 - in.uv.y) + uniforms.scrollOffset);

    float magnitude = spectrumTexture.sample(s, float2(texU, texV)).r;
    return float4(waterfallColor(magnitude), 1.0);
}
