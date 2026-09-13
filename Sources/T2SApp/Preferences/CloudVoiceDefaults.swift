import Foundation
import T2SAudio

/// The hosted route the app ships with (cloud-first bootstrap spec), so a reader hears Kokoro Heart
/// from the first launch without choosing anything. It is the only cloud route: the endpoint list is
/// a build constant, not a reader setting. Non-secret; the key travels separately
/// (`CloudVoiceKeySeeder`).
public struct CloudVoiceDefaults: Hashable, Sendable {
    /// One endpoint per line, the primary first.
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

    /// The route these values name. Blank lines are ignored; anything that is not a valid HTTPS
    /// endpoint is a build mistake and throws rather than half-configuring the renderer.
    public func configuration() throws -> HTTPVoiceConfiguration {
        let endpoints = try endpointText.split(whereSeparator: \.isNewline).compactMap { line -> URL? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            guard let url = URL(string: trimmed) else { throw HTTPVoiceError.invalidConfiguration }
            return url
        }
        guard !endpoints.isEmpty else { throw HTTPVoiceError.invalidConfiguration }
        let configuration = HTTPVoiceConfiguration(endpoints: endpoints, model: model, voice: voice,
                                                   requestRatePerMinute: requestRatePerMinute)
        try configuration.validate()
        return configuration
    }
}
