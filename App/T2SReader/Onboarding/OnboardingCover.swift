// App/T2SReader/Onboarding/OnboardingCover.swift
import SwiftUI
import T2SApp

/// The welcome, presented over the pager on a fresh install (design:
/// `docs/superpowers/specs/2026-09-14-onboarding-design.md`). This is the first scene — one field
/// of covers drifting in depth, a few opening lines chattering past on their own clock, and the
/// hero settling out of the crowd, silent — with Skip from the first frame. The settled hero waits for Play, the ATC reference's
/// "listen to this replay": the reader chooses the clean listen. For now Play speaks the hero's
/// passage in the default voice and is followed by Continue; the voice row, the question, the
/// benefits and the Pro mock follow in later slices.
///
/// The scene runs on the wall clock from the moment it appears, through `RisingChoreography`:
/// the field draws from it and the chatter takes its gains from it, once a frame. It follows the
/// app's theme — covers on the ground, light or dark (the owner, 2026-09-14).
struct OnboardingCover: View {
    var manifest: OnboardingManifest
    var onFinish: () -> Void

    @State private var chatter: ClipPlayer
    @State private var solo = SoloClipPlayer()
    @State private var startedAt: Date?
    @State private var heroPlayed = false
    /// The books that speak, then the hero: the chatter's order, and the choreography's count.
    private let rising: [OnboardingManifest.Book]
    private let scene: RisingChoreography

    init(manifest: OnboardingManifest, onFinish: @escaping () -> Void) {
        self.manifest = manifest
        self.onFinish = onFinish
        rising = manifest.risingOrder
        _chatter = State(initialValue: ClipPlayer(urls: rising.map { book in
            guard let voice = book.voice else { return nil }
            return Bundle.main.url(forResource: OnboardingManifest.clipName(book: book.id, voice: voice), withExtension: "m4a")
        }))
        scene = RisingChoreography(count: rising.count)
    }

    /// The hero's passage in the row's first voice, the app's default.
    private var heroClip: URL? {
        guard let hero = manifest.heroBook, let voice = manifest.voices.first else { return nil }
        return Bundle.main.url(forResource: OnboardingManifest.passageClipName(book: hero.id, voice: voice), withExtension: "m4a")
    }

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = startedAt.map { context.date.timeIntervalSince($0) } ?? 0
            let settled = elapsed >= scene.total
            ZStack {
                Tokens.ground.ignoresSafeArea()
                CoverField(books: manifest.books, hero: manifest.hero, scene: scene, elapsed: elapsed)
                    .ignoresSafeArea()
                VStack {
                    HStack {
                        Spacer()
                        Pill(label: "Skip", style: .soft) { finish() }
                            .accessibilityLabel("Skip the welcome")
                    }
                    .padding(.horizontal, Spacing.margin)
                    Spacer()
                    if settled {
                        VStack(spacing: Spacing.row) {
                            if !heroPlayed {
                                Text("Hear the first lines")
                                    .typeRole(.rowTitle)
                                    .foregroundStyle(Tokens.ink2)
                                Pill(label: "Play", glyph: "play.fill", style: .accent) {
                                    heroPlayed = true
                                    solo.play(heroClip)
                                }
                            } else {
                                BarButton(label: "Continue") { finish() }
                            }
                        }
                        .padding(.horizontal, Spacing.margin)
                        .padding(.bottom, Spacing.section)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: settled)
                .animation(.snappy, value: heroPlayed)
            }
            .onChange(of: context.date) { _, _ in
                // The chatter is driven here rather than in the body, which must not mutate.
                if startedAt != nil { chatter.update(gains: scene.gains(at: elapsed)) }
            }
        }
        .onAppear { startedAt = Date() }
        .onDisappear { chatter.stop(); solo.stop() }
    }

    private func finish() {
        chatter.stop()
        solo.stop()
        onFinish()
    }
}
