import Foundation
import Testing
import T2SAudio
import T2SCore
@testable import T2SApp

@MainActor
@Suite struct SoundscapeModelTests {
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    @MainActor final class FakeBed: BedPlaying {
        var loops: [PCMAudio?] = []
        var volumes: [Float] = []
        func setBed(_ loop: PCMAudio?) { loops.append(loop) }
        func setBedVolume(_ volume: Float) { volumes.append(volume) }
    }

    struct FakeLoader: SoundscapeLoading {
        func load(_ soundscape: Soundscape) async -> PCMAudio? {
            PCMAudio(sampleRate: 48_000, samples: [Float](repeating: 0.1, count: 10))
        }
    }

    final class Voice { var playing = false }

    struct Rig {
        let model: SoundscapeModel
        let bed: FakeBed
        let clock: Clock
        let voice: Voice
        let defaults: UserDefaults
    }

    func make() -> Rig {
        let suite = "t2s-soundscape-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let clock = Clock(), bed = FakeBed(), voice = Voice()
        let model = SoundscapeModel(bed: bed, loader: FakeLoader(), preferences: ReaderPreferences(defaults: defaults),
                                    isVoicePlaying: { voice.playing }, clock: { clock.now })
        return Rig(model: model, bed: bed, clock: clock, voice: voice, defaults: defaults)
    }

    /// The ticker's part: a tick every 50 ms for `seconds`.
    func run(_ rig: Rig, seconds: TimeInterval) {
        for _ in 0..<Int((seconds / 0.05).rounded()) {
            rig.clock.advance(0.05)
            rig.model.tick()
        }
    }

    /// −24 dB, the default 0.4 on the slider, as the player is told it.
    let heard = Loudness.linear(SoundscapeModel.decibels(0.4))

    @Test func aChoiceLoadsTheBedAndAuditionsItWhilePaused() async {
        let rig = make()
        await rig.model.choose(Soundscape.named("rain"))
        #expect(rig.bed.loops.count == 1 && rig.bed.loops[0] != nil)
        #expect(rig.model.choice?.id == "rain" && rig.defaults.string(forKey: "soundscape.id") == "rain")
        run(rig, seconds: 1.5)
        #expect(abs((rig.bed.volumes.last ?? 0) - heard) < 1e-4)              // heard: the audition
        run(rig, seconds: 9)                                                   // the window closes, then the fade
        #expect(rig.bed.volumes.last == 0)
    }

    @Test func theBedFollowsTheVoice() async {
        let rig = make()
        await rig.model.choose(Soundscape.named("fire"))
        run(rig, seconds: 10)
        #expect(rig.bed.volumes.last == 0)
        rig.voice.playing = true
        run(rig, seconds: 1.55)                                                // the play is seen on run's first tick, one tick after voice.playing flips
        #expect(abs((rig.bed.volumes.last ?? 0) - heard) < 1e-4)
        rig.voice.playing = false
        run(rig, seconds: 1.6)                                                 // ditto for the pause, with a hair more room: this fade also lands right on the ramp's own grid line
        #expect(rig.bed.volumes.last == 0)
    }

    @Test func aFadeInRisesWithoutAStepBack() async {
        let rig = make()
        await rig.model.choose(Soundscape.named("ocean"))
        run(rig, seconds: 10)
        rig.voice.playing = true
        let before = rig.bed.volumes.count
        run(rig, seconds: 1.6)                                                 // one tick after voice.playing flips, and a hair more: see above
        let fade = Array(rig.bed.volumes[before...])
        #expect(fade.count >= 20)
        #expect(zip(fade.dropFirst(), fade).allSatisfy { $0 >= $1 })
        #expect(rig.model.isRamping == false)
    }

    @Test func theLingerTakesTwentySecondsAndAPlayCancelsIt() async {
        let rig = make()
        await rig.model.choose(Soundscape.named("night"))
        rig.voice.playing = true
        run(rig, seconds: 10)
        rig.voice.playing = false                                              // the sleep timer paused it…
        rig.model.linger()                                                     // …and said so
        run(rig, seconds: 10)
        #expect((rig.bed.volumes.last ?? 0) > 0)                               // halfway down, still heard
        run(rig, seconds: 10.5)
        #expect(rig.bed.volumes.last == 0)
        rig.model.linger()
        rig.voice.playing = true
        run(rig, seconds: 1.55)                                                // one tick after voice.playing flips, as above
        #expect(abs((rig.bed.volumes.last ?? 0) - heard) < 1e-4)
    }

    @Test func changingTheChoiceFadesOutSwapsAndFadesIn() async {
        let rig = make()
        await rig.model.choose(Soundscape.named("rain"))
        rig.voice.playing = true
        run(rig, seconds: 10)
        await rig.model.choose(Soundscape.named("stream"))
        #expect(rig.bed.loops.count == 1)                                      // not yet: it is still up
        run(rig, seconds: 0.9)                                                 // the swap lands one tick past the fade's own 0.8s
        #expect(rig.bed.loops.count == 2)                                      // swapped at the floor
        run(rig, seconds: 1.5)
        #expect(abs((rig.bed.volumes.last ?? 0) - heard) < 1e-4)
    }

    @Test func offDropsTheLoopAfterTheFade() async {
        let rig = make()
        await rig.model.choose(Soundscape.named("forest"))
        rig.voice.playing = true
        run(rig, seconds: 10)
        await rig.model.choose(nil)
        #expect(rig.model.choice == nil && rig.defaults.string(forKey: "soundscape.id") == nil)
        run(rig, seconds: 0.9)                                                 // the swap lands one tick past the fade's own 0.8s
        #expect(rig.bed.loops.count == 2 && rig.bed.loops.last! == nil)
        #expect(rig.bed.volumes.last == 0)
    }

    @Test func theSliderMovesTheLevelAtOnceWhileItPlays() async {
        let rig = make()
        await rig.model.choose(Soundscape.named("brown"))
        rig.voice.playing = true
        run(rig, seconds: 10)
        rig.model.volume = 1
        rig.model.tick()
        #expect(abs((rig.bed.volumes.last ?? 0) - Loudness.linear(-6)) < 1e-4)
        #expect(rig.defaults.double(forKey: "soundscape.volume") == 1)
    }

    @Test func theChoiceAndVolumeComeBackOnTheNextLaunch() async {
        let rig = make()
        await rig.model.choose(Soundscape.named("pink"))
        rig.model.volume = 0.7
        let clock = rig.clock                                                 // Sendable on its own; `rig` is not
        let next = SoundscapeModel(bed: FakeBed(), loader: FakeLoader(), preferences: ReaderPreferences(defaults: rig.defaults),
                                   isVoicePlaying: { false }, clock: { clock.now })
        #expect(next.choice?.id == "pink" && next.volume == 0.7)
    }
}
