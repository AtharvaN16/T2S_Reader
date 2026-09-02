// Sources/T2SCore/Timeline/PositionResolver.swift
import Foundation

extension Utterance {
    var normalized: NormalizedText {
        NormalizedText(source: source, spoken: spoken, spans: spans)
    }

    /// Seconds at 1x at which the source character at `offset` is spoken.
    public func time(atSourceOffset offset: Int) -> TimeInterval {
        let clamped = max(0, min(offset, source.utf16.count))
        let spokenAt = normalized.spokenRange(forSource: clamped..<min(clamped + 1, source.utf16.count)).lowerBound
        if let timings = wordTimings, !timings.isEmpty {
            if let w = timings.last(where: { $0.spokenRange.lowerBound <= spokenAt }) { return w.start }
            return 0
        }
        let n = max(1, spoken.utf16.count)
        return duration.seconds * Double(spokenAt) / Double(n)
    }

    /// Source UTF-16 offset being spoken at `time` seconds at 1x.
    public func sourceOffset(atTime time: TimeInterval) -> Int {
        let spokenAt: Int
        if let timings = wordTimings, !timings.isEmpty {
            spokenAt = timings.last(where: { $0.start <= time })?.spokenRange.lowerBound ?? 0
        } else {
            let fraction = duration.seconds > 0 ? max(0, min(1, time / duration.seconds)) : 0
            spokenAt = Int((Double(spoken.utf16.count) * fraction).rounded(.down))
        }
        return normalized.sourceRange(forSpoken: spokenAt..<min(spokenAt + 1, spoken.utf16.count)).lowerBound
    }
}

public enum PositionResolver {
    /// Never fails. Falls back to chapter start, never to document start (spec §6).
    public static func resolve(_ p: Position, in t: Timeline) -> Playhead {
        var index = 0
        var candidates: [(Int, Utterance)] = []
        for ch in t.chapters {
            for u in ch.utterances {
                if u.position.resourceHref == p.resourceHref { candidates.append((index, u)) }
                index += 1
            }
        }

        if !candidates.isEmpty {
            if let c = p.charOffset {
                if let (i, u) = candidates.first(where: {
                    guard let start = $0.1.position.charOffset else { return false }
                    return start <= c && c < start + $0.1.source.utf16.count
                }) {
                    return Playhead(utteranceIndex: i, offset: u.time(atSourceOffset: c - u.position.charOffset!))
                }
                if let (i, u) = candidates.last(where: { ($0.1.position.charOffset ?? Int.max) <= c }) {
                    return Playhead(utteranceIndex: i, offset: u.duration.seconds)
                }
                return Playhead(utteranceIndex: candidates[0].0, offset: 0)
            }
            let (i, _) = candidates.last(where: { $0.1.position.progression <= p.progression }) ?? candidates[0]
            return Playhead(utteranceIndex: i, offset: 0)
        }

        if let c = t.chapters.firstIndex(where: { $0.position.resourceHref == p.resourceHref }),
           !t.chapters[c].utterances.isEmpty {
            return Playhead(utteranceIndex: t.utteranceRange(ofChapter: c).lowerBound, offset: 0)
        }
        return Playhead(utteranceIndex: 0, offset: 0)
    }

    public static func position(for ph: Playhead, in t: Timeline) -> Position {
        let u = t[utterance: ph.utteranceIndex]
        var p = u.position
        p.charOffset = u.position.charOffset.map { $0 + u.sourceOffset(atTime: ph.offset) }
        return p
    }
}
