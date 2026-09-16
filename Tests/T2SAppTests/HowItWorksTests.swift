import Foundation
import Testing
@testable import T2SApp

/// Settings → About → "How the app works". The copy is data so it can be read on the Mac: a sheet
/// of sentences is exactly the kind of thing that goes quietly untrue as the app changes, and the
/// claims here are load-bearing — one of them is a privacy promise and one of them is a number.
@Suite struct HowItWorksTests {
    @Test func everyPointCarriesAGlyphATitleAndABody() {
        for points in [HowItWorks.points(hasOnDeviceVoice: true), HowItWorks.points(hasOnDeviceVoice: false)] {
            #expect(!points.isEmpty)
            for point in points {
                #expect(!point.symbol.isEmpty)
                #expect(!point.title.isEmpty)
                #expect(!point.body.isEmpty)
            }
        }
    }

    /// The download is the one point that is only true where there is a model to download. The
    /// everyday build plays in the system voice and must not be told about a 620 MB file it will
    /// never fetch.
    @Test func theDownloadIsOnlyPromisedWhereThereIsAModel() {
        let withVoice = HowItWorks.points(hasOnDeviceVoice: true)
        let without = HowItWorks.points(hasOnDeviceVoice: false)
        #expect(withVoice.contains { $0.body.contains("620 MB") })
        #expect(!without.contains { $0.body.contains("620 MB") })
        #expect(without.count == withVoice.count - 1)
    }

    /// The build without the on-device voice still has to say where its voice comes from, or the
    /// sheet opens on "Made on your iPhone" and means something it cannot deliver.
    @Test func theEverydayBuildNamesTheSystemVoice() {
        let without = HowItWorks.points(hasOnDeviceVoice: false)
        #expect(without.contains { $0.body.lowercased().contains("system voice") })
    }

    /// Titles are lines, not paragraphs, and each one appears once — a sheet read top to bottom
    /// with two points called the same thing reads as a mistake.
    @Test func titlesAreShortAndDistinct() {
        let points = HowItWorks.points(hasOnDeviceVoice: true)
        #expect(Set(points.map(\.title)).count == points.count)
        #expect(Set(points.map(\.id)).count == points.count)
        for point in points { #expect(point.title.count <= 30) }
    }

    /// The lead is the sheet's one sentence of summary and sits above the list.
    @Test func theLeadSaysWhereTheVoiceIsMade() {
        #expect(HowItWorks.lead(hasOnDeviceVoice: true).contains("iPhone"))
        #expect(!HowItWorks.lead(hasOnDeviceVoice: false).isEmpty)
    }
}
