// App/T2SReader/Onboarding/OnboardingCover.swift
import SwiftUI
import T2SApp

/// The welcome, presented over the pager on a fresh install (design:
/// `docs/superpowers/specs/2026-09-16-onboarding-reel-welcome-page-design.md`). One scene in three
/// beats, wiped between rather than cut, with `Skip` top-right from the first frame:
///
/// 1. **The reel.** Every book in the manifest drifts upward in one field, scattered wide and
///    silent, for a few seconds only. No cover leaves the drift; the reel is the shelf, not a
///    shortlist.
/// 2. **The name.** As the last line tails off, a veil rises from the foot of the screen to the
///    crown and uncovers *Welcome to T2S* standing on it (`RisingVeil`). It holds there, silent.
/// 3. **The page.** The veil rises a second time and brings up the passage: the chosen voice's
///    voice's rim of light at the crown (`VoiceGlow`) and every voice as a row that plays it
///    (`VoiceList`), and the key at the foot behind a tall bottom
///    fade, which makes the voice on screen the app's default.
///
/// The scene runs on the wall clock from the moment it appears and plays itself through — there is
/// no key between the beats. Everything drawn is a function of `elapsed` through `WelcomeScript`,
/// so the field, the veils and the player agree without any of them owning a timer. It follows the
/// app's theme — covers on the ground, light or dark.
struct OnboardingCover: View {
    var manifest: OnboardingManifest
    var onFinish: () -> Void

    @Environment(AppEnvironment.self) private var env

    @State private var solo = SoloClipPlayer()
    @State private var startedAt: Date?
    @State private var beat: WelcomeScript.Beat = .reel
    @State private var selectedVoice: String
    @State private var timings: [String: OnboardingClipTimings] = [:]
    /// Debug only: a clock pinned at one instant, so a beat can be photographed. See `onAppear`.
    @State private var frozen: TimeInterval?

    private let script = WelcomeScript()

    init(manifest: OnboardingManifest, onFinish: @escaping () -> Void) {
        self.manifest = manifest
        self.onFinish = onFinish
        _selectedVoice = State(initialValue: manifest.voices.first ?? "af_heart")
    }

    private var heroBook: OnboardingManifest.Book? { manifest.heroBook }

    private func passageClip(_ voice: String) -> URL? {
        guard let hero = heroBook else { return nil }
        return Bundle.main.url(forResource: OnboardingManifest.passageClipName(book: hero.id, voice: voice), withExtension: "m4a")
    }

    private func passageTimings(_ voice: String) -> OnboardingClipTimings? {
        if let cached = timings[voice] { return cached }
        guard let hero = heroBook,
              let loaded = try? OnboardingClipTimings.load(named: OnboardingManifest.passageClipName(book: hero.id, voice: voice), from: .main)
        else { return nil }
        timings[voice] = loaded
        return loaded
    }

