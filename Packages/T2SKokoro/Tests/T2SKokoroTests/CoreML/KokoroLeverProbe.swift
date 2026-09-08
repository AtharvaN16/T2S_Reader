import AVFoundation
import Foundation
import KokoroPipeline
import Testing
import T2SAudio
import T2SCore
@testable import T2SKokoro

/// Quality levers that need no other model (`spikes/findings/2026-09-08-quality-levers.md`): the four
/// voices the author grades B- or better, blends of the reference voice with each of them (a voice is
/// a 510×256 style table; a blend is the weighted sum of two tables, row by row, as the community
/// tools do it), one extrapolation past the blend, and the pitch-spread hook at three strengths. One
/// passage, the app's own packing, one WAV per variant for the owner's ears, and numbers for the rest
/// (`scripts/analyze-wav.swift` adds pitch spread and pauses afterwards).
///
/// Not a test: `.enabled` only while `spikes/findings/lever-probe` exists.
@Suite(.serialized) struct KokoroLeverProbe {
    static let outputDirectory: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "spikes/findings/lever-probe", directoryHint: .isDirectory)
    }()

    static var isRequested: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: outputDirectory.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    struct Variant {
        var name: String
        var voice: String
        var f0Spread: Float = 1
    }

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroLeverProbe.isRequested))
    func render() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let out = Self.outputDirectory
        let staged = try await KokoroTestSupport.compiledCoreMLResources()

        // Blended voices, written beside the staged ones under names the engine treats as American.
        let blendDirectory = out.appending(path: "voices", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: blendDirectory, withIntermediateDirectories: true)
        var voices = staged.voices
        func blend(_ name: String, _ a: String, _ b: String, weight: Float) throws {
            let x = try Self.table(staged.voices[a]!), y = try Self.table(staged.voices[b]!)
            precondition(x.count == y.count)
            let mixed = zip(x, y).map { (1 - weight) * $0 + weight * $1 }
            let url = blendDirectory.appending(path: "\(name).bin")
            try Self.write(mixed, to: url)
            voices[name] = url
        }
        try blend("af_heart_bella50", "af_heart", "af_bella", weight: 0.5)
        try blend("af_heart_bella150", "af_heart", "af_bella", weight: 1.5)
        try blend("af_heart_nicole50", "af_heart", "af_nicole", weight: 0.5)
        try blend("af_heart_emma50", "af_heart", "bf_emma", weight: 0.5)
        let resources = KokoroCoreMLResources.Located(
            stages: staged.stages, voices: voices, vocab: staged.vocab, hnsfWeights: staged.hnsfWeights, isPrecompiled: true
        )
        let engine = KokoroCoreMLEngine(resources: resources)

        let variants: [Variant] = [
            .init(name: "01-heart", voice: "af_heart"),
            .init(name: "02-bella", voice: "af_bella"),
            .init(name: "03-nicole", voice: "af_nicole"),
            .init(name: "04-emma", voice: "bf_emma"),
            .init(name: "05-heart-bella-50", voice: "af_heart_bella50"),
            .init(name: "06-heart-bella-150", voice: "af_heart_bella150"),
            .init(name: "07-heart-nicole-50", voice: "af_heart_nicole50"),
            .init(name: "08-heart-emma-50", voice: "af_heart_emma50"),
            .init(name: "09-heart-spread-1.25", voice: "af_heart", f0Spread: 1.25),
            .init(name: "10-heart-spread-1.5", voice: "af_heart", f0Spread: 1.5),
            .init(name: "11-heart-spread-2.0", voice: "af_heart", f0Spread: 2.0),
        ]

        let segmenter = Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength)
        let block = SourceBlock(text: KokoroAudioProbe.passage, position: Position(resourceHref: "probe", progression: 0, charOffset: 0))
        let utterances = segmenter.segment(block).map(\.spoken)

        var report = ["# Lever probe — \(Date().ISO8601Format())", "", "Passage: the Dickens paragraph as \(utterances.count) packed utterances; engine options: app default plus the variant's pitch spread.", "",
                      "| variant | audio s | render s | RTF | peak | rms | impulses |", "|---|---|---|---|---|---|---|"]
        for v in variants {
            var options = KokoroCoreMLEngine.Options.default
            options.f0Spread = v.f0Spread
            await engine.setOptions(options)
            let voiceID = KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: v.voice).rawValue
            var samples: [Float] = []
            let started = Date()
            for text in utterances {
                let r = try await engine.synthesize(.init(spoken: text, voiceID: voiceID))
                samples += r.audio.samples
            }
            let seconds = Date().timeIntervalSince(started)
            try KokoroAudioProbe.writeWAV(samples, to: out.appending(path: "\(v.name).wav"))
            let duration = Double(samples.count) / 24_000
            let peak = samples.map { abs($0) }.max() ?? 0
            let rms = (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count))).squareRoot()
            let impulses = KokoroQualityProbe.impulseReport(samples, nil, symbols: [:]).count - 1
            report.append(String(format: "| %@ | %.2f | %.1f | %.2f | %.2f | %.3f | %d |", v.name, duration, seconds, seconds / duration, peak, rms, impulses))
        }
        try report.joined(separator: "\n").write(to: out.appending(path: "report.md"), atomically: true, encoding: .utf8)
        print(report.joined(separator: "\n"))
    }

    /// A voice file as float32 little-endian values.
    static func table(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return (0 ..< data.count / 4).map { i in
            Float(bitPattern: UInt32(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self) }))
        }
    }

    static func write(_ values: [Float], to url: URL) throws {
        var data = Data(capacity: values.count * 4)
        for v in values { var bits = v.bitPattern.littleEndian; withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) } }
        try data.write(to: url)
    }
}
