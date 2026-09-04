//
//  MLXUtilsLibrary — added for the vendored copy (see the package README)
//
import Compression
import Foundation

/// Just enough of the ZIP format to read a `.npz` file: an npz is a plain ZIP whose members are
/// `.npy` files, written stored or deflated, never encrypted, never spanned. This replaces the
/// upstream `ZIPFoundation` dependency, whose package identity collides with Readium's fork of the
/// same library.
///
/// Deliberately unsupported, each an error rather than a guess: ZIP64, encryption, and any
/// compression method other than stored (0) and deflate (8). CRCs are not checked — upstream
/// extracted with `skipCRC32: true`, and this app verifies the whole file's SHA-256 before reading it.
public enum NpzArchive {
    public enum Failure: Error, Equatable, Sendable, LocalizedError {
        /// No end-of-central-directory record: not a ZIP file at all.
        case notAnArchive
        case truncated(String)
        /// A ZIP64 archive, which an npz of this size never is.
        case unsupportedZIP64
        case unsupportedCompressionMethod(UInt16, entry: String)
        /// The entry did not decompress to the length the directory promised.
        case sizeMismatch(entry: String)

        public var errorDescription: String? {
            switch self {
            case .notAnArchive: return "The archive has no end-of-central-directory record."
            case .truncated(let part): return "The archive ends inside its \(part)."
            case .unsupportedZIP64: return "ZIP64 archives are not supported."
            case .unsupportedCompressionMethod(let method, let entry):
                return "Entry \(entry) uses unsupported compression method \(method)."
            case .sizeMismatch(let entry): return "Entry \(entry) did not decompress to its declared size."
            }
        }
    }

    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50
    private static let centralDirectorySignature: UInt32 = 0x0201_4b50
    private static let localHeaderSignature: UInt32 = 0x0403_4b50
    /// A size or offset of `0xFFFF_FFFF` means "the real value is in the ZIP64 extra field".
    private static let zip64Sentinel: UInt32 = 0xFFFF_FFFF

    /// Every file entry in the archive, by name. Directory entries (a trailing `/`) are skipped,
    /// as upstream skipped everything that was not a file.
    public static func entries(in data: Data) throws -> [String: Data] {
        let base = data.startIndex
        var cursor = try centralDirectoryStart(in: data)
        var result: [String: Data] = [:]

        while cursor + 46 <= data.count, read32(data, at: cursor) == centralDirectorySignature {
            let method = read16(data, at: cursor + 10)
            let compressedSize = read32(data, at: cursor + 20)
            let uncompressedSize = read32(data, at: cursor + 24)
            let nameLength = Int(read16(data, at: cursor + 28))
            let extraLength = Int(read16(data, at: cursor + 30))
            let commentLength = Int(read16(data, at: cursor + 32))
            let localHeaderOffset = read32(data, at: cursor + 42)
            let nameEnd = cursor + 46 + nameLength
            guard nameEnd <= data.count else { throw Failure.truncated("central directory") }
            let name = String(decoding: data[(base + cursor + 46) ..< (base + nameEnd)], as: UTF8.self)

            guard compressedSize != zip64Sentinel, uncompressedSize != zip64Sentinel,
                  localHeaderOffset != zip64Sentinel else { throw Failure.unsupportedZIP64 }

            if !name.hasSuffix("/") {
                result[name] = try entry(in: data, at: Int(localHeaderOffset), method: method,
                                         compressedSize: Int(compressedSize),
                                         uncompressedSize: Int(uncompressedSize), name: name)
            }
            cursor = nameEnd + extraLength + commentLength
        }
        return result
    }

    /// The local header repeats the name and carries an extra field of its own, whose length
    /// routinely differs from the central directory's — so where the bytes start has to be computed
    /// from this header, never from the central one.
    private static func entry(in data: Data, at offset: Int, method: UInt16, compressedSize: Int,
                              uncompressedSize: Int, name: String) throws -> Data {
        let base = data.startIndex
        guard offset >= 0, offset + 30 <= data.count,
              read32(data, at: offset) == localHeaderSignature else {
            throw Failure.truncated("local header for \(name)")
        }
        let nameLength = Int(read16(data, at: offset + 26))
        let extraLength = Int(read16(data, at: offset + 28))
        let start = offset + 30 + nameLength + extraLength
        let end = start + compressedSize
        guard compressedSize >= 0, start <= data.count, end <= data.count else {
            throw Failure.truncated("data for \(name)")
        }
        let payload = Data(data[(base + start) ..< (base + end)])

        switch method {
        case 0:
            guard payload.count == uncompressedSize else { throw Failure.sizeMismatch(entry: name) }
            return payload
        case 8:
            let inflated = inflate(payload, to: uncompressedSize)
            guard inflated.count == uncompressedSize else { throw Failure.sizeMismatch(entry: name) }
            return inflated
        default:
            throw Failure.unsupportedCompressionMethod(method, entry: name)
        }
    }

    /// `COMPRESSION_ZLIB` decodes raw deflate with no zlib wrapper, which is exactly what a ZIP
    /// entry stores. An empty entry never reaches the decoder, which refuses a zero-length buffer.
    private static func inflate(_ payload: Data, to uncompressedSize: Int) -> Data {
        guard uncompressedSize > 0, !payload.isEmpty else { return Data() }
        var output = Data(count: uncompressedSize)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return payload.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destinationBase, uncompressedSize,
                                                 sourceBase, payload.count, nil, COMPRESSION_ZLIB)
            }
        }
        return output.prefix(written)
    }

    /// The end-of-central-directory record is last, but it carries a variable-length comment, so it
    /// is found by scanning backwards for its signature across the longest comment ZIP allows.
    private static func centralDirectoryStart(in data: Data) throws -> Int {
        guard data.count >= 22 else { throw Failure.notAnArchive }
        let earliest = max(0, data.count - 22 - 0xFFFF)
        var candidate = data.count - 22
        while candidate >= earliest {
            if read32(data, at: candidate) == endOfCentralDirectorySignature {
                let offset = read32(data, at: candidate + 16)
                guard offset != zip64Sentinel else { throw Failure.unsupportedZIP64 }
                guard Int(offset) <= data.count else { throw Failure.truncated("central directory") }
                return Int(offset)
            }
            candidate -= 1
        }
        throw Failure.notAnArchive
    }

    // ZIP is little-endian throughout. `data` may be a slice, so every read is relative to
    // `startIndex` rather than to zero.
    private static func read16(_ data: Data, at offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        return UInt16(data[base]) | UInt16(data[base + 1]) << 8
    }

    private static func read32(_ data: Data, at offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return UInt32(data[base]) | UInt32(data[base + 1]) << 8
            | UInt32(data[base + 2]) << 16 | UInt32(data[base + 3]) << 24
    }
}
