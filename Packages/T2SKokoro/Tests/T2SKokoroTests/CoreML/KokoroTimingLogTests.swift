import Foundation
import Testing
@testable import T2SKokoro

@Suite struct KokoroTimingLogTests {
    private func path() -> String {
        FileManager.default.temporaryDirectory.appending(path: "timing-\(UUID().uuidString).log").path(percentEncoded: false)
    }

    private func write(_ line: String, to descriptor: Int32) {
        Array((line + "\n").utf8).withUnsafeBufferPointer { _ = Darwin.write(descriptor, $0.baseAddress, $0.count) }
    }

    @Test func eachLaunchAppendsUnderItsHeader() throws {
        let path = path()
        let first = KokoroTimingLog.open(path: path, launchedAt: Date(timeIntervalSince1970: 0))
        #expect(first >= 0)
        write("00:00:01.000 kokoro stage a loaded in 59.46 s (1/14)", to: first)
        close(first)
        let second = KokoroTimingLog.open(path: path, launchedAt: Date(timeIntervalSince1970: 3600))
        write("01:00:01.000 kokoro stage a loaded in 0.47 s (1/14)", to: second)
        close(second)

        let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 4)
        #expect(lines[0].hasPrefix("==== launch "))
        #expect(lines[1].contains("59.46 s"))
        #expect(lines[2].hasPrefix("==== launch "))
        #expect(lines[3].contains("0.47 s"))
        #expect(lines[0] != lines[2])
    }

    @Test func aFilePastTheCapIsMovedAsideFirst() throws {
        let path = path()
        try Data(repeating: UInt8(ascii: "x"), count: 300).write(to: URL(filePath: path))
        let descriptor = KokoroTimingLog.open(path: path, capBytes: 256)
        close(descriptor)
        let fresh = try String(contentsOfFile: path, encoding: .utf8)
        #expect(fresh.hasPrefix("==== launch "))
        #expect(!fresh.contains("xxx"))
        #expect(try String(contentsOfFile: path + ".1", encoding: .utf8).count == 300)
    }

    @Test func theHeaderIsLocalTimeToTheSecond() {
        let header = KokoroTimingLog.header(launchedAt: Date(timeIntervalSince1970: 0))
        #expect(header.hasPrefix("==== launch 19"))
        #expect(header.hasSuffix(" ===="))
        #expect(header.count == "==== launch 1970-01-01 00:00:00 ====".count)
    }
}
