import Foundation

/// Spec §3.4.1 tiers, in priority order. `allCases` *is* that order: `RenderArbiter.release()`
/// walks it to hand the lease on, so a tier added here is arbitrated without a second list to
/// keep in step — a tier the arbiter did not know about waited forever.
public enum RenderTier: Int, Hashable, Comparable, CaseIterable, Sendable {
    /// The playing document's window ahead of the playhead — always wins the next boundary.
    case playAhead = 0
    /// A new import's first 30 s, or the continue-document's at launch.
    case prime
    /// The rest of the playing document's chapter, clamped, while frontmost and listening (Plan
    /// 18). After `prime` — an import during playback must not wait ten minutes behind a fill —
    /// and before `prepare`, which on a charger plans the same utterances at the budget's pace.
    case chapterAhead
    /// The continue-document, then the queue, while charging.
    case prepare
    /// "Render whole document".
    case manual
    public static func < (a: RenderTier, b: RenderTier) -> Bool { a.rawValue < b.rawValue }
}

public struct RenderJob: Hashable, Sendable {
    public var documentID: UUID
    public var utteranceIndex: Int
    public var tier: RenderTier
    public init(documentID: UUID, utteranceIndex: Int, tier: RenderTier) {
        self.documentID = documentID
        self.utteranceIndex = utteranceIndex
        self.tier = tier
    }
}

/// What the policy needs to know about one document.
public struct RenderSnapshot: Hashable, Sendable {
    public var documentID: UUID
    /// Current duration per utterance (estimated or actual), at 1x.
    public var seconds: [TimeInterval]
    /// Whether the store already holds each utterance's audio.
    public var rendered: [Bool]
    public var resumeIndex: Int
    /// The flat utterance index each chapter starts at, in chapter order; an empty chapter repeats
    /// the next one's start. The fill tier rounds its bound to the chapter with it (Plan 18); the
    /// other tiers never look.
    public var chapterStarts: [Int]

    public init(documentID: UUID, seconds: [TimeInterval], rendered: [Bool], resumeIndex: Int, chapterStarts: [Int] = [0]) {
        precondition(seconds.count == rendered.count)
        self.documentID = documentID
        self.seconds = seconds
        self.rendered = rendered
        self.resumeIndex = resumeIndex
        self.chapterStarts = chapterStarts
    }

    public init(documentID: UUID, timeline: Timeline, rendered: [Bool], resumeIndex: Int) {
        var secs: [TimeInterval] = []
        var starts: [Int] = []
        secs.reserveCapacity(timeline.utteranceCount)
        starts.reserveCapacity(timeline.chapters.count)
        for ch in timeline.chapters {
            starts.append(secs.count)
            for u in ch.utterances { secs.append(u.duration.seconds) }
        }
        self.init(documentID: documentID, seconds: secs, rendered: rendered, resumeIndex: resumeIndex, chapterStarts: starts)
    }

    /// One past the last utterance of the chapter holding `i`: the next chapter's start, or the
    /// document's end for the last chapter. Duplicate starts (empty chapters) are skipped by the
    /// `> i` test, and an `i` past every start ends at the document.
    public func chapterEnd(containing i: Int) -> Int {
        chapterStarts.first { $0 > i } ?? seconds.count
    }
}

public struct PlayingState: Hashable, Sendable {
    public var documentID: UUID
    public var playhead: Playhead
    public var rate: Double
    public init(documentID: UUID, playhead: Playhead, rate: Double) {
        self.documentID = documentID
        self.playhead = playhead
        self.rate = rate
    }
}

public struct DeviceState: Hashable, Sendable {
    public var charging: Bool
    public var thermalSerious: Bool
    public var lowPowerMode: Bool
    public var storeFull: Bool
    public init(charging: Bool, thermalSerious: Bool, lowPowerMode: Bool, storeFull: Bool) {
        self.charging = charging
        self.thermalSerious = thermalSerious
        self.lowPowerMode = lowPowerMode
        self.storeFull = storeFull
    }
    public static let unplugged = DeviceState(charging: false, thermalSerious: false, lowPowerMode: false, storeFull: false)
}

