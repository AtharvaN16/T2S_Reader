import Foundation
import Testing
import T2SCore
import T2SStore
@testable import T2SApp

@Suite struct DocumentProgressTests {
    func utterance(_ text: String, href: String, offset: Int, seconds: TimeInterval, rendered: Bool = false) -> Utterance {
        let n = text.utf16.count
        return Utterance(position: Position(resourceHref: href, progression: 0, charOffset: offset), source: text, spoken: text,
                         spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)], audioRef: rendered ? "k" : nil,
                         duration: rendered ? .actual(seconds) : .estimated(seconds))
    }

    func timeline(rendered: Bool = false) -> Timeline {
        Timeline(chapters: [
            Chapter(title: "One", position: Position(resourceHref: "a", progression: 0, charOffset: 0), utterances: [
                utterance("Alpha.", href: "a", offset: 0, seconds: 10, rendered: rendered),
                utterance("Beta.", href: "a", offset: 7, seconds: 10, rendered: rendered),
            ]),
            Chapter(title: "Two", position: Position(resourceHref: "b", progression: 0, charOffset: 0), utterances: [
                utterance("Gamma.", href: "b", offset: 0, seconds: 20, rendered: rendered),
            ]),
        ])
    }

    func summary(resume: Position?) -> DocumentSummary {
        DocumentSummary(document: Document(title: "D", sourceType: .epub, resumePosition: resume), chapterCount: 2, utteranceCount: 3,
                        totalSeconds: 40, renderedCount: 0, isFinished: false, queueOrder: 0, lastPlayedAt: nil)
    }

    @Test func freshDocumentStartsAtZero() {
        let p = DocumentProgress.compute(summary: summary(resume: nil), timeline: timeline())
        #expect(p.elapsedSeconds == 0 && p.totalSeconds == 40 && p.remainingSeconds == 40)
        #expect(p.chapterIndex == 0 && p.chapterCount == 2 && p.fraction == 0)
        #expect(p.isApproximate)
    }

    @Test func resumeInsideTheSecondChapter() {
        let p = DocumentProgress.compute(summary: summary(resume: Position(resourceHref: "b", progression: 0, charOffset: 0)),
                                         timeline: timeline(rendered: true))
        #expect(p.elapsedSeconds == 20 && p.remainingSeconds == 20 && p.chapterIndex == 1)
        #expect(p.fraction == 0.5)
        #expect(!p.isApproximate)
    }

    @Test func emptyTimelineIsSafe() {
        let p = DocumentProgress.compute(summary: summary(resume: nil), timeline: Timeline(chapters: []))
        #expect(p.totalSeconds == 0 && p.fraction == 0 && p.chapterIndex == nil && p.chapterCount == 0)
    }
}
