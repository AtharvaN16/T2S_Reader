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

    /// Endpoint texts earlier builds shipped, so a route stored by one of them — before the app
    /// kept a marker of what it wrote — is still recognised as the app's own and upgraded.
    public static let superseded: [String] = [
        """
        https://kokoro-t2s-a007171ff076.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m2-d13cbe083bd3.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m3-71b4e3836076.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m4-b46b9e051494.herokuapp.com/v1/audio/speech
        """,
    ]

    /// The seven Basic mirrors (`Server/HerokuVoice/scripts/mirrors.sh`), primary first.
    public static let pilot = CloudVoiceDefaults(
        endpointText: """
        https://kokoro-t2s-a007171ff076.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m2-d13cbe083bd3.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m3-71b4e3836076.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m4-b46b9e051494.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m5-aa90f85dde1c.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m6-00b5b70ab03d.herokuapp.com/v1/audio/speech
        https://kokoro-t2s-m7-e73d54cc01ec.herokuapp.com/v1/audio/speech
        """,
        model: "kokoro",
        voice: "af_heart",
        requestRatePerMinute: 20
    )
}
