import Foundation

public struct ZipEntry: Hashable, Sendable {
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

/// Writes a ZIP archive with every entry stored (method 0) in the order given, a fixed timestamp,
/// and no extra fields — exactly what the EPUB container (OCF) needs for `mimetype`, and enough for
/// everything else we write. Not a general ZIP library: no compression, no ZIP64, ASCII names.
public enum StoredZipWriter {
    private static let versionNeeded: UInt16 = 20
    private static let dosTime: UInt16 = 0          // 00:00:00
    private static let dosDate: UInt16 = 0x0021     // 1980-01-01

    public static func archive(_ entries: [ZipEntry]) -> Data {
        var out = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(out.count)

            // Local file header (30 bytes + name), then the stored bytes.
            out.append(le32(0x0403_4B50))
            out.append(le16(versionNeeded))
            out.append(le16(0))                       // general purpose flags
            out.append(le16(0))                       // method: stored
            out.append(le16(dosTime))
            out.append(le16(dosDate))
            out.append(le32(crc))
            out.append(le32(size))
            out.append(le32(size))
            out.append(le16(UInt16(name.count)))
            out.append(le16(0))                       // extra field length
            out.append(name)
            out.append(entry.data)

            // Central directory header (46 bytes + name).
            central.append(le32(0x0201_4B50))
            central.append(le16(versionNeeded))       // version made by
            central.append(le16(versionNeeded))       // version needed
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(dosTime))
            central.append(le16(dosDate))
            central.append(le32(crc))
            central.append(le32(size))
            central.append(le32(size))
            central.append(le16(UInt16(name.count)))
            central.append(le16(0))                   // extra
            central.append(le16(0))                   // comment
            central.append(le16(0))                   // disk number start
            central.append(le16(0))                   // internal attributes
            central.append(le32(0))                   // external attributes
            central.append(le32(offset))
            central.append(name)
        }

        let centralOffset = UInt32(out.count)
        out.append(central)
        // End of central directory (22 bytes).
        out.append(le32(0x0605_4B50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(entries.count)))
        out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(centralOffset))
        out.append(le16(0))
        return out
    }

    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }
}
