import Foundation

/// Spoken text plus the mapping back to the untouched source (spec §4.1).
/// Offsets are UTF-16 throughout, matching NSRange.
public struct NormalizedText: Hashable, Sendable {
    public let source: String
    public private(set) var spoken: String
    /// Sorted by spokenRange.lowerBound; spoken ranges never overlap.
    public private(set) var spans: [SpanMap]

    public init(source: String) {
        self.source = source
        self.spoken = source
        let n = source.utf16.count
        self.spans = [SpanMap(sourceRange: 0..<n, spokenRange: 0..<n)]
    }

    /// Rebuilds a persisted mapping without re-running rules. The caller guarantees the
    /// three parts came from one normalization pass (they are stored together on Utterance).
    public init(source: String, spoken: String, spans: [SpanMap]) {
        self.source = source
        self.spoken = spoken
        self.spans = spans
    }

    /// The one primitive rules use. Replaces `r` in `spoken` and rewrites spans so the
    /// new text maps to whatever source the replaced text mapped to.
    public mutating func replace(spokenRange r: Range<Int>, with replacement: String) {
        precondition(r.lowerBound >= 0 && r.upperBound <= spoken.utf16.count, "range out of bounds")
        let newLen = replacement.utf16.count
        var before: [SpanMap] = []
        var after: [SpanMap] = []
        var coveredLo = Int.max
        var coveredHi = Int.min

        for span in spans {
            let sr = span.spokenRange
            if sr.isEmpty {
                if sr.lowerBound <= r.lowerBound { before.append(span) } else { after.append(span) }
                continue
            }
            if sr.upperBound <= r.lowerBound { before.append(span); continue }
            if sr.lowerBound >= r.upperBound { after.append(span); continue }

            let ol = max(sr.lowerBound, r.lowerBound)
            let ou = min(sr.upperBound, r.upperBound)
            if span.isLinear {
                let base = span.sourceRange.lowerBound - sr.lowerBound
                coveredLo = min(coveredLo, base + ol)
                coveredHi = max(coveredHi, base + ou)
                if sr.lowerBound < ol {
                    before.append(SpanMap(sourceRange: (base + sr.lowerBound)..<(base + ol), spokenRange: sr.lowerBound..<ol))
                }
                if ou < sr.upperBound {
                    after.append(SpanMap(sourceRange: (base + ou)..<(base + sr.upperBound), spokenRange: ou..<sr.upperBound))
                }
            } else {
                coveredLo = min(coveredLo, span.sourceRange.lowerBound)
                coveredHi = max(coveredHi, span.sourceRange.upperBound)
                if sr.lowerBound < ol {
                    before.append(SpanMap(sourceRange: span.sourceRange, spokenRange: sr.lowerBound..<ol))
                }
                if ou < sr.upperBound {
                    after.append(SpanMap(sourceRange: span.sourceRange, spokenRange: ou..<sr.upperBound))
                }
            }
        }

        if coveredLo == Int.max {
            // Pure insertion: zero-width source point after the preceding span.
            let p = before.last?.sourceRange.upperBound ?? 0
            coveredLo = p
            coveredHi = p
        }

        let delta = newLen - r.count
        let inserted = SpanMap(sourceRange: coveredLo..<coveredHi, spokenRange: r.lowerBound..<(r.lowerBound + newLen))
        let shifted = after.map {
            SpanMap(sourceRange: $0.sourceRange,
                    spokenRange: ($0.spokenRange.lowerBound + delta)..<($0.spokenRange.upperBound + delta))
        }
        spans = before + [inserted] + shifted

        let lo = String.Index(utf16Offset: r.lowerBound, in: spoken)
        let hi = String.Index(utf16Offset: r.upperBound, in: spoken)
        spoken.replaceSubrange(lo..<hi, with: replacement)
    }

    /// Projection used at playback time: a spoken range → the source range to highlight.
    public func sourceRange(forSpoken r: Range<Int>) -> Range<Int> {
        var lo = Int.max
        var hi = Int.min
        for span in spans where !span.spokenRange.isEmpty {
            let ol = max(span.spokenRange.lowerBound, r.lowerBound)
            let ou = min(span.spokenRange.upperBound, r.upperBound)
            guard ol < ou else { continue }
            if span.isLinear {
                let s = span.sourceRange.lowerBound + (ol - span.spokenRange.lowerBound)
                lo = min(lo, s)
                hi = max(hi, s + (ou - ol))
            } else {
                lo = min(lo, span.sourceRange.lowerBound)
                hi = max(hi, span.sourceRange.upperBound)
            }
        }
        if lo == Int.max {
            let p = spans.last(where: { $0.spokenRange.lowerBound <= r.lowerBound })?.sourceRange.upperBound ?? 0
            return p..<p
        }
        return lo..<hi
    }

    /// Inverse projection used when resolving a persisted Position.
    public func spokenRange(forSource r: Range<Int>) -> Range<Int> {
        var lo = Int.max
        var hi = Int.min
        for span in spans {
            let ol = max(span.sourceRange.lowerBound, r.lowerBound)
            let ou = min(span.sourceRange.upperBound, r.upperBound)
            let overlaps = span.sourceRange.isEmpty
                ? (r.lowerBound <= span.sourceRange.lowerBound && span.sourceRange.lowerBound < r.upperBound)
                : ol < ou
            guard overlaps else { continue }
            if span.isLinear {
                let s = span.spokenRange.lowerBound + (ol - span.sourceRange.lowerBound)
                lo = min(lo, s)
                hi = max(hi, s + (ou - ol))
            } else {
                lo = min(lo, span.spokenRange.lowerBound)
                hi = max(hi, span.spokenRange.upperBound)
            }
        }
        if lo == Int.max {
            let p = spans.last(where: { $0.sourceRange.lowerBound <= r.lowerBound })?.spokenRange.upperBound ?? 0
            return p..<p
        }
        return lo..<hi
    }
}
