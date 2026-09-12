import Foundation

/// The hosted route the app ships with (cloud-first bootstrap spec): written into empty settings on
/// the first launch, so a reader hears Kokoro Heart before choosing anything. Non-secret; the key
/// travels separately (`CloudVoiceKeySeeder`).
public struct CloudVoiceDefaults: Hashable, Sendable {
    /// One endpoint per line, the primary first, as the Cloud voices screen stores it.
    public var endpointText: String
    public var model: String
    public var voice: String
    public var requestRatePerMinute: Int

    public init(endpointText: String, model: String, voice: String, requestRatePerMinute: Int) {
        self.endpointText = endpointText
        self.model = model
        self.voice = voice
        self.requestRatePerMinute = requestRatePerMinute
    }

    /// The four Eco mirrors (`Server/HerokuVoice/scripts/mirrors.sh`), primary first.
    public static let pilot = CloudVoiceDefaults(
        endpointText: """
        https://kokoro-t2s-a007171ff076.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m2-d13cbe083bd3.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m3-71b4e3836076.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m4-b46b9e051494.herokuapp.com/v1/audio/speech
        """,
        model: "kokoro",
        voice: "af_heart",
        requestRatePerMinute: 20
    )
}
