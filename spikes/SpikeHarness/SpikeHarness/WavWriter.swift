import Foundation

/// Minimal 16-bit PCM mono WAV writer for the §7.4 listening check. Throwaway spike code.
enum WavWriter {
    static func write(samples: [Float], sampleRate: Int, to url: URL) throws {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))                       // PCM, mono
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))  // byte rate
        append(UInt16(2)); append(UInt16(16))                      // block align, bits
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        data.reserveCapacity(data.count + Int(byteCount))
        for s in samples {
            append(Int16(max(-1, min(1, s)) * 32767))
        }
        try data.write(to: url, options: .atomic)
    }
}
