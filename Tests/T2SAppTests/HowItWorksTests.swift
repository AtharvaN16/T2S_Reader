import Foundation
import Testing
@testable import T2SApp

/// Settings → About → "How it works". The copy is data so it can be read on the Mac: one of these
/// lines is a privacy promise, and all of them are the kind of writing that grows.
@Suite struct HowItWorksTests {
    @Test func everyPointCarriesAGlyphATitleAndABody() {
        #expect(!HowItWorks.points.isEmpty)
        for point in HowItWorks.points {
            #expect(!point.symbol.isEmpty)
            #expect(!point.title.isEmpty)
            #expect(!point.body.isEmpty)
        }
    }

    /// The guard on the writing, and the reason this file exists (owner, 2026-09-16: "too many
    /// options and this is very bad UX writing"). The first draft was six points of 200 characters
    /// each — 233 words of prose on a settings sheet. A short list of short lines is the whole
    /// design, so the length is a test rather than a note nobody reads.
    @Test func theSheetStaysShortEnoughToBeRead() {
        #expect(HowItWorks.points.count <= 4)
        #expect(HowItWorks.lead.count <= 80)
        for point in HowItWorks.points {
            #expect(point.title.count <= 16)             // two or three plain words
            #expect(point.body.count <= 140)             // two sentences, no more
        }
    }

    /// Titles appear once each: a list read straight down with two points named the same thing
    /// reads as a mistake.
    @Test func titlesAndIdentifiersAreDistinct() {
        #expect(Set(HowItWorks.points.map(\.title)).count == HowItWorks.points.count)
        #expect(Set(HowItWorks.points.map(\.id)).count == HowItWorks.points.count)
    }

    /// The two facts a reader cannot learn anywhere else in the app: where the speech is made, and
    /// that the phone getting warm is the app working rather than the app failing.
    @Test func theSheetKeepsItsTwoLoadBearingClaims() {
        #expect(HowItWorks.points.contains { $0.body.contains("never on a server") })
        #expect(HowItWorks.points.contains { $0.title == "May warm up" })
    }
}
