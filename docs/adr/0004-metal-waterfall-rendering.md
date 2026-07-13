# Waterfall view renders with Metal, not SwiftUI Canvas

The scrolling waterfall is the app's primary view and redraws continuously at the UI publish rate (~30Hz) with a rolling 10-20s history — a performance-sensitive real-time visualization. We considered starting with SwiftUI `Canvas` (drawing new rows into an accumulated offscreen buffer, so per-frame cost stays low) and falling back to Metal only if that proved insufficient, but decided to commit to Metal from the start.

This is a bigger upfront investment (custom render pipeline instead of SwiftUI's built-in drawing) but avoids a costly rendering-layer rewrite later for a view this central to the app's value proposition, and gives more headroom for future additions (e.g. richer color mapping, higher-resolution history) without hitting a Canvas performance ceiling.
