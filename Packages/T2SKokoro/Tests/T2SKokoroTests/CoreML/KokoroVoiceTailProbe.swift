import Foundation
import KokoroPipeline
import Testing
import T2SAudio
import T2SCore
@testable import T2SKokoro

/// Diagnostic probe for the owner's report of 2026-09-10: "does changing voice reintroduce the click
/// sounds in the playback? I am getting them when I change voice". `KokoroCoreMLTailClick` was shaped
/// on `af_heart` alone (`spikes/findings/2026-09-08-ticks-and-hyphens.md`): an island under 30 ms,
/// bounded by at least 10 ms of digital silence (under −80 dBFS) on both sides, within the last
/// 120 ms of a call. This renders the same utterances through every one of the 28 voices, with the
/// pieces plain-appended so each pipeline call's audio can be sliced out exactly, and asks of every
/// call's tail: what shape is the burst for this voice, does the shipped detector remove it, and what
/// is left above −50 dBFS afterwards. Then it streams one two-piece utterance per voice down the
/// app's own path (`synthesizeStreaming`, app options) and measures the joins.
///
/// Not a test: `.enabled` only while `spikes/findings/voice-tail-probe` exists.
@Suite(.serialized) struct KokoroVoiceTailProbe {
    static let outputDirectory: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "spikes/findings/voice-tail-probe", directoryHint: .isDirectory)
    }()

    static var isRequested: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: outputDirectory.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    static let voices = [
        "af_heart", "af_alloy", "af_aoede", "af_bella", "af_jessica", "af_kore", "af_nicole",
        "af_nova", "af_river", "af_sarah", "af_sky", "am_adam", "am_echo", "am_eric", "am_fenrir",
        "am_liam", "am_michael", "am_onyx", "am_puck", "am_santa", "bf_alice", "bf_emma",
        "bf_isabella", "bf_lily", "bm_daniel", "bm_fable", "bm_george", "bm_lewis",
    ]
    static let rate = PipelineConstants.sampleRate
    static func ms(_ samples: Int) -> Int { samples * 1000 / rate }
    static func dB(_ peak: Float) -> Float { peak > 0 ? 20 * log10(peak) : -120 }

    /// The app's delivery rides on the route (`Delivery.spread`), so the render is the app's.
    static func voiceID(_ voice: String) -> String {
        KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: voice, spread: 1.25).rawValue
    }

    final class TraceBox: @unchecked Sendable {
        private let lock = NSLock()
        private var trace: KokoroCoreMLEngine.UtteranceTrace?
        func set(_ t: KokoroCoreMLEngine.UtteranceTrace) { lock.lock(); trace = t; lock.unlock() }
        func take() -> KokoroCoreMLEngine.UtteranceTrace? { lock.lock(); defer { trace = nil; lock.unlock() }; return trace }
    }

    /// The shape of a call's tail: how it ends, walking back from the last sample.
    struct TailShape {
        /// Silence (under `bound`) at the very end.
        var trailingMs: Int
        /// The non-silent stretch before that, bounded on its far side by ≥ 10 ms under `bound`, or
        /// nil when speech runs on for more than 200 ms — no island.
        var islandMs: Int?
        var islandPeak: Float
        /// Silence under `bound` before the island.
        var precedingMs: Int
        var description: String {
            if let islandMs {
                return String(format: "silence %d ms | island %d ms peak %.3f (%.0f dBFS) | silence %d ms",
                              precedingMs, islandMs, islandPeak, Self.dB(islandPeak), trailingMs)
            }
            return String(format: "speech to %d ms before the end (peak in the last 200 ms %.3f)", trailingMs, islandPeak)
        }
        static func dB(_ peak: Float) -> Float { KokoroVoiceTailProbe.dB(peak) }
    }

    static func shape(_ x: ArraySlice<Float>, bound: Float) -> TailShape {
        let minSilence = rate * 10 / 1000
        var i = x.endIndex
        while i > x.startIndex, abs(x[i - 1]) < bound { i -= 1 }
        let trailing = x.endIndex - i
        guard i > x.startIndex else { return TailShape(trailingMs: ms(trailing), islandMs: nil, islandPeak: 0, precedingMs: 0) }
        let islandEnd = i
        var j = i
        var run = 0
        var islandStart: Int?
        var peak: Float = 0
        while j > x.startIndex, islandEnd - j <= rate * 200 / 1000 {
            j -= 1
            let v = abs(x[j])
            if v < bound {
                run += 1
                if run >= minSilence { islandStart = j + minSilence; break }
            } else {
                run = 0
                peak = max(peak, v)
            }
        }
        guard let islandStart else { return TailShape(trailingMs: ms(trailing), islandMs: nil, islandPeak: peak, precedingMs: 0) }
        var k = islandStart
        while k > x.startIndex, abs(x[k - 1]) < bound { k -= 1 }
        return TailShape(trailingMs: ms(trailing), islandMs: ms(islandEnd - islandStart), islandPeak: peak, precedingMs: ms(islandStart - k))
    }

    static let dickens = """
        "Bah!" said Scrooge, "Humbug!" He had so heated himself with rapid walking in the fog and \
        frost, this nephew of Scrooge's, that he was all in a glow; his face was ruddy and handsome; \
        his eyes sparkled, and his breath smoked again. "Christmas a humbug, uncle!" said Scrooge's \
        nephew. "You don't mean that, I am sure?" "I do," said Scrooge. "Merry Christmas! What right \
        have you to be merry? What reason have you to be merry? You're poor enough."
        """

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroVoiceTailProbe.isRequested))
    func render() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let out = Self.outputDirectory
        let resources = try await KokoroTestSupport.compiledCoreMLResources()
        // Pieces plain-appended and untouched, so the trace's offsets slice each call's audio exactly.
        let raw = KokoroCoreMLEngine.Options(punctuationSuppression: .none, crossfadePieces: false, removeTailClick: false, trimSeams: false)
        let engine = KokoroCoreMLEngine(resources: resources, options: raw)
        let box = TraceBox()
        await engine.setUtteranceTrace { box.set($0) }

        let segmenter = Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength)
        let block = SourceBlock(text: Self.dickens, position: Position(resourceHref: "probe", progression: 0, charOffset: 0))
        let utterances = segmenter.segment(block).map(\.spoken)
        let texts = [0, 1, 3].filter { $0 < utterances.count }.map { (index: $0, text: utterances[$0]) }

        var report: [String] = ["# Voice tail probe — \(Date().ISO8601Format())", "",
                                "Every voice renders the same utterances at the app's delivery (spread 1.25). Raw pass: no crossfade,",
                                "no seam trim, no tail-click removal, so each pipeline call is sliced exactly; `detector` is the shipped",
                                "`KokoroCoreMLTailClick.removed(from:)` run over that slice. Bounds: −80 dBFS is the detector's own",
                                "silence, −50 dBFS is `KokoroCoreMLSeam`'s. Stream pass: `synthesizeStreaming` with the app's options.", ""]
        for (index, text) in texts { report.append("- packed-\(index): \(text)") }
        report.append("")
        report.append("## Summary")
        report.append("")
        report.append("| voice | calls | raw island (−80) | removed by detector | left above −50 after detector, loudest | streamed pieces | streamed tails above −50, loudest | largest join step |")
        report.append("|---|---|---|---|---|---|---|---|")
        var details: [String] = []
        var wavsWritten = 0

        for voice in Self.voices {
            var calls = 0, rawIslands = 0, removed = 0, left = 0
            var loudestLeft: Float = 0
            details.append("")
            details.append("## \(voice)")
            for (index, text) in texts {
                let r = try await engine.synthesize(.init(spoken: text, voiceID: Self.voiceID(voice)))
                guard let trace = box.take() else { throw KokoroCoreMLError.emptyAudio }
                let samples = r.audio.samples
                for (p, piece) in trace.pieces.enumerated() {
                    let slice = samples[piece.offsetSamples ..< min(samples.count, piece.offsetSamples + piece.sampleCount)]
                    calls += 1
                    let before80 = Self.shape(slice, bound: 1e-4)                       // −80 dBFS: the first rule's silence
                    let before50 = Self.shape(slice, bound: KokoroCoreMLSeam.silence)
                    let cleaned = KokoroCoreMLTailClick.removed(from: Array(slice))
                    let zeroed = zip(cleaned, slice).filter { $0 != $1 }.count
                    let after50 = Self.shape(cleaned[...], bound: KokoroCoreMLSeam.silence)
                    if before80.islandMs != nil { rawIslands += 1 }
                    if zeroed > 0 { removed += 1 }
                    let residual = after50.islandMs != nil && after50.islandPeak >= 0.01   // −40 dBFS: what an ear might catch
                    if residual { left += 1; loudestLeft = max(loudestLeft, after50.islandPeak) }
                    details.append(String(format: "- packed-%d call %d/%d (%d ms): raw at −80: %@; raw at −50: %@; detector zeroed %d samples; after, at −50: %@%@",
                                          index, p + 1, trace.pieces.count, Self.ms(slice.count),
                                          before80.description, before50.description, zeroed, after50.description,
                                          residual ? "  **LEFT IN**" : ""))
                    if residual, wavsWritten < 12 {
                        wavsWritten += 1
                        try KokoroAudioProbe.writeWAV(Array(slice), to: out.appending(path: "\(voice)-packed-\(index)-call\(p + 1)-raw.wav"))
                        try KokoroAudioProbe.writeWAV(cleaned, to: out.appending(path: "\(voice)-packed-\(index)-call\(p + 1)-detector.wav"))
                    }
                }
            }

            // The app's path: the head utterance streams in pieces, each finalized on its own.
            await engine.setOptions(.default)
            var pieces: [[Float]] = []
            let twoPiece = texts.first { $0.index == 1 } ?? texts[0]
            for try await chunk in engine.synthesizeStreaming(.init(spoken: twoPiece.text, voiceID: Self.voiceID(voice))) {
                if case .piece(let audio, _, _) = chunk { pieces.append(audio.samples) }
            }
            await engine.setOptions(raw)
            var streamedLeft = 0
            var streamedLoudest: Float = 0
            var largestStep: Float = 0
            for (k, piece) in pieces.enumerated() {
                let tail = Self.shape(piece[...], bound: KokoroCoreMLSeam.silence)
                let residual = k < pieces.count - 1 && tail.islandMs != nil && tail.islandPeak >= 0.01
                if residual { streamedLeft += 1; streamedLoudest = max(streamedLoudest, tail.islandPeak) }
                var join = ""
                if k + 1 < pieces.count, let last = piece.last, let first = pieces[k + 1].first {
                    let step = abs(first - last)
                    largestStep = max(largestStep, step)
                    join = String(format: "; join step to the next %.4f", step)
                }
                details.append(String(format: "- streamed packed-%d piece %d/%d (%d ms): tail at −50: %@%@%@",
                                      twoPiece.index, k + 1, pieces.count, Self.ms(piece.count), tail.description, join,
                                      residual ? "  **LEFT IN**" : ""))
            }
            report.append(String(format: "| %@ | %d | %d | %d | %d, %.3f (%.0f dBFS) | %d | %d, %.3f (%.0f dBFS) | %.4f |",
                                 voice, calls, rawIslands, removed, left, loudestLeft, Self.dB(loudestLeft),
                                 pieces.count, streamedLeft, streamedLoudest, Self.dB(streamedLoudest), largestStep))
            print("voice-tail-probe: \(voice) calls \(calls) raw islands \(rawIslands) removed \(removed) left \(left) streamed left \(streamedLeft)")
        }

        report.append("")
        report.append("## Every call")
        report += details
        let reportURL = out.appending(path: "report.md")
        try report.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        print(report.joined(separator: "\n"))
    }
}
