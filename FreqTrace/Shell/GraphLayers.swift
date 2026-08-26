//
//  GraphLayers.swift
//  FreqTrace
//
//  Which layers the Waterfall/RTA zone is currently showing (issue #45).
//  The waterfall and the RTA are independent on/off layers rather than a
//  mutually-exclusive pick: either one alone, or both at once -- the
//  combined view, where the RTA is drawn as a floating dB curve over the
//  scrolling waterfall (treatment B). "Combined" is not a separate mode,
//  just both layers lit.
//
//  At least one layer is always shown, so the graph is never blank while
//  capture is running; `toggling(_:)` is the guard -- turning off the only
//  lit layer is a no-op. This is the one piece of real logic here, and the
//  test seam (GraphLayersTests).
//
//  Pure value type, nonisolated per the module convention (read from view
//  state and from nonisolated unit tests alike).
//

nonisolated struct GraphLayers: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let waterfall = GraphLayers(rawValue: 1 << 0)
    static let rta = GraphLayers(rawValue: 1 << 1)

    /// Toggle one layer on/off, but never clear the last remaining layer:
    /// turning a layer *off* when it's the only one lit returns `self`
    /// unchanged (the at-least-one-on guard). Turning a layer *on* is always
    /// allowed. To "switch" from one sole layer to the other, turn the other
    /// on first, then the first off.
    func toggling(_ layer: GraphLayers) -> GraphLayers {
        guard contains(layer) else { return union(layer) }
        let remaining = subtracting(layer)
        return remaining.isEmpty ? self : remaining
    }

    var showsWaterfall: Bool { contains(.waterfall) }
    var showsRTA: Bool { contains(.rta) }

    /// RTA as its standalone bar chart -- only when it's the sole layer.
    var showsStandaloneRTA: Bool { contains(.rta) && !contains(.waterfall) }

    /// RTA as the floating dB curve over the waterfall (treatment B) -- when
    /// both layers are lit. Same underlying data as the standalone bars, a
    /// different rendering.
    var showsOverlayRTA: Bool { contains(.rta) && contains(.waterfall) }
}
