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
/// 2. On Play the hero lifts and its lines are read under it, oversized and faded with the
///    spoken word tinted (`ReadAlongPassage`), under "Choose your default voice" and over one big
///    voice pill at a time (`VoiceCarousel`): swiping to another plays the passage again in that
///    voice and washes the ground a colour of its own, and the blue Continue makes the pill on
///    screen the app's default voice.
///
/// The scene runs on the wall clock from the moment it appears: the field draws from it and the
/// chatter takes its gains from it, once a frame. It follows the app's theme — covers on the
/// ground, light or dark.
struct OnboardingCover: View {
    var manifest: OnboardingManifest
    var onFinish: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var scheme

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

    /// Each voice washes the ground its own way: a soft hue spaced around the wheel by its place
    /// in the row, faint on light and deep on dark (the owner, 2026-09-15: "as voice changes also
    /// change the color of the bg").
    private func tint(for voice: String) -> Color {
        let index = manifest.voices.firstIndex(of: voice) ?? 0
        let count = max(manifest.voices.count, 1)
        let hue = (Double(index) / Double(count) + 0.08).truncatingRemainder(dividingBy: 1)
        return scheme == .dark
            ? Color(hue: hue, saturation: 0.35, brightness: 0.24)
            : Color(hue: hue, saturation: 0.14, brightness: 0.99)
    }

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = startedAt.map { context.date.timeIntervalSince($0) } ?? 0
            let settled = elapsed >= schedule.total
            let lift = liftedAt.map { smooth(context.date.timeIntervalSince($0) / 0.7) } ?? 0
            ZStack {
                Tokens.ground.ignoresSafeArea()
                tint(for: selectedVoice)
                    .ignoresSafeArea()
                    .opacity(phase == .reading ? 1 : 0)
                    .animation(.smooth(duration: 0.7), value: selectedVoice)
                    .animation(.smooth(duration: 0.7), value: phase)
                CoverField(books: manifest.books, hero: manifest.hero, schedule: schedule, elapsed: elapsed, lift: lift)
                    .ignoresSafeArea()
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
                        readingBody
                            .transition(.opacity)
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

    /// The lines under the lifted hero, the heading, the voice pill, and Continue.
    private var readingBody: some View {
        GeometryReader { geo in
            VStack(spacing: Spacing.row) {
                // The lifted hero's foot is about 0.27 of the height down; the lines start just
                // under it and the mask eases them in.
                Spacer().frame(height: geo.size.height * 0.22)
                ReadAlongPassage(timings: passageTimings(selectedVoice),
                                 fallback: heroBook?.passage ?? heroBook?.line ?? "",
                                 time: solo.currentTime,
                                 isFinished: hasHeard && !solo.isPlaying)
                    .frame(height: geo.size.height * 0.30)
                Text("Choose your default voice")
                    .typeRole(.sectionHeader)
                    .foregroundStyle(Tokens.ink)
                VoiceCarousel(voices: manifest.voices, selected: $selectedVoice,
                              isFinished: hasHeard && !solo.isPlaying) { play(selectedVoice) }
                RaisedButton(label: "Continue", tone: .blue, size: .bar) { finish(setDefault: true) }
                    .padding(.horizontal, Spacing.margin)
                    .padding(.bottom, Spacing.grid)
            }
        }
        .onChange(of: selectedVoice) { _, voice in play(voice) }
    }

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
