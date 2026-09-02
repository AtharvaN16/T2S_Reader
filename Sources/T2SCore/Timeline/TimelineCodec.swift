import Foundation

public enum TimelineCodec {
    public static let formatVersion: UInt16 = 1
    static let magic = Data("T2SC".utf8)

    public enum Error: Swift.Error, Equatable {
        case badMagic
        case unsupportedVersion(UInt16)
        case corrupt
    }

    public static func encode(_ chapter: Chapter) throws -> Data {
        let json = try JSONEncoder().encode(chapter)
        let compressed = try (json as NSData).compressed(using: .lzfse) as Data
        var out = magic
        var v = formatVersion.littleEndian
        withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
        out.append(compressed)
        return out
    }

    public static func decode(_ input: Data) throws -> Chapter {
        // Rebase: a slice keeps its parent's indices, so absolute subscripts below would trap.
        let data = Data(input)
        guard data.count >= 6, data.prefix(4) == magic else { throw Error.badMagic }
        let version = UInt16(data[4]) | (UInt16(data[5]) << 8)
        guard version == formatVersion else { throw Error.unsupportedVersion(version) }
        let payload = data.dropFirst(6)
        guard let json = try? (payload as NSData).decompressed(using: .lzfse) as Data else { throw Error.corrupt }
        do { return try JSONDecoder().decode(Chapter.self, from: json) }
        catch { throw Error.corrupt }
    }
}
