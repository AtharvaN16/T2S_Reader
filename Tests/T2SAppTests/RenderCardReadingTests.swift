import Foundation
import Testing
@testable import T2SApp

@Suite struct RenderCardReadingTests {
    private let book = UUID()

    private func jobs(ready: Int, total: Int) -> [ChapterRenderJob] {
        (0..<total).map { index in
            ChapterRenderJob(documentID: book, chapterIndex: index, title: "Chapter \(index + 1)",
                             utteranceCount: 10, rendered: index < ready ? 10 : 0,
                             state: index < ready ? .ready : .queued)
        }
    }

    @Test func restingSaysHowManyOfHowMany() throws {
        let reading = try #require(RenderCardReading.make(jobs: jobs(ready: 3, total: 8),
                                                          bookTitle: "India in 1857",
                                                          hold: nil, justFinished: nil))
        #expect(reading.headline == "India in 1857")
        #expect(reading.detail == "3 of 8 chapters ready")
        #expect(reading.ready == 3 && reading.total == 8)
        #expect(reading.fraction == 3.0 / 8.0)
        #expect(!reading.alerts)
        #expect(!reading.isFinished)
    }

    @Test func aJustFinishedChapterTakesTheHeadlineAndAlerts() throws {
        let reading = try #require(RenderCardReading.make(jobs: jobs(ready: 4, total: 8),
                                                          bookTitle: "India in 1857", hold: nil,
                                                          justFinished: "Chp 4: The Siege of Delhi"))
        #expect(reading.headline == "Chp 4: The Siege of Delhi is ready")
        #expect(reading.detail == "4 of 8 chapters ready")
        #expect(reading.alerts)
    }

    @Test func theLastOneEndsTheCard() throws {
        let reading = try #require(RenderCardReading.make(jobs: jobs(ready: 8, total: 8),
                                                          bookTitle: "India in 1857", hold: nil,
                                                          justFinished: "Chp 8: Aftermath"))
        #expect(reading.headline == "India in 1857 is ready")
        #expect(reading.detail == "8 chapters ready")
        #expect(reading.fraction == 1)
        #expect(reading.isFinished)
        #expect(reading.alerts)
    }

    /// A hold is not an error and must not alert — the phone being hot is not news worth a buzz.
    @Test func aHoldSaysWhyAndStaysQuiet() throws {
        let hot = try #require(RenderCardReading.make(jobs: jobs(ready: 2, total: 8),
                                                      bookTitle: "India in 1857",
                                                      hold: .hot, justFinished: nil))
        #expect(hot.detail == "Paused while the phone cools")
        #expect(!hot.alerts)

        let full = try #require(RenderCardReading.make(jobs: jobs(ready: 2, total: 8),
                                                       bookTitle: "India in 1857",
                                                       hold: .storeFull, justFinished: nil))
        #expect(full.detail == "Paused — storage is full")

        let paused = try #require(RenderCardReading.make(jobs: jobs(ready: 2, total: 8),
                                                         bookTitle: "India in 1857",
                                                         hold: .byReader, justFinished: nil))
        #expect(paused.detail == "Paused")
    }

    @Test func noJobsMeansNoCard() {
        #expect(RenderCardReading.make(jobs: [], bookTitle: "India in 1857",
                                       hold: nil, justFinished: nil) == nil)
    }
}
