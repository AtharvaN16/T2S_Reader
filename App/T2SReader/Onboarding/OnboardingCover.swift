// App/T2SReader/Onboarding/OnboardingCover.swift
import SwiftUI
import T2SApp

/// The welcome, presented over the pager on a fresh install (design:
/// `docs/superpowers/specs/2026-09-16-onboarding-reel-welcome-page-design.md`). One scene in three
/// beats, wiped between rather than cut, with `Skip` top-right from the first frame:
///
/// 1. **The reel.** Every book in the manifest drifts upward in one field, laid back in
///    perspective, while a few opening lines chatter past — each heard whole and the next fading
///    into its tail (`ChatterSchedule`). No cover leaves the drift; the reel is the shelf, not a
///    shortlist.
/// 2. **The name.** As the last line tails off, a veil rises from the foot of the screen to the
///    crown and uncovers *Welcome to T2S* standing on it (`RisingVeil`). It holds there, silent.
/// 3. **The page.** The veil rises a second time and brings up the passage: the chosen voice's
///    light blooming at the crown (`VoiceGlow`), the row of voices under it (`VoiceCarousel`) over
///    a tall top fade, the words lighting as they are spoken and following themselves the way the
///    Reader's own page does (`ReadAlongPassage`), and Continue at the foot behind a tall bottom
///    fade, which makes the voice on screen the app's default.
///
/// The scene runs on the wall clock from the moment it appears and plays itself through — there is
/// no key between the beats, which extends the owner's 2026-09-14 decision that the clips start
/// with the cards. Everything drawn is a function of `elapsed` through `WelcomeScript`, so the
/// field, the veils, the chatter and the player agree without any of them owning a timer. It
/// follows the app's theme — covers on the ground, light or dark.
struct OnboardingCover: View {
    var manifest: OnboardingManifest
    var onFinish: () -> Void

    @Environment(AppEnvironment.self) private var env

    @State private var chatter: ClipPlayer
    @State private var solo = SoloClipPlayer()
    @State private var startedAt: Date?
    @State private var beat: WelcomeScript.Beat = .reel
    @State private var selectedVoice: String
    @State private var hasHeard = false
    @State private var timings: [String: OnboardingClipTimings] = [:]

    private let schedule: ChatterSchedule
    private let script: WelcomeScript

    init(manifest: OnboardingManifest, onFinish: @escaping () -> Void) {
        self.manifest = manifest
        self.onFinish = onFinish
        let voiced = manifest.voiced
        let player = ClipPlayer(urls: voiced.map { book in
            guard let voice = book.voice else { return nil }
            return Bundle.main.url(forResource: OnboardingManifest.clipName(book: book.id, voice: voice), withExtension: "m4a")
        })
        _chatter = State(initialValue: player)
        let chatter = ChatterSchedule(durations: player.durations)
        schedule = chatter
        script = WelcomeScript(chatter: chatter)
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
        // in it, and a row of pills padded from the top of *that* would sit under the Dynamic
        // Island. Measured once here and passed down instead.
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            TimelineView(.animation) { context in
                let elapsed = startedAt.map { context.date.timeIntervalSince($0) } ?? 0
                ZStack {
                    // The ground throughout (the owner, 2026-09-15: "don't change backgrounds for
                    // voice, keep the default bg") — an earlier cut washed it a hue per voice.
                    Tokens.ground.ignoresSafeArea()

                    // The three beats, each standing on the one below and uncovered by its own
                    // rise. All of them are in the tree the whole time rather than switched in:
                    // the passage has to be laid out where it will stay before its first word is
                    // spoken, and a view inserted as its veil passes would reflow under the edge.
                    CoverField(books: manifest.books, hero: manifest.hero, elapsed: elapsed)
                        .ignoresSafeArea()

                    RisingVeil(progress: script.welcomeSweep(at: elapsed)) {
                        welcomeName
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
                    chatter.update(gains: schedule.gains(at: elapsed))
                    advance(to: script.beat(at: elapsed), settled: elapsed >= script.pageSettled)
                    if beat == .page, hasHeard == false, solo.hasPlayed, !solo.isPlaying { hasHeard = true }
                }
            }
        }
        .onAppear {
            startedAt = Date()
            #if DEBUG
            // A script-driven simulator cannot wait out the reel: `T2S_ONBOARDING=page` in a debug
            // build lands on beat three at once, both veils home, for a photograph. `=welcome`
            // stops on the name.
            switch ProcessInfo.processInfo.environment["T2S_ONBOARDING"] {
            case "page", "reading":
                startedAt = Date().addingTimeInterval(-(script.pageSettled + 0.1))
                beat = .page
                play(selectedVoice)
            case "welcome":
                startedAt = Date().addingTimeInterval(-(script.welcomeStart + WelcomeScript.defaultRise))
                beat = .welcome
            default:
                break
            }
            #endif
        }
        .onDisappear { chatter.stop(); solo.stop() }
    }

