import Foundation
import Testing
@testable import T2SLibrary

@Suite struct StoredZipWriterTests {
    @Test func crc32MatchesTheCheckValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data()) == 0)
    }

    @Test func layoutIsStoredAndInOrder() {
        let entries = [ZipEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
                       ZipEntry(name: "META-INF/container.xml", data: Data("<x/>".utf8))]
        let archive = StoredZipWriter.archive(entries)
        let nameBytes = entries.reduce(0) { $0 + $1.name.utf8.count }
        let payload = entries.reduce(0) { $0 + $1.data.count }
        #expect(archive.count == 30 * 2 + 46 * 2 + 22 + 2 * nameBytes + payload)
        #expect(archive.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))      // local file header
        #expect(archive[8..<10] == Data([0x00, 0x00]))                     // method 0 = stored
        #expect(archive[26..<28] == Data([0x08, 0x00]))                    // name length 8
        #expect(archive[28..<30] == Data([0x00, 0x00]))                    // no extra field
        #expect(archive[30..<38] == Data("mimetype".utf8))
        #expect(archive[38..<58] == Data("application/epub+zip".utf8))    // payload follows the name directly
        let eocd = Data(archive.suffix(22))
        #expect(eocd.prefix(4) == Data([0x50, 0x4B, 0x05, 0x06]))
        #expect(eocd[10..<12] == Data([0x02, 0x00]))                       // two entries
        #expect(StoredZipWriter.archive([]).count == 22)
    }

    @Test func unzipVerifiesTheArchive() throws {
        #if os(macOS)
        let entries = [ZipEntry(name: "mimetype", data: Data("application/epub+zip".utf8)),
                       ZipEntry(name: "OEBPS/a.txt", data: Data(repeating: 0x41, count: 5_000)),
                       ZipEntry(name: "OEBPS/b.txt", data: Data())]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).zip")
        try StoredZipWriter.archive(entries).write(to: url)
        let test = try Shell.run("/usr/bin/unzip", ["-t", url.path])
        #expect(test.status == 0, "\(test.output)")
        let list = try Shell.run("/usr/bin/unzip", ["-Z1", url.path])
        #expect(list.output.split(separator: "\n").map(String.init) == ["mimetype", "OEBPS/a.txt", "OEBPS/b.txt"])
        let verbose = try Shell.run("/usr/bin/unzip", ["-Zv", url.path])
        #expect(!verbose.output.lowercased().contains("defl"))
        #endif
    }
}
