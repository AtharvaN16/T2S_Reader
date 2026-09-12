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
    static func displayName(for name: String) -> String {
        let stem = name.split(separator: "_").last.map(String.init) ?? name
        return stem.prefix(1).uppercased() + stem.dropFirst()
    }

    /// The row's second line: three short traits, not a sentence — the ElevenReader row the owner
    /// pointed at reads "Expressive, Deep and Emotive", and `.lineLimit(1)` on the row truncates
    /// whatever doesn't fit. Kokoro ships no descriptions of its own, so this is condensed from
    /// independent listener write-ups per voice (voicerankings.com's Kokoro-82M profiles, checked
    /// against Hugging Face's `hexgrad/Kokoro-82M` voice list) rather than a guess from the name —
    /// the first draft here was guessed and the owner correctly called it out as not matching. Still
    /// worth re-checking against the phone once it can be heard. A name not in the table (none
    /// today) gets a neutral line.
    public static let personalities: [String: String] = [
        "af_heart": "Breathy, Intimate and Tender",
        "af_alloy": "Bright, Clean and Cheerful",
        "af_aoede": "Deep, Relaxed and Unhurried",
        "af_bella": "Husky, Easy and Conversational",
        "af_jessica": "Energetic, Airy and Lively",
        "af_kore": "Steady, Guiding and Assured",
        "af_nicole": "Hushed, Whisper-Soft and Close",
        "af_nova": "Polished, Clear and Poised",
        "af_river": "Husky, Casual and Candid",
        "af_sarah": "Polite, Friendly and Approachable",
        "af_sky": "Smooth, Composed and Helpful",
        "am_adam": "Trustworthy, Clear and Even",
        "am_echo": "Soft, Breathy and Gentle",
        "am_eric": "Relaxed, Modern and Casual",
        "am_fenrir": "Confident, Energetic and Rich",
        "am_liam": "Cheerful, Upbeat and Brisk",
        "am_michael": "Resonant, Trustworthy and Mellow",
        "am_onyx": "Deep, Resonant and Reassuring",
        "am_puck": "Youthful, Bouncy and Eager",
        "am_santa": "Deep, Jolly and Grandfatherly",
        "bf_alice": "Polished, Articulate and Professional",
        "bf_emma": "Inviting, Rounded and Gracious",
        "bf_isabella": "Breathy, Sophisticated and Sultry",
        "bf_lily": "Clear, Crisp and Sophisticated",
        "bm_daniel": "Crisp, Articulate and Polished",
        "bm_fable": "Refined, Velvety and Storytelling",
        "bm_george": "Distinguished, Articulate and Reassuring",
        "bm_lewis": "Sophisticated, Smooth and Composed",
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