    /// Beat two: the app's name, standing on the first veil so the rising edge uncovers it rather
    /// than fading it in over the covers.
    private var welcomeName: some View {
        ZStack {
            Tokens.ground
            Text("Welcome to T2S")
                .typeRole(.pageTitle)
                .foregroundStyle(Tokens.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.margin)
        }
    }

    /// Beat three: the passage, with the voice's light and the row of voices at the crown and
    /// Continue at the foot, each behind a fade of its own so the text dissolves under them
    /// instead of colliding with them (the owner, 2026-09-16: "over a tall fade and there is a
    /// bottom fade. The text moves between these two phases").
    private func page(_ insets: EdgeInsets) -> some View {
        ZStack {
            Tokens.ground

            ReadAlongPassage(timings: passageTimings(selectedVoice),
                             fallback: heroBook?.passage ?? heroBook?.line ?? "",
                             time: solo.currentTime,
                             isFinished: hasHeard && !solo.isPlaying)
                .padding(.top, insets.top + Self.textTop)
                .padding(.bottom, insets.bottom + Self.textBottom)

            VStack(spacing: 0) {
                crown(insets)
                Spacer(minLength: 0)
                foot(insets)
            }
        }
        .onChange(of: selectedVoice) { _, voice in play(voice) }
    }

    /// The crown: the voice's light, the row of voices inside it, and the tall fade that carries
    /// the passage up under both.
    private func crown(_ insets: EdgeInsets) -> some View {
        ZStack(alignment: .top) {
            VoiceGlow(voice: selectedVoice,
                      voices: manifest.voices,
                      level: VoiceEnvelope(timings: passageTimings(selectedVoice)).level(at: solo.currentTime))

            // Over the glow, and over the fade that stands behind both: the row has to be legible
            // against the brightest part of the light. Clear of the Skip pill, which keeps the
            // same corner it has held since the first frame of the reel.
            VStack(spacing: Spacing.grid) {
                VoiceCarousel(voices: manifest.voices, selected: $selectedVoice,
                              isFinished: hasHeard && !solo.isPlaying) { play(selectedVoice) }
                Text("Swipe to try a voice")
                    .typeRole(.meta)
                    .foregroundStyle(Tokens.ink2)
            }
            .padding(.top, insets.top + Spacing.section + Spacing.row)
        }
        .background(alignment: .top) {
            // The app's own curve read upward, and tall: the passage runs the whole height of the
            // screen behind this, and the ramp has to reach past the caption as well as the pills.
            LinearGradient(stops: BottomFade.stops(color: Tokens.ground), startPoint: .bottom, endPoint: .top)
                .frame(height: Self.topFade)
                .ignoresSafeArea(edges: .top)
        }
    }

    /// The foot: Continue behind the tall bottom fade that carries the passage out of sight under
    /// it (the owner, 2026-09-15: "the bottom fade should be taller").
    private func foot(_ insets: EdgeInsets) -> some View {
        RaisedButton(label: "Continue", tone: .blue, size: .bar) { finish(setDefault: true) }
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

    /// How far the crown reaches below the safe area, and so where the passage's first line can
    /// start without landing in the pills. Shorter than `topFade` because the last of the ramp is
    /// nearly clear and a line is meant to dissolve into it rather than begin below it.
    static let textTop: CGFloat = 170
    static let topFade: CGFloat = 320
    static let bottomFade: CGFloat = 200
    static let textBottom: CGFloat = 120

    /// One place the beat changes, so the audio and the flag never disagree: the chatter stops as
    /// the name goes up, and the passage starts once the page is fully uncovered rather than while
    /// its veil is still travelling — a voice reading words that are half under a fade reads as a
    /// mistimed clip.
    private func advance(to next: WelcomeScript.Beat, settled: Bool) {
        if next != beat {
            beat = next
            if next == .welcome { chatter.stop() }
        }
        if beat == .page, settled, !solo.hasPlayed { play(selectedVoice) }
    }

    private func play(_ voice: String) {
        hasHeard = false
        solo.play(passageClip(voice))
    }

    /// Continue writes the chosen voice as the app's default, by the id the voice picker uses for
    /// the same on-device voice; Skip leaves the default alone.
    private func finish(setDefault: Bool) {
        chatter.stop()
        solo.stop()
        if setDefault, let option = env.voices.voices().first(where: { $0.id.hasSuffix(":\(selectedVoice)") }) {
            env.preferences.defaultVoiceID = option.id
        }
        onFinish()
    }
}
