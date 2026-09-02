import Foundation

public protocol AudioCodec: Sendable {
    var identifier: String { get }
    func encode(_ pcm: PCMAudio) throws -> Data
    func decode(_ data: Data) throws -> PCMAudio
}

public enum AudioCodecError: Error, Equatable, Sendable {
    case malformed
}

/// Tests only. Raw PCM is never persisted in production (spec §3.4).
public struct RawPCMCodec: AudioCodec {
    public let identifier = "pcm-f32le"
    public init() {}

    public func encode(_ pcm: PCMAudio) throws -> Data {
        var out = Data(capacity: 8 + pcm.samples.count * 4)
        var rate = pcm.sampleRate.bitPattern.littleEndian
        withUnsafeBytes(of: &rate) { out.append(contentsOf: $0) }
        for s in pcm.samples {
            var bits = s.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { out.append(contentsOf: $0) }
        }
        return out
    }

    public func decode(_ input: Data) throws -> PCMAudio {
        let data = Data(input)
        guard data.count >= 8, (data.count - 8) % 4 == 0 else { throw AudioCodecError.malformed }
        let rate = Double(bitPattern: UInt64(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }))
        var samples: [Float] = []
        samples.reserveCapacity((data.count - 8) / 4)
        var offset = 8
        while offset < data.count {
            let bits = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            samples.append(Float(bitPattern: UInt32(littleEndian: bits)))
            offset += 4
        }
        return PCMAudio(sampleRate: rate, samples: samples)
    }
}
