import Foundation
import Testing
@testable import T2SKokoro

/// Every Core ML call ends with the model's end-of-input pause and begins with the BOS lead-in, so
/// the seam between two pieces of one sentence held 400–820 ms of silence (the finding's probe).
/// The trim brings it down to what the model puts at that kind of boundary inside one call.
@Suite struct KokoroCoreMLSeamTests {
    static let rate = 24_000
    static func ms(_ n: Int) -> Int { rate * n / 1000 }
    /// "Speech": a square wave at −10 dBFS, so no sample of it — first or last — ever sits inside the
    /// −50 dBFS silence threshold the way a sine's zero crossings do.
    static func tone(ms n: Int) -> [Float] {
        (0 ..< ms(n)).map { $0 % 2 == 0 ? 0.3 : -0.3 }
    }
    static func zeros(ms n: Int) -> [Float] { [Float](repeating: 0, count: ms(n)) }

    @Test func dropsFromTheHeadFirst() {
        let previous = Self.tone(ms: 500) + Self.zeros(ms: 100)
        let next = Self.zeros(ms: 300) + Self.tone(ms: 500)
        let t = KokoroCoreMLSeam.trimmed(previous: previous, next: next, budget: Self.ms(300), tailCap: Self.ms(100), headCap: Self.ms(300))
        #expect(t.droppedHead == Self.ms(100))
        #expect(t.droppedTail == 0)
        #expect(t.previous == previous)
        #expect(t.next == Array(next.dropFirst(Self.ms(100))))
    }

    @Test func thenFromTheTailWithinItsCap() {
        let previous = Self.tone(ms: 500) + Self.zeros(ms: 460)
        let next = Self.zeros(ms: 280) + Self.tone(ms: 500)
        let t = KokoroCoreMLSeam.trimmed(previous: previous, next: next, budget: Self.ms(60), tailCap: Self.ms(150), headCap: Self.ms(280))
        #expect(t.droppedHead == Self.ms(280))
        #expect(t.droppedTail == Self.ms(150))
        #expect(t.previous == Array(previous.dropLast(Self.ms(150))))
        #expect(t.next == Array(next.dropFirst(Self.ms(280))))
    }

    @Test func leavesASeamWithinItsBudget() {
        let previous = Self.tone(ms: 500) + Self.zeros(ms: 40)
        let next = Self.zeros(ms: 200) + Self.tone(ms: 500)
        let t = KokoroCoreMLSeam.trimmed(previous: previous, next: next, budget: Self.ms(320), tailCap: Self.ms(40), headCap: Self.ms(200))
        #expect(t.droppedHead == 0 && t.droppedTail == 0)
        #expect(t.previous == previous && t.next == next)
    }

    @Test func treatsTheNoiseFloorAsSilence() {
        let floor = (0 ..< Self.ms(300)).map { Float($0 % 2 == 0 ? 5e-5 : -5e-5) }
        let t = KokoroCoreMLSeam.trimmed(previous: Self.tone(ms: 500), next: floor + Self.tone(ms: 500), budget: Self.ms(60), tailCap: 0, headCap: Self.ms(300))
        #expect(t.droppedHead == Self.ms(240))
    }

    @Test func neverEmptiesEitherSide() {
        let t = KokoroCoreMLSeam.trimmed(previous: Self.zeros(ms: 100), next: Self.zeros(ms: 100), budget: 0, tailCap: Self.ms(100), headCap: Self.ms(100))
        #expect(t.droppedHead == 0 && t.droppedTail == 0)
    }

    @Test func budgetsFollowTheKindOfCut() {
        #expect(KokoroCoreMLSeam.budgetSamples(for: .word) == Self.ms(60))
        #expect(KokoroCoreMLSeam.budgetSamples(for: .clause) == Self.ms(320))
        #expect(KokoroCoreMLSeam.budgetSamples(for: .sentence) == Self.ms(500))
    }

    /// Streaming finalizes a piece before the next exists: its tail silence is cut to the budget on
    /// its own, and the next piece's lead-in is cut on its own, up to its BOS frames (Plan 14).
    @Test func tailAndHeadAreTrimmedIndependently() {
        let loud: [Float] = Array(repeating: 0.5, count: 100)
        let quiet: [Float] = Array(repeating: 0.001, count: 1000)
        let tail = KokoroCoreMLSeam.trimmedTail(loud + quiet, budget: 300)
        #expect(tail.dropped == 700 && tail.audio.count == 400)
        let untouched = KokoroCoreMLSeam.trimmedTail(loud + quiet, budget: .max)
        #expect(untouched.dropped == 0)
        let head = KokoroCoreMLSeam.trimmedHead(quiet + loud, cap: 250)
        #expect(head.dropped == 250 && head.audio.count == 850)
        let all = KokoroCoreMLSeam.trimmedHead(quiet + loud, cap: 5000)
        #expect(all.dropped == 1000 && all.audio.first == 0.5)
        let silentOnly = KokoroCoreMLSeam.trimmedTail(quiet, budget: 300)
        #expect(silentOnly.dropped == 0)                             // never emptied: nothing but silence is left alone
    }
}
