import Foundation
import T2SCore

/// A loop's seam, baked in (soundscape design §2.4): the last `crossfadeSeconds` of the audio fade
/// out under the first `crossfadeSeconds` fading in, and the result is the loop without its tail.
/// So the moment it wraps, the sound that was playing has already become the sound that starts,
/// and any cut loops cleanly. Equal-power, which keeps the loudness of noise-like material — rain,
/// surf, a fire — level through the seam; a pure tone would swell there, but no bed is one.
public enum LoopSeam {
    public static func bake(_ audio: PCMAudio, crossfadeSeconds: TimeInterval = 2) -> PCMAudio {
        let n = audio.samples.count
        let x = Int((crossfadeSeconds * audio.sampleRate).rounded())
        guard x > 0, n >= 2 * x else { return audio }                       // too short to seam
        let tail = n - x
        var out = Array(audio.samples[0..<tail])
        for i in 0..<x {
            let t = Double(i) / Double(x)
            let rising = Float(sin(t * .pi / 2))
            let falling = Float(cos(t * .pi / 2))
            out[i] = audio.samples[i] * rising + audio.samples[tail + i] * falling
        }
        return PCMAudio(sampleRate: audio.sampleRate, samples: out)
    }
}