    var body: some View {
        // Outside every `ignoresSafeArea` below, and the only place the insets can still be read:
        // each veil covers the whole screen, so its content is handed a frame with no insets left
        // in it, and a pill padded from the top of *that* would sit under the Dynamic Island.
        // Measured once here and passed down instead.
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            TimelineView(.animation) { context in
                let elapsed = frozen ?? startedAt.map { context.date.timeIntervalSince($0) } ?? 0
                ZStack {
                    // The ground throughout (the owner, 2026-09-15: "don't change backgrounds for
                    // voice, keep the default bg") — an earlier cut washed it a hue per voice.
                    Tokens.ground.ignoresSafeArea()

                    // The three beats, each standing on the one below and uncovered by its own
                    // rise. All of them are in the tree the whole time rather than switched in:
                    // the passage has to be laid out where it will stay before its first word is
                    // spoken, and a view inserted as its veil passes would reflow under the edge.
                    CoverField(books: manifest.books, elapsed: elapsed)
                        .ignoresSafeArea()

                    RisingVeil(progress: script.welcomeSweep(at: elapsed)) {
                        welcomeName(elapsed)
                    }
                    .ignoresSafeArea()

                    RisingVeil(progress: script.pageSweep(at: elapsed)) {
                        page(insets)
                    }
                    .ignoresSafeArea()

                    skip(insets)
                }
                .onChange(of: context.date) { _, _ in
                    // Driven here rather than in the body, which must not mutate.
                    guard startedAt != nil else { return }
                    advance(to: script.beat(at: elapsed), settled: elapsed >= script.pageSettled)
                }
            }
        }
        .onAppear {
            startedAt = Date()
            #if DEBUG
            // A script-driven simulator cannot wait out a 35-second reel, and three of the frames
            // worth looking at last about a second each. `T2S_ONBOARDING` pins the scene's clock
            // at one instant and leaves it there, so a screenshot taken whenever it lands shows
            // the same thing:
            //
            //   reel     the field alone, mid-drift
            //   rising   the first veil half way up, the name coming out of the reel
            //   welcome  the name alone, both feet on the ground
            //   opening  the second veil half way up, the page coming out of the name
            //   page     the page settled, the passage playing  (`reading` is the old name for it)
            //
            // The passage still runs on the player's own clock, not this one, so `page` reads
            // along normally. Nothing here compiles into a release build.
            // And which voice it starts on, since a simulator cannot tap a pill and the whole
            // point of the row is that each voice brings its own colour and its own form of light.
            if let voice = ProcessInfo.processInfo.environment["T2S_ONBOARDING_VOICE"],
               manifest.voices.contains(voice) {
                selectedVoice = voice
            }
            switch ProcessInfo.processInfo.environment["T2S_ONBOARDING"] {
            case "reel":
                frozen = script.reelEnd * 0.6
            case "rising":
                frozen = script.welcomeStart + script.rise * 0.45
            case "greeting":
                // The veil home and the name not yet arrived — the stagger's first half.
                frozen = script.welcomeStart + script.rise
            case "welcome":
                // Both words up. Freezing on the veil's arrival photographs the greeting alone,
                // because the name is on its own clock and has not started.
                frozen = script.welcomeStart + script.rise + script.nameDelay + script.nameFade
            case "opening":
                frozen = script.pageStart + script.rise * 0.45
                beat = .page
            case "page", "reading":
                frozen = script.pageSettled + 0.1
                beat = .page
                play(selectedVoice)
            default:
                break
            }
            #endif
        }
        .onDisappear { solo.stop() }
    }

    /// Beat two: the greeting and the app's name, standing on the first veil so the rising edge
    /// uncovers them rather than fading them in over the covers — and staggered, the greeting
    /// first and the name after it (the owner, 2026-09-18, with Queue's own welcome as the
    /// reference: "the T2S reveal should be in staggered formation so welcome to and then T2S
    /// fades in").
    ///
    /// The stagger is `WelcomeScript.nameIn`, not a transition. The veil uncovers upward and the
    /// name sits under the greeting, so anything carried up by the veil arrives in the wrong order;
    /// the name waits for its own clock and then rises the last few points into place as it fades.
    private func welcomeName(_ elapsed: TimeInterval) -> some View {
        let arrival = script.nameIn(at: elapsed)
        return ZStack {
            Tokens.ground
            WelcomeWash()
            VStack(spacing: 4) {
                Text("Welcome to")
                    .typeRole(.playerTitle)
                    .foregroundStyle(Tokens.ink2)
                Text("T2S")
                    .font(.custom("InterDisplay-Black", size: 68))
                    .foregroundStyle(Tokens.ink)
                    // Up into place as it comes in, and softened on the way: a name that only
                    // fades reads as a layer being switched on, where one that travels a little
                    // reads as arriving. Eight points is enough to see and too few to notice.
                    .opacity(arrival)
                    .offset(y: 8 * (1 - arrival))
                    .blur(radius: 5 * (1 - arrival))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.margin)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Welcome to T2S")
        }
    }

    /// Beat three: the voices as a list, under the chosen one's rim of light (the owner,
    /// 2026-09-18: "for the voice screen, I am thinking let us just keep a list", with Queue's
    /// *Add Podcasts* as the reference — a title, rows that scroll under it, one key at the foot).
    ///
    /// The passage and its read-along are gone from here; `VoiceList` records what that cost and
    /// what it bought. The sample still plays when a row is tapped, and `VoiceGlow` still breathes
    /// with it, so the light at the crown is the only thing left saying a voice is sounding.
    private func page(_ insets: EdgeInsets) -> some View {
        ZStack {
            Tokens.ground

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Choose a voice")
                        .typeRole(.pageTitle)
                        .foregroundStyle(Tokens.ink)
                    Text("You can change it later in Settings.")
                        .typeRole(.meta)
                        .foregroundStyle(Tokens.ink2)
                        .padding(.top, 6)
                    VoiceList(voices: manifest.voices,
                              selected: $selectedVoice,
                              isPlaying: solo.isPlaying,
                              onPlay: { play($0) },
                              onStop: { solo.stop() })
                        .padding(.top, Spacing.row)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.margin)
                // Clear of the crown's light above and the key's fade below, so the title is never
                // under the glow and the last row is never under the key.
                .padding(.top, insets.top + Self.listTop)
                .padding(.bottom, insets.bottom + Self.bottomFade)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 0) {
                crown(insets)
                Spacer(minLength: 0)
                foot(insets)
            }
        }
    }

    private func crown(_ insets: EdgeInsets) -> some View {
        ZStack(alignment: .top) {
            crownGround(insets)
            VoiceGlow(voice: selectedVoice,
                      voices: manifest.voices,
                      level: VoiceEnvelope(timings: passageTimings(selectedVoice)).level(at: solo.currentTime))
        }
    }

    /// The ground the light stands on and the list scrolls under: **one** gradient, solid across
    /// the status bar and the Skip pill, then easing to nothing above the first row.
    ///
    /// One, because that is the owner's band (2026-09-17: "remove the banding caused by the voice
    /// pill row"). It used to be a solid `Tokens.ground` block with a separate ramp stood under it,
    /// and however continuous the two are in theory, they are two views with two rasterisations
    /// meeting on a straight line. The eased half here leaves full opacity with zero slope
    /// (smoothstep squared), so there is no join to see where the solid gives way.
    ///
    /// **Not dithered**, though the warm-up's ramps are and the first cut of this copied them.
    /// `StatusRamp.ditherTile` is grey noise blended `.overlay` against the real backdrop, and
    /// `StatusGlow` already records what that costs: "grey noise lands *on* the blue and greys it".
    /// Over a coloured light that is a fair trade for breaking a step. Over `Tokens.ground` — which
    /// is near-white, and which this paints across the whole top of the screen — it is the whole
    /// surface that goes grey, and the photograph showed a crown visibly dirtier than the page
    /// under it. A band traded for a stain. The gradient's own 16 stops over 330 pt are shallow
    /// enough not to need it; if stepping ever does show here, it wants the `compositingGroup`
    /// arrangement `StatusRamp` uses — noise scattered against an opaque ground of its own — and
    /// not this one.
    private func crownGround(_ insets: EdgeInsets) -> some View {
        LinearGradient(stops: Self.crownStops, startPoint: .top, endPoint: .bottom)
            .frame(height: insets.top + Self.crownFade)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    /// Solid to `crownHold`, then the app's own curve down to nothing.
    static let crownStops: [Gradient.Stop] = {
        let hold = 0.46
        var stops: [Gradient.Stop] = [.init(color: Tokens.ground, location: 0)]
        let steps = 16
        for i in 0 ... steps {
            let t = Double(i) / Double(steps)
            let eased = pow(t * t * (3 - 2 * t), 2)
            stops.append(.init(color: Tokens.ground.opacity(1 - eased), location: hold + (1 - hold) * t))
        }
        return stops
    }()

    /// The foot: Continue behind the tall bottom fade that carries the passage out of sight under
    /// it (the owner, 2026-09-15: "the bottom fade should be taller").
    private func foot(_ insets: EdgeInsets) -> some View {
        RaisedButton(label: "Make default", tone: .blue, size: .bar) { finish(setDefault: true) }
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, insets.bottom + Spacing.grid)
            .background { BottomFade(fade: Self.bottomFade, color: Tokens.ground) }
    }

    /// Over every beat and every veil, so the reader can leave from the first frame — including
    /// mid-rise, when neither the beat below nor the one above owns the screen.
    private func skip(_ insets: EdgeInsets) -> some View {
        VStack {
            HStack {
                Spacer()
                Pill(label: "Skip", style: .soft) { finish(setDefault: false) }
                    .accessibilityLabel("Skip the welcome")
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.top, insets.top)
            Spacer()
        }
        .ignoresSafeArea()
    }

    /// How far the crown's ground reaches below the safe area: solid across the status bar and the
    /// Skip pill, then easing to nothing *above* the list's title.
    ///
    /// It has only the Skip pill to clear, not a pill and a caption as it did when this beat was a
    /// page of prose, so it is less than half what it was. At 240 the ramp reached 300 points down
    /// and the title sat inside it — "Choose a voice" came out greyed at the crown, which reads as
    /// a disabled control rather than as a heading (seen in the first photograph of the list).
    static let crownFade: CGFloat = 120
    /// Where the list's own content begins: clear of the ramp above, and clear of the glow's
    /// bezel, whose mask has let go by `StatusRamp.height * 0.85`.
    static let listTop: CGFloat = 150
    /// Taller than a bar's usual 72: the passage runs the whole height of the screen, so the ramp
    /// has to carry it out of sight well above the key (the owner, 2026-09-15: "the bottom fade
    /// should be taller").
    static let bottomFade: CGFloat = 200

    /// One place the beat changes, so the audio and the flag never disagree: the passage starts
    /// once the page is fully uncovered rather than while
    /// its veil is still travelling — a voice reading words that are half under a fade reads as a
    /// mistimed clip.
    private func advance(to next: WelcomeScript.Beat, settled: Bool) {
        if next != beat { beat = next }
        if beat == .page, settled, !solo.hasPlayed { play(selectedVoice) }
    }

    private func play(_ voice: String) {
        solo.play(passageClip(voice))
    }

    /// Continue writes the chosen voice as the app's default, by the id the voice picker uses for
    /// the same on-device voice; Skip leaves the default alone.
    private func finish(setDefault: Bool) {
        solo.stop()
        if setDefault, let option = env.voices.voices().first(where: { $0.id.hasSuffix(":\(selectedVoice)") }) {
            env.preferences.defaultVoiceID = option.id
        }
        onFinish()
    }
}
