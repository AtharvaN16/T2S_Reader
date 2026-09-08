import Testing
import T2SAudio
@testable import T2SApp

/// The on-device voice's delivery is fixed at 1.25 (Plan 14; the owner's listen) and rides on the
/// voice route of every render, never on the stored voice choice.
@Suite struct DeliveryTests {
    @Test func isFixedAtOneAndAQuarter() {
        #expect(Delivery.spread == 1.25)
    }

    @Test(arguments: [
        ("kokoro:e:af_heart", "kokoro:e:af_heart@1.25"),
        ("kokoro:e:af_heart@2", "kokoro:e:af_heart@1.25"),     // the app decides, not a stored id
        ("kokoro:e:af_heart@1.25", "kokoro:e:af_heart@1.25"),  // idempotent
        ("default", "default"),
        ("system:com.apple.voice", "system:com.apple.voice"),
        ("cloud:fp:v", "cloud:fp:v"),
        ("kokoro:bad", "kokoro:bad"),                           // not a route: left for the router to refuse
    ])
    func appliesToKokoroRoutesOnly(voiceID: String, expected: String) {
        #expect(Delivery.applied(to: voiceID) == expected)
    }
}