public struct PolicyInput: Sendable {
    public var documents: [UUID: RenderSnapshot]
    public var playing: PlayingState?
    public var lastPlayed: UUID?
    public var queue: [UUID]
    /// Newly imported documents that have not been primed yet.
    public var primes: [UUID]
    /// "Render whole document" requests.
    public var manual: [UUID]
    public var device: DeviceState
    /// Play-ahead window at 1x (spec §3.4); multiplied by the rate.
    public var windowSeconds: TimeInterval = 60
    public var primeSeconds: TimeInterval = 30
    /// Spec §3.4.1 default: 3 hours of listening ready.
    public var prepareBudgetSeconds: TimeInterval = 3 * 3600
    /// The foreground fill's bound, in audio seconds at 1x from the playhead: the rest of the
    /// playing document's chapter, clamped to this range (Plan 18). Nil — the default, and every
    /// state but frontmost-and-listening — renders only the window.
    public var foregroundFill: ClosedRange<TimeInterval>? = nil

    public init(documents: [UUID: RenderSnapshot], playing: PlayingState? = nil, lastPlayed: UUID? = nil,
                queue: [UUID] = [], primes: [UUID] = [], manual: [UUID] = [], device: DeviceState = .unplugged) {
        self.documents = documents
        self.playing = playing
        self.lastPlayed = lastPlayed
        self.queue = queue
        self.primes = primes
        self.manual = manual
        self.device = device
    }
}

/// Pure: (library, playback, device) → ordered jobs (spec §3.4.1). Table-testable.
public enum RenderPolicy {
    public static func plan(_ input: PolicyInput) -> [RenderJob] {
        var jobs: [RenderJob] = []
        var seen: Set<Pair> = []

        /// Walks `doc` from `start`, accumulating every utterance's seconds (rendered or not) against
        /// `budget`, emitting jobs for the unrendered ones. Returns the seconds consumed.
        @discardableResult
        func walk(_ doc: RenderSnapshot, from start: Int, budget: TimeInterval?, tier: RenderTier) -> TimeInterval {
            var used: TimeInterval = 0
            var i = max(0, start)
            while i < doc.seconds.count {
                if let budget, used >= budget { break }
                if !doc.rendered[i], seen.insert(Pair(doc.documentID, i)).inserted {
                    jobs.append(RenderJob(documentID: doc.documentID, utteranceIndex: i, tier: tier))
                }
                used += doc.seconds[i]
                i += 1
            }
            return used
        }

        // Tier 1: play-ahead, window in playback-seconds at the current rate.
        if let p = input.playing, let doc = input.documents[p.documentID] {
            walk(doc, from: p.playhead.utteranceIndex, budget: input.windowSeconds * p.rate, tier: .playAhead)
        }
        // Tier 2: prime — a newly imported document from its start, the continue-document from where
        // the reader left it (spec §3.4.1; `resumeIndex` is 0 for a new import).
        for id in input.primes {
            if let doc = input.documents[id] { walk(doc, from: doc.resumeIndex, budget: input.primeSeconds, tier: .prime) }
        }
        let d = input.device
        // Tier 2b: the foreground fill — the rest of the playing document's chapter, clamped to the
        // range, in any power state but not on a hot, low-power, or full device (Plan 18). The bound
        // is 1x audio seconds, not scaled by the rate: the window is a time-to-dry, the fill a CPU
        // and disk spend. What the window planned is in `seen`, so the chapter's jobs follow it in
        // index order; a remainder shorter than the minimum runs on into the next chapter, which is
        // simply the walk continuing.
        if let fill = input.foregroundFill, let p = input.playing, let doc = input.documents[p.documentID],
           !d.thermalSerious, !d.lowPowerMode, !d.storeFull {
            let start = max(0, p.playhead.utteranceIndex)
            let end = min(doc.chapterEnd(containing: start), doc.seconds.count)
            let toChapterEnd = start < end ? doc.seconds[start..<end].reduce(0, +) : 0
            walk(doc, from: start, budget: min(max(toChapterEnd, fill.lowerBound), fill.upperBound), tier: .chapterAhead)
        }
        // Tier 3: prepare while charging — continue-document first, then queue order, one shared budget.
        if d.charging && !d.thermalSerious && !d.lowPowerMode && !d.storeFull {
            var order: [UUID] = []
            for id in [input.lastPlayed].compactMap({ $0 }) + input.queue where !order.contains(id) { order.append(id) }
            var remaining = input.prepareBudgetSeconds
            for id in order {
                guard remaining > 0, let doc = input.documents[id] else { continue }
                remaining -= walk(doc, from: doc.resumeIndex, budget: remaining, tier: .prepare)
            }
        }
        // Tier 4: manual whole-document renders, any power state, unless the store is full.
        if !d.storeFull {
            for id in input.manual {
                if let doc = input.documents[id] { walk(doc, from: 0, budget: nil, tier: .manual) }
            }
        }
        return jobs
    }

    private struct Pair: Hashable {
        let id: UUID, index: Int
        init(_ id: UUID, _ index: Int) { self.id = id; self.index = index }
    }
}
