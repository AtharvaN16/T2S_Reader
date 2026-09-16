// App/T2SReader/Import/ImportGraphic.swift
import SwiftUI
import T2SApp

/// The picture over the Import hub: the app's mark in the middle, and the four kinds it takes —
/// a book, a PDF, a web page and a page of text — circling in toward it, shrinking and fading as
/// they pass behind it, over and over (owner, 2026-09-16, with a reference: a podcast app drawing
/// artwork into its icon while it sets a library up). Everything the app can read becomes the app.
///
/// **Swapping the mark.** It is one image asset, `AppMark`, and nothing here knows what is on it:
/// drop a PNG over `App/T2SReader/Assets.xcassets/AppMark.imageset/AppMark.png` and the picture
/// takes it, at whatever `markSize` says. `scripts/make-app-icon.swift` writes that file and the
/// app icon from one drawing, so today they are the same pixels; a designed icon replaces both and
/// nothing in this file changes.
///
/// The four are the app's own placeholder covers at the size that is too small for words, which is
/// the face they were drawn for: a cloth binding with the title's letter, the PDF's light red
/// badged "PDF", a browser page with a globe, a notepad with the text glyph. Nothing here stands
/// for a real document — this is the shape of what the page accepts, so a real book's artwork
/// (*Circe*, on the first cut) said the wrong thing.
struct ImportGraphic: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The loop's own zero. `@State`, so it is the moment the picture first appeared and not a
    /// number that jumps when the view is rebuilt.
    @State private var start = Date()

    /// The frame the picture stands in: the ring's far edge (`orbit`) plus half a card, doubled.
    /// A card is faded almost to nothing that far out, so the couple of points it overhangs at the
    /// very start of its trip cost nothing.
    static let height: CGFloat = 286
    /// The mark, a half again the cards it pulls in — the reference's proportion.
    private static let markSize: CGFloat = 96
    /// The radius a kind enters at, and spirals in from. It has to clear the mark's own corner
    /// (68 pt out) by a card's half-width, or the four begin their trip already touching it, which
    /// is what 96 did: a huddle round the icon rather than a ring with room in it.
    private static let orbit: CGFloat = 116
    /// One trip in, in seconds. Four kinds a quarter-turn of the loop apart means one arrives
    /// every 1.8 s, which is about the pace of the reference.
    private static let period: Double = 7.2
    /// How far round the mark a kind travels on its way in. Under about 70° it reads as a fall
    /// straight inward rather than as circling; much over 120° and the card crosses the path of
    /// the one behind it.
    private static let sweep: Double = 96
    /// A card's height: under `ClothCover`'s 64 pt, so all four wear their compact faces.
    private static let cardHeight: CGFloat = 62

    private enum Kind: CaseIterable, Identifiable {
        case pdf, book, link, text
        var id: Self { self }
    }

    private struct Orbiter: Identifiable {
        var kind: Kind
        /// Where it comes in, in degrees clockwise from twelve o'clock.
        var entry: Double
        /// Where in the loop it starts, 0..1 — the stagger.
        var phase: Double
        /// The card's own tilt, so the four read as objects dropped onto the ring rather than as
        /// icons pegged to it.
        var lean: Double
        var id: Kind { kind }
    }

    /// The PDF enters from the left, on the owner's word (2026-09-16); the other three take the
    /// remaining quarters, each a quarter of the loop behind the last.
    private static let orbiters = [
        Orbiter(kind: .pdf, entry: 270, phase: 0, lean: -7),
        Orbiter(kind: .book, entry: 0, phase: 0.25, lean: 5),
        Orbiter(kind: .link, entry: 90, phase: 0.5, lean: 8),
        Orbiter(kind: .text, entry: 180, phase: 0.75, lean: -6),
    ]

    var body: some View {
        ZStack {
            bloom
            ring
            mark
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var ring: some View {
        if reduceMotion {
            // Nothing travels with Reduce Motion on: the four stand still where they enter, and
            // the picture is a diagram of what the page takes rather than an animation of it.
            ZStack {
                ForEach(Self.orbiters) { orbiter in
                    card(orbiter.kind)
                        .rotationEffect(.degrees(orbiter.lean))
                        .offset(place(angle: orbiter.entry, radius: Self.orbit))
                }
            }
        } else {
            TimelineView(.animation) { timeline in
                let clock = timeline.date.timeIntervalSince(start) / Self.period
                ZStack {
                    ForEach(Self.orbiters) { orbiter in
                        travelling(orbiter, at: (clock + orbiter.phase).truncatingRemainder(dividingBy: 1))
                    }
                }
            }
        }
    }

    /// One kind, `progress` of the way in. Radius, angle and size all run off one smoothstep, so a
    /// card drifts at the far edge, gathers pace across the middle and settles as it reaches the
    /// mark — one movement, not three that happen to overlap. It is blurred while it is far out
    /// (the reference's depth) and gone before it touches the mark's edge, so nothing is ever seen
    /// being clipped by it; `zIndex` is not needed, because the mark is drawn after the whole ring.
    private func travelling(_ orbiter: Orbiter, at progress: Double) -> some View {
        let eased = progress * progress * (3 - 2 * progress)
        return card(orbiter.kind)
            .rotationEffect(.degrees(orbiter.lean))
            .scaleEffect(1 - 0.52 * eased)
            .blur(radius: 2.6 * max(0, 1 - progress / 0.42))
            .opacity(fade(progress))
            .offset(place(angle: orbiter.entry + Self.sweep * eased, radius: Self.orbit * (1 - eased)))
    }

    /// In over the first beat, out over the last third: a kind arrives out of the blur and has gone
    /// by the time it is behind the mark, so the loop's seam — the jump from the middle back to the
    /// ring — happens at nothing and cannot be seen.
    private func fade(_ progress: Double) -> Double {
        if progress < 0.16 { return progress / 0.16 }
        if progress > 0.68 { return max(0, (1 - progress) / 0.32) }
        return 1
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
            .shadow(color: Tokens.shade.opacity(0.18), radius: 16, y: 8)
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
            ], center: .center, startRadius: 0, endRadius: 112))
            .frame(width: 224, height: 224)
    }

    /// One kind's placeholder cover. The titles are only what deals each one its colour
    /// (`CoverStyle.paletteIndex`) and letters the book: a teal book, the PDF's light red, an
    /// indigo globe on a white page, a forest-green text glyph on cream — four cards no two of
    /// which are the same colour or the same shape of thing.
    private func card(_ kind: Kind) -> some View {
        face(kind).shadow(color: Tokens.shade.opacity(0.12), radius: 7, y: 3)
    }

    /// The two sheets are white and cream paper; on `ground` they need the shadow `card` adds or
    /// they read as holes in the page rather than as things standing over it.
    @ViewBuilder private func face(_ kind: Kind) -> some View {
        switch kind {
        case .book:
            BookCover(relativePath: nil, paths: env.paths, height: Self.cardHeight, title: "Book")
        case .pdf:
            BookCover(relativePath: nil, paths: env.paths, height: Self.cardHeight, title: "PDF", isPDF: true)
        case .link:
            SheetCover(title: "Page", sourceURL: URL(string: "https://www.newyorker.com"), height: Self.cardHeight)
        case .text:
            SheetCover(title: "Notes", sourceURL: nil, height: Self.cardHeight)
        }
    }
}
