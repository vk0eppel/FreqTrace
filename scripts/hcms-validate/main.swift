import Foundation

// HCMS retune (ticket #37): a grid sweep of the anomaly criteria against the
// real HCMS dataset (58 clips, real music/speech driven into feedback, howling
// ramping up at t=8 s at the CSV's MSG frequency, 16 kHz). Finds the achievable
// detection-vs-false-alarm frontier, sweeping FFT config, rise timing, floor,
// and the Sabine harmonic-isolation margin. Real FFT power is referenced to
// FrequencyTracker.fullScalePower before the dBFS thresholds (the step #38
// must do).
//
// Detection = the MSG frequency flagged during the howl phase (>= t=8 s).
// False-alarm RATE = fraction of clean-program hops (window entirely < 8 s)
// that emit any candidate -- a rate, not the earlier harsh "any flag = fail",
// so an occasional flag on an ambiguous sustained note isn't a whole-clip fail.

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

// One clip's per-hop normalized (dBFS-referenced) spectra at a given config,
// plus where the MSG bin is and which hops are clean vs. howl.
struct PreparedClip {
    let spectra: [[Float]]
    let msgHz: Double
    let cleanHops: Int       // hops whose window is entirely before onset
    let onsetHop: Int        // first hop whose window reaches onset
}

func prepare(samples: [Float], msgHz: Double, config: AnalysisConfig, tracker: FrequencyTracker) -> PreparedClip {
    let fsp = tracker.fullScalePower
    var window = [Float](repeating: 0, count: config.windowSize)
    let hopCount = max(0, samples.count / config.hopSize)
    var spectra: [[Float]] = []; spectra.reserveCapacity(hopCount)
    let onsetSample = Int(onsetSeconds * config.sampleRate)
    var cleanHops = 0, onsetHop = hopCount
    for hop in 0..<hopCount {
        window.removeFirst(config.hopSize)
        let start = hop * config.hopSize
        for i in 0..<config.hopSize { let idx = start+i; window.append(idx < samples.count ? samples[idx] : 0) }
        var mags = tracker.spectrum(in: window) ?? [Float](repeating: 0, count: config.windowSize/2)
        if fsp > 0 { for i in 0..<mags.count { mags[i] /= fsp } }
        spectra.append(mags)
        let windowEnd = (hop + 1) * config.hopSize
        if windowEnd <= onsetSample { cleanHops += 1 }
        if windowEnd > onsetSample && onsetHop == hopCount { onsetHop = hop }
    }
    return PreparedClip(spectra: spectra, msgHz: msgHz, cleanHops: cleanHops, onsetHop: onsetHop)
}

// Returns (detected?, cleanFlaggedHops) for one prepared clip + params.
func evaluate(_ clip: PreparedClip, config: AnalysisConfig, params: PrototypeParams) -> (Bool, Int) {
    let binHz = config.sampleRate / Double(config.windowSize)
    let tol = max(clip.msgHz * 0.03, 2 * binHz)
    var det = PrototypeAnomalyDetector(params: params)
    var detected = false, cleanFlagged = 0
    for (hop, mags) in clip.spectra.enumerated() {
        let cands = det.process(magnitudes: mags, config: config)
        if hop < clip.cleanHops, !cands.isEmpty { cleanFlagged += 1 }
        if hop >= clip.onsetHop, cands.contains(where: { abs($0.frequencyHz - clip.msgHz) <= tol }) { detected = true }
    }
    return (detected, cleanFlagged)
}

func baseParams(floorDb: Float, riseWindowHops: Int, riseDb: Float, margin: Float?) -> PrototypeParams {
    var p = PrototypeParams.tuned
    p.detectFloorDb = floorDb
    p.riseWindowHops = max(2, riseWindowHops)
    p.riseThresholdDb = riseDb
    p.harmonicMarginDb = margin      // nil = binary gate
    p.hotThresholdDb = -6            // unreachable on HCMS; rise gate does the work
    return p
}

// --- main ---
let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : (NSHomeDirectory() + "/hcms-data")
let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
let clipNames = files.filter { $0.hasSuffix(".wav") }.sorted()
guard !clipNames.isEmpty else { print("No .wav in \(dir)"); exit(1) }

struct Raw { let samples: [Float]; let msg: Double }
var raws: [Raw] = []
for wav in clipNames {
    let base = (wav as NSString).deletingPathExtension
    if let s = loadWavMono16("\(dir)/\(wav)"), let m = msgFrequency(csvPath: "\(dir)/\(base).csv") {
        raws.append(Raw(samples: s, msg: m))
    }
}
print("Loaded \(raws.count) HCMS clips from \(dir)\n")

struct Result { let label: String; let det: Double; let faRate: Double }

let configs: [(String, AnalysisConfig)] = [
    ("win2048/hop683 (128ms/43ms)", AnalysisConfig(sampleRate: 16000, windowSize: 2048, hopSize: 683)),
    ("win4096/hop683 (256ms/43ms)", AnalysisConfig(sampleRate: 16000, windowSize: 4096, hopSize: 683)),
    ("win4096/hop1024 (256ms/64ms)", AnalysisConfig(sampleRate: 16000, windowSize: 4096, hopSize: 1024)),
]
let floors: [Float] = [-45, -40, -35]
let riseMs: [Double] = [300, 500, 800]
let riseDbs: [Float] = [3, 4, 6]
let margins: [Float?] = [nil, 10, 15, 20, 33]

var all: [Result] = []
for (cfgLabel, config) in configs {
    let tracker = FrequencyTracker(config: config)
    let hopMs = Double(config.hopSize) / config.sampleRate * 1000
    let prepared = raws.map { prepare(samples: $0.samples, msgHz: $0.msg, config: config, tracker: tracker) }
    let n = Double(prepared.count)
    for floor in floors {
        for rMs in riseMs {
            let rHops = Int((rMs / hopMs).rounded())
            for rDb in riseDbs {
                for margin in margins {
                    let p = baseParams(floorDb: floor, riseWindowHops: rHops, riseDb: rDb, margin: margin)
                    var detCount = 0.0, faSum = 0.0
                    for clip in prepared {
                        let (d, cf) = evaluate(clip, config: config, params: p)
                        if d { detCount += 1 }
                        if clip.cleanHops > 0 { faSum += Double(cf) / Double(clip.cleanHops) }
                    }
                    let mg = margin.map { "Sab\(Int($0))" } ?? "binary"
                    let label = "\(cfgLabel) floor\(Int(floor)) rise\(Int(rMs))ms/\(Int(rDb))dB \(mg)"
                    all.append(Result(label: label, det: detCount / n * 100, faRate: faSum / n * 100))
                }
            }
        }
    }
}

// Frontier: best detection achievable at each false-alarm-rate ceiling.
print("=== achievable detection vs. clean-program false-alarm rate (all 58 clips) ===")
for faCap in [0.0, 0.5, 1.0, 2.0, 5.0, 10.0] {
    let eligible = all.filter { $0.faRate <= faCap + 1e-9 }
    if let best = eligible.max(by: { $0.det < $1.det }) {
        print(String(format: "FA <= %4.1f%%  ->  best detection %5.1f%%  (FA %.2f%%)  |  %@",
                     faCap, best.det, best.faRate, best.label as NSString))
    } else {
        print(String(format: "FA <= %4.1f%%  ->  (no combo)", faCap))
    }
}
let bestDet = all.max(by: { $0.det < $1.det })!
print(String(format: "\nabsolute max detection: %.1f%% (FA %.2f%%)  |  %@", bestDet.det, bestDet.faRate, bestDet.label as NSString))
