import AVFoundation
import Foundation
import KokoroPipeline
import Testing
import T2SAudio
import T2SCore
@testable import T2SKokoro

/// Renders the same sentences through the shipped fp16 model set and through a quantized candidate,
/// writes both WAVs side by side, and measures how far apart they are — so a human can listen to the
/// pairs the numbers rank worst.
///
/// The candidate is built by `scripts/quantize-kokoro-coreml.py` into
/// `App/Resources/KokoroCoreML-int8`. Everything before this point could only compare tensors:
/// f0ntrain and decoder_pre match the fp16 stages at cosine ≥ 0.9999 and the duration model shifts
/// about 1% of phonemes by one 12.5 ms frame (`scripts/compare-kokoro-durations.py`), but no tensor
/// distance answers the only question that decides whether this ships, which is whether it sounds
/// the same. This probe produces the audio that does.
///
/// What it covers: the bucket variants of a stage share one weight file, so rendering short
/// sentences exercises the same quantized weights the long buckets would — four of the five distinct
/// weight files in the set. The fifth is the 256-token duration model, which only a passage longer
/// than 126 phonemes reaches; the long passage below is there to reach it.
///
/// What it cannot answer: anything about the phones. Core ML expands quantized weights back to
/// float16 when a model loads on the CPU path, so the A13's compute-plan build times (60 s and 235 s
/// for the two longest stages) and its ~1 GB plan cache are unchanged by anything measured here and
/// have to be re-measured on the device.
///
/// Not a test: `.enabled` only while `spikes/findings/quantization-probe` exists, so it never runs
/// as part of `scripts/test-kokoro.sh`. Run it with `scripts/quantization-probe.sh`.
@Suite(.serialized) struct KokoroQuantizationProbe {
    static let outputDirectory: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "spikes/findings/quantization-probe", directoryHint: .isDirectory)
    }()

    /// The candidate staging, beside the development one it was built from.
    static let candidateDirectory: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "App/Resources/KokoroCoreML-int8", directoryHint: .isDirectory)
    }()

    static var isRequested: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: outputDirectory.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    static var haveCandidate: Bool {
        (try? KokoroCoreMLResources.locate(inDirectory: candidateDirectory).get()) != nil
    }

    static let voice = "af_heart"
    static var voiceID: String { KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: voice).rawValue }

    /// Sentences chosen for what quantization is most likely to damage rather than for variety:
    /// sibilance and high-frequency detail (where a generator artefact would land), a long held
    /// vowel and a question contour (where the pitch predictor shows), the hyphen and quotation
    /// passages this repo already listens to, and one passage long enough to reach the 256-token
    /// duration model — the one distinct weight file the short sentences never touch.
    static let sentences: [(name: String, text: String)] = [
        ("01-sibilance", "She sells sea shells by the sea shore, and the shells she sells are surely seashells."),
        ("02-plosives", "Peter picked a peck of pickled peppers; the batch popped, cracked and sputtered."),
        ("03-question", "You don't mean that, I am sure? Why would anyone believe such a thing?"),
        ("04-held-vowels", "The lone loon called across the cool blue lake, oh so slowly, all evening."),
        ("05-hyphen", "The commander-in-chief announced a cost-cutting plan, and twenty-five officers re-entered the well-known hall."),
        ("06-quotes", "\"Bah!\" said Scrooge, \"Humbug!\" His eyes sparkled, and his breath smoked again."),
        ("07-numbers", "In 1843 he wrote 1,400 words a day for 6 weeks, earning £230 and 15 shillings."),
        ("08-soft-consonants", "The thin feather fell through the frosty air, a whisper of warmth in the thawing month."),
        (
            "09-long-passage",
            """
            He had so heated himself with rapid walking in the fog and frost, this nephew of \
            Scrooge's, that he was all in a glow; his face was ruddy and handsome; his eyes \
            sparkled, and his breath smoked again, and every separate hair upon his head stood up \
            in the bitter cold of that grey December afternoon.
            """
        ),
    ]

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles
        && KokoroQuantizationProbe.haveCandidate
        && KokoroQuantizationProbe.isRequested))
    func compareTheCandidateToTheShippedModels() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let out = Self.outputDirectory
        var report: [String] = [
            "Quantization probe — \(Self.voice), \(Self.sentences.count) passages",
            "  reference: App/Resources/KokoroCoreML (fp16, the shipped set)",
            "  candidate: App/Resources/KokoroCoreML-int8 (scripts/quantize-kokoro-coreml.py)",
            "",
        ]

        // Both stagings, each compiled once and kept under its own .build key.
        let reference = try await KokoroTestSupport.compiledCoreMLResources()
        let candidate = try await KokoroTestSupport.compiledCoreMLResources(
            inDirectory: Self.candidateDirectory, cacheKey: "int8"
        )

        // The app's shipped options, so the comparison is of the thing users hear.
        let options = KokoroCoreMLEngine.Options()
        let referenceEngine = KokoroCoreMLEngine(resources: reference, options: options)
        let candidateEngine = KokoroCoreMLEngine(resources: candidate, options: options)

        var rows: [(name: String, worst: Double, line: String)] = []
        for (name, text) in Self.sentences {
            let a = try await referenceEngine.synthesize(.init(spoken: text, voiceID: Self.voiceID)).audio.samples
            let b = try await candidateEngine.synthesize(.init(spoken: text, voiceID: Self.voiceID)).audio.samples
            try Self.writeWAV(a, to: out.appending(path: "\(name)-fp16.wav"))
            try Self.writeWAV(b, to: out.appending(path: "\(name)-int8.wav"))

            // Two controls, without which the candidate's distance from the reference has no scale.
            //  -fp16again: the same engine, the same text, a second time. Any difference here is the
            //              pipeline's own nondeterminism, i.e. the floor every other number sits on.
            //  -fp16split: the same fp16 weights rendering the same words as separate utterances and
            //              butted together — the streamed-vs-whole case docs/HANDOFF.md already
            //              settled as "two performances of the same words" and ships today. A
            //              candidate no further from the reference than this is within what the app
            //              has already accepted.
            let again = try await referenceEngine.synthesize(.init(spoken: text, voiceID: Self.voiceID)).audio.samples
            try Self.writeWAV(again, to: out.appending(path: "\(name)-fp16again.wav"))

            var split: [Float] = []
            for sentence in Self.split(text) {
                split += try await referenceEngine.synthesize(.init(spoken: sentence, voiceID: Self.voiceID)).audio.samples
            }
            try Self.writeWAV(split, to: out.appending(path: "\(name)-fp16split.wav"))

            let measured = Self.compare(a, b)
            let line = """
                \(name)
                  samples      \(a.count) -> \(b.count)  (\(String(format: "%+.0f", Double(b.count - a.count) / 24.0)) ms)
                  peak         \(String(format: "%.3f", measured.peakA)) -> \(String(format: "%.3f", measured.peakB))
                  correlation  \(String(format: "%.5f", measured.correlation)) over the common prefix
                  difference   \(String(format: "%.1f", measured.differenceDB)) dB below the reference (RMS)
                """
            report.append(line)
            rows.append((name, measured.differenceDB, line))
        }

        // Rank worst-first: the least negative difference is the pair most worth listening to.
        let ranked = rows.sorted { $0.worst > $1.worst }
        report.append("")
        report.append("Listen in this order (loudest difference first):")
        for row in ranked {
            report.append("  \(row.name)  \(String(format: "%.1f", row.worst)) dB")
        }
        report.append("")
        report.append("""
            Reading the numbers: a difference RMS far below the reference means the two renders are \
            nearly the same waveform. Correlation is computed over the common prefix because a \
            one-frame duration flip shifts everything after it, which a sample-wise measure reads \
            as a large error even when nothing audible changed — so trust the ranking to choose \
            what to listen to, and trust your ears for the verdict.
            """)

        let reportURL = out.appending(path: "report.txt")
        try report.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        print(report.joined(separator: "\n"))
    }

    /// Splits a passage into sentence-sized utterances for the `-fp16split` control. Crude on
    /// purpose: the control only has to produce the same words through more than one pipeline call,
    /// which is what makes it the streamed-vs-whole comparison.
    static func split(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "." || character == "!" || character == "?" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append(trimmed) }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { out.append(trimmed) }
        return out.isEmpty ? [text] : out
    }

    // MARK: Measurement

    struct Measured {
        var peakA: Double
        var peakB: Double
        var correlation: Double
        /// RMS of (candidate − reference) relative to the reference's RMS, in dB. Very negative is good.
        var differenceDB: Double
    }

    static func compare(_ a: [Float], _ b: [Float]) -> Measured {
        let n = min(a.count, b.count)
        var dot = 0.0, sumA = 0.0, sumB = 0.0, sumDifference = 0.0
        for index in 0 ..< n {
            let x = Double(a[index]), y = Double(b[index])
            dot += x * y
            sumA += x * x
            sumB += y * y
            sumDifference += (y - x) * (y - x)
        }
        let correlation = (sumA > 0 && sumB > 0) ? dot / (sumA.squareRoot() * sumB.squareRoot()) : 0
        let referenceRMS = (sumA / Double(max(n, 1))).squareRoot()
        let differenceRMS = (sumDifference / Double(max(n, 1))).squareRoot()
        let differenceDB = (referenceRMS > 0 && differenceRMS > 0)
            ? 20 * log10(differenceRMS / referenceRMS) : -.infinity
        return Measured(
            peakA: a.reduce(0) { Swift.max($0, Double(abs($1))) },
            peakB: b.reduce(0) { Swift.max($0, Double(abs($1))) },
            correlation: correlation,
            differenceDB: differenceDB
        )
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
