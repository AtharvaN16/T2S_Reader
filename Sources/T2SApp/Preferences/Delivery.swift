import T2SAudio

/// How the on-device voice delivers a line — the model's own pitch contour, widened by a fixed
/// quarter before the decoder sees it (`KokoroSynthesisRequest.f0Spread`) — and which revision of
/// the engine's finishing the render gets.
///
/// The spread is fixed, not a setting, by the owner's listen of 2026-09-08
/// (`spikes/findings/2026-09-08-quality-levers.md`): 1.25 "feels more alive", 1.5 "not wrong", and
/// three presets "unnecessarily complicated". Both values are attached to the voice route of every
/// render (`kokoro:<engine>:<voice>@1.25#2`) rather than baked into the engine's defaults, so they
/// are part of every render key — a library re-renders consistently the first time it plays under a
/// new value, instead of mixing utterances rendered either side of the change — while the reader's
/// stored voice choice never carries them and survives any change unharmed. Bumping the engine
/// identity would have re-rendered too, but the router treats an unknown identity as "fall back to
/// the default voice", which would have turned every reader's Bella into Heart.
public enum Delivery {
    /// The one value the app renders at. 1 would be the model's own.
    public static let spread: Float = 1.25

    /// The revision of the engine's finishing — what it does to each call's audio after the model.
    /// Spec §5: a change that alters an engine's audio must change the key, and this is the Kokoro
    /// key's lever for a change the engine identity cannot carry. 2 (2026-09-10) is the tail window
    /// zeroed by place (`KokoroCoreMLTailClick`); the island rule before it went out untagged, on the
    /// spread's re-render. Bump it whenever the engine's post-processing changes what it renders.
    public static let finish = 2

    /// `voiceID` with the app's delivery and finishing attached when it is an on-device Kokoro
    /// route; any other route, and anything the router will refuse anyway, comes back untouched.
    /// Replaces whatever a stored ID might carry: the app decides, not the store.
    public static func applied(to voiceID: String) -> String {
        guard let id = KokoroVoiceID(rawValue: voiceID) else { return voiceID }
        return id.withSpread(spread).withFinish(finish).rawValue
    }
}
