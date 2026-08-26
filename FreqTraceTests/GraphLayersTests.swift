//
//  GraphLayersTests.swift
//  FreqTraceTests
//
//  Exercises GraphLayers.toggling(_:) -- the one piece of real logic behind
//  the independent Waterfall/RTA layer toggles (issue #45). The guarantee
//  worth locking down is the at-least-one-on guard: turning off the only
//  lit layer is a no-op, so the graph is never blank while capture runs.
//

import Testing
@testable import FreqTrace

struct GraphLayersTests {

    @Test func togglingOnAddsTheLayer() {
        #expect(GraphLayers.waterfall.toggling(.rta) == [.waterfall, .rta])
        #expect(GraphLayers.rta.toggling(.waterfall) == [.waterfall, .rta])
    }

    @Test func togglingOffRemovesWhenAnotherLayerRemains() {
        let both: GraphLayers = [.waterfall, .rta]
        #expect(both.toggling(.rta) == .waterfall)
        #expect(both.toggling(.waterfall) == .rta)
    }

    @Test func togglingOffTheLastLayerIsANoOp() {
        #expect(GraphLayers.waterfall.toggling(.waterfall) == .waterfall)
        #expect(GraphLayers.rta.toggling(.rta) == .rta)
    }

    @Test func presentationFlagsDistinguishStandaloneFromOverlay() {
        #expect(GraphLayers.rta.showsStandaloneRTA)
        #expect(!GraphLayers.rta.showsOverlayRTA)

        let both: GraphLayers = [.waterfall, .rta]
        #expect(both.showsOverlayRTA)
        #expect(!both.showsStandaloneRTA)
        #expect(both.showsWaterfall)
        #expect(both.showsRTA)

        #expect(GraphLayers.waterfall.showsWaterfall)
        #expect(!GraphLayers.waterfall.showsRTA)
    }

    @Test func everyCombinationIsReachableByToggling() {
        var layers: GraphLayers = .waterfall          // default: waterfall only
        layers = layers.toggling(.rta)                // -> both
        #expect(layers == [.waterfall, .rta])
        layers = layers.toggling(.waterfall)          // -> rta only
        #expect(layers == .rta)
        layers = layers.toggling(.waterfall)          // -> both
        #expect(layers == [.waterfall, .rta])
        layers = layers.toggling(.rta)                // -> waterfall only
        #expect(layers == .waterfall)
    }
}
