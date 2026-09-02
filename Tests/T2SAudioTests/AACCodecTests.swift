import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@Suite struct AACCodecTests {
    @Test func roundTripsASecondOfToneCompactly() throws {
        let rate = 24_000.0
        let tone = PCMAudio(sampleRate: rate, samples: (0..<24_000).map { sin(Double($0) * 2 * .pi * 440 / rate) }.map(Float.init))
        let codec = AACCodec()
        let data = try codec.encode(tone)
        #expect(data.count < 12_000)                              // ~32 kbps → about 4 KB/s plus container
        #expect(!Self.topLevelBoxTypes(of: data).contains("free")) // the reserved padding atom must be stripped
        let back = try codec.decode(data)
        #expect(back.sampleRate == rate)
        #expect(abs(back.duration - 1.0) < 0.05)
        let energy = back.samples.reduce(0) { $0 + Double($1 * $1) } / Double(back.samples.count)
        #expect(energy > 0.3)                                     // a sine of amplitude 1 has mean square 0.5
        #expect(codec.identifier == "aac-32k-mono-24k")
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { try AACCodec().decode(Data("not audio".utf8)) }
    }

    /// A minimal top-level MP4/M4A box walker: reads `size`/`type` pairs and returns the `type`
    /// four-char codes found at the top level, without descending into any box's contents.
    private static func topLevelBoxTypes(of data: Data) -> [String] {
        let bytes = [UInt8](data)
        var types: [String] = []
        var off = 0
        while off + 8 <= bytes.count {
            let size = Int(bytes[off]) << 24 | Int(bytes[off + 1]) << 16 | Int(bytes[off + 2]) << 8 | Int(bytes[off + 3])
            guard let type = String(bytes: bytes[(off + 4)..<(off + 8)], encoding: .ascii) else { break }
            types.append(type)
            if size == 0 { break }              // box extends to end of data
            guard size >= 8, off + size <= bytes.count else { break }
            off += size
        }
        return types
    }
}
