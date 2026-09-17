import Foundation
import Testing
@testable import T2SApp

@Suite struct ChapterReadyMessageTests {
    private func job(_ state: ChapterRenderJob.State, title: String = "4. The Siege of Delhi",
                     index: Int = 3) -> ChapterRenderJob {
        ChapterRenderJob(documentID: UUID(), chapterIndex: index, title: title,
                         utteranceCount: 10, rendered: 10, state: state)
    }

    @Test func aChapterOfABookIsNamedAndNumbered() {
        let message = ChapterReadyMessage.make(job: job(.ready), documentTitle: "India in 1857",
                                               chapterCount: 12)
        #expect(message.title == "Chapter ready to play")
        #expect(message.detail == "Chp 4: The Siege of Delhi has finished rendering")
        // The name on its own, for a surface that composes its own sentence out of it. The Live
        // Activity was handed `detail` and read "…has finished rendering is ready" (review I1).
        #expect(message.name == "Chp 4: The Siege of Delhi")
        #expect(!message.isFailure)
    }

    /// One chapter is not a book with a chapter in it — an article, or an imported PDF — and its
    /// single piece has no name worth printing, so the document's own title stands in.
    @Test func aSingleChapterDocumentUsesItsOwnTitle() {
        let message = ChapterReadyMessage.make(job: job(.ready), documentTitle: "India in 1857",
                                               chapterCount: 1)
        #expect(message.title == "Document ready to play")
        #expect(message.detail == "India in 1857 has finished rendering")
        #expect(message.name == "India in 1857")
    }

    @Test func aFailureCarriesTheRunnersOwnSentence() {
        let message = ChapterReadyMessage.make(job: job(.failed("The store is full")),
                                               documentTitle: "India in 1857", chapterCount: 12)
        #expect(message.title == "Chapter couldn't be rendered")
        #expect(message.detail == "The store is full")
        // Named even when it failed: the card's failure line says which chapter it was.
        #expect(message.name == "Chp 4: The Siege of Delhi")
        #expect(message.isFailure)
    }

    @Test func aSingleChapterFailureDropsTheWordChapter() {
        let message = ChapterReadyMessage.make(job: job(.failed("The store is full")),
                                               documentTitle: "India in 1857", chapterCount: 1)
        #expect(message.title == "Couldn't be rendered")
    }
}
