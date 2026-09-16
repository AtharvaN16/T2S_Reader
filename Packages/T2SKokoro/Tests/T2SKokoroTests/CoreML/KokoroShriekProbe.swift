import Foundation
import KokoroPipeline
import Testing
import T2SAudio
import T2SCore
@testable import T2SKokoro

/// Diagnostic probe for the owner's report of 2026-09-16 (second one): listening to *Bad Blood* on
/// `af_aoede`, "while the narration was going on normally suddenly the voice would almost scream in
/// a shrill voice… as if it ran out of breath". Six screenshots placed the moment at the end of the
/// last-painted words each time — the end of an utterance.
///
/// These are the six paragraphs, verbatim from the owner's EPUB. Each is segmented exactly as the
/// app does and rendered on `af_aoede` down the app's streaming path, one WAV per utterance plus the
/// paragraph joined the way the coordinator plays it, so the seam can be looked at.
///
/// Not a test: `.enabled` only while `spikes/findings/shriek-probe/` exists. `segmentation()` and
/// the sweeps also want `spikes/findings/shriek-probe/paragraphs.json`, a JSON array of paragraph
/// strings — the book's own text, so it stays out of the repository. Make one from any EPUB:
///
///     python3 -c 'import re,html,json,sys;s=open(sys.argv[1],encoding="utf-8").read();\
///       p=[html.unescape(re.sub(r"<[^>]+>","",x)).strip() for x in re.findall(r"<p[^>]*>(.*?)</p>",s,re.S)];\
///       json.dump([t for t in p if t],open(sys.argv[2],"w"),ensure_ascii=False)' chapter.html paragraphs.json
@Suite(.serialized) struct KokoroShriekProbe {
    static let outputDirectory: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "spikes/findings/shriek-probe", directoryHint: .isDirectory)
    }()

    static var isRequested: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: outputDirectory.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    static var voiceID: String {
        KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: "af_aoede", spread: 1.25, finish: 2).rawValue
    }

    /// The paragraph, and the words the owner's screenshot showed last painted.
    static let paragraphs: [(name: String, lastPainted: String, text: String)] = [
        ("p10", "turn of the twentieth century",
         "On her father\u{2019}s side, she was descended from Charles Louis Fleischmann, a Hungarian immigrant who founded a thriving business known as the Fleischmann Yeast Company. Its remarkable success turned the Fleischmanns into one of the wealthiest families in America at the turn of the twentieth century."),
        ("p15", "younger brother, Christian",
         "ELIZABETH\u{2019}S\nEARLY YEARS were spent in Washington, D.C., where her father held a succession of jobs at government agencies ranging from the State Department to the Agency for International Development. Her mother worked as an aide on Capitol Hill until she interrupted her career to raise Elizabeth and her younger brother, Christian."),
        ("p20", "becoming an entrepreneur / called Google",
         "As college drew closer, Elizabeth set her sights on Stanford. It was the obvious choice for an accomplished student interested in science and computers who dreamed of becoming an entrepreneur. The little agricultural college founded by railroad tycoon Leland Stanford at the end of the nineteenth century had become inextricably linked with Silicon Valley. The internet boom was in full swing then and some of its biggest stars, like Yahoo, had been founded on the Stanford campus. In Elizabeth\u{2019}s senior year, two Stanford Ph.D. students were beginning to attract attention with another little startup called Google."),
        ("p25", "fifty-nine years",
         "The face of Stanford\u{2019}s chemical engineering department was Channing Robertson. Charismatic, handsome, and funny, Robertson had been teaching at the university since 1970 and had a rare ability to connect with his students. He was also by far the hippest member of the engineering faculty, sporting a graying blond mane and showing up to class in leather jackets that made him seem a decade younger than his fifty-nine years."),
        ("p26", "controlled drug-delivery devices",
         "Elizabeth took Robertson\u{2019}s Introduction to Chemical Engineering class and a seminar he taught on controlled drug-delivery devices. She also lobbied him to let her help out in his research lab. Robertson agreed and farmed her out to a Ph.D. student who was working on a project to find the best enzymes to put in laundry detergent."),
    ]

    /// Segmentation only, no model: every utterance of a stretch of the chapter with its length, so
    /// the short ones — the ones a voice like `af_aoede` reads high — can be found without rendering.
    @Test(.enabled(if: KokoroShriekProbe.isRequested))
    func segmentation() throws {
        let url = Self.outputDirectory.appending(path: "paragraphs.json")
        let paragraphs = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        let segmenter = Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength)
        for (p, text) in paragraphs.enumerated() {
            let block = SourceBlock(text: text, position: Position(resourceHref: "probe", progression: 0, charOffset: 0))
            for (i, utterance) in segmenter.segment(block).enumerated() {
                let n = utterance.source.utf16.count
                print(String(format: "seg: p%02d-u%d %4d chars%@ | %@", p, i, n,
                             n < 60 ? "  <<< SHORT" : "          ", utterance.spoken.prefix(64).description))
            }
        }
    }

    /// The same utterance on four voices: is the opening excursion `af_aoede`'s, or every voice's?
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroShriekProbe.isRequested))
    func onset() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: .default)
        let segmenter = Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength)
        let paragraphs = try JSONDecoder().decode([String].self, from: Data(contentsOf: Self.outputDirectory.appending(path: "paragraphs.json")))
        let block = SourceBlock(text: paragraphs[12], position: Position(resourceHref: "probe", progression: 0, charOffset: 0))
        let text = segmenter.segment(block)[2].spoken
        for voice in ["af_aoede", "af_heart", "af_bella", "bf_emma", "af_sky", "am_liam"] {
            let id = KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: voice, spread: 1.25, finish: 2).rawValue
            var audio: [Float] = []
            for try await chunk in engine.synthesizeStreaming(.init(spoken: text, voiceID: id)) {
                if case .piece(let a, _, _) = chunk { audio += a.samples }
            }
            try KokoroAudioProbe.writeWAV(audio, to: Self.outputDirectory.appending(path: "onset-\(voice).wav"))
            print("shriek-probe: onset \(voice)")
        }
    }

    /// Every utterance opens with a pitch peak; on `af_aoede` the peak reaches an octave above the
    /// voice's own narration median. `Delivery.spread` widens the model's predicted contour about its
    /// mean by a quarter before the decoder sees it — chosen on `af_heart`, applied to every voice.
    /// This renders the same utterances at the model's own contour and at the app's, to see how much
    /// of the onset is the app's doing.
    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroShriekProbe.isRequested))
    func spread() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: .default)
        let segmenter = Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength)
        let paragraphs = try JSONDecoder().decode([String].self, from: Data(contentsOf: Self.outputDirectory.appending(path: "paragraphs.json")))
        // The utterances the owner's screenshots sat at the edge of, plus the drop-cap fragment.
        let wanted: [(Int, Int)] = [(12, 2), (7, 0), (7, 2), (3, 0), (18, 0), (13, 0)]

        for spread in [Float(1.0), 1.25] {
            let voice = KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: "af_aoede",
                                      spread: spread, finish: 2).rawValue
            for (p, u) in wanted {
                let block = SourceBlock(text: paragraphs[p], position: Position(resourceHref: "probe", progression: 0, charOffset: 0))
                let utterances = segmenter.segment(block)
                guard u < utterances.count else { continue }
                var audio: [Float] = []
                for try await chunk in engine.synthesizeStreaming(.init(spoken: utterances[u].spoken, voiceID: voice)) {
                    if case .piece(let a, _, _) = chunk { audio += a.samples }
                }
                let tag = spread == 1.0 ? "own" : "app"
                try KokoroAudioProbe.writeWAV(audio, to: Self.outputDirectory.appending(path: "sp-\(tag)-p\(p)u\(u).wav"))
                print("shriek-probe: spread \(spread) p\(p)u\(u)")
            }
        }
    }

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroShriekProbe.isRequested))
    func render() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let engine = KokoroCoreMLEngine(resources: try await KokoroTestSupport.compiledCoreMLResources(), options: .default)
        let segmenter = Segmenter(normalizer: TextNormalizer(), packLength: Segmenter.appPackLength)

        for (name, lastPainted, text) in Self.paragraphs {
            print("heading-probe: ==== \(name)  last painted: \(lastPainted)")
            let block = SourceBlock(text: text, position: Position(resourceHref: "probe", progression: 0, charOffset: 0))
            let utterances = segmenter.segment(block)
            var joined: [Float] = []
            for (i, utterance) in utterances.enumerated() {
                // The app's path: pieces streamed and finalized one at a time.
                var audio: [Float] = []
                var pieceCount = 0
                for try await chunk in engine.synthesizeStreaming(.init(spoken: utterance.spoken, voiceID: Self.voiceID)) {
                    if case .piece(let a, _, _) = chunk { audio += a.samples; pieceCount += 1 }
                }
                joined += audio
                let seconds = Double(audio.count) / Double(PipelineConstants.sampleRate)
                try KokoroAudioProbe.writeWAV(audio, to: Self.outputDirectory.appending(path: "\(name)-u\(i).wav"))
                print(String(format: "shriek-probe: %@-u%d  %d src chars, %d pieces, %.2f s | %@",
                             name, i, utterance.source.utf16.count, pieceCount, seconds,
                             utterance.spoken.suffix(60).description))
            }
            try KokoroAudioProbe.writeWAV(joined, to: Self.outputDirectory.appending(path: "\(name)-joined.wav"))
        }
    }
}
