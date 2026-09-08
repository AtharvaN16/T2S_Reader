import Foundation
import Testing
@testable import T2SKokoro

/// The Core ML pipeline leaves a click at the tail of every call: a burst of about 20 ms, 60 to 40 ms
/// before the end of the trimmed audio, bounded by digital silence on both sides, loud when speech
/// ended recently (−12 dBFS after a comma or a closing quote), gone when the call ends in a long
/// pause. The MLX reference never produces it. `spikes/findings/2026-09-08-ticks-and-hyphens.md`
/// measured it; ``KokoroCoreMLTailClick`` removes exactly that shape and nothing else.
@Suite struct KokoroCoreMLTailClickTests {
    static let rate = 24_000

    /// A 220 Hz tone at `amplitude` for `ms` milliseconds.
    static func tone(ms: Int, amplitude: Float = 0.3) -> [Float] {
        (0 ..< rate * ms / 1000).map { amplitude * sin(Float($0) * 2 * .pi * 220 / Float(rate)) }
    }
    static func silence(ms: Int, floor: Float = 0) -> [Float] {
        (0 ..< rate * ms / 1000).map { floor * (($0 % 2 == 0) ? 1 : -1) }
    }

    @Test func zeroesAnIslandBoundedBySilenceAtTheTail() {
        let speech = Self.tone(ms: 1000)
        let island = Self.tone(ms: 20, amplitude: 0.2)
        let samples = speech + Self.silence(ms: 100) + island + Self.silence(ms: 40)
        let cleaned = KokoroCoreMLTailClick.removed(from: samples)
        #expect(cleaned.count == samples.count)
        #expect(Array(cleaned.prefix(speech.count)) == speech)
        let tail = Array(cleaned.suffix(samples.count - speech.count))
        #expect(tail.allSatisfy { $0 == 0 })
    }

    @Test func treatsTheNoiseFloorAsSilence() {
        let speech = Self.tone(ms: 1000)
        let island = Self.tone(ms: 20, amplitude: 0.2)
        let samples = speech + Self.silence(ms: 100, floor: 5e-5) + island + Self.silence(ms: 40, floor: 5e-5)
        let cleaned = KokoroCoreMLTailClick.removed(from: samples)
        let islandRange = (speech.count + Self.rate / 10) ..< (speech.count + Self.rate / 10 + island.count)
        #expect(cleaned[islandRange].allSatisfy { $0 == 0 })
        #expect(Array(cleaned.prefix(speech.count)) == speech)
    }

    @Test func leavesACallThatEndsInSpeech() {
        let samples = Self.tone(ms: 1000)
        #expect(KokoroCoreMLTailClick.removed(from: samples) == samples)
    }

    @Test func leavesAnAllSilentTail() {
        let samples = Self.tone(ms: 1000) + Self.silence(ms: 200)
        #expect(KokoroCoreMLTailClick.removed(from: samples) == samples)
    }

    /// Eighty milliseconds after a pause is a short word, not the artifact.
    @Test func leavesATailSegmentLongerThanTheArtifact() {
        let samples = Self.tone(ms: 1000) + Self.silence(ms: 50) + Self.tone(ms: 80, amplitude: 0.2) + Self.silence(ms: 40)
        #expect(KokoroCoreMLTailClick.removed(from: samples) == samples)
    }

    /// Only the tail is examined: an island in the middle of the audio is left for the ear.
    @Test func leavesAnIslandFarFromTheEnd() {
        let samples = Self.tone(ms: 500) + Self.silence(ms: 20) + Self.tone(ms: 20, amplitude: 0.2) + Self.silence(ms: 20)
            + Self.tone(ms: 500) + Self.silence(ms: 40)
        #expect(KokoroCoreMLTailClick.removed(from: samples) == samples)
    }

    @Test func leavesAudioShorterThanTheWindow() {
        let samples = Self.tone(ms: 30)
        #expect(KokoroCoreMLTailClick.removed(from: samples) == samples)
        #expect(KokoroCoreMLTailClick.removed(from: []) == [])
    }
}
