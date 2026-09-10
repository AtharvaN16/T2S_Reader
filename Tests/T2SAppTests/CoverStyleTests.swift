import Foundation
import Testing
@testable import T2SApp

@Suite struct CoverStyleTests {
    @Test func paletteIndexIsStableAndInRange() {
        let a = CoverStyle.paletteIndex(for: "The Last Mughal", count: 8)
        #expect(a == CoverStyle.paletteIndex(for: "The Last Mughal", count: 8))
        #expect((0..<8).contains(a))
    }

    @Test func paletteIndexIgnoresCaseAndSurroundingSpace() {
        #expect(CoverStyle.paletteIndex(for: "  the last mughal ", count: 8) == CoverStyle.paletteIndex(for: "The Last Mughal", count: 8))
    }

    @Test func paletteIndexSpreadsDifferentTitles() {
        let titles = ["The Last Mughal", "Children's Literature", "Thinking in Systems", "Weirdly useful books",
                      "2008 - A Case of Exploding Mangoes", "Surgical Inference", "Dune", "Middlemarch", "Ulysses", "Emma"]
        let used = Set(titles.map { CoverStyle.paletteIndex(for: $0, count: 8) })
        #expect(used.count >= 4)
    }

    @Test func paletteIndexHandlesAnEmptyCountAndTitle() {
        #expect(CoverStyle.paletteIndex(for: "", count: 8) == 0 || (0..<8).contains(CoverStyle.paletteIndex(for: "", count: 8)))
        #expect(CoverStyle.paletteIndex(for: "Dune", count: 0) == 0)
    }

    @Test(arguments: [
        ("The Last Mughal", "T"),
        ("2008 - A Case of Exploding Mangoes", "2"),
        ("  émile", "É"),
        ("«Quoted»", "Q"),
        ("", "•"),
        ("---", "•"),
    ])
    func monogram(title: String, expected: String) {
        #expect(CoverStyle.monogram(for: title) == expected)
    }

    @Test(arguments: [
        ("https://www.theatlantic.com/ideas/archive/2024/x", "theatlantic.com"),
        ("https://newsletter.pragmaticengineer.com/p/one", "newsletter.pragmaticengineer.com"),
        ("http://example.org", "example.org"),
        ("https://WWW.Example.COM/a", "example.com"),
    ])
    func host(url: String, expected: String) {
        #expect(CoverStyle.host(of: URL(string: url)!) == expected)
    }

    @Test func hostFallsBackToTheWholeStringWithoutOne() {
        #expect(CoverStyle.host(of: URL(string: "mailto:someone@example.com")!) == "mailto:someone@example.com")
    }

    @Test func dateLabelIsDayAndShortMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))!
        #expect(CoverStyle.dateLabel(for: date, locale: Locale(identifier: "en_GB"), timeZone: calendar.timeZone) == "9 Sep")
        #expect(CoverStyle.dateLabel(for: date, locale: Locale(identifier: "en_US"), timeZone: calendar.timeZone) == "Sep 9")
    }
}
