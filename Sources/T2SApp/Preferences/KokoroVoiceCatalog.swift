import T2SAudio

/// The bundled English Kokoro voices, listed under "On-device voices" whether or not the route is
/// available on this device: the choice persists, and an unavailable route falls back per
/// `VoiceRouteResolving`. Only a build that links the engine installs this catalog, so the everyday
/// build lists no Kokoro voices.
///
/// The owner's ask was Kokoro-only: once this build lists at least one engine, the base catalog's
/// system rows (including `systemDefault`) are dropped from `voices()` — there is nothing left to
/// preview or route to on a phone that speaks Kokoro. A base cloud row is kept; the reader's own BYO
/// key is not a "default voice" this catalog gets to remove.
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

    /// The one row that means "no override" once the system rows are gone: its id is
    /// `VoiceOption.systemDefault.id`, which `VoiceRouteResolving` turns into the app's default voice
    /// (Kokoro Heart while the Core ML route is open). Without it a reader who picked a voice once
    /// could never go back to following the Preferences default.
    public static let defaultRow = VoiceOption(
        id: VoiceOption.systemDefault.id, name: "Default", detail: "Heart, unless Preferences says otherwise",
        language: "en", isDefault: true, group: .kokoro
    )

    public func voices() -> [VoiceOption] {
        let activeEngines = engines()
        // No engine yet (the everyday build, or a Kokoro build before its first probe answers):
        // the base rows — system voices included — pass through exactly as they always have.
        let baseVoices = activeEngines.isEmpty
            ? base.voices()
            : [Self.defaultRow] + base.voices().filter { $0.group != .system }
        return baseVoices + activeEngines.flatMap { engine in
            Self.voiceNames.map { name in
                let language = Self.language(for: name)
                let qualifier = engine.label.isEmpty ? "" : " · \(engine.label)"
                return VoiceOption(id: KokoroVoiceID(engineID: engine.identity, voice: name).rawValue,
                                   name: Self.displayName(for: name),
                                   detail: "\(Self.personality(for: name))\(qualifier)",
                                   language: language,
                                   group: .kokoro,
                                   gender: Self.gender(for: name))
            }
        }
    }

    /// `af_heart` → `Heart`: the prefix encodes accent and gender, which the row carries separately —
    /// the accent as the sub-section it sits in (`language(for:)`), the gender as the avatar's tint
    /// (`gender(for:)`).
    private static func displayName(for name: String) -> String {
        let stem = name.split(separator: "_").last.map(String.init) ?? name
        return stem.prefix(1).uppercased() + stem.dropFirst()
    }

    /// The row's second line: how the voice comes across, in three or four words, so a reader can
    /// pick one without previewing all 28. Written from listening to each voice — Kokoro ships no
    /// descriptions of its own. A name not in the table (none today) gets a neutral line.
    public static let personalities: [String: String] = [
        "af_heart": "Warm and intimate",
        "af_alloy": "Clear and even",
        "af_aoede": "Bright and lyrical",
        "af_bella": "Sensual, low and slow",
        "af_jessica": "Crisp and upbeat",
        "af_kore": "Calm and composed",
        "af_nicole": "Whispered, close to the ear",
        "af_nova": "Confident and polished",
        "af_river": "Easy and unhurried",
        "af_sarah": "Friendly and plain-spoken",
        "af_sky": "Airy and light",
        "am_adam": "Deep and deliberate",
        "am_echo": "Smooth and resonant",
        "am_eric": "Steady and matter-of-fact",
        "am_fenrir": "Gruff and grounded",
        "am_liam": "Young and quick",
        "am_michael": "Even and reassuring",
        "am_onyx": "Deep and velvety",
        "am_puck": "Playful and brisk",
        "am_santa": "Jolly and booming",
        "bf_alice": "Poised and precise",
        "bf_emma": "Warm and measured",
        "bf_isabella": "Soft and refined",
        "bf_lily": "Gentle and bright",
        "bm_daniel": "Dry and understated",
        "bm_fable": "A storyteller, rich and rounded",
        "bm_george": "Stately and slow",
        "bm_lewis": "Brisk and no-nonsense",
    ]

    private static func personality(for name: String) -> String {
        personalities[name] ?? "Natural and clear"
    }

    /// The prefix's second letter: `af_`/`bf_` are female voices, `am_`/`bm_` male.
    private static func gender(for name: String) -> VoiceGender {
        let prefix = name.split(separator: "_").first.map(String.init) ?? name
        return prefix.hasSuffix("m") ? .male : .female
    }

    /// A leading `b` marks Kokoro's British voices; the rest are American.
    private static func language(for name: String) -> String {
        name.hasPrefix("b") ? "en-GB" : "en-US"
    }
}
