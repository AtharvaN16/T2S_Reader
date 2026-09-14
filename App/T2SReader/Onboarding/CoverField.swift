// App/T2SReader/Onboarding/CoverField.swift
import SwiftUI
import T2SApp

/// The welcome's first scene: the sample books rise through a field of covers in depth parallax
/// while their opening lines chatter past (design: `docs/superpowers/specs/2026-09-14-onboarding-design.md`;
/// the owner's references, the Queue podcast app's rising cards and the ATC replay app's card that
/// settles out of the drift). Depth, not motion sensing — far cards are small, blurred and slow,
/// near cards large, sharp and fast, all drifting upward on one axis — and no tap: the voices
/// start with the cards.
///
/// Everything is a function of `elapsed` on the scene's clock, through `RisingChoreography`: the
/// card at the near, sharp layer is the one whose voice is up, and its voice's volume is the
/// card's height on screen. The last book is the hero. It rises the same way but eases to rest
/// top centre instead of leaving, and the field dims out behind it, the way the ATC app's red
/// card is left alone on black.
///
/// With Reduce Motion nothing travels: each book fades in and out at the centre for its slot, the
/// field stands still and dim, and the hero fades in at its rest.
struct CoverField: View {
    /// In rising order, the hero last.
    var books: [OnboardingManifest.Book]
    var scene: RisingChoreography
    var elapsed: TimeInterval

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let nearHeight: CGFloat = 300
    /// Where the hero rests, as a fraction of the height above the centre.
    static let heroRest: CGFloat = -0.16
    /// How long the field takes to dim once the hero begins to settle.
    static let fieldFade: TimeInterval = 1.1

    /// The near layer's small variations per card, so five in a row do not read as one card
    /// repeated: a lean and a shift, alternating.
    private static let leans: [Double] = [-4, 3.5, -2.5, 4, 0]
    private static let shifts: [CGFloat] = [-22, 18, -12, 24, 0]

    /// The ambient field: which cover, how deep, where across the screen, how fast, and where on
    /// its loop it starts. Fixed, so the choreography is the same every launch.
    private struct FieldCard {
        var book: Int
        var layer: Layer
        var x: CGFloat        // fraction of the width from the centre
        var speed: CGFloat    // points per second, upward
        var phase: CGFloat    // fraction of the loop
        var lean: Double
    }

    private enum Layer {
        case far, middle
        var height: CGFloat { self == .far ? 118 : 188 }
        var blur: CGFloat { self == .far ? 14 : 6 }
        var opacity: Double { self == .far ? 0.5 : 0.82 }
    }

    private static let field: [FieldCard] = [
        FieldCard(book: 1, layer: .far, x: -0.34, speed: 14, phase: 0.05, lean: -9),
        FieldCard(book: 3, layer: .far, x: 0.36, speed: 12, phase: 0.42, lean: 7),
        FieldCard(book: 0, layer: .far, x: 0.08, speed: 16, phase: 0.72, lean: -5),
        FieldCard(book: 2, layer: .middle, x: -0.40, speed: 30, phase: 0.28, lean: -8),
        FieldCard(book: 4, layer: .middle, x: 0.42, speed: 26, phase: 0.62, lean: 10),
        FieldCard(book: 1, layer: .middle, x: 0.30, speed: 34, phase: 0.90, lean: -6),
        FieldCard(book: 3, layer: .far, x: -0.12, speed: 11, phase: 0.20, lean: 4),
        FieldCard(book: 0, layer: .middle, x: -0.18, speed: 28, phase: 0.08, lean: 6),
    ]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(Array(Self.field.enumerated()), id: \.offset) { _, card in
                    if card.book < books.count {
                        fieldCard(card, in: size)
                    }
                }
                ForEach(Array(books.enumerated()), id: \.offset) { index, book in
                    nearCard(book, index: index, in: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .accessibilityHidden(true)
    }

    // MARK: The near layer

    private var fieldOpacity: Double {
        let t = (elapsed - scene.settleStart) / Self.fieldFade
        return 1 - min(max(t, 0), 1)
    }

    @ViewBuilder
    private func nearCard(_ book: OnboardingManifest.Book, index: Int, in size: CGSize) -> some View {
        let isHero = index == scene.heroIndex
        let p = scene.progress(of: index, at: elapsed)
        let travel = Self.nearHeight + size.height   // from fully below to fully above
        let cover = BookCover(relativePath: nil, paths: env.paths, height: Self.nearHeight,
                              title: book.title, author: book.author)

        if reduceMotion {
            // In place, fading: on for its slot, the hero on for good at its rest.
            let fadeIn = smooth(p / 0.15)
            let fadeOut = isHero ? 0 : smooth((p - 0.75) / 0.2)
            cover
                .offset(y: isHero ? size.height * Self.heroRest : 0)
                .opacity(fadeIn * (1 - fadeOut))
        } else if isHero {
            // Up like the others, then eased to rest over the same span, and held.
            let clamped = min(max(p, 0), 1)
            let eased = 1 - pow(1 - clamped, 3)
            let y = (travel / 2) - (travel / 2 - size.height * Self.heroRest) * eased
            let lean = Self.leans[index % Self.leans.count] * (1 - eased)
            cover
                .rotationEffect(.degrees(lean))
                .offset(x: Self.shifts[index % Self.shifts.count] * (1 - eased), y: y)
                .opacity(p >= 0 ? 1 : 0)
        } else {
            // A straight drift from below the screen to above it.
            let y = travel / 2 - travel * p
            cover
                .rotationEffect(.degrees(Self.leans[index % Self.leans.count]))
                .offset(x: Self.shifts[index % Self.shifts.count], y: y)
                .opacity(p > -0.02 && p < 1.02 ? 1 : 0)
        }
    }

    // MARK: The field

    @ViewBuilder
    private func fieldCard(_ card: FieldCard, in size: CGSize) -> some View {
        let book = books[card.book]
        let loop = size.height + card.layer.height * 1.5
        let travelled = reduceMotion ? 0 : card.speed * elapsed
        // Start `phase` of the way up the loop and drift upward; wrap to below when past the top.
        let along = (card.phase * loop + travelled).truncatingRemainder(dividingBy: loop)
        let y = loop / 2 - along
        BookCover(relativePath: nil, paths: env.paths, height: card.layer.height,
                  title: book.title, author: book.author)
            .rotationEffect(.degrees(card.lean))
            .blur(radius: card.layer.blur)
            .offset(x: size.width * card.x, y: y)
            .opacity(card.layer.opacity * (reduceMotion ? 0.6 : 1) * fieldOpacity)
    }

    private func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
