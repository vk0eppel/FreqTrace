import Foundation

// HCMS validator (ticket #37): scores the PrototypeAnomalyDetector against
// real howling-corrupted music/speech (KU Leuven HCMS, CC-BY-4.0). Each clip
// is 20 s at 16 kHz; the howling ramps up starting at t=8 s at the CSV's MSG
// frequency. We check: does the detector flag the MSG frequency after 8 s
// (and how fast), and does it false-flag during the clean 0-8 s program?
// Real FFT power is referenced to fullScalePower before the dBFS thresholds
// (the step #38 must do), exactly as the criteria require.

let config = AnalysisConfig(sampleRate: 16000, windowSize: 2048, hopSize: 683)
let onsetSeconds = 8.0

func loadWavMono16(_ path: String) -> [Float]? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    let bytes = [UInt8](data)
    func u32(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o+1])<<8 | Int(bytes[o+2])<<16 | Int(bytes[o+3])<<24 }
    func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o+1])<<8 }
    guard bytes.count > 44, bytes[0]==0x52, bytes[1]==0x49, bytes[2]==0x46, bytes[3]==0x46 else { return nil } // RIFF
    var o = 12, channels = 1, bits = 16
    var dataStart = -1, dataLen = 0
    while o + 8 <= bytes.count {
        let id = String(bytes: bytes[o..<o+4], encoding: .ascii) ?? ""
        let sz = u32(o+4)
        if id == "fmt " { channels = u16(o+10); bits = u16(o+22) }
        else if id == "data" { dataStart = o+8; dataLen = sz; break }
        o += 8 + sz + (sz & 1)
    }
    guard dataStart >= 0, bits == 16 else { return nil }
    let end = min(dataStart + dataLen, bytes.count)
    var out: [Float] = []
    out.reserveCapacity((end - dataStart) / (2 * channels))
    var i = dataStart
    while i + 2*channels <= end {
        let s = Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i+1])<<8)   // first channel
        out.append(Float(s) / 32768.0)
        i += 2 * channels
    }
    return out
}

func msgFrequency(csvPath: String) -> Double? {
    guard let txt = try? String(contentsOfFile: csvPath, encoding: .utf8) else { return nil }
    let lines = txt.split(separator: "\n").filter { !$0.isEmpty }
    guard let last = lines.last else { return nil }
    let f = last.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard f.count >= 9, let hz = Double(f[8]) else { return nil }
    return hz
}

struct ClipResult {
    let name: String
    let msgHz: Double
    let flaggedHop: Int?
    let cleanFalseFlag: Bool
    let latencyMs: Double?
    let peakMsgDbfs: Float
}

func score(samples: [Float], msgHz: Double, tracker: FrequencyTracker, params: PrototypeParams) -> (Int?, Bool, Float) {
    let fsp = tracker.fullScalePower
    let binHz = config.sampleRate / Double(config.windowSize)
    let msgBin = Int((msgHz / binHz).rounded())
    let tol = max(msgHz * 0.03, 2 * binHz)
    var detector = PrototypeAnomalyDetector(params: params)
    var window = [Float](repeating: 0, count: config.windowSize)
    let hopCount = max(0, samples.count / config.hopSize)
    var flaggedHop: Int?
    var cleanFalseFlag = false
    var peakMsg: Float = -200
    let onsetSample = Int(onsetSeconds * config.sampleRate)
    for hop in 0..<hopCount {
        window.removeFirst(config.hopSize)
        let start = hop * config.hopSize
        for i in 0..<config.hopSize { let idx = start+i; window.append(idx < samples.count ? samples[idx] : 0) }
        guard var mags = tracker.spectrum(in: window) else { continue }
        // Reference raw FFT power to full-scale -> the dBFS domain the thresholds expect.
        for i in 0..<mags.count { mags[i] = fsp > 0 ? mags[i] / fsp : mags[i] }
        if msgBin > 0 && msgBin < mags.count {
            peakMsg = max(peakMsg, MagnitudeScaling.decibels(power: mags[msgBin]))
        }
        let cands = detector.process(magnitudes: mags, config: config)
        let windowEndsBeforeOnset = (hop + 1) * config.hopSize <= onsetSample
        if !cands.isEmpty && windowEndsBeforeOnset { cleanFalseFlag = true }
        if flaggedHop == nil, cands.contains(where: { abs($0.frequencyHz - msgHz) <= tol }) {
            flaggedHop = hop
        }
    }
    return (flaggedHop, cleanFalseFlag, peakMsg)
}

// --- main ---
let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : (NSHomeDirectory() + "/hcms-data")
let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
let clips = files.filter { $0.hasSuffix(".wav") }.sorted()
guard !clips.isEmpty else { print("No .wav in \(dir)"); exit(1) }

