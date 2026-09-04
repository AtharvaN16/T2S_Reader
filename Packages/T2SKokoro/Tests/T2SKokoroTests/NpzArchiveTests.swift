import Compression
import Foundation
import MLXUtilsLibrary
import Testing

/// `NpzArchive` replaces ZIPFoundation in the vendored `Packages/MLXUtilsLibrary` (see its README),
/// so it is tested here, where that package is already in the graph. The archives are built by hand
/// in memory: an npz is a plain ZIP, and writing the bytes is the only way to pin what the reader
/// must tolerate — a stored entry, a deflated one, a directory entry, and the malformed cases.
///
/// The end-to-end proof is elsewhere: the model-backed suites read the real 14 MB `voices.npz`
/// through `NpyzReader.read(fileFromPath:)`, which goes through this reader.
struct NpzArchiveTests {
    @Test func readsStoredAndDeflatedEntriesFromOneArchive() throws {
        let stored = Data("the quick brown fox".utf8)
        // Repetitive enough that deflate actually shrinks it, so the entry is really compressed.
        let deflated = Data(String(repeating: "kokoro voices ", count: 64).utf8)
        let archive = try ZipWriter()
            .adding("stored.npy", stored, compressed: false)
            .adding("deflated.npy", deflated, compressed: true)
            .finish()

        let entries = try NpzArchive.entries(in: archive)

        #expect(entries.count == 2)
        #expect(entries["stored.npy"] == stored)
        #expect(entries["deflated.npy"] == deflated)
    }

    @Test func skipsDirectoryEntries() throws {
        let payload = Data("af_heart".utf8)
        let archive = try ZipWriter()
            .adding("voices/", Data(), compressed: false)
            .adding("voices/af_heart.npy", payload, compressed: false)
            .finish()

        let entries = try NpzArchive.entries(in: archive)

        #expect(entries.keys.sorted() == ["voices/af_heart.npy"])
        #expect(entries["voices/af_heart.npy"] == payload)
    }

    @Test func readsAnEntryStoredBehindALocalExtraField() throws {
        // The local header's extra field is routinely a different length from the central
        // directory's, so the data offset has to come from the local header.
        let payload = Data("behind an extra field".utf8)
        let archive = try ZipWriter()
            .adding("padded.npy", payload, compressed: false, localExtraFieldLength: 20)
            .finish()

        #expect(try NpzArchive.entries(in: archive)["padded.npy"] == payload)
    }

    @Test func readsAnEmptyArchive() throws {
        #expect(try NpzArchive.entries(in: ZipWriter().finish()).isEmpty)
    }

    @Test func rejectsDataThatIsNotAnArchive() {
        #expect(throws: NpzArchive.Failure.notAnArchive) {
            try NpzArchive.entries(in: Data(repeating: 0x41, count: 512))
        }
    }

    @Test func rejectsAnArchiveThatLostItsDirectory() throws {
        let archive = try ZipWriter()
            .adding("stored.npy", Data(repeating: 0x2A, count: 256), compressed: false)
            .finish()

        #expect(throws: NpzArchive.Failure.notAnArchive) {
            try NpzArchive.entries(in: archive.prefix(archive.count / 2))
        }
    }

    @Test func rejectsAnEntryThatRunsPastTheEndOfTheArchive() throws {
        let archive = try ZipWriter()
            .adding("stored.npy", Data(repeating: 0x2A, count: 8), compressed: false,
                    centralCompressedSizeOverride: 4096)
            .finish()

        #expect(throws: NpzArchive.Failure.truncated("data for stored.npy")) {
            try NpzArchive.entries(in: archive)
        }
    }

    @Test func rejectsAnUnsupportedCompressionMethod() throws {
        let archive = try ZipWriter()
            .adding("bzip2.npy", Data("payload".utf8), compressed: false, methodOverride: 12)
            .finish()

        #expect(throws: NpzArchive.Failure.unsupportedCompressionMethod(12, entry: "bzip2.npy")) {
            try NpzArchive.entries(in: archive)
        }
    }

    @Test func rejectsAnEntryThatDoesNotDecompressToItsDeclaredSize() throws {
        let archive = try ZipWriter()
            .adding("short.npy", Data("payload".utf8), compressed: false, uncompressedSizeOverride: 99)
            .finish()

        #expect(throws: NpzArchive.Failure.sizeMismatch(entry: "short.npy")) {
            try NpzArchive.entries(in: archive)
        }
    }
}

