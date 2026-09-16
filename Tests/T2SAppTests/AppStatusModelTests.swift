import Foundation
import Testing
@testable import T2SApp

/// The band's one slot, and who gets it. The rank is the whole of the logic, and the case that
/// matters is the one where two jobs want the band at once: the reader must be told about the
/// voice, because it is the wait they cannot end and the one that stops all audio.
@MainActor
@Suite struct AppStatusModelTests {

    private final class Fake: StatusSource {
        let kind: StatusKind
        var isActive: Bool
        var endedAt: Date?
        var reading: StatusReading?
        /// `showing` sets both, which is the ordinary case. `fading` is the one that matters:
        /// a job whose claim on the band has ended but whose words must survive the fade out.
        init(_ kind: StatusKind, showing: Bool, fading: Bool = false) {
            self.kind = kind
            isActive = showing
            reading = showing || fading ? StatusReading(kind: kind, title: "\(kind)", progress: 0.5) : nil
        }
        func reading(now: Date) -> StatusReading? { reading }
    }

    @Test func theVoiceOutranksARenderThatWantsTheBandAtTheSameTime() {
        let model = AppStatusModel()
        model.register(Fake(.render, showing: true))
        model.register(Fake(.voice, showing: true))
        #expect(model.current(now: Date())?.kind == .voice)
    }

    @Test func aLowerRankedJobTakesTheBandWhenNothingAboveItIsSpeaking() {
        let model = AppStatusModel()
        model.register(Fake(.voice, showing: false))
        model.register(Fake(.render, showing: true))
        #expect(model.current(now: Date())?.kind == .render)
    }

    @Test func nothingShowsWhenNoJobHasAnythingToSay() {
        let model = AppStatusModel()
        model.register(Fake(.voice, showing: false))
        #expect(model.current(now: Date()) == nil)
        #expect(model.isShowing == false)
    }

    /// The regression this pair exists for. The band's gate and the band's words are two different
    /// questions, and a source answers them a fade apart: it stops wanting the screen the moment its
    /// job ends, and keeps saying what happened for as long as the fade takes to carry it off. Asked
    /// as one question, the words blanked on the first frame of a 1.5 s fade and left a lit rim over
    /// nothing.
    @Test func aJobThatHasEndedStopsAskingForTheBandOnTheFrameItEnds() {
        let model = AppStatusModel()
        model.register(Fake(.voice, showing: false, fading: true))
        #expect(model.isShowing == false)
    }

    @Test func butItKeepsItsWordsSoTheEndingIsWhatFadesOut() {
        let model = AppStatusModel()
        model.register(Fake(.voice, showing: false, fading: true))
        #expect(model.current(now: Date())?.kind == .voice)
    }

    @Test func registeringTheSameKindTwiceLeavesOneSourceAnsweringForIt() {
        let model = AppStatusModel()
        model.register(Fake(.voice, showing: true))
        model.register(Fake(.voice, showing: false))
        #expect(model.current(now: Date()) == nil)
    }
}
