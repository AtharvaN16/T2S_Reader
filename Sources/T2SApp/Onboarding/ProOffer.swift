import Foundation

/// What Pro is, what the free tier is, and what Pro costs — in one place, as data (the owner,
/// 2026-09-18, settling the tiers; design:
/// `docs/superpowers/specs/2026-09-16-onboarding-reel-welcome-page-design.md`).
///
/// Nothing here charges anyone. The welcome's last screen is a mock-up that only continues, as the
/// 2026-09-14 design decided and the owner reaffirmed: no StoreKit, no account, nothing gated. This
/// type exists so the copy has one home and can be checked — a paywall whose prices live in three
/// view files is a paywall that will one day quote two of them.
///
/// **The free tier is meant to be worth using.** Eight voices rather than a taster, and the eight
/// are the catalogue's strongest rather than its leftovers (the owner: "we will use the best eight
/// voices because that will provide premium experience in free version"). That is a position, and
/// the paywall says it out loud rather than hiding it.
public struct ProOffer: Hashable, Sendable {
    /// One line of the comparison: what the free tier gives and what Pro adds.
    public struct Feature: Hashable, Sendable, Identifiable {
        public var id: String
        /// The promise, as Pro delivers it — "Every voice", not "Voices".
        public var title: String
        /// What the free tier does instead. Never "—": a blank reads as a punishment, where a
        /// sentence reads as a tier.
        public var free: String
        /// SF Symbol, and which of the app's tints carries it.
        public var glyph: String

        public init(id: String, title: String, free: String, glyph: String) {
            self.id = id
            self.title = title
            self.free = free
            self.glyph = glyph
        }
    }

    public struct Plan: Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        /// What is charged, formatted for display.
        public var price: String
        /// The same money by the month, or nil where the idea does not apply.
        public var perMonth: String?
        /// A badge — "Save 46%" — or nil.
        public var badge: String?

        public init(id: String, title: String, price: String, perMonth: String? = nil, badge: String? = nil) {
            self.id = id
            self.title = title
            self.price = price
            self.perMonth = perMonth
            self.badge = badge
        }
    }

    public var features: [Feature]
    public var plans: [Plan]
    /// Which plan is chosen when the screen opens. The yearly one, because it is the one most
    /// readers want and pre-selecting the dearest would be the kind of nudge this screen says it
    /// does not do.
    public var defaultPlan: String
    /// How many friends earn a free month, and how long that month is.
    public var referralsForFreeMonth: Int

    public static let monthlyPrice: Decimal = 1.99
    public static let yearlyPrice: Decimal = 12.99
    public static let lifetimePrice: Decimal = 39.99

    /// What a year costs if bought a month at a time — the number the yearly badge is measured
    /// against, computed rather than written down so the badge can never drift from the prices.
    public static var yearAtMonthlyRate: Decimal { monthlyPrice * 12 }

    /// The yearly plan's saving against paying monthly, as whole per cent, rounded down: a badge
    /// that rounds *up* is the overstatement this screen is trying not to make.
    public static var yearlySavingPercent: Int {
        let saved = yearAtMonthlyRate - yearlyPrice
        let fraction = (saved as NSDecimalNumber).doubleValue / (yearAtMonthlyRate as NSDecimalNumber).doubleValue
        return Int(fraction * 100)
    }

    public static func money(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    public static let standard = ProOffer(
        features: [
            Feature(id: "voices",
                    title: "Every voice",
                    free: "Eight to start with, free",
                    glyph: "waveform"),
            Feature(id: "library",
                    title: "As many books as you like",
                    free: "Five at a time, free",
                    glyph: "books.vertical.fill"),
            Feature(id: "render",
                    title: "Render a whole book at once",
                    free: "A chapter at a time, free",
                    glyph: "bolt.fill"),
            Feature(id: "sync",
                    title: "Your place on every device",
                    free: "This device, free",
                    glyph: "arrow.triangle.2.circlepath"),
            Feature(id: "themes",
                    title: "Every reading theme",
                    free: "The default theme, free",
                    glyph: "paintpalette.fill"),
        ],
        plans: [
            Plan(id: "yearly",
                 title: "Yearly",
                 price: money(yearlyPrice),
                 perMonth: "\(money(yearlyPrice / 12)) / month",
                 badge: "Save \(yearlySavingPercent)%"),
            Plan(id: "monthly",
                 title: "Monthly",
                 price: money(monthlyPrice),
                 perMonth: "\(money(monthlyPrice)) / month"),
            Plan(id: "lifetime",
                 title: "Lifetime",
                 price: money(lifetimePrice),
                 perMonth: "Pay once",
                 badge: "Best value"),
        ],
        defaultPlan: "yearly",
        referralsForFreeMonth: 4)
}
