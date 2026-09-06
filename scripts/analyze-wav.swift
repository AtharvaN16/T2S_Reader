#!/usr/bin/env swift
// Measures what a listener describes — flat pitch, dead air, clicks — on the WAVs the audio probe
// writes (scripts/audio-probe.sh), so two renders of the same passage can be compared by number.
// Usage: swift scripts/analyze-wav.swift spikes/findings/audio-probe/*.wav
//
// Per file: duration; voiced fraction; F0 median, spread (standard deviation in semitones) and
// 5th–95th percentile range — a monotone voice has a small spread; pauses (quiet stretches of
// 150 ms or more) with their lengths; impulses (a sample at least six times the RMS of its own
// 40 ms neighbourhood and above -20 dBFS) — clicks the decoder or the post-processing leaves.
import AVFoundation
import Foundation

func samples(of url: URL) throws -> ([Float], Int) {
    let file = try AVAudioFile(forReading: url)
    let rate = Int(file.processingFormat.sampleRate)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 1),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw NSError(domain: "analyze", code: 1)
    }
    try file.read(into: buffer)
    return (Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))), rate)
}

func rms(_ x: ArraySlice<Float>) -> Float {
    guard !x.isEmpty else { return 0 }
    var sum: Float = 0
    for v in x { sum += v * v }
    return (sum / Float(x.count)).squareRoot()
}

/// Normalised autocorrelation pitch per 40 ms frame, 10 ms hop, 60–400 Hz.
func pitchTrack(_ x: [Float], rate: Int) -> (f0: [Float], voicedFraction: Double) {
    let frame = rate * 40 / 1000, hop = rate / 100
    let minLag = rate / 400, maxLag = rate / 60
    var f0s: [Float] = []
    var frames = 0
    var i = 0
    while i + frame + maxLag < x.count {
        frames += 1
        let seg = x[i ..< i + frame]
        let energy = rms(seg)
        if energy > 0.01 {
            var best: Float = 0, bestLag = 0
            var e0: Float = 0
            for k in 0 ..< frame { e0 += x[i + k] * x[i + k] }
            for lag in minLag ... maxLag {
                var c: Float = 0, e1: Float = 0
                for k in 0 ..< frame {
                    c += x[i + k] * x[i + k + lag]
                    e1 += x[i + k + lag] * x[i + k + lag]
                }
                let n = c / max(1e-9, (e0 * e1).squareRoot())
                if n > best { best = n; bestLag = lag }
            }
            if best > 0.7 { f0s.append(Float(rate) / Float(bestLag)) }
        }
        i += hop
    }
    return (f0s, frames == 0 ? 0 : Double(f0s.count) / Double(frames))
}

func semitones(_ f: Float, ref: Float) -> Double { 12 * log2(Double(f) / Double(ref)) }

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let (x, rate) = try? samples(of: url) else { print("\(path): unreadable"); continue }
    let duration = Double(x.count) / Double(rate)

    // Pauses: 10 ms windows under -50 dBFS, runs of 15+.
    let win = rate / 100
    var quiet: [Bool] = []
    var j = 0
    while j + win <= x.count { quiet.append(rms(x[j ..< j + win]) < 0.00316); j += win }
    var pauses: [Int] = []
    var run = 0
    for q in quiet { if q { run += 1 } else { if run >= 15 { pauses.append(run * 10) }; run = 0 } }
    if run >= 15 { pauses.append(run * 10) }

    // Impulses.
    let half = rate * 20 / 1000
    var impulses = 0
    var k = half
    while k < x.count - half {
        let v = abs(x[k])
        if v > 0.1 {
            let local = rms(x[k - half ..< k + half])
            if v > 6 * local { impulses += 1; k += half }   // one count per neighbourhood
        }
        k += 1
    }

    let (f0, voiced) = pitchTrack(x, rate: rate)
    let sorted = f0.sorted()
    let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    let st = f0.map { semitones($0, ref: max(1, median)) }
    let mean = st.reduce(0, +) / Double(max(1, st.count))
    let sd = (st.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, st.count))).squareRoot()
    let p5 = sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count) * 0.05)]
    let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    let level = rms(x[...])
    print(String(
        format: "%@\n  %.2f s, rms %.3f, voiced %.0f%%; F0 median %.0f Hz, spread %.1f st, 5–95%% %.0f–%.0f Hz (%.1f st); pauses ≥150 ms: %d [%@]; impulses: %d",
        url.lastPathComponent, duration, level, voiced * 100, median, sd, p5, p95,
        p5 > 0 ? semitones(p95, ref: p5) : 0, pauses.count,
        pauses.map(String.init).joined(separator: ","), impulses
    ))
}
