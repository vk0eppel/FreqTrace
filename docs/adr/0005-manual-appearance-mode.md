# Appearance Mode is manual (Dark/high-contrast Light), not tied to system appearance

FreqTrace is used in two lighting extremes that don't correlate with a user's general macOS preference: dim/dark venues (where a dark, saturated-color display is most readable) and direct sunlight/bright outdoor stages (where dark UIs wash out and glare, and a bright high-contrast display reads better). We decided to expose Appearance Mode as an explicit, manually-toggled control (in the Controls row) rather than following the system's light/dark appearance setting, and rather than trying to auto-detect ambient brightness (Macs don't expose a usable ambient light sensor for this).

This is a deliberate deviation from typical macOS conventions, where apps are expected to follow the system appearance. Dark is the default. A future auto-detection mechanism isn't ruled out, but isn't planned for v1.
