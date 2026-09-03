import Foundation
import Testing
@testable import T2SAudio

@Suite struct KokoroVoiceIDTests {
    @Test func buildsTheRawValueFromTheEngineAndVoice() {
        let id = KokoroVoiceID(engineID: "kokoro-4e9ecdf0-mlx-misaki1.0.6", voice: "af_heart")
        #expect(id.rawValue == "kokoro:kokoro-4e9ecdf0-mlx-misaki1.0.6:af_heart")
    }

    @Test func roundTripsThroughItsRawValue() throws {
        let id = KokoroVoiceID(engineID: "kokoro-4e9ecdf0-mlx-misaki1.0.6", voice: "bf_emma")
        let parsed = try #require(KokoroVoiceID(rawValue: id.rawValue))
        #expect(parsed == id)
        #expect(parsed.engineID == "kokoro-4e9ecdf0-mlx-misaki1.0.6")
        #expect(parsed.voice == "bf_emma")
    }

    @Test(arguments: [
        "",                         // not a voice ID at all
        "kokoro:",                  // no engine, no voice
        "kokoro:x",                 // an engine but no voice separator
        "kokoro::af_heart",         // empty engine
        "kokoro:a:b:c",             // an engine ID may not contain ':'
        "kokoro:engine:",           // empty voice
        "kokoro:engine:   ",        // blank voice
        "system:foo",               // the system route
        "cloud:fp:v",               // the cloud route
        "KOKORO:engine:af_heart",   // the prefix is exact
    ])
    func rejectsIdentitiesThatAreNotKokoroRoutes(rawValue: String) {
        #expect(KokoroVoiceID(rawValue: rawValue) == nil)
    }

    @Test func advertisesThePrefixItParses() {
        #expect(KokoroVoiceID.prefix == "kokoro:")
        #expect(KokoroVoiceID(engineID: "e", voice: "v").rawValue.hasPrefix(KokoroVoiceID.prefix))
    }
}
