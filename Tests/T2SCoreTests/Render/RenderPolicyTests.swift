import Foundation
import Testing
@testable import T2SCore

@Suite struct RenderPolicyTests {
    let a = UUID(), b = UUID(), c = UUID()

    /// 100 utterances of 10 s each = 1,000 s per document.
    func snap(_ id: UUID, rendered: Set<Int> = [], resume: Int = 0) -> RenderSnapshot {
        RenderSnapshot(documentID: id, seconds: Array(repeating: 10, count: 100),
                       rendered: (0..<100).map { rendered.contains($0) }, resumeIndex: resume)
    }
    func input(playing: PlayingState? = nil, lastPlayed: UUID? = nil, queue: [UUID] = [], primes: [UUID] = [],
               manual: [UUID] = [], device: DeviceState = .init(charging: false, thermalSerious: false, lowPowerMode: false, storeFull: false),
               docs: [RenderSnapshot]) -> PolicyInput {
        var i = PolicyInput(documents: Dictionary(uniqueKeysWithValues: docs.map { ($0.documentID, $0) }),
                            playing: playing, lastPlayed: lastPlayed, queue: queue, primes: primes, manual: manual, device: device)
        i.windowSeconds = 60
        i.primeSeconds = 30
        i.prepareBudgetSeconds = 300
        return i
    }
    func indices(_ jobs: [RenderJob], _ id: UUID, _ tier: RenderTier) -> [Int] {
        jobs.filter { $0.documentID == id && $0.tier == tier }.map(\.utteranceIndex)
    }

    @Test func playAheadWindowScalesWithRate() {
        let one = RenderPolicy.plan(input(playing: .init(documentID: a, playhead: .init(utteranceIndex: 5, offset: 3), rate: 1), docs: [snap(a)]))
        #expect(indices(one, a, .playAhead) == [5, 6, 7, 8, 9, 10])          // 60 s at 1x → 6 utterances
        let three = RenderPolicy.plan(input(playing: .init(documentID: a, playhead: .init(utteranceIndex: 5, offset: 3), rate: 3), docs: [snap(a)]))
        #expect(indices(three, a, .playAhead) == Array(5..<23))                // 180 s at 3x → 18 utterances
    }

    @Test func renderedUtterancesCountTowardTheWindowButAreNotJobs() {
        let jobs = RenderPolicy.plan(input(playing: .init(documentID: a, playhead: .init(utteranceIndex: 0, offset: 0), rate: 1), docs: [snap(a, rendered: [0, 1, 2])]))
        #expect(indices(jobs, a, .playAhead) == [3, 4, 5])
    }

    @Test func primeRendersTheFirstThirtySeconds() {
        let jobs = RenderPolicy.plan(input(primes: [b], docs: [snap(b)]))
        #expect(indices(jobs, b, .prime) == [0, 1, 2])
    }

    /// The continue-document is primed at launch from where the reader left it, not from page one.
    @Test func primeStartsAtTheResumeIndex() {
        let jobs = RenderPolicy.plan(input(primes: [b], docs: [snap(b, resume: 50)]))
        #expect(indices(jobs, b, .prime) == [50, 51, 52])
    }

    @Test func prepareOnlyWhileCharging() {
        let off = RenderPolicy.plan(input(lastPlayed: a, queue: [a, b], docs: [snap(a), snap(b)]))
        #expect(off.isEmpty)
        for bad in [DeviceState(charging: true, thermalSerious: true, lowPowerMode: false, storeFull: false),
                    DeviceState(charging: true, thermalSerious: false, lowPowerMode: true, storeFull: false),
                    DeviceState(charging: true, thermalSerious: false, lowPowerMode: false, storeFull: true)] {
            #expect(RenderPolicy.plan(input(lastPlayed: a, queue: [a], device: bad, docs: [snap(a)])).isEmpty)
        }
    }

