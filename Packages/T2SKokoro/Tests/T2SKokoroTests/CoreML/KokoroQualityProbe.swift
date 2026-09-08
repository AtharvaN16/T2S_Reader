import AVFoundation
import Foundation
import KokoroPipeline
import Testing
import T2SAudio
import T2SCore
@testable import T2SKokoro

/// Diagnostic probe for the owner's second listen (2026-09-08): "a tick or a clap mid-sentence
/// before the sentence resumes" and "commander-in-chief / cost-cutting pause at the hyphen". Renders
/// a few passages through the app's engine options, and — using the engine's utterance trace — places
/// every impulse in the audio on the token that owns it and measures its distance to the nearest
/// piece seam; measures what the hyphen becomes and how long the model pauses on it; and checks the
/// join between two consecutive app utterances after the AAC round trip the player actually hears.
///
/// Not a test: `.enabled` only while `spikes/findings/audio-probe/quality` exists.
@Suite(.serialized) struct KokoroQualityProbe {
    static let outputDirectory: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "spikes/findings/audio-probe/quality", directoryHint: .isDirectory)
    }()

    static var isRequested: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: outputDirectory.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    static let voice = "af_heart"
    static var voiceID: String { KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: voice).rawValue }
    static let rate = PipelineConstants.sampleRate
    static let samplesPerFrame = PipelineConstants.samplesPerDurationFrame

    /// Thread-safe mailbox for the engine's trace callback.
    final class TraceBox: @unchecked Sendable {
        private let lock = NSLock()
        private var trace: KokoroCoreMLEngine.UtteranceTrace?
        func set(_ t: KokoroCoreMLEngine.UtteranceTrace) { lock.lock(); trace = t; lock.unlock() }
        func take() -> KokoroCoreMLEngine.UtteranceTrace? { lock.lock(); defer { trace = nil; lock.unlock() }; return trace }
    }

    static let hyphenated = "The commander-in-chief announced a cost-cutting plan, and twenty-five officers re-entered the well-known hall."

    static let dickens = """
        "Bah!" said Scrooge, "Humbug!" He had so heated himself with rapid walking in the fog and \
        frost, this nephew of Scrooge's, that he was all in a glow; his face was ruddy and handsome; \
        his eyes sparkled, and his breath smoked again. "Christmas a humbug, uncle!" said Scrooge's \
        nephew. "You don't mean that, I am sure?" "I do," said Scrooge. "Merry Christmas! What right \
        have you to be merry? What reason have you to be merry? You're poor enough."
        """

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroQualityProbe.isRequested))
    func render() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let out = Self.outputDirectory
        let resources = try await KokoroTestSupport.compiledCoreMLResources()
        let symbols = try Self.symbols(vocab: resources.vocab)
        let engine = KokoroCoreMLEngine(resources: resources)   // the app's options
        let box = TraceBox()
        await engine.setUtteranceTrace { box.set($0) }
        var report: [String] = ["# Quality probe — \(Date().ISO8601Format())", "", "Voice \(Self.voice); engine options: app default (no punctuation suppression, 5 ms crossfade).", ""]

        func render(_ name: String, _ text: String) async throws -> (samples: [Float], trace: KokoroCoreMLEngine.UtteranceTrace, timings: [WordTiming]) {
            let r = try await engine.synthesize(.init(spoken: text, voiceID: Self.voiceID))
            guard let trace = box.take() else { throw KokoroCoreMLError.emptyAudio }
            try KokoroAudioProbe.writeWAV(r.audio.samples, to: out.appending(path: "\(name).wav"))
            return (r.audio.samples, trace, r.wordTimings)
        }

        // 1. Hyphens: what the G2P makes of them, and how long the model pauses there.
        report.append("## 1. Hyphenated words")
        for (name, text) in [("hyphen-as-is", Self.hyphenated), ("hyphen-spaced", Self.hyphenated.replacingOccurrences(of: "-", with: " "))] {
            let (samples, trace, _) = try await render(name, text)
            report.append("")
            report.append("### \(name)")
            report.append("Text: \(text)")
            report.append("Phonemes: `\(trace.phonemes)`")
            report.append(String(format: "Audio: %.2f s, %d ids, %d pieces", Double(samples.count) / Double(Self.rate), trace.ids.count, trace.pieces.count))
            report.append("Tokens: " + trace.words.map { "[\($0.text)→\($0.phonemes ?? "❓")]" }.joined(separator: " "))
            report += Self.tokenSpanTable(trace, symbols: symbols, only: { symbol, word in symbol == "—" || symbol == " " || word == "-" })
            report += Self.gaps(samples, minMs: 60)
        }

        // 2. A sentence long enough for two pipeline calls: the seam.
        report.append("")
        report.append("## 2. Two-piece sentence (the seam)")
        do {
            let (samples, trace, _) = try await render("long-two-pieces", KokoroCoreMLEngineTests.longSentence)
            report.append(String(format: "Audio: %.2f s, %d ids, %d pieces", Double(samples.count) / Double(Self.rate), trace.ids.count, trace.pieces.count))
            report += Self.seamReport(samples, trace, symbols: symbols)
            report += Self.impulseReport(samples, trace, symbols: symbols)
            report += Self.gaps(samples, minMs: 60)
        }

        // 3. The app path: packed utterances of a paragraph, every impulse placed on its token, then the
        //    AAC round trip and the join between consecutive utterances the player performs.
        report.append("")
        report.append("## 3. Packed utterances (the app's segmenter) and the join between them")
        let segmenter = Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength)
        let block = SourceBlock(text: Self.dickens, position: Position(resourceHref: "probe", progression: 0, charOffset: 0))
        let utterances = segmenter.segment(block).map(\.spoken)
        report.append("Segmenter produced \(utterances.count) utterances:")
        for u in utterances { report.append("  - \(u)") }
        var clips: [[Float]] = []
        for (index, text) in utterances.prefix(4).enumerated() {
            let name = "packed-\(index)"
            let (samples, trace, _) = try await render(name, text)
            clips.append(samples)
            report.append("")
            report.append("### \(name)")
            report.append(String(format: "Audio: %.2f s, %d ids, %d pieces, framed ids per piece %@", Double(samples.count) / Double(Self.rate), trace.ids.count, trace.pieces.count, trace.pieces.map { "\($0.ids.count + 2)" }.joined(separator: ",")))
            report += Self.seamReport(samples, trace, symbols: symbols)
            report += Self.impulseReport(samples, trace, symbols: symbols)
            report += Self.edges(samples, label: "raw")
            report += Self.tails(samples, trace)
        }
        // The same utterances with the tail click left in, for the A/B: only the tails may differ.
        report.append("")
        report.append("### The same utterances without the tail-click removal (upstream's tails)")
        await engine.setOptions(.init(punctuationSuppression: .none, crossfadePieces: true, removeTailClick: false))
        for (index, text) in utterances.prefix(4).enumerated() {
            let (samples, trace, _) = try await render("packed-\(index)-unfixed", text)
            let differing = zip(samples, clips[index]).filter { $0 != $1 }.count
            report.append("packed-\(index)-unfixed: \(samples.count) samples, \(differing) differ from the fixed render")
            report += Self.tails(samples, trace)
        }
        await engine.setOptions(.default)
        report.append("")
        report.append("### AAC round trip and the join")
        let codec = AACCodec()
        var decoded: [[Float]] = []
        for (index, clip) in clips.enumerated() {
            let pcm = PCMAudio(sampleRate: Double(Self.rate), samples: clip)
            let d = try codec.decode(try codec.encode(pcm)).samples
            decoded.append(d)
            report.append("packed-\(index): raw \(clip.count) samples, decoded \(d.count) samples")
            report += Self.edges(d, label: "aac")
        }
        var joined: [Float] = []
        var joins: [Int] = []
        for d in decoded { if !joined.isEmpty { joins.append(joined.count) }; joined += d }
        try KokoroAudioProbe.writeWAV(joined, to: out.appending(path: "packed-joined-aac.wav"))
        for j in joins {
            let step = abs(joined[j] - joined[j - 1])
            let window = joined[max(0, j - 240) ..< min(joined.count, j + 240)]
            let maxJump = zip(window.dropFirst(), window).map { abs($0 - $1) }.max() ?? 0
            report.append(String(format: "join at %.3f s: step %.4f, max jump within ±10 ms %.4f, quiet before %d ms, quiet after %d ms",
                                 Double(j) / Double(Self.rate), step, maxJump, Self.quietRun(joined, endingAt: j), Self.quietRun(joined, startingAt: j)))
        }
        report += Self.impulseReport(joined, nil, symbols: symbols, seams: joins)

        let reportURL = out.appending(path: "report.md")
        try report.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        print(report.joined(separator: "\n"))
    }

    // MARK: Trace geometry

    struct Span { var start: Int; var end: Int; var id: Int32; var symbol: String; var owner: Int; var word: String; var piece: Int }

    static func symbols(vocab: URL) throws -> [Int32: String] {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: vocab)) as! [String: Any]
        let raw = json["vocab"] as! [String: Any]
        var out: [Int32: String] = [:]
        for (k, v) in raw { out[(v as! NSNumber).int32Value] = k }
        return out
    }

    /// Sample spans of every framed id (BOS, ids, EOS) of every piece, in audio order.
    static func spans(_ trace: KokoroCoreMLEngine.UtteranceTrace, symbols: [Int32: String]) -> [Span] {
        var spans: [Span] = []
        for (p, piece) in trace.pieces.enumerated() {
            let framed: [Int32] = [0] + piece.ids + [0]
            let owners: [Int] = [-2] + piece.owners + [-3]
            var cursor = piece.offsetSamples
            for (k, id) in framed.enumerated() {
                let frames = k < piece.frames.count ? piece.frames[k] : 0
                let n = frames * samplesPerFrame
                let owner = owners[k]
                let word = owner == -2 ? "<BOS>" : owner == -3 ? "<EOS>" : owner < 0 ? "<ws>" : trace.words[owner].text
                let symbol = k == 0 ? "<BOS>" : k == framed.count - 1 ? "<EOS>" : (symbols[id] ?? "?")
                spans.append(Span(start: cursor, end: cursor + n, id: id, symbol: symbol, owner: owner, word: word, piece: p))
                cursor += n
            }
        }
        return spans
    }

    static func tokenSpanTable(_ trace: KokoroCoreMLEngine.UtteranceTrace, symbols: [Int32: String], only: (String, String) -> Bool) -> [String] {
        var lines = ["", "| t (s) | id | symbol | owner | frames | ms |", "|---|---|---|---|---|---|"]
        for s in spans(trace, symbols: symbols) where only(s.symbol, s.word) {
            lines.append(String(format: "| %.3f | %d | `%@` | %@ | %d | %d |", Double(s.start) / Double(rate), s.id, s.symbol, s.word, (s.end - s.start) / samplesPerFrame, (s.end - s.start) * 1000 / rate))
        }
        return lines
    }

    // MARK: Measurements

    static func rms(_ x: ArraySlice<Float>) -> Float { x.isEmpty ? 0 : (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot() }

    /// Length in ms of the near-silent run (10 ms windows under -50 dBFS) ending at `index`.
    static func quietRun(_ x: [Float], endingAt index: Int) -> Int {
        let w = rate / 100
        var i = index
        while i - w >= 0, rms(x[(i - w) ..< i]) < 0.00316 { i -= w }
        return (index - i) * 1000 / rate
    }

    static func quietRun(_ x: [Float], startingAt index: Int) -> Int {
        let w = rate / 100
        var i = index
        while i + w <= x.count, rms(x[i ..< (i + w)]) < 0.00316 { i += w }
        return (i - index) * 1000 / rate
    }

    /// Quiet stretches of at least `minMs`, with the words around them.
    static func gaps(_ x: [Float], minMs: Int) -> [String] {
        let w = rate / 100
        var lines: [String] = []
        var i = 0
        var runStart: Int?
        while i + w <= x.count {
            let quiet = rms(x[i ..< (i + w)]) < 0.00316
            if quiet, runStart == nil { runStart = i }
            if !quiet, let s = runStart {
                if (i - s) * 1000 / rate >= minMs { lines.append(String(format: "  gap %.3f–%.3f s (%d ms)", Double(s) / Double(rate), Double(i) / Double(rate), (i - s) * 1000 / rate)) }
                runStart = nil
            }
            i += w
        }
        return ["Quiet stretches ≥ \(minMs) ms:"] + (lines.isEmpty ? ["  none"] : lines)
    }

    static func seamReport(_ x: [Float], _ trace: KokoroCoreMLEngine.UtteranceTrace, symbols: [Int32: String]) -> [String] {
        guard trace.pieces.count > 1 else { return ["One piece: no seam."] }
        var lines = ["Seams:"]
        for (p, piece) in trace.pieces.enumerated().dropFirst() {
            let s = piece.offsetSamples
            let previous = trace.pieces[p - 1]
            let eosMs = (previous.frames.last ?? 0) * samplesPerFrame * 1000 / rate
            let lastReal = previous.frames.dropLast().last ?? 0
            let bosMs = (piece.frames.first ?? 0) * samplesPerFrame * 1000 / rate
            let lastSymbol = symbols[previous.ids.last ?? -1] ?? "?"
            let firstWord = piece.owners.first.map { $0 >= 0 ? trace.words[$0].text : "<ws>" } ?? "?"
            let step = abs(x[s] - x[s - 1])
            let window = x[max(0, s - 240) ..< min(x.count, s + 240)]
            let maxJump = zip(window.dropFirst(), window).map { abs($0 - $1) }.max() ?? 0
            let headPeak = x[s ..< min(x.count, s + rate / 20)].map { abs($0) }.max() ?? 0
            lines.append(String(format: "  seam %d at %.3f s: previous piece ends with `%@` (its last real id got %d frames, EOS %d ms); next piece begins with \"%@\" (BOS %d ms). quiet before %d ms, quiet after %d ms; step at the join %.4f, max jump ±10 ms %.4f, peak in the first 50 ms of the new piece %.3f",
                                 p, Double(s) / Double(rate), lastSymbol, lastReal, eosMs, firstWord, bosMs,
                                 quietRun(x, endingAt: s), quietRun(x, startingAt: s), step, maxJump, headPeak))
        }
        return lines
    }

    /// Impulses: a sample above -20 dBFS and at least six times the RMS of its 40 ms neighbourhood
    /// (a 1 ms core around it excluded, so it cannot inflate its own reference). Each is placed on
    /// the framed id whose span holds it and measured against the nearest seam.
    static func impulseReport(_ x: [Float], _ trace: KokoroCoreMLEngine.UtteranceTrace?, symbols: [Int32: String], seams: [Int]? = nil) -> [String] {
        let spans = trace.map { self.spans($0, symbols: symbols) } ?? []
        let seamOffsets = seams ?? (trace?.pieces.dropFirst().map(\.offsetSamples) ?? [])
        let half = rate * 20 / 1000
        let core = rate / 1000
        var lines = ["Impulses (> -20 dBFS and ≥ 6× the 40 ms neighbourhood):"]
        var k = half
        var count = 0
        while k < x.count - half {
            let v = abs(x[k])
            if v > 0.1 {
                let local = rms(x[(k - half) ..< (k - core)] + x[(k + core) ..< (k + half)])
                if v > 6 * local {
                    count += 1
                    var lo = k, hi = k
                    while lo > k - 120, abs(x[lo - 1]) > v / 4 { lo -= 1 }
                    while hi < min(x.count - 2, k + 120), abs(x[hi + 1]) > v / 4 { hi += 1 }
                    let span = spans.first { $0.start <= k && k < $0.end }
                    let where_ = span.map { s in
                        String(format: "in `%@` of \"%@\" (span %d ms, %d ms in)", s.symbol, s.word, (s.end - s.start) * 1000 / rate, (k - s.start) * 1000 / rate)
                    } ?? "unplaced"
                    let seam = seamOffsets.map { abs($0 - k) }.min().map { String(format: ", %d ms from the nearest seam", $0 * 1000 / rate) } ?? ""
                    lines.append(String(format: "  t=%7.3f s peak %.3f (x%.0f local rms %.4f) width %d samples %@%@",
                                        Double(k) / Double(rate), v, v / max(local, 1e-6), local, hi - lo + 1, where_, seam))
                    k += half
                }
            }
            k += 1
        }
        if count == 0 { lines.append("  none") }
        return lines
    }

    /// The last 160 ms of every piece: its runs of silence (under −80 dBFS) and the peak of whatever
    /// lies between them — the shape of the tail click.
    static func tails(_ x: [Float], _ trace: KokoroCoreMLEngine.UtteranceTrace) -> [String] {
        var lines: [String] = []
        let ends = trace.pieces.dropFirst().map { $0.offsetSamples + 120 } + [x.count]
        for (p, end) in ends.enumerated() {
            let from = max(0, end - rate * 160 / 1000)
            var runs: [String] = []
            var start: Int? = nil
            var peak: Float = 0
            var peakAt = end
            for i in from ..< end {
                let quiet = abs(x[i]) < 1e-4
                if quiet, start == nil { start = i }
                if !quiet {
                    if let s = start { if i - s >= 24 { runs.append("\((s - end) * 1000 / rate)…\((i - end) * 1000 / rate)") }; start = nil }
                    if abs(x[i]) > peak { peak = abs(x[i]); peakAt = i }
                }
            }
            if let s = start { runs.append("\((s - end) * 1000 / rate)…0") }
            lines.append(String(format: "  tail of piece %d: silence at %@ ms; loudest sample between the runs %.3f (%.0f dBFS) at %d ms before the end",
                                p, runs.joined(separator: ", "), peak, peak > 0 ? 20 * log10(peak) : -120, (end - peakAt) * 1000 / rate))
        }
        return lines
    }

    static func edges(_ x: [Float], label: String) -> [String] {
        guard x.count > rate / 20 else { return [] }
        let headPeak = x[0 ..< rate / 100].map { abs($0) }.max() ?? 0
        let tailPeak = x[(x.count - rate / 100)...].map { abs($0) }.max() ?? 0
        return [String(format: "  %@ edges: first sample %.5f, peak in first 10 ms %.5f, quiet at start %d ms; last sample %.5f, peak in last 10 ms %.5f, quiet at end %d ms",
                       label, x[0], headPeak, quietRun(x, startingAt: 0), x[x.count - 1], tailPeak, quietRun(x, endingAt: x.count))]
    }
}
