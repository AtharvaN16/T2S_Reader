import AVFoundation
import Foundation
import KokoroPipeline
import Testing
import T2SAudio
import T2SCore
@testable import T2SKokoro

/// Renders the onboarding's pre-recorded clips — each sample book's opening line in its own voice,
/// and the hero's line in every voice the voice row offers — with the app's own Core ML engine at
/// the app's delivery, and writes a WAV and a word-timing JSON per clip to
/// `spikes/findings/onboarding-clips/`, for the owner to listen to and for
/// `scripts/render-onboarding-clips.sh` to convert into the app bundle. Design:
/// `docs/superpowers/specs/2026-09-14-onboarding-design.md`.
///
/// Not a test: `.enabled` only while that directory exists, which the script creates before running
/// it, so the ordinary suite never pays the minutes it takes. Reads the lines from the app's own
/// `App/Resources/Onboarding/onboarding-manifest.json`, so the manifest is the one source of what
/// is said and by whom.
///
/// The render is the app's: `Segmenter` at the app's pack length and `TextNormalizer` decide the
/// utterances and the spoken form, the engine runs with `.default` options, and the voice route
/// carries the app's spread (`Delivery.spread` in T2SApp, which this package's tests cannot import;
/// the value is repeated here and checked against the app by `DeliveryTests`). Utterances are
/// appended without a gap, as the player plays them, and the timings are offset onto the joined
/// clip. Word ranges index the joined `spoken` string, which is what the onboarding displays.
@Suite(.serialized) struct OnboardingClipProbe {
    /// `<repo>`; this file is `<repo>/Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/OnboardingClipProbe.swift`.
    static let repoRoot: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root
    }()

    static let outputDirectory = repoRoot.appending(path: "spikes/findings/onboarding-clips", directoryHint: .isDirectory)
    static let manifestURL = repoRoot.appending(path: "App/Resources/Onboarding/onboarding-manifest.json")

    static var isRequested: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: outputDirectory.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// `Delivery.spread`: the one value the app renders at.
    static let spread: Float = 1.25

    struct Manifest: Decodable {
        struct Book: Decodable {
            var id: String
            var title: String
            var author: String
            /// The voice its line rises in; nil for a book that only floats.
            var voice: String?
            /// The short line that rises with the card; nil for a book that only floats.
            var line: String?
            /// The hero's longer passage for the voice screen, rendered in every voice.
            var passage: String?
        }
        var hero: String
        var voices: [String]
        var books: [Book]
    }

    /// What the app reads back beside each clip: the joined spoken text and each word's range in it.
    struct Timings: Encodable {
        struct Word: Encodable {
            var start: TimeInterval
            var end: TimeInterval
            var range: [Int]
        }
        var book: String
        var voice: String
        var spoken: String
        var duration: TimeInterval
        var words: [Word]
    }

    static func voiceID(_ voice: String) -> String {
        KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: voice, spread: spread).rawValue
    }

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && OnboardingClipProbe.isRequested))
    func render() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let out = Self.outputDirectory
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: Self.manifestURL))
        let hero = try #require(manifest.books.first { $0.id == manifest.hero })

        // Each book's line in its own voice — what rises with the cards — then the hero's passage
        // in every voice the row offers, under its own name, for the voice screen.
        var jobs: [(book: Manifest.Book, voice: String, text: String, name: String)] = []
        for book in manifest.books where book.id != hero.id {
            guard let voice = book.voice, let line = book.line else { continue }
            jobs.append((book, voice, line, "onboarding-\(book.id)-\(voice)"))
        }
        let passage = try #require(hero.passage ?? hero.line, "the hero needs a passage or a line")
        for voice in manifest.voices { jobs.append((hero, voice, passage, "onboarding-\(hero.id)-passage-\(voice)")) }

        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: .default)
        let segmenter = Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var report: [String] = ["# Onboarding clips — \(Date().ISO8601Format())", ""]

        for job in jobs {
            let name = job.name
            let block = SourceBlock(text: job.text, position: Position(resourceHref: job.book.id, progression: 0, charOffset: 0))
            let utterances = segmenter.segment(block)
            var samples: [Float] = []
            var spoken = ""
            var words: [Timings.Word] = []
            for utterance in utterances {
                let result = try await engine.synthesize(.init(spoken: utterance.spoken, voiceID: Self.voiceID(job.voice)))
                let offset = TimeInterval(samples.count) / result.audio.sampleRate
                if !spoken.isEmpty { spoken += " " }
                let base = spoken.utf16.count
                spoken += utterance.spoken
                samples += result.audio.samples
                for timing in result.wordTimings {
                    words.append(.init(start: offset + timing.start, end: offset + timing.end,
                                       range: [base + timing.spokenRange.lowerBound, base + timing.spokenRange.upperBound]))
                }
            }
            let duration = TimeInterval(samples.count) / PCMAudio.defaultSampleRate
            try KokoroAudioProbe.writeWAV(samples, to: out.appending(path: "\(name).wav"))
            let timings = Timings(book: job.book.id, voice: job.voice, spoken: spoken, duration: duration, words: words)
            try encoder.encode(timings).write(to: out.appending(path: "\(name).json"))
            report.append(String(format: "- %@: %.1f s, %d utterance(s), %d words", name, duration, utterances.count, words.count))
        }
        try report.joined(separator: "\n").write(to: out.appending(path: "README.md"), atomically: true, encoding: .utf8)
        for line in report { print(line) }
    }
}
