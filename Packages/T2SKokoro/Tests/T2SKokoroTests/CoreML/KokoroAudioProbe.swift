import AVFoundation
import Foundation
import KokoroPipeline
import Testing
import T2SAudio
import T2SCore
@testable import T2SKokoro

/// Renders one dialogue-heavy passage several ways and writes the WAVs and a metrics table to
/// `spikes/findings/audio-probe/`, for a human to listen to side by side. Not a test of anything:
/// it is `.enabled` only when that directory exists, which `scripts/audio-probe.sh` creates before
/// running it, so the ordinary suite never pays the minutes it takes.
///
/// Why it exists: the first listen on the iPhone 11 Pro (2026-09-05) heard cut-off word endings,
/// abrupt joins between sentences and a flat, effortful delivery. Each variant below isolates one
/// suspect — upstream's punctuation silencing, the butt-joined pieces, one Kokoro call per sentence
/// versus one per paragraph — and the MLX engine (kokoro-ios, a faithful port of the PyTorch
/// reference) is rendered beside them as the control. Findings:
/// `spikes/findings/2026-09-05-coreml-audio-quality.md`.
@Suite(.serialized) struct KokoroAudioProbe {
    /// `<repo>/spikes/findings/audio-probe`; this file is
    /// `<repo>/Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroAudioProbe.swift`.
    static let outputDirectory: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "spikes/findings/audio-probe", directoryHint: .isDirectory)
    }()

    /// The MLX weights the Plan 0 spike harness downloaded; `scripts/fetch-kokoro-model.sh` would
    /// copy them into the app's resources, which this probe deliberately avoids (the phone build
    /// would bundle them).
    static let mlxResourcesDirectory: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "spikes/SpikeHarness/Resources", directoryHint: .isDirectory)
    }()

    static var isRequested: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: outputDirectory.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Dickens, *A Christmas Carol* (public domain): quotation marks, commas, semicolons, questions
    /// and exclamations in ninety words — every punctuation span upstream silences.
    static let passage = """
        "Bah!" said Scrooge, "Humbug!" He had so heated himself with rapid walking in the fog and \
        frost, this nephew of Scrooge's, that he was all in a glow; his face was ruddy and handsome; \
        his eyes sparkled, and his breath smoked again. "Christmas a humbug, uncle!" said Scrooge's \
        nephew. "You don't mean that, I am sure?" "I do," said Scrooge. "Merry Christmas! What right \
        have you to be merry? What reason have you to be merry? You're poor enough."
        """

    static let voice = "af_heart"

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroAudioProbe.isRequested))
    func renderTheVariants() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let out = Self.outputDirectory
        var report: [String] = ["# Audio probe — \(Date().ISO8601Format())", "", "Passage: \(Self.passage.count) characters, voice \(Self.voice).", ""]

        // One utterance per sentence, normalized — what the app did before Plan 9 packed sentences
        // (`Segmenter.appPackLength`); the per-sentence variants are the "before".
        let segmenter = Segmenter(normalizer: TextNormalizer(), packLength: 0)
        let block = SourceBlock(text: Self.passage, position: Position(resourceHref: "probe", progression: 0, charOffset: 0))
        let sentences = segmenter.segment(block).map(\.spoken)
        report.append("Segmenter produced \(sentences.count) utterances:")
        for s in sentences { report.append("  - \(s)") }
        report.append("")

        // Calibration: how many pipeline ids the passage and each sentence phonemize to.
        let calibrationEngine = try await Self.coreMLEngine(.init())
        let whole = try await calibrationEngine.phonemization(of: Self.passage, voice: Self.voice)
        report.append(String(format: "Whole passage: %d ids for %d source characters (%.2f ids/char); %d phoneme characters",
                             whole.ids, Self.passage.count, Double(whole.ids) / Double(Self.passage.count), whole.phonemes.count))
        var idsPerSentence: [Int] = []
        for s in sentences {
            let p = try await calibrationEngine.phonemization(of: s, voice: Self.voice)
            idsPerSentence.append(p.ids)
        }
        report.append("Per sentence ids: \(idsPerSentence)")
        report.append("Piece cap is \(KokoroCoreMLEngine.maxPieceTokenCount) ids.")
        report.append("")

        struct Variant {
            let name: String
            let options: KokoroCoreMLEngine.Options
            let perSentence: Bool
        }
        let variants: [Variant] = [
            .init(name: "A-current-per-sentence-all-suppressed", options: .init(punctuationSuppression: .allPunctuation, crossfadePieces: false), perSentence: true),
            .init(name: "B-per-sentence-no-suppression-crossfade", options: .init(punctuationSuppression: .none, crossfadePieces: true), perSentence: true),
            .init(name: "C-paragraph-no-suppression-crossfade", options: .init(punctuationSuppression: .none, crossfadePieces: true), perSentence: false),
            .init(name: "D-paragraph-sentence-final-crossfade", options: .init(punctuationSuppression: .sentenceFinal, crossfadePieces: true), perSentence: false),
        ]

        // One engine for every variant: the stages are loaded once, and the Core ML runtime's
        // per-model cache (which fills a disk at one copy per engine instance) is written once.
        let engine = calibrationEngine
        for v in variants {
            await engine.setOptions(v.options)
            let url = out.appending(path: "\(v.name).wav")
            if let existing = Self.readWAV(url) {
                report.append(Self.metrics(name: v.name + " (kept from an earlier run)", samples: existing, renderSeconds: 0))
                continue
            }
            let texts = v.perSentence ? sentences : [Self.passage]
            var samples: [Float] = []
            let started = Date()
            for text in texts {
                let r = try await engine.synthesize(.init(spoken: text, voiceID: Self.coreMLVoiceID))
                samples += r.audio.samples
            }
            let seconds = Date().timeIntervalSince(started)
            try Self.writeWAV(samples, to: url)
            report.append(Self.metrics(name: v.name, samples: samples, renderSeconds: seconds))
        }

        // The long sentence the engine has to cut into two pieces: the seam, joined both ways.
        let long = KokoroCoreMLEngineTests.longSentence
        for (name, options) in [("E-long-sentence-current", KokoroCoreMLEngine.Options(punctuationSuppression: .allPunctuation, crossfadePieces: false)),
                                ("F-long-sentence-no-suppression-crossfade", KokoroCoreMLEngine.Options(punctuationSuppression: .none, crossfadePieces: true))] {
            let url = out.appending(path: "\(name).wav")
            if let existing = Self.readWAV(url) {
                report.append(Self.metrics(name: name + " (kept from an earlier run)", samples: existing, renderSeconds: 0))
                continue
            }
            await engine.setOptions(options)
            let started = Date()
            let r = try await engine.synthesize(.init(spoken: long, voiceID: Self.coreMLVoiceID))
            try Self.writeWAV(r.audio.samples, to: url)
            report.append(Self.metrics(name: name, samples: r.audio.samples, renderSeconds: Date().timeIntervalSince(started)))
        }

        // The control: kokoro-ios on MLX, the reference implementation's behaviour.
        if case .success(let located) = KokoroResources.locate(in: Self.mlxResourcesDirectory) {
            let mlx = KokoroEngine(resources: located)
            let mlxVoice = KokoroVoiceID(engineID: KokoroEngine.identity, voice: Self.voice).rawValue
            for (name, texts) in [("G-mlx-per-sentence", sentences), ("H-mlx-paragraph", [Self.passage]), ("I-mlx-long-sentence", [long])] {
                let url = out.appending(path: "\(name).wav")
                if let existing = Self.readWAV(url) {
                    report.append(Self.metrics(name: name + " (kept from an earlier run)", samples: existing, renderSeconds: 0))
                    continue
                }
                var samples: [Float] = []
                let started = Date()
                do {
                    for text in texts {
                        let r = try await mlx.synthesize(.init(spoken: text, voiceID: mlxVoice))
                        samples += r.audio.samples
                    }
                } catch {
                    // The control is optional: record the failure and keep the report.
                    report.append("- \(name): MLX failed — \(error)")
                    continue
                }
                try Self.writeWAV(samples, to: url)
                report.append(Self.metrics(name: name, samples: samples, renderSeconds: Date().timeIntervalSince(started)))
            }
        } else {
            report.append("MLX control skipped: no weights in \(Self.mlxResourcesDirectory.path())")
        }

        let reportURL = out.appending(path: "metrics.md")
        try report.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        print(report.joined(separator: "\n"))
    }

    static var coreMLVoiceID: String { KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: voice).rawValue }

    static func coreMLEngine(_ options: KokoroCoreMLEngine.Options) async throws -> KokoroCoreMLEngine {
        // `KokoroTestSupport.compiledCoreMLResources()` compiles the development staging once and
        // shares it: every engine instance would otherwise compile its own copy of the eight stages
        // into `$TMPDIR` (about 350 MB each), and this probe builds several.
        KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: options)
    }

    // MARK: Measurement

    /// Numbers a listener can check against what they hear. Exact-zero runs are what the
    /// suppression leaves behind (the generator never emits a true zero); "holes" are such runs
    /// inside the audio; "clicks" are sample-to-sample jumps a fifth of full scale or more.
    static func metrics(name: String, samples: [Float], renderSeconds: Double) -> String {
        let rate = 24_000
        let duration = Double(samples.count) / Double(rate)
        // Exact-zero runs of at least 10 ms, ignoring the very start and end.
        var zeroRuns: [(start: Int, length: Int)] = []
        var runStart: Int? = nil
        for (i, s) in samples.enumerated() {
            if s == 0 {
                if runStart == nil { runStart = i }
            } else if let start = runStart {
                if i - start >= rate / 100 { zeroRuns.append((start, i - start)) }
                runStart = nil
            }
        }
        if let start = runStart, samples.count - start >= rate / 100 { zeroRuns.append((start, samples.count - start)) }
        let holes = zeroRuns.filter { $0.start > 0 && $0.start + $0.length < samples.count }
        let holeMs = holes.map { Double($0.length) * 1000 / Double(rate) }
        // Near-silent stretches (RMS below -50 dBFS over 10 ms windows) of 150 ms or more: pauses.
        let window = rate / 100
        var quiet: [Bool] = []
        var i = 0
        while i + window <= samples.count {
            var sum = 0.0
            for j in i ..< i + window { sum += Double(samples[j]) * Double(samples[j]) }
            let rms = (sum / Double(window)).squareRoot()
            quiet.append(rms < 0.00316)
            i += window
        }
        var pauses = 0
        var run = 0
        for q in quiet {
            if q { run += 1 } else { if run >= 15 { pauses += 1 }; run = 0 }
        }
        // Clicks.
        var clicks = 0
        var maxJump: Float = 0
        for k in 1 ..< max(1, samples.count) {
            let jump = abs(samples[k] - samples[k - 1])
            if jump > maxJump { maxJump = jump }
            if jump >= 0.2 { clicks += 1 }
        }
        let peak = samples.map { abs($0) }.max() ?? 0
        let rms = (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count))).squareRoot()
        return String(
            format: "- %@: %.2f s audio, rendered in %.1f s (RTF %.2f); peak %.2f, rms %.3f; holes ≥10 ms inside the audio: %d (%@); pauses ≥150 ms: %d; clicks ≥0.2: %d (max jump %.2f)",
            name, duration, renderSeconds, renderSeconds / max(0.001, duration), peak, rms, holes.count,
            holeMs.map { String(format: "%.0f", $0) }.joined(separator: ","), pauses, clicks, maxJump
        )
    }

    static func readWAV(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let format = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return nil }
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    static func writeWAV(_ samples: [Float], to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 24_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw AudioCodecError.malformed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
    }
}