/// A minimal ZIP writer for the tests: local headers, then the central directory, then the
/// end-of-central-directory record. No CRCs (the reader does not check them) and no ZIP64.
private struct ZipWriter {
    private struct Entry {
        var name: String
        var method: UInt16
        /// What the central directory claims, which one failure test makes deliberately wrong.
        var compressedSize: UInt32
        var uncompressedSize: UInt32
        var offset: UInt32
    }

    private var bytes = Data()
    private var entries: [Entry] = []

    /// `compressed` deflates the payload; the overrides exist to write archives a well-behaved
    /// writer never would, which is exactly what the failure tests need.
    func adding(_ name: String, _ payload: Data, compressed: Bool,
                localExtraFieldLength: Int = 0, methodOverride: UInt16? = nil,
                uncompressedSizeOverride: UInt32? = nil,
                centralCompressedSizeOverride: UInt32? = nil) throws -> ZipWriter {
        var copy = self
        let stored = compressed ? try Self.deflate(payload) : payload
        let offset = UInt32(copy.bytes.count)
        let nameBytes = Data(name.utf8)

        copy.bytes.append(Self.uint32(0x0403_4b50))
        copy.bytes.append(Self.uint16(20))                                  // version needed
        copy.bytes.append(Self.uint16(0))                                   // flags
        copy.bytes.append(Self.uint16(methodOverride ?? (compressed ? 8 : 0)))
        copy.bytes.append(Self.uint16(0))                                   // mod time
        copy.bytes.append(Self.uint16(0))                                   // mod date
        copy.bytes.append(Self.uint32(0))                                   // crc32, unchecked
        copy.bytes.append(Self.uint32(UInt32(stored.count)))
        copy.bytes.append(Self.uint32(uncompressedSizeOverride ?? UInt32(payload.count)))
        copy.bytes.append(Self.uint16(UInt16(nameBytes.count)))
        copy.bytes.append(Self.uint16(UInt16(localExtraFieldLength)))
        copy.bytes.append(nameBytes)
        copy.bytes.append(Data(repeating: 0, count: localExtraFieldLength))
        copy.bytes.append(stored)

        copy.entries.append(Entry(name: name, method: methodOverride ?? (compressed ? 8 : 0),
                                  compressedSize: centralCompressedSizeOverride ?? UInt32(stored.count),
                                  uncompressedSize: uncompressedSizeOverride ?? UInt32(payload.count),
                                  offset: offset))
        return copy
    }

    func finish() throws -> Data {
        var output = bytes
        let directoryStart = UInt32(output.count)
        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            output.append(Self.uint32(0x0201_4b50))
            output.append(Self.uint16(20))                                  // version made by
            output.append(Self.uint16(20))                                  // version needed
            output.append(Self.uint16(0))                                   // flags
            output.append(Self.uint16(entry.method))
            output.append(Self.uint16(0))                                   // mod time
            output.append(Self.uint16(0))                                   // mod date
            output.append(Self.uint32(0))                                   // crc32
            output.append(Self.uint32(entry.compressedSize))
            output.append(Self.uint32(entry.uncompressedSize))
            output.append(Self.uint16(UInt16(nameBytes.count)))
            output.append(Self.uint16(0))                                   // extra length
            output.append(Self.uint16(0))                                   // comment length
            output.append(Self.uint16(0))                                   // disk number
            output.append(Self.uint16(0))                                   // internal attributes
            output.append(Self.uint32(0))                                   // external attributes
            output.append(Self.uint32(entry.offset))
            output.append(nameBytes)
        }
        let directorySize = UInt32(output.count) - directoryStart

        output.append(Self.uint32(0x0605_4b50))
        output.append(Self.uint16(0))                                       // this disk
        output.append(Self.uint16(0))                                       // disk with directory
        output.append(Self.uint16(UInt16(entries.count)))
        output.append(Self.uint16(UInt16(entries.count)))
        output.append(Self.uint32(directorySize))
        output.append(Self.uint32(directoryStart))
        output.append(Self.uint16(0))                                       // comment length
        return output
    }

    /// Raw deflate, the same encoding a ZIP entry carries.
    private static func deflate(_ payload: Data) throws -> Data {
        var destination = Data(count: payload.count + 64)
        let written = destination.withUnsafeMutableBytes { output -> Int in
            payload.withUnsafeBytes { input -> Int in
                compression_encode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, output.count,
                                          input.bindMemory(to: UInt8.self).baseAddress!, payload.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        #expect(written > 0)
        return destination.prefix(written)
    }

    private static func uint16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func uint32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
              UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }
}
