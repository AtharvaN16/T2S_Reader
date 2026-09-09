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

    /// The row's second line: how the voice comes across, so a reader can pick one without
    /// previewing all 28. Kokoro ships no descriptions of its own, so this is grounded in
    /// independent listener write-ups per voice (voicerankings.com's Kokoro-82M profiles, checked
    /// against Hugging Face's `hexgrad/Kokoro-82M` voice list) rather than a guess from the name —
    /// the first draft here was guessed and the owner correctly called it out as not matching. Still
    /// worth re-checking against the phone once it can be heard. A name not in the table (none
    /// today) gets a neutral line.
    public static let personalities: [String: String] = [
        "af_heart": "Warm and breathy, a smile in it",
        "af_alloy": "Bright, clean and cheerful",
        "af_aoede": "Deep, velvety and unhurried",
        "af_bella": "Warm and husky, easygoing",
        "af_jessica": "Bright and quick, a little breathy",
        "af_kore": "Warm and steady, a patient guide",
        "af_nicole": "Hushed and whisper-soft, built for sleep",
        "af_nova": "Polished, clear and efficiently warm",
        "af_river": "Husky and unhurried, Gen Z casual",
        "af_sarah": "Polite and plain-spoken, easy to trust",
        "af_sky": "Smooth and composed, an assistant's calm",
        "am_adam": "Trustworthy and clear, neighborly warmth",
        "am_echo": "Soft, breathy and deeply empathetic",
        "am_eric": "Relaxed and modern, a little grit",
        "am_fenrir": "Confident and energetic, a rich texture",
        "am_liam": "Cheerful and quick, upbeat energy",
        "am_michael": "Deep and grounded, quietly trustworthy",
        "am_onyx": "Very deep and resonant, real gravitas",
        "am_puck": "Bouncy and eager, youthful energy",
        "am_santa": "Deep and jolly, unmistakably Santa",
        "bf_alice": "Polished and precise, bright and clear",
        "bf_emma": "Polished and warm, efficiently friendly",
        "bf_isabella": "Warm and breathy, gently sophisticated",
        "bf_lily": "Polished and brisk, efficiently clear",
        "bm_daniel": "Crisp and articulate, polished warmth",
        "bm_fable": "A velvety storyteller, refined and warm",
        "bm_george": "Distinguished and reassuring, polished delivery",
        "bm_lewis": "Sophisticated and composed, corporate calm",
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
