import T2SAudio

/// The bundled English Kokoro voices, listed under "Kokoro (beta)" whether or not the route is
/// available on this device: the choice persists, and an unavailable route falls back per
/// `VoiceRouteResolving`. Only a build that links the engine installs this catalog, so the everyday
/// build lists no Kokoro voices.
public struct KokoroVoiceCatalog: VoiceCatalog {
    /// The 28 English voice names, in picker order — `af_heart`, the model's reference voice, leads.
    /// One list for both runtimes: the same voices ship as rows of `voices.npz` on the MLX route and
    /// as one `<name>.bin` each on the Core ML route.
    public static let voiceNames: [String] = [
        "af_heart", "af_alloy", "af_aoede", "af_bella", "af_jessica", "af_kore", "af_nicole",
        "af_nova", "af_river", "af_sarah", "af_sky", "am_adam", "am_echo", "am_eric", "am_fenrir",
        "am_liam", "am_michael", "am_onyx", "am_puck", "am_santa", "bf_alice", "bf_emma",
        "bf_isabella", "bf_lily", "bm_daniel", "bm_fable", "bm_george", "bm_lewis",
    ]

    private let base: any VoiceCatalog
    private let engines: @Sendable () -> [(identity: String, label: String)]

    /// Every linked runtime's voices, in the order given: a build that links two runtimes lists the
    /// same 28 voices twice, under different identities, because they are different renders (spec
    /// §5). `label` names the runtime in the row and is empty for the default route, whose rows read
    /// as they always have.
    ///
    /// A closure rather than an array, because a runtime's availability is not always known when the
    /// composition root builds this catalog: a probe that has to hash its weights answers seconds
    /// into the launch, and its rows must appear on the next redraw rather than the next launch.
    /// Asked once per ``voices()`` call — that is, once per body evaluation — so it must stay cheap.
    public init(base: any VoiceCatalog, engines: @escaping @Sendable () -> [(identity: String, label: String)]) {
        self.base = base
        self.engines = engines
    }

    /// The fixed form, for the runtimes a build already knows about before it draws anything.
    public init(base: any VoiceCatalog, engines: [(identity: String, label: String)]) {
        self.init(base: base, engines: { engines })
    }

    public init(base: any VoiceCatalog, engineIdentity: String) {
        self.init(base: base, engines: [(engineIdentity, "")])
    }

    public func voices() -> [VoiceOption] {
        base.voices() + engines().flatMap { engine in
            Self.voiceNames.map { name in
                let language = Self.language(for: name)
                let qualifier = engine.label.isEmpty ? "" : " · \(engine.label)"
                return VoiceOption(id: KokoroVoiceID(engineID: engine.identity, voice: name).rawValue,
                                   name: "\(Self.displayName(for: name)) · \(language)\(qualifier)",
                                   language: language,
                                   group: .kokoro)
            }
        }
    }

    /// `af_heart` → `Heart`: the prefix encodes accent and gender, which the row shows separately.
    private static func displayName(for name: String) -> String {
        let stem = name.split(separator: "_").last.map(String.init) ?? name
        return stem.prefix(1).uppercased() + stem.dropFirst()
    }

    /// A leading `b` marks Kokoro's British voices; the rest are American.
    private static func language(for name: String) -> String {
        name.hasPrefix("b") ? "en-GB" : "en-US"
    }
}
