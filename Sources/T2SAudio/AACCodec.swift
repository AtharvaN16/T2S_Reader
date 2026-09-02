import AVFoundation
import Foundation
import T2SCore

/// AAC ≈ 32 kbps mono 24 kHz ≈ 14 MB/hour (spec §3.4).
public struct AACCodec: T2SCore.AudioCodec {
    public let identifier = "aac-32k-mono-24k"
    public init() {}

    public func encode(_ pcm: PCMAudio) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeAAC(pcm, to: url)
        let raw = try Data(contentsOf: url)
        return Self.strippingReservedPadding(raw)
    }

    /// Isolated so the `AVAudioFile` deallocates (finalizing the container) before the caller reads the URL back.
    private static func writeAAC(_ pcm: PCMAudio, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: pcm.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: pcm.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.samples.count)) else {
            throw AudioCodecError.malformed
        }
        buffer.frameLength = AVAudioFrameCount(pcm.samples.count)
        pcm.samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: pcm.samples.count)
        }
        try file.write(from: buffer)
    }

    /// `AVAudioFile`/`ExtAudioFile` reserves a fixed `free` atom ahead of `mdat` when writing a
    /// compressed `.m4a` (room for the sample table to grow without relocating audio data). For
    /// short clips that padding dominates the file size, so this strips it and rewrites the
    /// `stco`/`co64` chunk-offset tables in `moov` to point at the new (smaller) `mdat` position.
    /// If the box layout doesn't match what `AVAudioFile` produces, this is a no-op — correctness
    /// (round-tripping through `decode`) matters more than shaving bytes.
    private static func strippingReservedPadding(_ data: Data) -> Data {
        var bytes = [UInt8](data)

        struct Box { var offset: Int; var size: Int; var type: String; var headerSize: Int }

        func readU32(_ off: Int) -> UInt32 {
            UInt32(bytes[off]) << 24 | UInt32(bytes[off + 1]) << 16 | UInt32(bytes[off + 2]) << 8 | UInt32(bytes[off + 3])
        }
        func writeU32(_ off: Int, _ v: UInt32) {
            bytes[off] = UInt8((v >> 24) & 0xFF)
            bytes[off + 1] = UInt8((v >> 16) & 0xFF)
            bytes[off + 2] = UInt8((v >> 8) & 0xFF)
            bytes[off + 3] = UInt8(v & 0xFF)
        }
        func readU64(_ off: Int) -> UInt64 {
            var v: UInt64 = 0
            for i in 0..<8 { v = (v << 8) | UInt64(bytes[off + i]) }
            return v
        }
        func writeU64(_ off: Int, _ v: UInt64) {
            var v = v
            for i in stride(from: 7, through: 0, by: -1) {
                bytes[off + i] = UInt8(v & 0xFF)
                v >>= 8
            }
        }
        func topLevelBoxes(in range: Range<Int>) -> [Box] {
            var result: [Box] = []
            var off = range.lowerBound
            while off + 8 <= range.upperBound {
                let size32 = Int(readU32(off))
                guard let type = String(bytes: bytes[(off + 4)..<(off + 8)], encoding: .ascii) else { break }
                var size = size32
                var headerSize = 8
                if size32 == 1 {
                    guard off + 16 <= range.upperBound else { break }
                    size = Int(readU64(off + 8))
                    headerSize = 16
                } else if size32 == 0 {
                    size = range.upperBound - off
                }
                guard size >= headerSize, off + size <= range.upperBound else { break }
                result.append(Box(offset: off, size: size, type: type, headerSize: headerSize))
                off += size
            }
            return result
        }

        let top = topLevelBoxes(in: 0..<bytes.count)
        let freeBoxes = top.filter { $0.type == "free" }
        guard !freeBoxes.isEmpty, let moovBox = top.first(where: { $0.type == "moov" }) else { return data }

        // Only a `free` box that precedes a given chunk offset should shift that offset down —
        // a `free` box located after `mdat` (before a trailing `moov`, say) must not move chunks
        // that come before it.
        let removed = freeBoxes.map { (start: $0.offset, size: $0.size) }
        func shift(for chunkOffset: Int) -> Int {
            removed.filter { $0.start < chunkOffset }.reduce(0) { $0 + $1.size }
        }

        // Descend only into known container boxes to find the sample-table chunk-offset boxes.
        let containerTypes: Set<String> = ["moov", "trak", "mdia", "minf", "stbl", "mvex", "edts"]
        var offsetBoxes: [Box] = []
        func walk(_ range: Range<Int>) {
            for box in topLevelBoxes(in: range) {
                if box.type == "stco" || box.type == "co64" {
                    offsetBoxes.append(box)
                } else if containerTypes.contains(box.type) {
                    walk((box.offset + box.headerSize)..<(box.offset + box.size))
                } else if box.type == "meta" {
                    walk((box.offset + box.headerSize + 4)..<(box.offset + box.size))  // meta has a 4-byte version/flags header
                }
            }
        }
        walk((moovBox.offset + moovBox.headerSize)..<(moovBox.offset + moovBox.size))
        guard !offsetBoxes.isEmpty else { return data }

        for box in offsetBoxes {
            let contentStart = box.offset + box.headerSize
            guard contentStart + 8 <= bytes.count else { continue }
            let count = Int(readU32(contentStart + 4))
            let entrySize = box.type == "co64" ? 8 : 4
            var entryOff = contentStart + 8
            for _ in 0..<count {
                guard entryOff + entrySize <= bytes.count else { break }
                if box.type == "co64" {
                    let v = readU64(entryOff)
                    writeU64(entryOff, v - UInt64(shift(for: Int(v))))
                } else {
                    let v = readU32(entryOff)
                    writeU32(entryOff, v - UInt32(shift(for: Int(v))))
                }
                entryOff += entrySize
            }
        }

        for box in freeBoxes.sorted(by: { $0.offset > $1.offset }) {
            bytes.removeSubrange(box.offset..<(box.offset + box.size))
        }
        return Data(bytes)
    }

    public func decode(_ data: Data) throws -> PCMAudio {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioCodecError.malformed
        }
        try file.read(into: buffer)
        let n = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: n))
        return PCMAudio(sampleRate: rate, samples: samples)
    }
}
