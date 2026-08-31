# FreqTrace

A real-time audio analysis tool for live sound environments. Visualize sounds, track frequencies, and identify resonances and feedback on the fly.

## Features

- **Real-time Spectrograph** — Live frequency spectrum visualization (scrolling waterfall + RTA)
- **Frequency Tracker** — Monitor and track the loudest frequency, resonances, and feedback candidates
- **SPL Meter** — Simple sound pressure level metering (A/C/Z weighting, Fast/Slow)
- **Signal Generator** — Generate test tones (sine) and pink/white noise

## Requirements

- **macOS 15 (Sequoia) or later**
- **Any Mac — Apple Silicon or Intel.** Releases ship as a universal binary.
- A microphone or audio input device (built-in mic, USB interface, aggregate device, etc.)

## Install

1. Download the latest `FreqTrace-vX.Y.Z-macos.zip` from the [**Releases**](https://github.com/vk0eppel/FreqTrace/releases/latest) page.
2. Double-click the `.zip` to unpack `FreqTrace.app`, then drag it into your **Applications** folder.
3. **First launch.** The app is signed for development but **not notarized by Apple**, so macOS Gatekeeper blocks it the first time. To open it anyway:
   - **Right-click** (or Control-click) `FreqTrace.app` → **Open**, then click **Open** in the dialog. macOS remembers your choice, so later launches are ordinary double-clicks.
   - If no **Open** button appears, clear the quarantine flag in Terminal and try again:
     ```
     xattr -dr com.apple.quarantine /Applications/FreqTrace.app
     ```
4. **Grant microphone access** when prompted — FreqTrace needs it to analyze live audio. If you miss the prompt, enable it later under **System Settings → Privacy & Security → Microphone**.

> **Heads up:** because these builds use an Apple *Development* certificate and aren't notarized, some Macs may refuse to open the app at all rather than just warn. If the steps above don't work, [build from source](#build-from-source) instead — a notarized, friction-free build is future work.

## Running

1. Launch FreqTrace and press **Start** (or the **Space** bar) to begin measuring.
2. Choose your input in the **Input Device** control (bottom-left). The waterfall and RTA fill in as audio arrives.
3. The big **Tracked Frequency** readout shows the loudest frequency in real time; flagged **Anomaly Candidates** highlight narrowband tones that are ringing up (feedback / resonance).
4. **Freeze** pauses the display for a closer look (capture keeps running); **Stop** halts capture entirely.

## Build from source

Requires **Xcode 16 or later**.

```
git clone https://github.com/vk0eppel/FreqTrace.git
cd FreqTrace
open FreqTrace.xcodeproj    # then press Cmd-R to build and run
```

Or from the command line:

```
xcodebuild -project FreqTrace.xcodeproj -scheme FreqTrace -destination 'platform=macOS' build
xcodebuild -project FreqTrace.xcodeproj -scheme FreqTrace -destination 'platform=macOS' test
```

## License

[GPLv3](LICENSE)
