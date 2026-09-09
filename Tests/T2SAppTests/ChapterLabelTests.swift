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
        ["Title Page", "Introduction", "The Fall", "Epilogue"],             // no numbered chapter at all
        ["Chapters of My Life", "Chapel"],                                  // words that only start like one
        [],
    ])
    func bodyStartIsNilWithNothingToSkipTo(titles: [String]) {
        #expect(ChapterLabel.bodyStart(titles: titles) == nil)
    }
}
