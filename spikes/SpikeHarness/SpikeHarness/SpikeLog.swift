import Foundation
import os

/// Append-only CSV in Documents (visible in the Files app): ts,event,key,value.
final class SpikeLog: @unchecked Sendable {
    static let shared = SpikeLog()
    let url: URL
    private let queue = DispatchQueue(label: "spikelog")
    private let logger = Logger(subsystem: "com.t2s.spike", category: "bench")
    private let iso = ISO8601DateFormatter()

    private init() {
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("spike-\(Int(Date().timeIntervalSince1970)).csv")
        FileManager.default.createFile(atPath: url.path, contents: Data("ts,event,k,v\n".utf8))
    }

    func record(_ event: String, _ fields: [String: String] = [:]) {
        let ts = iso.string(from: Date())
        let lines = fields.isEmpty
            ? ["\(ts),\(event),,"]
            : fields.sorted { $0.key < $1.key }.map { "\(ts),\(event),\($0.key),\(Self.csv($0.value))" }
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        queue.sync {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            }
        }
        logger.info("\(event, privacy: .public) \(fields.description, privacy: .public)")
    }

    private static func csv(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : s
    }
}
