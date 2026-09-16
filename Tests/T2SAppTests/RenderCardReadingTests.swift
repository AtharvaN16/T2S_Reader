import Foundation
import Testing
@testable import T2SApp

@Suite struct RenderCardReadingTests {
    private let book = UUID()

    private func jobs(ready: Int, total: Int, failed: Int = 0,
                      document: UUID? = nil) -> [ChapterRenderJob] {
        (0..<total).map { index in
            let state: ChapterRenderJob.State = index < ready
                ? .ready
                : index < ready + failed ? .failed("The store is full") : .queued
            return ChapterRenderJob(documentID: document ?? book, chapterIndex: index,
                                    title: "Chapter \(index + 1)", utteranceCount: 10,
                                    rendered: index < ready ? 10 : 0, state: state)
        }
    }

    @Test func restingSaysHowManyOfHowMany() throws {
        let reading = try #require(RenderCardReading.make(jobs: jobs(ready: 3, total: 8),
                                                          bookTitle: "India in 1857",
                                                          hold: nil, event: nil, canAlert: true))
        #expect(reading.headline == "India in 1857")
        #expect(reading.detail == "3 of 8 chapters ready")
        #expect(reading.ready == 3 && reading.total == 8)
        #expect(reading.fraction == 3.0 / 8.0)
        #expect(!reading.alerts)
        #expect(!reading.isFinished)
    }

    @Test func aJustFinishedChapterTakesTheHeadlineAndAlerts() throws {
        let reading = try #require(RenderCardReading.make(
            jobs: jobs(ready: 4, total: 8), bookTitle: "India in 1857", hold: nil,
            event: .finished(name: "Chp 4: The Siege of Delhi"), canAlert: true))
        #expect(reading.headline == "Chp 4: The Siege of Delhi is ready")
        #expect(reading.detail == "4 of 8 chapters ready")
        #expect(reading.alerts)
    }

    @Test func theLastOneEndsTheCard() throws {
        let reading = try #require(RenderCardReading.make(
            jobs: jobs(ready: 8, total: 8), bookTitle: "India in 1857", hold: nil,
            event: .finished(name: "Chp 8: Aftermath"), canAlert: true))
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
                                                      hold: .hot, event: nil, canAlert: true))
        #expect(hot.detail == "Paused while the phone cools")
        #expect(!hot.alerts)

        let full = try #require(RenderCardReading.make(jobs: jobs(ready: 2, total: 8),
                                                       bookTitle: "India in 1857",
                                                       hold: .storeFull, event: nil, canAlert: true))
        #expect(full.detail == "Paused — storage is full")

        let paused = try #require(RenderCardReading.make(jobs: jobs(ready: 2, total: 8),
                                                         bookTitle: "India in 1857",
                                                         hold: .byReader, event: nil, canAlert: true))
        #expect(paused.detail == "Paused")
    }

    @Test func noJobsMeansNoCard() {
        #expect(RenderCardReading.make(jobs: [], bookTitle: "India in 1857",
                                       hold: nil, event: nil, canAlert: true) == nil)
    }

    /// One chapter is one chapter. The card said "1 chapters ready" until 2026-09-16.
    @Test func oneChapterIsNotPlural() throws {
        let reading = try #require(RenderCardReading.make(jobs: jobs(ready: 1, total: 1),
                                                          bookTitle: "A Short Essay", hold: nil,
                                                          event: nil, canAlert: true))
        #expect(reading.detail == "1 chapter ready")

        let resting = try #require(RenderCardReading.make(jobs: jobs(ready: 0, total: 1),
                                                          bookTitle: "A Short Essay", hold: nil,
                                                          event: nil, canAlert: true))
        #expect(resting.detail == "0 of 1 chapter ready")
    }

    /// A batch where nothing survived still settles, and still took the "is ready" branch. It
    /// must not congratulate the reader on a book that does not exist.
    @Test func aWhollyFailedBatchSaysSo() throws {
        let reading = try #require(RenderCardReading.make(jobs: jobs(ready: 0, total: 3, failed: 3),
                                                          bookTitle: "India in 1857", hold: nil,
                                                          event: nil, canAlert: true))
        #expect(reading.headline == "India in 1857 couldn't be rendered")
        #expect(reading.detail == "3 chapters failed")
        #expect(reading.isFinished)
    }

    /// A chapter that fails while the reader is away is announced on the card and nowhere else,
    /// so the card has to carry the reason (review I6).
    @Test func aFailureCarriesItsReasonAndAlerts() throws {
        let reading = try #require(RenderCardReading.make(
            jobs: jobs(ready: 2, total: 8, failed: 1), bookTitle: "India in 1857", hold: nil,
            event: .failed(title: "Chapter couldn't be rendered", reason: "The store is full"),
            canAlert: true))
        #expect(reading.headline == "Chapter couldn't be rendered")
        #expect(reading.detail == "The store is full")
        #expect(reading.alerts)
        #expect(!reading.isFinished)
    }

    /// "Never both" (owner, 2026-09-16): with the app on screen the capsule says it, and every
    /// reading the card can produce has to stay silent — including the batch-complete branch,
    /// which alerted unconditionally and was only quiet by the accident of never being called
    /// from the foreground (review C2/I2).
    @Test func nothingAlertsWhenTheCallerForbidsIt() throws {
        let finished = try #require(RenderCardReading.make(
            jobs: jobs(ready: 4, total: 8), bookTitle: "India in 1857", hold: nil,
            event: .finished(name: "Chp 4: The Siege of Delhi"), canAlert: false))
        #expect(!finished.alerts)

        let complete = try #require(RenderCardReading.make(
            jobs: jobs(ready: 8, total: 8), bookTitle: "India in 1857", hold: nil,
            event: nil, canAlert: false))
        #expect(!complete.alerts)
        #expect(complete.isFinished, "silent, but still the last thing the card says")

        let failure = try #require(RenderCardReading.make(
            jobs: jobs(ready: 2, total: 8, failed: 1), bookTitle: "India in 1857", hold: nil,
            event: .failed(title: "Chapter couldn't be rendered", reason: "The store is full"),
            canAlert: false))
        #expect(!failure.alerts)
    }

    /// The queue is the whole session's, across every document. The second book's batch must be
    /// counted on its own or the card names the first book and tallies both (review C3).
    @Test func theCardCountsOneBookAndNotTheSession() {
        let alchemist = UUID()
        let delhi = UUID()
        let session = jobs(ready: 1, total: 1, document: alchemist)
            + jobs(ready: 0, total: 3, document: delhi)

        let running = RenderCardReading.focus(session)
        #expect(running.count == 3)
        #expect(running.allSatisfy { $0.documentID == delhi })

        let named = RenderCardReading.focus(session, preferring: alchemist)
        #expect(named.count == 1)
        #expect(named[0].documentID == alchemist)
    }

    /// With a job running, the running one's book wins over the most recently enqueued.
    @Test func theRunningJobDecidesWhichBookTheCardIsAbout() {
        let running = UUID()
        let queuedLater = UUID()
        let session = [
            ChapterRenderJob(documentID: running, chapterIndex: 0, title: "One",
                             utteranceCount: 10, rendered: 3, state: .running),
            ChapterRenderJob(documentID: queuedLater, chapterIndex: 0, title: "Two",
                             utteranceCount: 10, rendered: 0, state: .queued),
        ]
        #expect(RenderCardReading.focus(session).map(\.documentID) == [running])
    }

    @Test func anEmptyQueueFocusesOnNothing() {
        #expect(RenderCardReading.focus([]).isEmpty)
    }
}