    @Test func prepareContinuesLastPlayedThenQueueWithinBudget() {
        let charging = DeviceState(charging: true, thermalSerious: false, lowPowerMode: false, storeFull: false)
        let jobs = RenderPolicy.plan(input(lastPlayed: b, queue: [a, b, c], device: charging,
                                           docs: [snap(a, resume: 50), snap(b, resume: 90), snap(c)]))
        let prepare = jobs.filter { $0.tier == .prepare }
        // b from 90: 10 utterances = 100 s; then a from 50: 200 s remaining = 20 utterances; c gets nothing.
        #expect(prepare.prefix(10).allSatisfy { $0.documentID == b })
        #expect(indices(jobs, b, .prepare) == Array(90..<100))
        #expect(indices(jobs, a, .prepare) == Array(50..<70))
        #expect(indices(jobs, c, .prepare).isEmpty)
    }

    @Test func manualRendersWholeDocumentRegardlessOfPower() {
        let jobs = RenderPolicy.plan(input(manual: [c], docs: [snap(c, rendered: [7])]))
        #expect(indices(jobs, c, .manual) == (0..<100).filter { $0 != 7 })
    }

    @Test func tiersAreOrderedAndDeduplicated() {
        let charging = DeviceState(charging: true, thermalSerious: false, lowPowerMode: false, storeFull: false)
        let jobs = RenderPolicy.plan(input(playing: .init(documentID: a, playhead: .init(utteranceIndex: 0, offset: 0), rate: 1),
                                           lastPlayed: a, queue: [a], primes: [a], manual: [a], device: charging, docs: [snap(a)]))
        #expect(jobs.map(\.tier) == jobs.map(\.tier).sorted())
        #expect(Set(jobs.map(\.utteranceIndex)).count == jobs.count)
        #expect(indices(jobs, a, .playAhead) == [0, 1, 2, 3, 4, 5])
        #expect(indices(jobs, a, .prime).isEmpty)                             // already covered by play-ahead
        #expect(indices(jobs, a, .prepare) == Array(6..<30))                  // budget 300 s counts the 60 s already ahead
        #expect(indices(jobs, a, .manual) == Array(30..<100))
    }

    @Test func unknownDocumentsAreIgnored() {
        #expect(RenderPolicy.plan(input(primes: [b], manual: [c], docs: [])).isEmpty)
    }

    /// The snapshot carries where each chapter starts, so the fill tier can round its bound to the
    /// chapter (Plan 18). An empty chapter repeats the next start; `chapterEnd` skips it.
    @Test func snapshotCarriesChapterStartsAndEnds() {
        let timeline = makeTimeline([3, 4, 0, 2].map { n in (0..<n).map { makeUtterance("u\($0)", seconds: 10) } })
        let snapshot = RenderSnapshot(documentID: a, timeline: timeline, rendered: Array(repeating: false, count: 9), resumeIndex: 0)
        #expect(snapshot.chapterStarts == [0, 3, 7, 7])
        #expect(snapshot.seconds.count == 9)
        #expect(snapshot.chapterEnd(containing: 0) == 3)
        #expect(snapshot.chapterEnd(containing: 2) == 3)
        #expect(snapshot.chapterEnd(containing: 4) == 7)
        #expect(snapshot.chapterEnd(containing: 7) == 9)
        #expect(snapshot.chapterEnd(containing: 8) == 9)
        #expect(snapshot.chapterEnd(containing: 40) == 9)                                          // past the end: the document's end
        #expect(snap(a).chapterStarts == [0])                                                     // the array init: one chapter
        #expect(snap(a).chapterEnd(containing: 50) == 100)
    }

    /// The arbiter hands the lease on in `allCases` order, so declaration order must be priority order.
    @Test func tierDeclarationOrderIsPriorityOrder() {
        #expect(RenderTier.allCases == RenderTier.allCases.sorted())
        #expect(RenderTier.allCases == [.playAhead, .prime, .chapterAhead, .prepare, .manual])
    }
}
