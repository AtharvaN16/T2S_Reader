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
        ("The Fall", 3, "Chp 3: The Fall"),
        ("Chapter 7", 7, "Chapter 7"),
        ("Chapter Seven: The Fall", 7, "Chapter Seven: The Fall"),
        ("Part Two", 9, "Part Two"),
        ("Prologue", 1, "Prologue"),
        ("Epilogue", 30, "Epilogue"),
    ])
    func labels(title: String, ordinal: Int, expected: String) {
        #expect(ChapterLabel.text(for: title, ordinal: ordinal) == expected)
    }
}
