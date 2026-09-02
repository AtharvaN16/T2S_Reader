import CryptoKit
import Foundation

/// Filename of a rendered utterance (spec §5). Changing any input makes a new key, so a voice
/// or engine change invalidates the old audio structurally instead of serving it.
public struct RenderKey: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public init(documentID: UUID, utteranceIndex: Int, voiceID: String, engineID: String,
                normalizerVersion: Int, segmenterVersion: Int) {
        let material = [documentID.uuidString, String(utteranceIndex), voiceID, engineID,
                        String(normalizerVersion), String(segmenterVersion)].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(material.utf8))
        rawValue = digest.map { String(format: "%02x", $0) }.joined()
    }

    public var fileName: String { rawValue + ".audio" }
}
