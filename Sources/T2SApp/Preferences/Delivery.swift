import T2SAudio

/// How the on-device voice delivers a line: the model's own pitch contour, widened by a fixed
/// quarter before the decoder sees it (`KokoroSynthesisRequest.f0Spread`).
///
/// Fixed, not a setting, by the owner's listen of 2026-09-08
/// (`spikes/findings/2026-09-08-quality-levers.md`): 1.25 "feels more alive", 1.5 "not wrong", and
/// three presets "unnecessarily complicated". The value is attached to the voice route of every render
/// (`kokoro:<engine>:<voice>@1.25`) rather than baked into the engine's defaults, so it is part of
/// every render key — a library re-renders consistently the first time it plays under a new value,
/// instead of mixing utterances rendered either side of the change — while the reader's stored voice
/// choice never carries it and survives any change unharmed. Bumping the engine identity would have
/// re-rendered too, but the router treats an unknown identity as "fall back to the default voice",
/// which would have turned every reader's Bella into Heart.
public enum Delivery {
    /// The one value the app renders at. 1 would be the model's own.
    public static let spread: Float = 1.25

    /// `voiceID` with the app's delivery attached when it is an on-device Kokoro route; any other
    /// route, and anything the router will refuse anyway, comes back untouched. Replaces a delivery a
    /// stored ID might carry: the app decides, not the store.
    public static func applied(to voiceID: String) -> String {
        guard let id = KokoroVoiceID(rawValue: voiceID) else { return voiceID }
        return id.withSpread(spread).rawValue
    }
}
