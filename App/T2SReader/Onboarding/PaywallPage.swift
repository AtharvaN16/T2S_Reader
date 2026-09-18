// App/T2SReader/Onboarding/PaywallPage.swift
import SwiftUI
import T2SApp

/// The welcome's last screen: what Pro is, what it costs, and an honest way past it (the owner,
/// 2026-09-18: "then paywall page with mockup of all premium features", with two references —
/// Amie's *everyday package* for the shape, and timespent's note to its readers for the tone).
///
/// **It charges nobody.** No StoreKit, no product ids, no receipt: the key continues, exactly as
/// the 2026-09-14 design decided and the owner reaffirmed. Everything it says comes from
/// `ProOffer`, so the prices and the saving cannot drift apart from one another or be quoted twice
/// differently.
///
/// The shape is Amie's: a title, a list of what you get with a coloured mark against each, the
/// plans as rows you pick between, and one key. Two things are deliberately not Amie's:
///
/// - **Each line says what the free tier does instead**, in the same size and only a shade
///   quieter. A feature list that shows only what is withheld is a list of things the reader
///   cannot have; naming the free tier beside it makes it a comparison, which is what it is.
/// - **The foot is timespent's note**, not a smaller "maybe later" link. A reader who is not going
///   to pay today is told that is fine, and told what the free tier will always be — which costs
///   this screen nothing and is the difference between a price list and a squeeze.
///
/// The yearly plan is pre-selected because it is the one most readers want; pre-selecting lifetime
/// would be the sort of nudge the foot of this screen promises not to make.
struct PaywallPage: View {
    var offer: ProOffer
    var onSubscribe: (String) -> Void
    var onSkip: () -> Void

    @State private var plan: String

    init(offer: ProOffer, onSubscribe: @escaping (String) -> Void, onSkip: @escaping () -> Void) {
        self.offer = offer
        self.onSubscribe = onSubscribe
        self.onSkip = onSkip
        _plan = State(initialValue: offer.defaultPlan)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    features.padding(.top, Spacing.row)
                    plans.padding(.top, Spacing.section)
                    promises.padding(.top, Spacing.section)
                }
                .padding(.horizontal, Spacing.margin)
                .padding(.top, Spacing.row)
                .padding(.bottom, Spacing.section * 2 + 72)
            }
            .scrollIndicators(.hidden)

            key
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.grid) {
            Text("T2S Pro")
                .typeRole(.pageTitle)
                .foregroundStyle(Tokens.ink)
            Text("Everything in T2S, with nothing held back.")
                .typeRole(.rowTitle)
                .foregroundStyle(Tokens.ink2)
        }
    }

    /// One row per promise: a coloured mark, what Pro gives, and what the free tier gives under it.
    private var features: some View {
        VStack(alignment: .leading, spacing: Spacing.row - 6) {
            ForEach(Array(offer.features.enumerated()), id: \.element.id) { index, feature in
                HStack(alignment: .top, spacing: Spacing.grid + 4) {
                    Image(systemName: feature.glyph)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Tokens.onAccent)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Self.tint(index)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(feature.title)
                            .typeRole(.rowTitle)
                            .foregroundStyle(Tokens.ink)
                        Text(feature.free)
                            .typeRole(.meta)
                            .foregroundStyle(Tokens.ink2)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(feature.title). Free tier: \(feature.free)")
            }
        }
    }

    /// The marks' colours, spaced around the wheel the way the voices' are, so five rows read as
    /// five things rather than one list in one hue.
    private static func tint(_ index: Int) -> Color {
        Color(hue: (Double(index) / 5 + 0.56).truncatingRemainder(dividingBy: 1),
              saturation: 0.62, brightness: 0.78)
    }

    private var plans: some View {
        VStack(spacing: Spacing.grid + 2) {
            ForEach(offer.plans) { option in
                planRow(option)
            }
        }
    }

    private func planRow(_ option: ProOffer.Plan) -> some View {
        let isChosen = option.id == plan
        return Button { plan = option.id } label: {
            HStack(spacing: Spacing.grid + 4) {
                Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(isChosen ? Tokens.glow : Tokens.ink3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .typeRole(.rowTitle)
                        .foregroundStyle(Tokens.ink)
                    if let perMonth = option.perMonth {
                        Text(perMonth)
                            .typeRole(.meta)
                            .foregroundStyle(Tokens.ink2)
                    }
                }
                Spacer(minLength: Spacing.grid)
                VStack(alignment: .trailing, spacing: 3) {
                    if let badge = option.badge {
                        Text(badge)
                            .typeRole(.fine)
                            .foregroundStyle(Tokens.onAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Tokens.positive))
                    }
                    Text(option.price)
                        .typeRole(.rowTitle)
                        .foregroundStyle(Tokens.ink)
                }
            }
            .padding(.horizontal, Spacing.grid + 6)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Tokens.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isChosen ? Tokens.glow : .clear, lineWidth: 2)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isChosen)
        .accessibilityLabel("\(option.title), \(option.price)")
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    /// timespent's note, in this app's voice: what a reader who does not pay still gets, and what
    /// this screen will never do to them.
    private var promises: some View {
        VStack(alignment: .leading, spacing: Spacing.row - 8) {
            Text("Not ready for Pro? That's fine.")
                .typeRole(.sectionHeader)
                .foregroundStyle(Tokens.ink)
            promise("A free tier worth using",
                    "Eight of the best voices, five books, and the reader itself — not a trial, and not on a timer.")
            promise("No dark patterns",
                    "You will not be asked again on every launch, and nothing will start charging you quietly.")
            promise("Or bring friends instead",
                    "Invite \(offer.referralsForFreeMonth) people to T2S and a month of Pro is yours, free.")
        }
        .padding(Spacing.row - 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tokens.surface.opacity(0.6)))
    }

    private func promise(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .typeRole(.metaStrong)
                .foregroundStyle(Tokens.ink)
            Text(body)
                .typeRole(.meta)
                .foregroundStyle(Tokens.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var key: some View {
        VStack(spacing: Spacing.grid + 2) {
            RaisedButton(label: "Start Pro", tone: .blue, size: .bar) { onSubscribe(plan) }
            Button("Stay on the free tier", action: onSkip)
                .typeRole(.pill)
                .foregroundStyle(Tokens.ink2)
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.bottom, Spacing.grid)
        .background { BottomFade(fade: 150, color: Tokens.ground) }
    }
}
