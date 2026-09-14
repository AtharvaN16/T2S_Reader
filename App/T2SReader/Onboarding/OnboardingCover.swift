// App/T2SReader/Onboarding/OnboardingCover.swift
import SwiftUI
import T2SApp

/// The welcome, presented over the pager on a fresh install (design:
/// `docs/superpowers/specs/2026-09-14-onboarding-design.md`). This is the first scene — the covers
/// rising to their chattering lines and the hero settling — with Skip from the first frame. The
/// voice row, the question, the benefits and the Pro mock follow in later slices; until then the
/// settled hero is followed by one Continue, which ends the flow the way Skip does.
///
/// The scene runs on the wall clock from the moment it appears, through `RisingChoreography`:
/// the field draws from it and the player takes its gains from it, once a frame.
/// Dark whatever the theme: the scene is covers on black.
struct OnboardingCover: View {
    var manifest: OnboardingManifest
    var onFinish: () -> Void

    @State private var player: ClipPlayer
    @State private var startedAt: Date?
    private let books: [OnboardingManifest.Book]
    private let scene: RisingChoreography

    init(manifest: OnboardingManifest, onFinish: @escaping () -> Void) {
        self.manifest = manifest
        self.onFinish = onFinish
        let rising = manifest.risingOrder
        books = rising
        let player = ClipPlayer(urls: rising.map {
            Bundle.main.url(forResource: OnboardingManifest.clipName(book: $0.id, voice: $0.voice), withExtension: "m4a")
        })
        _player = State(initialValue: player)
        scene = RisingChoreography(count: rising.count, heroDuration: player.durations.last ?? ClipPlayer.fallbackDuration)
    }

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = startedAt.map { context.date.timeIntervalSince($0) } ?? 0
            let settled = elapsed >= scene.total
            ZStack {
                Color.black.ignoresSafeArea()
                CoverField(books: books, scene: scene, elapsed: elapsed)
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
                        BarButton(label: "Continue") { finish() }
                            .padding(.horizontal, Spacing.margin)
                            .padding(.bottom, Spacing.section)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: settled)
            }
            .onChange(of: context.date) { _, _ in
                // The player is driven here rather than in the body, which must not mutate.
                if startedAt != nil { player.update(gains: scene.gains(at: elapsed)) }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { startedAt = Date() }
        .onDisappear { player.stop() }
    }

    private func finish() {
        player.stop()
        onFinish()
    }
}
