// App/T2SReader/Onboarding/OnboardingCover.swift
import SwiftUI
import T2SApp

/// The welcome, presented over the pager on a fresh install (design:
/// `docs/superpowers/specs/2026-09-14-onboarding-design.md`). Two beats of one scene, with Skip
/// from the first frame:
///
/// 1. One field of covers drifting in depth while a few opening lines chatter past, each heard
///    whole and the next fading into its tail (`ChatterSchedule`), and the hero settling out of
///    the crowd, silent. Then the blue Play key alone under it — the ATC reference's "listen to
///    this replay": the reader chooses the clean listen.
/// 2. On Play the hero lifts; "Choose your default voice" sits just under it, and its lines fill
///    the rest of the space beneath, bigger and boundary-lit the way the Reader's own page is
///    (`ReadAlongPassage`). One big coloured container at a time (`VoiceCarousel`) floats over
///    the lower reach of the text — the containers' own colours are what set them off the page,
///    not a fade; the only fade in the scene is behind the blue Continue key at the foot, which
///    makes the container on screen the app's default voice.
///
/// The scene runs on the wall clock from the moment it appears: the field draws from it and the
/// chatter takes its gains from it, once a frame. It follows the app's theme — covers on the
/// ground, light or dark.
struct OnboardingCover: View {
    var manifest: OnboardingManifest
    var onFinish: () -> Void

    @Environment(AppEnvironment.self) private var env

    private enum Phase { case scene, ready, reading }

    @State private var chatter: ClipPlayer
    @State private var solo = SoloClipPlayer()
    @State private var startedAt: Date?
    @State private var phase: Phase = .scene
    @State private var liftedAt: Date?
    @State private var selectedVoice: String
    @State private var hasHeard = false
    @State private var timings: [String: OnboardingClipTimings] = [:]

    private let schedule: ChatterSchedule

