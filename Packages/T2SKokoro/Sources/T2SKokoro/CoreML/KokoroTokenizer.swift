import Foundation
import KokoroPipeline

/// Kokoro's phoneme vocabulary and per-voice style table, and the map from phonemized text to token
/// IDs the Core ML duration model consumes.
///
/// Ported from the Core ML spike's `KokoroTokenizer`
/// (`spikes/SpikeHarness/SpikeHarness/CoreMLBench.swift`), with the MisakiSwift dependency removed:
/// ``tokenize(phonemes:ownersByCharacter:)`` takes the phonemized string plus one Misaki-token owner
/// index per `Character` of that string, instead of walking a `[MToken]` array to build both — so
/// this file has no MisakiSwift import. The two arrays must agree by construction: Task 3 builds
/// `ownersByCharacter` from the same walk over `EnglishG2P`'s tokens that produces `phonemes`, so a
/// length mismatch is a caller bug, not a runtime condition — the `precondition` below says so.
public struct KokoroTokenizer: Sendable {
    /// BOS/EOS boundary and padding token; ``KokoroVocabulary/bosEosTokenId``.
    public static let boundary = KokoroVocabulary.bosEosTokenId

    private let vocab: [String: Int32]
    /// Row-major `[voiceRowCount][PipelineConstants.voiceEmbeddingDim]` float32 voice style table.
    private let voiceRows: [Float]
    public let voiceRowCount: Int

    /// Why a vocabulary or voice file cannot back a tokenizer.
    public enum Failure: Error, Hashable, Sendable, LocalizedError {
        case invalidVocabulary(String)
        case invalidVoiceTable(String)

        public var errorDescription: String? {
            switch self {
            case .invalidVocabulary(let reason): "The Kokoro vocabulary file is not valid: \(reason)."
            case .invalidVoiceTable(let reason): "The Kokoro voice table is not valid: \(reason)."
            }
        }
    }

    public init(vocabURL: URL, voiceURL: URL) throws {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: vocabURL))
        guard let dict = json as? [String: Any], let raw = dict["vocab"] as? [String: Any] else {
            throw Failure.invalidVocabulary("\(vocabURL.lastPathComponent) has no \"vocab\" object")
        }
        var table: [String: Int32] = [:]
        for (symbol, value) in raw {
            guard let number = value as? NSNumber else {
                throw Failure.invalidVocabulary("entry \(symbol) is not a number")
            }
            table[symbol] = number.int32Value
        }
        vocab = table

        let data = try Data(contentsOf: voiceURL)
        let stride = PipelineConstants.voiceEmbeddingDim * 4
        guard !data.isEmpty, data.count % stride == 0 else {
            throw Failure.invalidVoiceTable("\(voiceURL.lastPathComponent) is \(data.count) bytes, not a multiple of \(stride)")
        }
        var floats = [Float](repeating: 0, count: data.count / 4)
        data.withUnsafeBytes { raw in
            for i in 0 ..< floats.count {
                floats[i] = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)))
            }
        }
        voiceRows = floats
        voiceRowCount = data.count / stride
    }

    /// The voice row for a chunk, by the fleet rule in the upstream SDK's `VoiceTable.refS`:
    /// `clamp(count - 1, 0, rows - 1)`, over the *unframed* phonemized string's UTF-16 length —
    /// not the token-ID count ``tokenize(phonemes:ownersByCharacter:)`` returns, which the reference
    /// implementation never uses for this lookup.
    public func refS(phonemeUTF16Count: Int) -> [Float] {
        let dim = PipelineConstants.voiceEmbeddingDim
        let row = max(0, min(voiceRowCount - 1, phonemeUTF16Count - 1))
        return Array(voiceRows[(row * dim) ..< ((row + 1) * dim)])
    }

    /// Maps phoneme characters to token IDs, remembering which Misaki token each surviving character
    /// came from. `ownersByCharacter` must carry exactly one entry per `Character` in `phonemes`, in
    /// the same order; see the type's doc comment for why the two can never disagree except by a
    /// caller bug. Characters with no vocab entry — including Misaki's `❓` unknown marker — are
    /// dropped, matching the SDK's tokenizer.
    public func tokenize(phonemes: String, ownersByCharacter: [Int]) -> (ids: [Int32], owners: [Int], dropped: Int) {
        precondition(
            phonemes.count == ownersByCharacter.count,
            "ownersByCharacter has \(ownersByCharacter.count) entries for \(phonemes.count) phoneme characters"
        )
        var ids: [Int32] = []
        var owners: [Int] = []
        var dropped = 0
        for (character, owner) in zip(phonemes, ownersByCharacter) {
            if let id = vocab[String(character)] {
                ids.append(id)
                owners.append(owner)
            } else {
                dropped += 1
            }
        }
        return (ids, owners, dropped)
    }
}