let tracker = FrequencyTracker(config: config)
var results: [ClipResult] = []
for wav in clips {
    let base = (wav as NSString).deletingPathExtension
    guard let samples = loadWavMono16("\(dir)/\(wav)"),
          let msg = msgFrequency(csvPath: "\(dir)/\(base).csv") else { print("skip \(wav)"); continue }
    let (hop, clean, peak) = score(samples: samples, msgHz: msg, tracker: tracker, params: .tuned)
    let lat: Double? = hop.map { Double(($0 + 1) * config.hopSize) / config.sampleRate * 1000 - onsetSeconds * 1000 }
    results.append(ClipResult(name: base, msgHz: msg, flaggedHop: hop, cleanFalseFlag: clean, latencyMs: lat, peakMsgDbfs: peak))
}

print("\n=== HCMS validation — PrototypeParams.tuned, 16 kHz/2048/683 ===")
print("clip                  MSG Hz  flagged  latency(from 8s)  clean-FP  peak MSG dBFS")
for r in results {
    let flagged = r.flaggedHop != nil ? "yes" : "NO"
    let lat = r.latencyMs.map { String(format: "%+.0f ms", $0) } ?? "--"
    print(r.name.padding(toLength: 20, withPad: " ", startingAt: 0)
        + String(format: " %7.1f  %-7@  %-16@  %-8@  %6.1f", r.msgHz, flagged as NSString, lat as NSString, (r.cleanFalseFlag ? "FLAG" : "clean") as NSString, r.peakMsgDbfs))
}
let flaggedCount = results.filter { $0.flaggedHop != nil }.count
let cleanFP = results.filter { $0.cleanFalseFlag }.count
print(String(format: "\nflagged %d/%d | clean-program false-flags %d/%d | peak MSG level %.1f..%.1f dBFS",
             flaggedCount, results.count, cleanFP, results.count,
             results.map { $0.peakMsgDbfs }.min() ?? 0, results.map { $0.peakMsgDbfs }.max() ?? 0))

// Load all clips once, then sweep parameter variants to see what recovers
// detection on real, quiet, program-embedded howling.
struct Clip { let samples: [Float]; let msg: Double }
var loaded: [Clip] = []
for wav in clips {
    let base = (wav as NSString).deletingPathExtension
    if let s = loadWavMono16("\(dir)/\(wav)"), let m = msgFrequency(csvPath: "\(dir)/\(base).csv") {
        loaded.append(Clip(samples: s, msg: m))
    }
}
func sweep(_ label: String, _ p: PrototypeParams) {
    var flagged = 0, cleanFP = 0
    for c in loaded {
        let (hop, clean, _) = score(samples: c.samples, msgHz: c.msg, tracker: tracker, params: p)
        if hop != nil { flagged += 1 }
        if clean { cleanFP += 1 }
    }
    print("  " + label.padding(toLength: 44, withPad: " ", startingAt: 0)
        + "flagged \(flagged)/\(loaded.count)  clean-FP \(cleanFP)/\(loaded.count)")
}
print("\n=== parameter sweep on real HCMS ===")
sweep("tuned (floor -25, rise 6, hot -6, gate on)", .tuned)
var f35 = PrototypeParams.tuned; f35.detectFloorDb = -35; sweep("floor -35", f35)
var f45 = PrototypeParams.tuned; f45.detectFloorDb = -45; sweep("floor -45", f45)
var f45r4 = f45; f45r4.riseThresholdDb = 4; sweep("floor -45, rise 4", f45r4)
var f45r3 = f45; f45r3.riseThresholdDb = 3; sweep("floor -45, rise 3", f45r3)
var f45r3g = f45r3; f45r3g.harmonicGateEnabled = false; sweep("floor -45, rise 3, harmonic gate OFF", f45r3g)
print("  --- Sabine harmonic margin (vs binary gate) ---")
for margin: Float in [6, 10, 15, 20, 33] {
    var p = f45r3; p.harmonicMarginDb = margin
    sweep("floor -45, rise 3, Sabine margin \(Int(margin)) dB", p)
}
// best margin, tighter rise/floor combos
for (fl, ri, mg) in [(-40, 4, 10), (-40, 6, 10), (-35, 4, 15), (-45, 3, 15)] as [(Float,Float,Float)] {
    var p = PrototypeParams.tuned; p.detectFloorDb = fl; p.riseThresholdDb = ri; p.harmonicMarginDb = mg
    sweep("floor \(Int(fl)), rise \(Int(ri)), Sabine \(Int(mg)) dB", p)
}
