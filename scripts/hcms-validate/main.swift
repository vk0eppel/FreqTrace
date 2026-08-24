import Foundation

// HCMS validation (ticket #37/#38): runs the PRODUCTION AnomalyDetector over
// the real HCMS dataset (58 clips of real music/speech driven into feedback,
// howling ramping up at t=8 s at the CSV's MSG frequency, 16 kHz) and reports
// the detection rate and clean-program false-alarm rate -- confirming the
// shipped detector reproduces the retune's ~55% detection at 0% false-alarm
// (docs/research/anomaly-hcms-validation.md).
//
// The detector takes the raw FFT spectrum + fullScalePower (it references to
// dBFS internally). This validates exactly what ships, not a prototype.
//
// Detection  = the MSG frequency flagged during the howl phase (>= t=8 s).
// False-alarm = fraction of clean-program hops (window entirely < 8 s) that
//               emit any candidate.

// 16 kHz config with ~43 ms hops, so the detector's duration-derived rise
// window (~800 ms) lands at the same frame count as at the app's 48 kHz.
let config = AnalysisConfig(sampleRate: 16000, windowSize: 2048, hopSize: 683)
let onsetSeconds = 8.0

func loadWavMono16(_ path: String) -> [Float]? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    let bytes = [UInt8](data)
    func u32(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o+1])<<8 | Int(bytes[o+2])<<16 | Int(bytes[o+3])<<24 }
    func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o+1])<<8 }
    guard bytes.count > 44, bytes[0]==0x52, bytes[1]==0x49, bytes[2]==0x46, bytes[3]==0x46 else { return nil }
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
    var out: [Float] = []; out.reserveCapacity((end - dataStart) / (2 * channels))
    var i = dataStart
    while i + 2*channels <= end {
        out.append(Float(Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i+1])<<8)) / 32768.0)
        i += 2 * channels
    }
    return out
}

func msgFrequency(csvPath: String) -> Double? {
    guard let txt = try? String(contentsOfFile: csvPath, encoding: .utf8) else { return nil }
    guard let last = txt.split(separator: "\n").filter({ !$0.isEmpty }).last else { return nil }
    let f = last.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard f.count >= 9, let hz = Double(f[8]) else { return nil }
    return hz
}

// Returns (detected?, cleanFlaggedHops, cleanHops) for one clip.
func score(samples: [Float], msgHz: Double, tracker: FrequencyTracker) -> (Bool, Int, Int) {
    let fsp = tracker.fullScalePower
    let binHz = config.sampleRate / Double(config.windowSize)
    let tol = max(msgHz * 0.03, 2 * binHz)
    var detector = AnomalyDetector()
    var window = [Float](repeating: 0, count: config.windowSize)
    let hopCount = max(0, samples.count / config.hopSize)
    let onsetSample = Int(onsetSeconds * config.sampleRate)
    var detected = false, cleanFlagged = 0, cleanHops = 0
    for hop in 0..<hopCount {
        window.removeFirst(config.hopSize)
        let start = hop * config.hopSize
        for i in 0..<config.hopSize { let idx = start+i; window.append(idx < samples.count ? samples[idx] : 0) }
        guard let mags = tracker.spectrum(in: window) else { continue }
        let cands = detector.process(magnitudes: mags, fullScalePower: fsp, config: config)
        let clean = (hop + 1) * config.hopSize <= onsetSample
        if clean { cleanHops += 1; if !cands.isEmpty { cleanFlagged += 1 } }
        if !clean, cands.contains(where: { abs($0.frequencyHz - msgHz) <= tol }) { detected = true }
    }
    return (detected, cleanFlagged, cleanHops)
}

// --- main ---
let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : (NSHomeDirectory() + "/hcms-data")
let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
let clips = files.filter { $0.hasSuffix(".wav") }.sorted()
guard !clips.isEmpty else { print("No .wav in \(dir) (run fetch.sh first)"); exit(1) }

let tracker = FrequencyTracker(config: config)
var detectedCount = 0, total = 0
var faSum = 0.0
for wav in clips {
    let base = (wav as NSString).deletingPathExtension
    guard let samples = loadWavMono16("\(dir)/\(wav)"), let msg = msgFrequency(csvPath: "\(dir)/\(base).csv") else { continue }
    let (detected, cf, ch) = score(samples: samples, msgHz: msg, tracker: tracker)
    total += 1
    if detected { detectedCount += 1 }
    if ch > 0 { faSum += Double(cf) / Double(ch) }
}
print("\n=== HCMS validation — PRODUCTION AnomalyDetector, \(total) clips ===")
print(String(format: "detection: %d/%d (%.1f%%)  |  clean-program false-alarm rate: %.2f%%",
             detectedCount, total, Double(detectedCount) / Double(total) * 100, faSum / Double(total) * 100))
print("(expected ~55% detection at ~0% false-alarm — see docs/research/anomaly-hcms-validation.md)")
