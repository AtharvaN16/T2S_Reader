import Foundation

public enum TimelineCodec {
    public static let formatVersion: UInt16 = 1
    static let magic = Data("T2SC".utf8)
    static let headerSize = 10

    public enum Error: Swift.Error, Equatable {
        case badMagic
        case unsupportedVersion(UInt16)
        case corrupt
    }

    public struct EncodedChapter: Hashable, Sendable {
        public var chapter: Chapter
        public var segmenterVersion: Int
        public var normalizerVersion: Int

        public init(chapter: Chapter, segmenterVersion: Int, normalizerVersion: Int) {
            self.chapter = chapter
            self.segmenterVersion = segmenterVersion
            self.normalizerVersion = normalizerVersion
        }
    }

    public static func encode(_ chapter: Chapter, segmenterVersion: Int, normalizerVersion: Int) throws -> Data {
        let json = try JSONEncoder().encode(chapter)
        let compressed = try (json as NSData).compressed(using: .lzfse) as Data
        var out = magic
        appendUInt16LE(formatVersion, to: &out)
        appendUInt16LE(UInt16(segmenterVersion), to: &out)
        appendUInt16LE(UInt16(normalizerVersion), to: &out)
        out.append(compressed)
        return out
    }

    public static func decode(_ input: Data) throws -> EncodedChapter {
        // Rebase: a slice keeps its parent's indices, so absolute subscripts below would trap.
        let data = Data(input)
        guard data.count >= headerSize, data.prefix(4) == magic else { throw Error.badMagic }
        let version = readUInt16LE(data, at: 4)
        guard version == formatVersion else { throw Error.unsupportedVersion(version) }
        let segmenterVersion = readUInt16LE(data, at: 6)
        let normalizerVersion = readUInt16LE(data, at: 8)
        let payload = data.dropFirst(headerSize)
        guard let json = try? (payload as NSData).decompressed(using: .lzfse) as Data else { throw Error.corrupt }
        do {
            let chapter = try JSONDecoder().decode(Chapter.self, from: json)
            return EncodedChapter(
                chapter: chapter,
                segmenterVersion: Int(segmenterVersion),
                normalizerVersion: Int(normalizerVersion)
            )
        } catch { throw Error.corrupt }
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        return UInt16(data[base]) | (UInt16(data[base + 1]) << 8)
    }
}
