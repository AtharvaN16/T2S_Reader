import Foundation
import KokoroPipeline
import Testing
import T2SAudio
import T2SCore
@testable import T2SKokoro

/// Diagnostic probe for the owner's report of 2026-09-16: a chapter headed "3 An Uneasy Equilibrium"
/// says the number "in a very high-pitched sound".
///
/// The EPUB writes the heading as `<h2>3<br/>AN UNEASY EQUILIBRIUM</h2>` and Readium's content
/// iterator flushes at a `<br/>`, so — confirmed against the owner's own file by
/// `T2SReadiumTests/HeadingBlocksProbe` — the number arrives as a block of its own and the app
/// renders the single word "three" as a whole synthesis call.
///
/// `variants` asks what the number sounds like alone against the ways of not leaving it alone;
/// `voices` measures the lone number against each voice's own narration; `length` finds where the
/// effect fades; `joinFix` checks the remedy; `sequence` writes the A/B to listen to. A floor under
/// the voice row was tried and ruled out — Kokoro picks row `phonemes − 1`, so a one-word call reads
/// row 3 of 510, but forcing a higher row moved the pitch *up* on af_heart and never reached the
/// narration baseline on the voices where the lone number is worst.
///
/// Not a test: `.enabled` only while `spikes/findings/heading-probe/` exists.
@Suite(.serialized) struct KokoroHeadingProbe {
    static let outputDirectory: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "spikes/findings/heading-probe", directoryHint: .isDirectory)
    }()

    static var isRequested: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: outputDirectory.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// The app's own route: `Delivery.spread`, `Delivery.finish`.
    static func voiceID(_ voice: String) -> String {
        KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: voice, spread: 1.25, finish: 2).rawValue
    }

    static let allVoices = [
        "af_heart", "af_alloy", "af_aoede", "af_bella", "af_jessica", "af_kore", "af_nicole",
        "af_nova", "af_river", "af_sarah", "af_sky", "am_adam", "am_echo", "am_eric", "am_fenrir",
        "am_liam", "am_michael", "am_onyx", "am_puck", "am_santa", "bf_alice", "bf_emma",
        "bf_isabella", "bf_lily", "bm_daniel", "bm_fable", "bm_george", "bm_lewis",
    ]

    /// A block, as the reader would hand it over, segmented and normalized exactly as the app does.
    static func spoken(_ block: String) -> [String] {
        Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength)
            .segment(SourceBlock(text: block, position: Position(resourceHref: "probe", progression: 0, charOffset: 0)))
            .map(\.spoken)
    }

    /// The lone number as it ships, against every way of not leaving it alone.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroHeadingProbe.isRequested))
    func variants() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: .default)
        let cases: [(String, String)] = [
            ("v-bare", "3"),                                  // what ships today
            ("v-period", "3."),
            ("v-chapter", "Chapter 3"),
            ("v-chapter-period", "Chapter 3."),
            ("v-join-plain", "3\nAN UNEASY EQUILIBRIUM"),
            ("v-join-period", "3.\nAN UNEASY EQUILIBRIUM."),
            ("v-title-alone", "AN UNEASY EQUILIBRIUM"),
            ("v-body", "The ceremony was brief. The British authorities had made sure not only that the grave was already dug, but that quicklime was on hand."),
        ]
        for (name, block) in cases {
            for (i, text) in Self.spoken(block).enumerated() {
                let r = try await engine.synthesize(.init(spoken: text, voiceID: Self.voiceID("af_heart")))
                let suffix = i == 0 ? "" : "-\(i)"
                try KokoroAudioProbe.writeWAV(r.audio.samples, to: Self.outputDirectory.appending(path: "\(name)\(suffix).wav"))
                print("heading-probe: \(name)\(suffix) spoken=\(text.debugDescription)")
            }
        }
    }

    /// How short is too short: the same voice reading blocks of increasing length, against its own
    /// narration. Picks the threshold the merge rule uses.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroHeadingProbe.isRequested))
    func length() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: .default)
        let blocks = [
            "3",
            "Yes.",
            "The Prince.",
            "An uneasy equilibrium",
            "It was an uneasy equilibrium.",
            "It was an uneasy equilibrium that year.",
            "It was an uneasy equilibrium that year, and it did not last.",
            "It was an uneasy equilibrium that year, and it did not last beyond the spring that followed.",
        ]
        for voice in ["am_liam", "af_aoede", "af_sky", "af_heart"] {
            for block in blocks {
                let text = Self.spoken(block)[0]
                let r = try await engine.synthesize(.init(spoken: text, voiceID: Self.voiceID(voice)))
                let name = "len-\(voice)-\(String(format: "%03d", block.utf16.count)).wav"
                try KokoroAudioProbe.writeWAV(r.audio.samples, to: Self.outputDirectory.appending(path: name))
            }
            print("heading-probe: length sweep rendered for \(voice)")
        }
    }

    /// Does joining the number onto the title bring it back to the voice's narration pitch? Measured
    /// on the voices where the lone number is worst, plus the default.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroHeadingProbe.isRequested))
    func joinFix() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: .default)
        let cases: [(String, String)] = [
            ("bare", "3"),
            ("joined", "3\nAN UNEASY EQUILIBRIUM"),
            ("control", "The ceremony was brief, and the grave was already dug."),
        ]
        for voice in ["am_liam", "am_echo", "af_aoede", "af_sky", "af_heart"] {
            for (tag, block) in cases {
                let text = Self.spoken(block)[0]
                let r = try await engine.synthesize(.init(spoken: text, voiceID: Self.voiceID(voice)))
                try KokoroAudioProbe.writeWAV(r.audio.samples, to: Self.outputDirectory.appending(path: "fix-\(voice)-\(tag).wav"))
            }
            print("heading-probe: join fix rendered for \(voice)")
        }
    }

    /// The opening of chapter 3 as the reader actually hears it — the utterances butted together the
    /// way the coordinator plays them from the store — against the same opening with the number
    /// joined onto the title. For the owner's ears, beside the numbers.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroHeadingProbe.isRequested))
    func sequence() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: .default)
        let body = "By 1852, although the British and the Mughals inhabited the same city and sometimes lived in close physical proximity to each other, the two peoples were growing farther and farther apart."
        let takes: [(String, [String])] = [
            ("seq-a-ships", ["3", "AN UNEASY EQUILIBRIUM", body]),
            ("seq-b-joined", ["3\nAN UNEASY EQUILIBRIUM", body]),
        ]
        for (name, blocks) in takes {
            var audio: [Float] = []
            for block in blocks {
                for text in Self.spoken(block) {
                    audio += try await engine.synthesize(.init(spoken: text, voiceID: Self.voiceID("af_heart"))).audio.samples
                }
            }
            try KokoroAudioProbe.writeWAV(audio, to: Self.outputDirectory.appending(path: "\(name).wav"))
            print("heading-probe: \(name) \(String(format: "%.2f", Double(audio.count) / Double(PipelineConstants.sampleRate))) s")
        }
    }

    /// Where in an utterance a word sits, holding the word itself fixed: if Kokoro opens every call
    /// high and declines through it, a one-word call is nothing but the opening rise.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroHeadingProbe.isRequested))
    func position() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: .default)
        let cases: [(String, String)] = [
            ("p-alone", "3"),
            ("p-initial", "3 days passed quietly in the city that winter."),
            ("p-medial", "He waited 3 days in the city that winter."),
            ("p-final", "In the city that winter he waited 3."),
        ]
        for (name, block) in cases {
            for (i, text) in Self.spoken(block).enumerated() where i == 0 {
                let r = try await engine.synthesize(.init(spoken: text, voiceID: Self.voiceID("af_heart")))
                try KokoroAudioProbe.writeWAV(r.audio.samples, to: Self.outputDirectory.appending(path: "\(name).wav"))
                print("heading-probe: \(name) spoken=\(text.debugDescription)")
            }
        }
    }

    /// The lone number on every voice, with a short ordinary sentence beside it for scale.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroHeadingProbe.isRequested))
    func voices() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: .default)
        let bare = Self.spoken("3")[0]
        let control = Self.spoken("The ceremony was brief, and the grave was already dug.")[0]
        for voice in Self.allVoices {
            for (tag, text) in [("bare", bare), ("control", control)] {
                let r = try await engine.synthesize(.init(spoken: text, voiceID: Self.voiceID(voice)))
                try KokoroAudioProbe.writeWAV(r.audio.samples, to: Self.outputDirectory.appending(path: "voice-\(voice)-\(tag).wav"))
            }
            print("heading-probe: rendered \(voice)")
        }
    }
}
