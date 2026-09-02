import Foundation
import Testing
@testable import T2SCore

@Suite struct TimelineCodecTests {
    let chapter = Chapter(
        title: "One",
        position: Position(resourceHref: "c1.xhtml", progression: 0),
        utterances: (0..<200).map { i in
            var u = makeUtterance("Sentence number \(i) of the chapter.", seconds: 2, charOffset: i * 40)
            if i % 2 == 0 {
                u.audioRef = "key\(i)"
                u.duration = .actual(2.25)
                u.wordTimings = [WordTiming(spokenRange: 0..<8, start: 0, end: 0.5)]
            }
            return u
        }
    )

    @Test func roundTrips() throws {
        let data = try TimelineCodec.encode(chapter)
        #expect(try TimelineCodec.decode(data) == chapter)
    }

    @Test func isCompactAndTagged() throws {
        let data = try TimelineCodec.encode(chapter)
        #expect(data.prefix(4) == Data("T2SC".utf8))
        #expect(data.count < 200 * 100)                // well below one uncompressed JSON row per utterance
    }

    @Test func rejectsBadMagic() {
        #expect(throws: TimelineCodec.Error.badMagic) { try TimelineCodec.decode(Data("NOPE\u{0}\u{0}xx".utf8)) }
    }

    @Test func rejectsFutureVersion() throws {
        var data = try TimelineCodec.encode(chapter)
        data[4] = 0xFF; data[5] = 0xFF
        #expect(throws: TimelineCodec.Error.unsupportedVersion(0xFFFF)) { try TimelineCodec.decode(data) }
    }
}
