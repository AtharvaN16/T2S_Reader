// App/T2SReader/Import/ImportGraphic.swift
import SwiftUI
import T2SApp

/// The picture over the Import hub: the app's mark in the middle, and the four kinds it takes —
/// a book, a PDF, a web page and a page of text — circling it and then drawn down into it, over
/// and over (owner, 2026-09-16, with a reference: a podcast app pulling artwork into its icon
/// while it sets a library up). Everything the app can read becomes the app.
///
/// **One path, four followers.** Every kind travels the *same* spiral; they differ only in how far
/// along it they are (`phase`). That is what makes it read as a whirlpool rather than as four
/// objects each doing their own turn — the owner's note, 2026-09-17, on the first cut, which gave
/// each kind its own entry angle *and* its own phase and so drew four separate spirals at once.
/// The angle advances a full turn per loop, so kinds a quarter of a loop apart sit a quarter of a
/// circle apart while they are still out on the ring.
///
/// **Sharp on the ring, soft down the throat.** A kind is perfectly sharp for as long as it is
/// circling, and only begins to blur and fade once the pull has hold of it, deepening the closer
/// it gets to the mark (owner, 2026-09-17). The very first cut had this backwards — it faded each
/// kind *up* out of a blur as it arrived, which read as the picture being soft rather than as
/// depth, so arrival is now instant and clear and it is the departure that dissolves.
///
/// **Swapping the mark.** It is one image asset, `AppMark`, and nothing here knows what is on it:
/// drop a PNG over `App/T2SReader/Assets.xcassets/AppMark.imageset/AppMark.png` and the picture
/// takes it, at whatever `markSize` says. `scripts/make-app-icon.swift` writes that file and the
/// app icon from one drawing, so today they are the same pixels; a designed icon replaces both and
/// nothing in this file changes.
///
/// The four are the app's own placeholder covers at the size that is too small for words, which is
/// the face they were drawn for: cloth badged "EPUB", the PDF's light red badged "PDF", a browser
/// page with a globe, a notepad with the text glyph. Nothing here stands for a real document —
/// this is the shape of what the page accepts, so a real book's artwork (*Circe*, on the first
/// cut) said the wrong thing, and so did a lone "B". The badge names the *format*, not the idea:
/// "EPUB" beside "PDF" is the pair the file row already promises (owner, 2026-09-17).
struct ImportGraphic: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The loop's own zero. `@State`, so it is the moment the picture first appeared and not a
    /// number that jumps when the view is rebuilt.
    @State private var start = Date()
    /// How far into the loop it was when the scene stopped being active, in seconds; nil while it
    /// is running. `TimelineView(.animation)` redraws every frame for as long as it is on screen,
    /// which on a phone left on this page is a 60 fps burn on four blurred, scaled layers for
    /// nothing. Holding the clock here rather than dropping back to the still ring is what lets it
    /// pick up exactly where it stopped — a freeze that resumes with a jump is worse than no
    /// freeze, because the jump is the part a reader notices.
    @State private var frozen: Double?

    /// The frame the picture stands in: the ring's far edge plus half a card, doubled. Cut from
    /// 286 on the owner's word (2026-09-17) — at that height the third row of the list below was
    /// pushed off the bottom of the screen.
    static let height: CGFloat = 200
    /// The mark. Smaller than the ring it sits in, so the four have room to come round it.
    private static let markSize: CGFloat = 76
    /// The radius the kinds circle at before they are drawn in.
    private static let orbit: CGFloat = 80
    /// One trip round and in, in seconds.
    private static let period: Double = 9
    /// How much of a trip is spent out on the ring before the pull begins. At a half, two of the
    /// four are circling at any moment and two are on their way down.
    private static let ringFraction: Double = 0.5
    /// A full turn per loop: with the four a quarter-loop apart in `phase`, that puts them a
    /// quarter-circle apart on the ring without any of them owning an angle of its own.
    private static let turn: Double = 360
    /// Extra turn spent while being drawn in — the water speeding up as it narrows.
    private static let spinUp: Double = 140
    /// A card's height: under `ClothCover`'s 64 pt, so all four wear their compact faces.
    private static let cardHeight: CGFloat = 46
    /// How soft a kind goes as it reaches the mark. It is zero for the whole of the ring, so
    /// nothing is ever blurred on the way in — only on the way down.
    private static let throatBlur: CGFloat = 4

    private enum Kind: CaseIterable, Identifiable {
        case pdf, book, link, text
        var id: Self { self }
    }

    /// Where each kind is on the one path, a quarter of a loop apart. The PDF leads, so it is the
    /// one on the left as the picture opens (the owner's word, 2026-09-16).
    private static let phases: [(kind: Kind, phase: Double)] = [
        (.pdf, 0), (.book, 0.25), (.link, 0.5), (.text, 0.75),
    ]
    /// Where the path begins, in degrees clockwise from twelve o'clock: nine o'clock, so the kind
    /// at phase zero enters on the left.
    private static let entry: Double = 270

    var body: some View {
        ZStack {
            bloom
            ring
            mark
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .onChange(of: scenePhase, initial: true) { _, phase in follow(phase) }
    }

    @ViewBuilder private var ring: some View {
        if reduceMotion {
            // Nothing travels with Reduce Motion on: the four stand still, evenly spaced on the
            // ring — which is where the path puts them anyway — so the picture is a diagram of
            // what the page takes rather than an animation of it.
            ZStack {
                ForEach(Self.phases, id: \.kind) { step in
                    card(step.kind)
                        .offset(place(angle: Self.entry + Self.turn * step.phase, radius: Self.orbit))
                }
            }
        } else if let frozen {
            // Held mid-loop while the scene is away: the same frame it would have drawn, without a
            // timeline asking for the next one.
            wheel(clock: frozen / Self.period)
        } else {
            TimelineView(.animation) { timeline in
                wheel(clock: timeline.date.timeIntervalSince(start) / Self.period)
            }
        }
    }

    /// The four kinds at one moment of the loop.
    private func wheel(clock: Double) -> some View {
        ZStack {
            ForEach(Self.phases, id: \.kind) { step in
                travelling(step.kind, at: (clock + step.phase).truncatingRemainder(dividingBy: 1))
            }
        }
    }

    /// Stop the clock when the scene stops being active — backgrounded, in the switcher, under a
    /// locked screen — and start it again from the same instant. Nothing here can help an app left
    /// *foregrounded* and unwatched, which is still active as far as the system is concerned; that
    /// one is answered by not leaving a simulator booted.
    private func follow(_ phase: ScenePhase) {
        if phase == .active {
            if let frozen {
                start = Date().addingTimeInterval(-frozen)
                self.frozen = nil
            }
        } else if frozen == nil {
            frozen = Date().timeIntervalSince(start)
        }
    }

    /// One kind, `progress` of the way round and in. The first half of a trip is the ring at full
    /// radius; after that the pull takes over, easing the radius to nothing while the turn speeds
    /// up and the card shrinks. Every kind runs this same function, so they follow one another
    /// down one path instead of each tracing its own.
    private func travelling(_ kind: Kind, at progress: Double) -> some View {
        let pull = max(0, (progress - Self.ringFraction) / (1 - Self.ringFraction))
        let drawn = pull * pull * (3 - 2 * pull)                                // smoothstep
        return card(kind)
            .scaleEffect(1 - 0.58 * drawn)
            .blur(radius: Self.throatBlur * CGFloat(pow(drawn, 1.3)))
            .opacity(arrival(progress) * (1 - pow(drawn, 1.8)))
            .offset(place(angle: Self.entry + Self.turn * progress + Self.spinUp * drawn,
                          radius: Self.orbit * (1 - drawn)))
    }

    /// A kind's arrival on the ring, and nothing else: up over the first breath of a trip so it
    /// does not pop into being, then out of the way. What takes it away again is the pull itself
    /// (`drawn`), not the clock — which is what guarantees it is gone exactly as it reaches the
    /// middle, so the seam where the loop restarts always happens at nothing.
    private func arrival(_ progress: Double) -> Double {
        min(1, progress / 0.07)
    }

    /// A point on the ring, in degrees clockwise from twelve o'clock.
    private func place(angle: Double, radius: CGFloat) -> CGSize {
        let radians = (angle - 90) * .pi / 180
        return CGSize(width: radius * cos(radians), height: radius * sin(radians))
    }

    /// The app's mark: squircle-cornered at iOS's own ratio and lifted off the page, so it reads as
    /// the icon and not as a fifth card on the ring.
    private var mark: some View {
        Image("AppMark")
            .resizable()
            .frame(width: Self.markSize, height: Self.markSize)
            .clipShape(RoundedRectangle(cornerRadius: Self.markSize * 0.2237, style: .continuous))
            .shadow(color: Tokens.shade.opacity(0.18), radius: 12, y: 6)
    }

    /// The light the mark gives off, and the only ground under the ring. The empty shelves stand
    /// their books on a pool of the warm-up's blue; this one is the accent, because here the light
    /// comes off an orange icon and a blue pool under it would read as a second source.
    private var bloom: some View {
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: Tokens.accentSoft, location: 0),
                .init(color: Tokens.accentFaint, location: 0.4),
                .init(color: Tokens.accentFaint.opacity(0), location: 1),
            ], center: .center, startRadius: 0, endRadius: 92))
            .frame(width: 184, height: 184)
    }

    /// One kind's placeholder cover, lifted off the page by its own shadow — the two sheets are
    /// white and cream paper, and on `ground` they would otherwise read as holes in it.
    private func card(_ kind: Kind) -> some View {
        face(kind).shadow(color: Tokens.shade.opacity(0.12), radius: 6, y: 3)
    }

    /// The titles are only what deals each one its colour (`CoverStyle.paletteIndex`): a teal
    /// cloth, the PDF's light red, an indigo globe on a white page, a forest-green text glyph on
    /// cream — four cards no two of which are the same colour or the same shape of thing.
    @ViewBuilder private func face(_ kind: Kind) -> some View {
        switch kind {
        case .book:
            // The title is only what deals the cloth its colour — slate teal. "EPUB" as the title
            // would deal charcoal olive, which sits too near the notepad's cream to tell apart.
            BookCover(relativePath: nil, paths: env.paths, height: Self.cardHeight, title: "Book", badge: "EPUB")
        case .pdf:
            BookCover(relativePath: nil, paths: env.paths, height: Self.cardHeight, title: "PDF", isPDF: true)
        case .link:
            SheetCover(title: "Page", sourceURL: URL(string: "https://www.newyorker.com"), height: Self.cardHeight)
        case .text:
            SheetCover(title: "Notes", sourceURL: nil, height: Self.cardHeight)
        }
    }
}
