import Testing
@testable import T2SApp

@Suite struct ChapterLabelTests {
    @Test(arguments: [
        ("7 A Precarious Position", 7, "Chp 7: A Precarious Position"),
        ("7. A Precarious Position", 7, "Chp 7: A Precarious Position"),
        ("12: The Siege", 12, "Chp 12: The Siege"),
        ("7", 7, "Chapter 7"),
        ("", 4, "Chapter 4"),
        ("   ", 4, "Chapter 4"),
        ("The Fall", 3, "The Fall"),
        ("Title Page", 1, "Title Page"),
        ("Dramatis Personae", 5, "Dramatis Personae"),
        ("Chapter 7", 7, "Chapter 7"),
        ("Chapter Seven: The Fall", 7, "Chapter Seven: The Fall"),
        ("Part Two", 9, "Part Two"),
        ("Prologue", 1, "Prologue"),
        ("Epilogue", 30, "Epilogue"),
    ])
    func labels(title: String, ordinal: Int, expected: String) {
        #expect(ChapterLabel.text(for: title, ordinal: ordinal) == expected)
    }

    @Test func bodyStartIsTheFirstNumberedChapterAfterTheFrontMatter() {
        let titles = ["Title Page", "Dedication", "Contents", "Reviews of The Last Mughal", "Dramatis Personae",
                      "Introduction", "1 A Chessboard King", "2 Believers and Infidels"]
        let start = ChapterLabel.bodyStart(titles: titles)
        #expect(start?.index == 6 && start?.number == 1)
    }

    @Test(arguments: [
        (["Cover", "Chapter 1: The Fall"], 1, 1),
        (["Cover", "Copyright", "CHAPTER ONE"], 2, 1),
        (["Cover", "Chapter I. Marley's Ghost"], 1, 1),
        (["Cover", "Ch. 3"], 1, 3),
        (["Foreword", "Chp 2 The Siege"], 1, 2),
    ])
    func bodyStartReadsWordedChapterHeadings(titles: [String], index: Int, number: Int) {
        let start = ChapterLabel.bodyStart(titles: titles)
        #expect(start?.index == index && start?.number == number)
    }

    @Test(arguments: [
        ["1 A Chessboard King", "2 Believers and Infidels"],                // nothing before it to skip
        ["Chapter 1", "Chapter 2"],
        ["Chapters of My Life", "Chapel"],                                  // words that only start like one
        ["The Fall", "The Rise"],                                           // opens on the body already
        ["Title Page", "Contents"],                                         // front matter and nothing else
        [],
    ])
    func bodyStartIsNilWithNothingToSkipTo(titles: [String]) {
        #expect(ChapterLabel.bodyStart(titles: titles) == nil)
    }

    @Test(arguments: [
        (["Cover", "One: The Basics"], 1, 1),
        (["Foreword", "I. Marley's Ghost"], 1, 1),
        (["Title Page", "Part One", "Part Two"], 1, 1),
        (["Contents", "Section 2"], 1, 2),
    ])
    func bodyStartReadsABareNumberOrAPartHeading(titles: [String], index: Int, number: Int) {
        let start = ChapterLabel.bodyStart(titles: titles)
        #expect(start?.index == index && start?.number == number)
    }

    /// A book with no numbered heading anywhere still has a body: the first title that is not front
    /// matter, once some front matter has gone by. No number, so the pill says "Skip the front
    /// matter" (owner's book, 2026-09-10: "Introduction: The Systems Lens" then named chapters).
    @Test(arguments: [
        (["Title Page", "Introduction", "The Fall", "Epilogue"], 2),
        (["Cover", "Copyright", "Contents", "Introduction: The Systems Lens", "The Systems Zoo"], 4),
        (["Praise", "Also by This Author", "Preface — 2014", "A Brief Visit"], 3),
    ])
    func bodyStartFallsBackToTheEndOfTheFrontMatter(titles: [String], index: Int) {
        let start = ChapterLabel.bodyStart(titles: titles)
        #expect(start?.index == index && start?.number == nil)
    }
}
