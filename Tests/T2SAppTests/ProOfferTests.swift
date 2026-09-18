import Foundation
import Testing
@testable import T2SApp

@Suite struct ProOfferTests {
    let offer = ProOffer.standard

    @Test func thePricesAreTheOnesTheOwnerSet() {
        #expect(ProOffer.monthlyPrice == 1.99)
        #expect(ProOffer.yearlyPrice == 12.99)
        #expect(ProOffer.lifetimePrice == 39.99)
    }

    /// The badge is measured against the prices rather than written beside them, so the two can
    /// never drift apart when one is next tuned.
    @Test func theYearlyBadgeIsDerivedFromTheYearlySaving() {
        #expect(ProOffer.yearAtMonthlyRate == 23.88)
        #expect(ProOffer.yearlySavingPercent == 45)
        #expect(offer.plans.first { $0.id == "yearly" }?.badge == "Save 45%")
    }

    /// Rounded down, never up: a paywall that says it does not nudge cannot overstate its own
    /// discount by a point.
    @Test func theSavingRoundsDown() {
        let exact = (ProOffer.yearAtMonthlyRate - ProOffer.yearlyPrice) as NSDecimalNumber
        let fraction = exact.doubleValue / (ProOffer.yearAtMonthlyRate as NSDecimalNumber).doubleValue
        #expect(Double(ProOffer.yearlySavingPercent) <= fraction * 100)
    }

    /// Every feature says what the free tier does instead. A blank against a Pro line reads as a
    /// punishment where a sentence reads as a tier — and the free tier here is meant to be worth
    /// using on its own.
    @Test func everyFeatureNamesWhatTheFreeTierGives() {
        #expect(offer.features.count == 5)
        for feature in offer.features {
            #expect(!feature.free.isEmpty)
            #expect(!feature.title.isEmpty)
            #expect(feature.free.lowercased().contains("free"))
        }
    }

    @Test func theTiersAreTheOnesAgreed() {
        let free = Dictionary(uniqueKeysWithValues: offer.features.map { ($0.id, $0.free) })
        #expect(free["voices"]?.contains("Eight") == true)
        #expect(free["library"]?.contains("Five") == true)
        #expect(free["render"]?.contains("chapter") == true)
        #expect(offer.referralsForFreeMonth == 4)
    }

    /// Not the dearest plan. Pre-selecting lifetime on a screen that promises no dark patterns
    /// would be exactly one.
    @Test func theYearlyPlanIsTheOneSelected() {
        #expect(offer.defaultPlan == "yearly")
        #expect(offer.plans.contains { $0.id == offer.defaultPlan })
    }

    @Test func everyPlanIdIsDistinct() {
        #expect(Set(offer.plans.map(\.id)).count == offer.plans.count)
        #expect(Set(offer.features.map(\.id)).count == offer.features.count)
    }
}