    init(manifest: OnboardingManifest, onFinish: @escaping () -> Void) {
        self.manifest = manifest
        self.onFinish = onFinish
        let voiced = manifest.voiced
        let player = ClipPlayer(urls: voiced.map { book in
            guard let voice = book.voice else { return nil }
            return Bundle.main.url(forResource: OnboardingManifest.clipName(book: book.id, voice: voice), withExtension: "m4a")
        })
        _chatter = State(initialValue: player)
        schedule = ChatterSchedule(durations: player.durations)
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
        TimelineView(.animation) { context in
            let elapsed = startedAt.map { context.date.timeIntervalSince($0) } ?? 0
            let settled = elapsed >= schedule.total
            let lift = liftedAt.map { smooth(context.date.timeIntervalSince($0) / 0.7) } ?? 0
            ZStack {
                // The default ground throughout (the owner, 2026-09-15: "don't change backgrounds
                // for voice, keep the default bg") — an earlier cut washed it a hue per voice.
                Tokens.ground.ignoresSafeArea()
                // Beat two's page of text runs the whole height, under the book and the chrome —
                // the book is drawn over it, and `readingTopFade` between the two is what lets
                // the text dissolve beneath the book and the heading rather than collide with them.
                if phase == .reading {
                    ReadAlongPassage(timings: passageTimings(selectedVoice),
                                     fallback: heroBook?.passage ?? heroBook?.line ?? "",
                                     time: solo.currentTime,
                                     isFinished: hasHeard && !solo.isPlaying)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    readingTopFade
                }
                CoverField(books: manifest.books, hero: manifest.hero, schedule: schedule, elapsed: elapsed, lift: lift)
                    .ignoresSafeArea()
                // A layer of its own rather than a case in the chrome stack below: as a stack
                // child it had to win its height from the `Spacer` above it, and once its own
                // content stopped being full-height it lost, collapsing the voice row and the key
                // to the top of the screen.
                if phase == .reading {
                    readingBody
                        .transition(.opacity)
                }
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Pill(label: "Skip", style: .soft) { finish(setDefault: false) }
                            .accessibilityLabel("Skip the welcome")
                    }
                    .padding(.horizontal, Spacing.margin)
                    Spacer()
                    switch phase {
                    case .scene:
                        EmptyView()
                    case .ready:
                        RaisedButton(label: "Play", glyph: "play.fill", tone: .blue, size: .key) { startReading() }
                            .padding(.bottom, Spacing.section + Spacing.row)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    case .reading:
                        EmptyView()   // its own layer above, not a case in this stack
                    }
                }
                .animation(.snappy, value: phase)
            }
            .onChange(of: context.date) { _, _ in
                // Driven here rather than in the body, which must not mutate.
                guard startedAt != nil else { return }
                chatter.update(gains: schedule.gains(at: elapsed))
                if settled, phase == .scene { phase = .ready }
                if phase == .reading, hasHeard == false, solo.hasPlayed, !solo.isPlaying { hasHeard = true }
            }
        }
        .onAppear {
            startedAt = Date()
            #if DEBUG
            // A script-driven simulator cannot tap Play: `T2S_ONBOARDING=reading` in a debug
            // build lands on beat two at once, the scene already settled, for a photograph.
            if ProcessInfo.processInfo.environment["T2S_ONBOARDING"] == "reading" {
                startedAt = Date().addingTimeInterval(-(schedule.total + 1))
                phase = .ready
                startReading()
            }
            #endif
        }
        .onDisappear { chatter.stop(); solo.stop() }
    }

    /// Ground behind the book and the heading, over the page of text and under the book itself,
    /// so the text dissolves beneath them instead of running into them (the owner, 2026-09-15:
    /// "there should be a top fade for the book and header"). Solid as far as the lifted book's
    /// foot, then the app's own fade curve — `BottomFade.stops` read upward — across the heading.
    private var readingTopFade: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Tokens.ground
                    .frame(height: geo.size.height * 0.29)
                // The heading rides on the last of the solid ground rather than in the chrome
                // below, so it always has the fade's own ground behind it: its own layer's
                // geometry is the screen's, where the chrome's is only what is left under the
                // Skip row, and the two drifted apart by a tenth of the height.
                Text("Choose your default voice")
                    .typeRole(.sectionHeader)
                    .foregroundStyle(Tokens.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Spacing.grid)
                    .background(Tokens.ground)
                LinearGradient(stops: BottomFade.stops(color: Tokens.ground), startPoint: .bottom, endPoint: .top)
                    .frame(height: 110)
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    /// Beat two's foot over the page of text: the voice carousel floating over the text's lower
    /// reach, and Continue under it behind a tall bottom fade (the owner, 2026-09-15: "the bottom
    /// fade should be taller"), which is what carries the text out of sight behind both. The
    /// heading is not here but on `readingTopFade`, where the ground behind it is.
    private var readingBody: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                RaisedButton(label: "Continue", tone: .blue, size: .bar) { finish(setDefault: true) }
                    .padding(.horizontal, Spacing.margin)
                    .padding(.bottom, Spacing.grid)
            }
            .background { BottomFade(fade: Self.bottomFade, color: Tokens.ground) }

            // Floats over the text's lower reach — and over the fade's own upward ramp, last
            // in the stack so its colour paints solid through it rather than being bled into
            // by the gradient behind the button.
            VoiceCarousel(voices: manifest.voices, selected: $selectedVoice,
                          isFinished: hasHeard && !solo.isPlaying) { play(selectedVoice) }
                .padding(.bottom, Spacing.section + Spacing.row + Spacing.grid)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onChange(of: selectedVoice) { _, voice in play(voice) }
    }

    /// Taller than a bar's usual 72: the page of text runs the whole height now, so the ramp has
    /// to reach past the voice row as well as the key.
    static let bottomFade: CGFloat = 200

    private func startReading() {
        liftedAt = Date()
        phase = .reading
        play(selectedVoice)
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

    private func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
