import Foundation
@testable import T2SCore

func makeUtterance(_ text: String, seconds: TimeInterval = 1, href: String = "ch1.xhtml",
                   charOffset: Int = 0, progression: Double = 0) -> Utterance {
    let n = text.utf16.count
    return Utterance(
        position: Position(resourceHref: href, progression: progression, charOffset: charOffset),
        source: text, spoken: text,
        spans: [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)],
        audioRef: nil, duration: .estimated(seconds), wordTimings: nil
    )
}

func makeTimeline(_ chapters: [[Utterance]]) -> Timeline {
    Timeline(chapters: chapters.enumerated().map { i, us in
        Chapter(title: "Chapter \(i + 1)",
                position: us.first?.position ?? Position(resourceHref: "ch\(i + 1).xhtml", progression: 0),
                utterances: us)
    })
}
