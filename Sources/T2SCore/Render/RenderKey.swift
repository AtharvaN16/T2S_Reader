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
        // Lower-case hex by table: `String(format: "%02x")` per byte was most of the cost of the
        // thousands of keys a document load builds on the main actor (audit §5.4).
        var hex: [UInt8] = []
        hex.reserveCapacity(64)
        for byte in digest {
            hex.append(Self.hexDigits[Int(byte >> 4)])
            hex.append(Self.hexDigits[Int(byte & 0x0F)])
        }
        rawValue = String(decoding: hex, as: UTF8.self)
    }

    public var fileName: String { rawValue + ".audio" }

    private static let hexDigits = Array("0123456789abcdef".utf8)
}
