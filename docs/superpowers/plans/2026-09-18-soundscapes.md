# Soundscapes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A soft ambient bed (six CC0 recordings and two synthesised noises) that plays under the voice while a book is read, chosen and remembered as a Reader-wide setting, at no cost to make or ship.

**Architecture:** A second `AVAudioPlayerNode` on the engine `AudioPlayer` already owns loops one mono buffer whose seam and loudness are fixed when it is loaded. A `SoundscapeModel` in T2SApp follows the voice's state through the app's ticker — up while the book plays, down when it pauses, an eight-second audition after a tap, a twenty-second linger after the sleep timer — and ramps the node's volume in decibels. The picker is the last part of the Reader's Preferences sheet and, alone, a sheet the sleep timer's row opens.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation (`AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioFile`), Swift Testing, SwiftPM targets `T2SAudio` and `T2SApp`, the Xcode app target under `App/`, `xcodegen`, `ffprobe` (checks only).

**Spec:** `docs/superpowers/specs/2026-09-18-soundscapes-design.md` — read §1, §2 and §4 before any task; the plan argues from it.

## Global Constraints

- Minimum platforms as the package declares: iOS 18, macOS 15 (`Package.swift`); the app's deployment target is iOS 18.0 (`App/project.yml`).
- Swift language mode 6 in every package target: no non-`Sendable` captures across actors, no data races.
- No new dependencies. No paid service, key or account anywhere: the recordings come from a public GitHub repository at a pinned commit.
- Recordings are CC0 only; every one is named in `App/Resources/Soundscapes/soundscapes-manifest.json` and in `docs/licenses.md`.
- The bed never plays on its own: only with the voice, the eight-second audition, or the twenty-second linger (spec §1).
- Volume mapping: `dB = −36 + 30 × volume`; default volume 0.4 (−24 dB); the silence floor is −80 dB and is told to the player as 0 (spec §4.2).
- Fades: 1.5 s in and out; 0.8 s out before a swap; the linger is 20 s (spec §4.2).
- Mono beds at the file's own sample rate (the six recordings are 48 kHz); noise loops are 30 s at 48 kHz (spec §2.5, §4.2).
- Copy: pill titles are exactly Off, Rain, Fire, Ocean, Stream, Forest, Night, Brown noise, Pink noise; the picker's footnote is "Plays softly under the voice while the book is read."
- Design language: `ReaderPalette` colours only inside the Reader's sheets (never `Tokens` there), type through `typeRole`, spacing through `Spacing`; the picker's pill is the Preferences sheet's `modePill` form.
- Repo rules (`CLAUDE.md`): one `xcodebuild` at a time — wait with `while pgrep -x xcodebuild >/dev/null; do sleep 5; done`; never `git add -A`; stage and commit in one call; never leave a simulator booted; `SIMCTL_CHILD_T2S_SILENT=1` on every simulator launch.
- Every commit message ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Work in a worktree (`superpowers:using-git-worktrees`): the shared checkout is being edited by other sessions. Run `swift test` and `scripts/build-app.sh` from the worktree.

---

## File structure

**Created**
- `App/Resources/Soundscapes/soundscapes-manifest.json` — the six recordings: id, file, Freesound id, author, licence, URL; the pinned source commit.
- `scripts/fetch-soundscapes.sh` — downloads the six files and the credits file from the pinned commit.
- `App/Resources/Soundscapes/soundscape-{rain,fire,ocean,stream,forest,night}.m4a` and `soundscapes-credits.json` — fetched, committed.
- `Sources/T2SAudio/Bed/BedPlaying.swift` — the narrow protocol the model drives.
- `Sources/T2SAudio/Bed/LoopSeam.swift` — the crossfade seam.
- `Sources/T2SAudio/Bed/NoiseLoop.swift` — brown and pink noise, and the seeded generator.
- `Sources/T2SAudio/Bed/Loudness.swift` — RMS normalisation with a peak ceiling; dB helpers.
- `Sources/T2SApp/Soundscape/Soundscape.swift` — the catalogue.
- `Sources/T2SApp/Soundscape/SoundscapeLoader.swift` — `SoundscapeLoading` and the bundle loader.
- `Sources/T2SApp/Soundscape/GainRamp.swift` — a line in dB over time.
- `Sources/T2SApp/Soundscape/SoundscapeModel.swift` — the behaviour.
- `App/T2SReader/Preferences/SoundscapePicker.swift` — the pills and the slider.
- `App/T2SReader/Player/SoundscapeSheet.swift` — the picker alone, for the sleep sheet's row.
- Tests: `Tests/T2SAudioTests/BedHelpersTests.swift`, `Tests/T2SAudioTests/AudioPlayerBedTests.swift`, `Tests/T2SAppTests/SoundscapeCatalogTests.swift`, `Tests/T2SAppTests/SoundscapeLoaderTests.swift`, `Tests/T2SAppTests/GainRampTests.swift`, `Tests/T2SAppTests/SoundscapeModelTests.swift`.

**Modified**
- `Sources/T2SAudio/AudioPlayer.swift` — the bed node.
- `Sources/T2SApp/Preferences/ReaderPreferences.swift` — two keys.
- `Sources/T2SApp/Playback/SleepTimer.swift` — `onFire`.
- `App/T2SReader/AppEnvironment.swift` — one `AudioPlayer` by name; `soundscape`.
- `App/T2SReader/System/PlaybackTicker.swift`, `App/T2SReader/Root/RootPager.swift` — the tick.
- `App/T2SReader/Preferences/ReaderPreferencesSheet.swift` — the picker as the last part.
- `App/T2SReader/Player/SleepTimerSheet.swift` — the two-row group.
- `docs/licenses.md`, `README.md`, `docs/HANDOFF.md`, the spec's changelog.

---

### Task 1: The recordings — manifest, fetch script, six files, licence rows

**Files:**
- Create: `App/Resources/Soundscapes/soundscapes-manifest.json`
- Create: `scripts/fetch-soundscapes.sh`
- Create (by running the script): `App/Resources/Soundscapes/soundscape-*.m4a`, `App/Resources/Soundscapes/soundscapes-credits.json`
- Modify: `docs/licenses.md` (the "Vendored into the repository" table)
- Modify: `README.md:52-54` (the scripts line)

**Interfaces:**
- Produces: bundle resources named `soundscape-<id>` with extension `m4a` for ids `rain`, `fire`, `ocean`, `stream`, `forest`, `night` (Task 4's catalogue names exactly these).

- [ ] **Step 1: Write the manifest**

```json
{
  "source": {
    "repository": "https://github.com/abhinandansharma/ambiently",
    "commit": "8b99d668e91957d80b66d419fae5cb0dba2be528",
    "path": "demo/public/sounds",
    "note": "CC0 Freesound field recordings, cut to ~32 s AAC loops (48 kHz stereo) by the ambiently project (MIT). The loop's seam and its loudness are handled in the app when a file is loaded — see docs/superpowers/specs/2026-09-18-soundscapes-design.md §4.2."
  },
  "recordings": [
    { "id": "rain",   "file": "rain.m4a",      "title": "Soft Rain Ambience",          "author": "visionear",       "freesound": 573335, "licence": "cc0", "url": "https://freesound.org/people/visionear/sounds/573335/" },
    { "id": "fire",   "file": "fireplace.m4a", "title": "Fire in the stove",           "author": "mcmikai",         "freesound": 532191, "licence": "cc0", "url": "https://freesound.org/people/mcmikai/sounds/532191/" },
    { "id": "ocean",  "file": "ocean.m4a",     "title": "Waves of Hawaii",             "author": "florianreichelt", "freesound": 450755, "licence": "cc0", "url": "https://freesound.org/people/florianreichelt/sounds/450755/" },
    { "id": "stream", "file": "stream.m4a",    "title": "Stream River Water Up Close", "author": "jackthemurray",   "freesound": 433589, "licence": "cc0", "url": "https://freesound.org/people/jackthemurray/sounds/433589/" },
    { "id": "forest", "file": "forest.m4a",    "title": "Early summer, Czech wood",    "author": "J.Zazvurek",      "freesound": 353311, "licence": "cc0", "url": "https://freesound.org/people/J.Zazvurek/sounds/353311/" },
    { "id": "night",  "file": "night.m4a",     "title": "Crickets, night forest",      "author": "kyles",           "freesound": 453862, "licence": "cc0", "url": "https://freesound.org/people/kyles/sounds/453862/" }
  ]
}
```

- [ ] **Step 2: Write the fetch script** (`chmod +x scripts/fetch-soundscapes.sh`)

```bash
#!/usr/bin/env bash
# Fetches the soundscape loops named in App/Resources/Soundscapes/soundscapes-manifest.json — CC0
# Freesound field recordings, already cut to ~32 s AAC loops by the ambiently project
# (github.com/abhinandansharma/ambiently, MIT; the recordings themselves are CC0) — from that
# repository at the commit the manifest pins, and stages each as
# App/Resources/Soundscapes/soundscape-<id>.m4a, which App/project.yml bundles flat into the app.
# The project's credits file is kept beside the manifest for the record. No key, no account, no
# processing: the loop's seam and its loudness are handled in the app when a file is loaded
# (soundscape design §4.2). A file already staged is kept; pass --force to fetch again.
# Usage: scripts/fetch-soundscapes.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."
manifest=App/Resources/Soundscapes/soundscapes-manifest.json
out=App/Resources/Soundscapes
force=0
[[ "${1:-}" == "--force" ]] && force=1
mkdir -p "$out"
read -r repo commit path < <(python3 -c "
import json
s = json.load(open('$manifest'))['source']
print(s['repository'].replace('https://github.com/', ''), s['commit'], s['path'])")
base="https://raw.githubusercontent.com/$repo/$commit/$path"
fetched=0
kept=0
while read -r id file; do
  dest="$out/soundscape-$id.m4a"
  if [[ -f "$dest" && $force -eq 0 ]]; then kept=$((kept + 1)); continue; fi
  curl -fsSL --retry 3 -o "$dest" "$base/$file"
  echo "fetched $dest ($(du -k "$dest" | cut -f1) KB)"
  fetched=$((fetched + 1))
done < <(python3 -c "
import json
for r in json.load(open('$manifest'))['recordings']:
    print(r['id'], r['file'])")
if [[ ! -f "$out/soundscapes-credits.json" || $force -eq 1 ]]; then
  curl -fsSL --retry 3 -o "$out/soundscapes-credits.json" "$base/CREDITS.json"
fi
echo "soundscapes: $fetched fetched, $kept kept"
```

- [ ] **Step 3: Run it and check what arrived**

Run: `scripts/fetch-soundscapes.sh && for f in App/Resources/Soundscapes/soundscape-*.m4a; do echo "$f $(ffprobe -v error -show_entries stream=codec_name,sample_rate,channels,duration -of csv=p=0 "$f")"; done`
Expected: six lines, each `aac,48000,2,3x.xxx`; total under 2.5 MB (`du -sh App/Resources/Soundscapes`).

- [ ] **Step 4: Record the licences and the script**

In `docs/licenses.md`, add to the "Vendored into the repository" table:

```markdown
| Soundscape loops (6 `.m4a`, `App/Resources/Soundscapes/soundscape-*.m4a`) | fetched 2026-09-18 by `scripts/fetch-soundscapes.sh` from the ambiently repository at `8b99d66`; the Freesound id and author of each is in `App/Resources/Soundscapes/soundscapes-manifest.json` | CC0 1.0 (public domain; no attribution required, recorded anyway) | `App/Resources/Soundscapes/soundscapes-credits.json` |
```

In `README.md`, the scripts line (lines 52–54) gains `fetch-soundscapes.sh` after `fetch-readability.sh`.

- [ ] **Step 5: Commit**

```bash
git add App/Resources/Soundscapes scripts/fetch-soundscapes.sh docs/licenses.md README.md && git commit -F - <<'MSG'
Six CC0 soundscape loops, fetched by a script from a pinned commit

Rain, fire, ocean, stream, forest and night: Freesound field recordings
cut to ~32 s AAC loops by the ambiently project, taken from its
repository at one commit by scripts/fetch-soundscapes.sh, with a
manifest naming each recording's Freesound id and author. No key, no
account, no processing here: the seam and the loudness are the app's
job when a loop is loaded (soundscape design §4.2).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

---

### Task 2: T2SAudio pure helpers — `BedPlaying`, `LoopSeam`, `NoiseLoop`, `Loudness`

**Files:**
- Create: `Sources/T2SAudio/Bed/BedPlaying.swift`, `Sources/T2SAudio/Bed/LoopSeam.swift`, `Sources/T2SAudio/Bed/NoiseLoop.swift`, `Sources/T2SAudio/Bed/Loudness.swift`
- Test: `Tests/T2SAudioTests/BedHelpersTests.swift`

**Interfaces:**
- Consumes: `PCMAudio(sampleRate:samples:)` from T2SCore (`Sources/T2SCore/Render/PCMAudio.swift`), mono `[Float]`.
- Produces: `public protocol BedPlaying { func setBed(_ loop: PCMAudio?); func setBedVolume(_ volume: Float) }`; `LoopSeam.bake(_:crossfadeSeconds:) -> PCMAudio`; `public enum NoiseColour: String { case brown, pink }`; `NoiseLoop.make(_:seconds:sampleRate:seed:) -> PCMAudio`; `Loudness.normalised(_:toRMSDecibels:peakCeilingDecibels:) -> PCMAudio`; `Loudness.linear(_ dB: Float) -> Float`; `Loudness.decibels(_ linear: Float) -> Float`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@Suite struct BedHelpersTests {
    /// Deterministic "noise": a fixed pseudo-random sequence, so a seam test is the same every run.
    private func noise(_ count: Int, rate: Double = 1000) -> PCMAudio {
        var g = SplitMix64(seed: 42)
        return PCMAudio(sampleRate: rate, samples: (0..<count).map { _ in g.nextFloat() * 0.5 })
    }

    private func rms(_ s: ArraySlice<Float>) -> Float {
        sqrt(s.reduce(0) { $0 + $1 * $1 } / Float(max(1, s.count)))
    }

    @Test func theSeamDropsTheTailAndStaysContinuousAtTheWrap() {
        let audio = noise(1000)                                            // 1 s at 1 kHz
        let seamed = LoopSeam.bake(audio, crossfadeSeconds: 0.2)          // 200 samples crossfaded
        #expect(seamed.samples.count == 800)
        #expect(seamed.sampleRate == 1000)
        // The first output sample is the tail's first sample at full gain: what was playing at the
        // wrap carries straight on.
        #expect(abs(seamed.samples[0] - audio.samples[800]) < 1e-5)
        // Past the crossfade the loop is the original again.
        #expect(seamed.samples[300] == audio.samples[300])
    }

    @Test func theSeamKeepsTheLoudnessOfNoise() {
        let seamed = LoopSeam.bake(noise(4000), crossfadeSeconds: 1)      // 1000-sample seam
        let inSeam = rms(seamed.samples[0..<1000])
        let outside = rms(seamed.samples[1000..<3000])
        #expect(abs(Loudness.decibels(inSeam) - Loudness.decibels(outside)) < 1)   // within 1 dB
    }

    @Test func aLoopTooShortToSeamIsLeftAlone() {
        let short = noise(300)
        #expect(LoopSeam.bake(short, crossfadeSeconds: 0.2) == short)    // needs 400 samples
    }

    @Test func noiseIsDeterministicFiniteAndColoured() {
        let brown = NoiseLoop.make(.brown, seconds: 0.5, sampleRate: 8000, seed: 7)
        let again = NoiseLoop.make(.brown, seconds: 0.5, sampleRate: 8000, seed: 7)
        let pink = NoiseLoop.make(.pink, seconds: 0.5, sampleRate: 8000, seed: 7)
        #expect(brown == again)
        #expect(brown.samples.count == 4000 && brown.sampleRate == 8000)
        #expect(brown.samples.allSatisfy { $0.isFinite } && pink.samples.allSatisfy { $0.isFinite })
        #expect(rms(brown.samples[...]) > 0 && rms(pink.samples[...]) > 0)
        // Brown falls off faster with frequency than pink: after the same normalisation, the
        // sample-to-sample differences (a crude high-pass) are smaller for brown.
        let b = Loudness.normalised(brown).samples, p = Loudness.normalised(pink).samples
        let bHigh = rms(zip(b.dropFirst(), b).map { $0 - $1 }[...])
        let pHigh = rms(zip(p.dropFirst(), p).map { $0 - $1 }[...])
        #expect(bHigh < pHigh)
    }

    @Test func normalisationHitsTheTargetOrTheCeiling() {
        let quiet = PCMAudio(sampleRate: 1000, samples: (0..<1000).map { Float(sin(Double($0) * 0.3)) * 0.01 })
        let loud = Loudness.normalised(quiet, toRMSDecibels: -20)
        #expect(abs(Loudness.decibels(rms(loud.samples[...])) - (-20)) < 0.1)
        // One spike in silence: bringing its RMS to −20 dB would put the peak past 0 dB, so the
        // ceiling wins.
        var spiky = [Float](repeating: 0, count: 100); spiky[0] = 1
        let capped = Loudness.normalised(PCMAudio(sampleRate: 1000, samples: spiky), toRMSDecibels: -20, peakCeilingDecibels: -1)
        #expect(abs(capped.samples.max()! - Loudness.linear(-1)) < 1e-4)
        #expect(Loudness.normalised(PCMAudio(sampleRate: 1000, samples: [])).samples.isEmpty)
    }

    @Test func decibelsAndLinearRoundTrip() {
        #expect(abs(Loudness.linear(-20) - 0.1) < 1e-6)
        #expect(abs(Loudness.decibels(0.5) - (-6.0206)) < 1e-3)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter BedHelpersTests 2>&1 | grep -E "error:|passed|failed" | head`
Expected: compile errors — `LoopSeam`, `NoiseLoop`, `Loudness`, `SplitMix64` do not exist.

- [ ] **Step 3: Write the four files**

`Sources/T2SAudio/Bed/BedPlaying.swift`:

```swift
import Foundation
import T2SCore

/// What plays the ambient bed under the voice (soundscape design §4.1). `AudioPlayer` is the real
/// one; the model that drives it sees only this, and tests hand it a recorder. Narrow on purpose:
/// the coordinator's `AudioPlaying` has no business with a bed.
@MainActor
public protocol BedPlaying: AnyObject {
    /// One mono loop, its seam already baked, or nil for none. A new loop starts from its start.
    func setBed(_ loop: PCMAudio?)
    /// 0…1 linear gain, applied at once. The model ramps; the player does not.
    func setBedVolume(_ volume: Float)
}
```

`Sources/T2SAudio/Bed/LoopSeam.swift`:

```swift
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
```

`Sources/T2SAudio/Bed/NoiseLoop.swift`:

```swift
import Foundation
import T2SCore

public enum NoiseColour: String, Hashable, Sendable, CaseIterable {
    case brown, pink
}

/// Noise made in code, as a loop the bed can play like a recording (soundscape design §3, option
/// 3): thirty seconds of it is indistinguishable from endless, and it weighs nothing in the bundle.
/// Not normalised here — `Loudness` does that for every bed alike.
public enum NoiseLoop {
    public static func make(_ colour: NoiseColour, seconds: TimeInterval = 30, sampleRate: Double = 48_000,
                            seed: UInt64 = 0x5EED) -> PCMAudio {
        let n = Int((seconds * sampleRate).rounded())
        var generator = SplitMix64(seed: seed)
        var out = [Float](repeating: 0, count: n)
        switch colour {
        case .brown:
            // A leaky integrator over white noise: −6 dB per octave, the deep, even wash.
            var level: Float = 0
            for i in 0..<n {
                level = 0.995 * level + 0.02 * generator.nextFloat()
                out[i] = level
            }
        case .pink:
            // Kellet's economy filter: three one-pole stages summed, −3 dB per octave.
            var b0: Float = 0, b1: Float = 0, b2: Float = 0
            for i in 0..<n {
                let white = generator.nextFloat()
                b0 = 0.99765 * b0 + white * 0.0990460
                b1 = 0.96300 * b1 + white * 0.2965164
                b2 = 0.57000 * b2 + white * 1.0526913
                out[i] = (b0 + b1 + b2 + white * 0.1848) * 0.05
            }
        }
        return PCMAudio(sampleRate: sampleRate, samples: out)
    }
}

/// A tiny deterministic generator: the same seed gives the same noise on every device, every run.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in −1…1.
    mutating func nextFloat() -> Float {
        Float(Double(next() >> 11) / Double(1 << 52)) - 1
    }
}
```

`Sources/T2SAudio/Bed/Loudness.swift`:

```swift
import Foundation
import T2SCore

/// Every bed at the same loudness (soundscape design §2.4): scaled to a target RMS under a peak
/// ceiling, so the one Volume slider means the same for Rain as for Fire — or for noise.
public enum Loudness {
    public static func normalised(_ audio: PCMAudio, toRMSDecibels target: Float = -20,
                                  peakCeilingDecibels ceiling: Float = -1) -> PCMAudio {
        let samples = audio.samples
        guard !samples.isEmpty else { return audio }
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        let peak = samples.reduce(0) { max($0, abs($1)) }
        guard rms > 0, peak > 0 else { return audio }
        var gain = linear(target) / rms
        let ceilingLinear = linear(ceiling)
        if peak * gain > ceilingLinear { gain = ceilingLinear / peak }        // the ceiling wins
        return PCMAudio(sampleRate: audio.sampleRate, samples: samples.map { $0 * gain })
    }

    public static func linear(_ decibels: Float) -> Float { powf(10, decibels / 20) }

    public static func decibels(_ linear: Float) -> Float { 20 * log10f(max(linear, 1e-9)) }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter BedHelpersTests 2>&1 | grep -E "error:|Suite|Test run"`
Expected: `Suite BedHelpersTests passed`, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SAudio/Bed Tests/T2SAudioTests/BedHelpersTests.swift && git commit -F - <<'MSG'
The bed's arithmetic: a baked seam, two noises, one loudness

Pure and tested before any node exists. LoopSeam crossfades a loop's
tail into its head and drops the tail, so any cut loops cleanly;
NoiseLoop makes brown and pink noise from a seeded generator, thirty
seconds of it as good as endless; Loudness brings every bed to the same
RMS under a peak ceiling. BedPlaying is the two-call protocol the model
will drive (soundscape design §4.1).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

---

### Task 3: The bed node in `AudioPlayer`

**Files:**
- Modify: `Sources/T2SAudio/AudioPlayer.swift` (properties near line 12–36; `init` line 72–79; `makeGraph()` line 86–115; `rebuildAfterMediaServicesReset()` line 240–256; `renderOffline(seconds:)` line 259–270)
- Test: `Tests/T2SAudioTests/AudioPlayerBedTests.swift`

**Interfaces:**
- Consumes: `BedPlaying` (Task 2).
- Produces: `AudioPlayer: BedPlaying`; internal `private(set) var lastRenderPeak: Float` for manual-rendering tests.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
import T2SCore
@testable import T2SAudio

@MainActor
@Suite struct AudioPlayerBedTests {
    /// One second of a 220 Hz tone at 48 kHz, which is what a decoded loop looks like.
    private func tone() -> PCMAudio {
        PCMAudio(sampleRate: 48_000, samples: (0..<48_000).map { Float(sin(Double($0) * 2 * .pi * 220 / 48_000)) * 0.5 })
    }

    @Test func theBedIsHeardAtVolumeAndSilentAtZero() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.setBed(tone())
        p.setBedVolume(0)
        try p.renderOffline(seconds: 0.2)
        #expect(p.lastRenderPeak == 0)
        p.setBedVolume(0.5)
        try p.renderOffline(seconds: 0.2)
        #expect(p.lastRenderPeak > 0.1)
        p.setBed(nil)
        try p.renderOffline(seconds: 0.2)
        #expect(p.lastRenderPeak == 0)
    }

    @Test func theBedLeavesTheVoiceClockAlone() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.setBed(tone())
        p.setBedVolume(0.5)
        p.enqueue(.silence(seconds: 2), tag: 1)
        p.play()
        try p.renderOffline(seconds: 0.5)
        #expect(abs(p.consumedSeconds - 0.5) < 0.05)
        #expect(p.queuedSeconds > 1.4)
    }

    @Test func theBedSurvivesAMediaServicesRebuild() throws {
        let p = try AudioPlayer(manualRendering: true)
        p.setBed(tone())
        p.setBedVolume(0.5)
        p.rebuildAfterMediaServicesReset()
        try p.renderOffline(seconds: 0.2)
        #expect(p.lastRenderPeak > 0.1)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter AudioPlayerBedTests 2>&1 | grep -E "error:" | head -5`
Expected: `setBed`, `setBedVolume`, `lastRenderPeak` not found.

- [ ] **Step 3: Add the bed to `AudioPlayer`**

Conformance: `public final class AudioPlayer: AudioPlaying, BedPlaying {`.

New stored properties, after `private var configurationObserver: NSObjectProtocol?`:

```swift
    /// The ambient bed (soundscape design §4.1): a second player on the same engine, straight into
    /// the mixer so the time-pitch unit never touches it, looping one mono buffer. Like `player`,
    /// a fresh node every `makeGraph()`; unlike it, its buffer is kept, so a media-services rebuild
    /// puts the same bed back.
    private var bedPlayer: AVAudioPlayerNode
    private var bedBuffer: AVAudioPCMBuffer?
    private var bedVolume: Float = 0
    /// Manual rendering only: the loudest sample of the last `renderOffline(seconds:)`, so a test
    /// can tell silence from sound without reading the mixer.
    private(set) var lastRenderPeak: Float = 0
    /// The bed's connection before any loop has said its rate: the six recordings' 48 kHz.
    private static let defaultBedFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
```

In `init`, before `try makeGraph()`: `bedPlayer = AVAudioPlayerNode()`.

In `makeGraph()`, after `freshEngine.connect(freshTimePitch, to: freshEngine.mainMixerNode, format: format)`:

```swift
        let freshBed = AVAudioPlayerNode()
        freshEngine.attach(freshBed)
        freshEngine.connect(freshBed, to: freshEngine.mainMixerNode, format: bedBuffer?.format ?? Self.defaultBedFormat)
```

and after `timePitch = freshTimePitch`:

```swift
        bedPlayer = freshBed
        freshBed.volume = bedVolume
        if let bedBuffer {
            freshBed.scheduleBuffer(bedBuffer, at: nil, options: .loops, completionHandler: nil)
        }
```

New methods, after `rebuildAfterMediaServicesReset()`:

```swift
    // MARK: - The bed

    public func setBed(_ loop: PCMAudio?) {
        bedPlayer.stop()
        bedBuffer = nil
        guard let loop, !loop.samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: loop.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(loop.samples.count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(loop.samples.count)
        loop.samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: loop.samples.count)
        }
        // The node was connected at the default rate; a loop at another rate reconnects it, which
        // the engine allows while running.
        if bedPlayer.outputFormat(forBus: 0).sampleRate != format.sampleRate {
            engine.disconnectNodeOutput(bedPlayer)
            engine.connect(bedPlayer, to: engine.mainMixerNode, format: format)
        }
        bedBuffer = buffer
        bedPlayer.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        startBedIfWanted()
    }

    public func setBedVolume(_ volume: Float) {
        bedVolume = max(0, min(1, volume))
        bedPlayer.volume = bedVolume
        if bedVolume > 0 {
            startBedIfWanted()
        } else if bedPlayer.isPlaying {
            bedPlayer.pause()                                                  // a silent bed costs nothing
        }
    }

    /// The bed sounds only when there is a loop and a volume: then the engine must be up — the
    /// audition before the first play is the one time it may not be — and the node playing.
    private func startBedIfWanted() {
        guard bedBuffer != nil, bedVolume > 0 else { return }
        restartEngineIfNeeded()
        if !bedPlayer.isPlaying { bedPlayer.play() }
    }
```

In `rebuildAfterMediaServicesReset()`, after `if manual { manualBaseline = engine.manualRenderingSampleTime }` inside the `do`: `startBedIfWanted()`.

In `renderOffline(seconds:)`: set `lastRenderPeak = 0` before the loop, and after `let status = try engine.renderOffline(n, to: out)` add:

```swift
            if let data = out.floatChannelData, out.frameLength > 0 {
                var peak: Float = 0
                for i in 0..<Int(out.frameLength) { peak = max(peak, abs(data[0][i])) }
                lastRenderPeak = max(lastRenderPeak, peak)
            }
```

- [ ] **Step 4: Run the bed tests and the player's own**

Run: `swift test --filter "AudioPlayerBedTests|AudioPlayerTests|PlaybackCoordinatorTests" 2>&1 | grep -E "error:|Suite|Test run"`
Expected: all three suites pass. If `theBedIsHeardAtVolumeAndSilentAtZero` renders silence at volume 0.5, the manual engine is refusing the 48 kHz connection into its 24 kHz mixer: change the test's `tone()` to `PCMAudio.defaultSampleRate` and, in `setBed`, resample is *not* the fix — note it in the commit; the live engine converts.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SAudio/AudioPlayer.swift Tests/T2SAudioTests/AudioPlayerBedTests.swift && git commit -F - <<'MSG'
AudioPlayer carries the bed: a second node, straight into the mixer

One mono loop scheduled with .loops on a player node that bypasses the
time-pitch unit, its volume set at once and ramped by whoever calls;
the buffer is kept across a media-services rebuild so the same bed
comes back. Manual rendering records its peak so a test can hear it.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

---

### Task 4: The catalogue, the loader, two preferences, `SleepTimer.onFire`

**Files:**
- Create: `Sources/T2SApp/Soundscape/Soundscape.swift`, `Sources/T2SApp/Soundscape/SoundscapeLoader.swift`
- Modify: `Sources/T2SApp/Preferences/ReaderPreferences.swift` (`Key` enum ~line 75–90; properties after `autoplayNext`; `init`; `reset()`), `Sources/T2SApp/Playback/SleepTimer.swift` (`fire()`)
- Test: `Tests/T2SAppTests/SoundscapeCatalogTests.swift`, `Tests/T2SAppTests/SoundscapeLoaderTests.swift`, `Tests/T2SAppTests/ReaderPreferencesTests.swift`, `Tests/T2SAppTests/SleepTimerTests.swift`

**Interfaces:**
- Consumes: `NoiseColour`, `NoiseLoop`, `LoopSeam`, `Loudness` (Task 2).
- Produces: `public struct Soundscape: Identifiable, Hashable, Sendable { id, title, glyph, source }`, `Soundscape.all`, `Soundscape.named(_ id: String?) -> Soundscape?`; `public protocol SoundscapeLoading: Sendable { func load(_ soundscape: Soundscape) async -> PCMAudio? }`; `BundleSoundscapeLoader(bundle:)`; `ReaderPreferences.soundscapeID: String?`, `ReaderPreferences.soundscapeVolume: Double`; `SleepTimer.onFire: (() -> Void)?`.

- [ ] **Step 1: Write the failing tests**

`Tests/T2SAppTests/SoundscapeCatalogTests.swift`:

```swift
import Foundation
import Testing
@testable import T2SApp

@Suite struct SoundscapeCatalogTests {
    @Test func idsAreUniqueAndRecordingsAreNamedForTheirFiles() {
        let ids = Soundscape.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids == ["rain", "fire", "ocean", "stream", "forest", "night", "brown", "pink"])
        for s in Soundscape.all {
            if case .recording(let resource) = s.source { #expect(resource == "soundscape-\(s.id)") }
        }
        #expect(Soundscape.named("fire")?.title == "Fire")
        #expect(Soundscape.named(nil) == nil && Soundscape.named("bagpipes") == nil)
    }

    /// The manifest the fetch script reads names exactly the recordings the catalogue plays.
    @Test func theManifestAndTheCatalogueAgree() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Resources/Soundscapes/soundscapes-manifest.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let recordings = try #require(json?["recordings"] as? [[String: Any]])
        let manifestIDs = Set(recordings.compactMap { $0["id"] as? String })
        let catalogueIDs = Set(Soundscape.all.compactMap { s -> String? in
            if case .recording = s.source { return s.id } else { return nil }
        })
        #expect(manifestIDs == catalogueIDs)
        #expect(recordings.allSatisfy { ($0["licence"] as? String) == "cc0" })
    }
}
```

`Tests/T2SAppTests/SoundscapeLoaderTests.swift`:

```swift
import AVFoundation
import Foundation
import Testing
import T2SAudio
import T2SCore
@testable import T2SApp

@Suite struct SoundscapeLoaderTests {
    @Test func aNoiseLoadsSeamedAndAtTheCommonLoudness() async {
        let loader = BundleSoundscapeLoader(bundle: .main)
        let loop = await loader.load(Soundscape.named("brown")!)
        let samples = try! #require(loop).samples
        // 30 s at 48 kHz less the 2 s seam.
        #expect(samples.count == 28 * 48_000)
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        #expect(abs(Loudness.decibels(rms) - (-20)) < 0.5)
    }

    @Test func aStereoFileDecodesToMonoAtItsOwnRate() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bed-\(UUID().uuidString).caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = 4410
        for i in 0..<4410 {
            buffer.floatChannelData![0][i] = 0.4                              // left
            buffer.floatChannelData![1][i] = 0.2                              // right
        }
        try file.write(from: buffer)
        let mono = try #require(BundleSoundscapeLoader.decodeMono(url))
        #expect(mono.sampleRate == 44_100 && mono.samples.count == 4410)
        #expect(abs(mono.samples[100] - 0.3) < 1e-4)                          // the mean of the two
    }

    @Test func aMissingRecordingIsNil() async {
        let loader = BundleSoundscapeLoader(bundle: .main)                   // the package's bundle has no .m4a
        let loop = await loader.load(Soundscape.named("rain")!)
        #expect(loop == nil)
    }
}
```

Add to `Tests/T2SAppTests/ReaderPreferencesTests.swift`, before `@Test func scopeFlipsToTheOther()`:

```swift
    /// The Reader-wide soundscape (soundscape design §4.2): off until chosen, 0.4 on the slider.
    @Test func theSoundscapeIsRememberedAndTheVolumeClamps() {
        let defaults = fresh()
        let first = ReaderPreferences(defaults: defaults)
        #expect(first.soundscapeID == nil && first.soundscapeVolume == 0.4)
        first.soundscapeID = "rain"
        first.soundscapeVolume = 0.7
        let again = ReaderPreferences(defaults: defaults)
        #expect(again.soundscapeID == "rain" && again.soundscapeVolume == 0.7)
        again.soundscapeVolume = 3
        #expect(again.soundscapeVolume == 1)
        again.soundscapeID = nil
        #expect(ReaderPreferences(defaults: defaults).soundscapeID == nil)
        again.reset()
        #expect(ReaderPreferences(defaults: defaults).soundscapeVolume == 0.4)
    }
```

Add to `Tests/T2SAppTests/SleepTimerTests.swift`, after `cancelAndDocumentEnd`:

```swift
    /// The soundscape lingers after the timer, so the timer says when it fires — once, and not
    /// on a cancel.
    @Test func firingIsAnnouncedOnceAndCancelIsNot() async throws {
        let fixtures = try AppFixtures()
        let id = try await fixtures.importFake()
        let player = try makePlayer(fixtures)
        await player.load(try #require(try await fixtures.store.summary(id: id)), play: true)
        let clock = Clock()
        let timer = SleepTimer(player: player) { clock.now }
        var fired = 0
        timer.onFire = { fired += 1 }
        timer.start(.minutes(1))
        timer.cancel()
        #expect(fired == 0)
        timer.start(.minutes(1))
        clock.advance(61)
        timer.tick()
        timer.tick()
        #expect(fired == 1 && !player.isPlaying)
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter "SoundscapeCatalogTests|SoundscapeLoaderTests|ReaderPreferencesTests|SleepTimerTests" 2>&1 | grep -E "error:" | head -5`
Expected: compile errors for `Soundscape`, `BundleSoundscapeLoader`, `soundscapeID`, `onFire`.

- [ ] **Step 3: Write the catalogue**

`Sources/T2SApp/Soundscape/Soundscape.swift`:

```swift
import Foundation
import T2SAudio

/// One bed the reader can choose (soundscape design §4.2). "Off" is `nil` everywhere, not a case.
public struct Soundscape: Identifiable, Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        /// A bundled `.m4a` named `soundscape-<id>`, fetched by `scripts/fetch-soundscapes.sh`.
        case recording(resource: String)
        /// Made in code when chosen; nothing in the bundle.
        case noise(NoiseColour)
    }

    public let id: String
    public let title: String
    /// The SF Symbol the pill wears.
    public let glyph: String
    public let source: Source

    /// The catalogue, in the order the pills are drawn.
    public static let all: [Soundscape] = [
        Soundscape(id: "rain", title: "Rain", glyph: "cloud.rain", source: .recording(resource: "soundscape-rain")),
        Soundscape(id: "fire", title: "Fire", glyph: "flame", source: .recording(resource: "soundscape-fire")),
        Soundscape(id: "ocean", title: "Ocean", glyph: "water.waves", source: .recording(resource: "soundscape-ocean")),
        Soundscape(id: "stream", title: "Stream", glyph: "drop", source: .recording(resource: "soundscape-stream")),
        Soundscape(id: "forest", title: "Forest", glyph: "tree", source: .recording(resource: "soundscape-forest")),
        Soundscape(id: "night", title: "Night", glyph: "moon.stars", source: .recording(resource: "soundscape-night")),
        Soundscape(id: "brown", title: "Brown noise", glyph: "waveform", source: .noise(.brown)),
        Soundscape(id: "pink", title: "Pink noise", glyph: "waveform.path", source: .noise(.pink)),
    ]

    /// The bed with this id, or nil for an unknown id — and for nil, which is Off.
    public static func named(_ id: String?) -> Soundscape? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
```

- [ ] **Step 4: Write the loader**

`Sources/T2SApp/Soundscape/SoundscapeLoader.swift`:

```swift
import AVFoundation
import Foundation
import T2SAudio
import T2SCore

/// Turns a `Soundscape` into the mono loop the bed plays: a recording decoded from the bundle, or
/// a noise made on the spot — either way seamed and brought to the common loudness (soundscape
/// design §4.2). A protocol, so the model's tests hand it a loop of ten samples.
public protocol SoundscapeLoading: Sendable {
    func load(_ soundscape: Soundscape) async -> PCMAudio?
}

/// `Bundle` is not marked `Sendable` but is documented thread-safe, and this reads one URL from it.
public final class BundleSoundscapeLoader: SoundscapeLoading, @unchecked Sendable {
    private let bundle: Bundle

    public init(bundle: Bundle) { self.bundle = bundle }

    public func load(_ soundscape: Soundscape) async -> PCMAudio? {
        let raw: PCMAudio?
        switch soundscape.source {
        case .noise(let colour):
            raw = NoiseLoop.make(colour)
        case .recording(let resource):
            guard let url = bundle.url(forResource: resource, withExtension: "m4a") else { return nil }
            raw = await Task.detached(priority: .utility) { Self.decodeMono(url) }.value
        }
        guard let raw else { return nil }
        return Loudness.normalised(LoopSeam.bake(raw))
    }

    /// The file's samples mixed down to one channel, at the file's own rate.
    static func decodeMono(_ url: URL) -> PCMAudio? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let data = buffer.floatChannelData else { return nil }
        let channels = Int(file.processingFormat.channelCount)
        let n = Int(buffer.frameLength)
        guard channels > 0, n > 0 else { return nil }
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<channels {
            let channel = data[c]
            for i in 0..<n { mono[i] += channel[i] }
        }
        if channels > 1 {
            let k = 1 / Float(channels)
            for i in 0..<n { mono[i] *= k }
        }
        return PCMAudio(sampleRate: file.processingFormat.sampleRate, samples: mono)
    }
}
```

- [ ] **Step 5: The two preferences and `onFire`**

In `ReaderPreferences.swift`, `Key` gains:

```swift
        static let soundscape = "soundscape.id"
        static let soundscapeVolume = "soundscape.volume"
```

After `sleepsAtChapterEnd`:

```swift
    /// The Reader-wide soundscape (soundscape design §4.2): the bed's id, nil for Off.
    public var soundscapeID: String? {
        didSet { defaults.set(soundscapeID, forKey: Key.soundscape) }
    }

    /// The bed's volume, 0…1; 0.4 is −24 dB under the voice.
    public var soundscapeVolume: Double {
        didSet {
            let clamped = min(1, max(0, soundscapeVolume))
            if soundscapeVolume != clamped { soundscapeVolume = clamped }
            defaults.set(soundscapeVolume, forKey: Key.soundscapeVolume)
        }
    }
```

In `init`, after the `sleepsAtChapterEnd` line:

```swift
        soundscapeID = defaults.string(forKey: Key.soundscape)
        soundscapeVolume = min(1, max(0, defaults.object(forKey: Key.soundscapeVolume) as? Double ?? 0.4))
```

In `reset()`, after `sleepsAtChapterEnd = false`:

```swift
        soundscapeID = nil
        soundscapeVolume = 0.4
```

In `SleepTimer.swift`, a property after `sleepChapterTitle`:

```swift
    /// Called once when the timer stops the voice — after the pause, never on a cancel — so the
    /// soundscape can take its twenty seconds to go (soundscape design §4.2).
    public var onFire: (() -> Void)?
```

and `fire()` becomes:

```swift
    private func fire() {
        if player.isPlaying {
            player.coordinator.pause()
        }
        cancel()
        onFire?()
    }
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter "SoundscapeCatalogTests|SoundscapeLoaderTests|ReaderPreferencesTests|SleepTimerTests" 2>&1 | grep -E "error:|Suite|Test run"`
Expected: four suites pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SApp/Soundscape/Soundscape.swift Sources/T2SApp/Soundscape/SoundscapeLoader.swift Sources/T2SApp/Preferences/ReaderPreferences.swift Sources/T2SApp/Playback/SleepTimer.swift Tests/T2SAppTests/SoundscapeCatalogTests.swift Tests/T2SAppTests/SoundscapeLoaderTests.swift Tests/T2SAppTests/ReaderPreferencesTests.swift Tests/T2SAppTests/SleepTimerTests.swift && git commit -F - <<'MSG'
Eight soundscapes by name, a loader that seams and levels them, and two preferences

The catalogue is code — six recordings named for their bundled files and
two noises made when chosen — and the manifest the fetch script reads
is checked against it. BundleSoundscapeLoader decodes a file to mono
off the main actor, then bakes the seam and brings it to the common
loudness. ReaderPreferences remembers the choice and the volume; the
sleep timer says when it fires.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

---

### Task 5: `GainRamp` and `SoundscapeModel`

**Files:**
- Create: `Sources/T2SApp/Soundscape/GainRamp.swift`, `Sources/T2SApp/Soundscape/SoundscapeModel.swift`
- Test: `Tests/T2SAppTests/GainRampTests.swift`, `Tests/T2SAppTests/SoundscapeModelTests.swift`

**Interfaces:**
- Consumes: `BedPlaying`, `Loudness.linear` (Task 2); `Soundscape`, `SoundscapeLoading`, `ReaderPreferences.soundscapeID/soundscapeVolume` (Task 4).
- Produces: `public struct GainRamp { init(from:to:start:duration:); value(at:) -> Float; isDone(at:) -> Bool }`; `@MainActor @Observable public final class SoundscapeModel { init(bed:loader:preferences:isVoicePlaying:clock:); choice: Soundscape?; volume: Double; isRamping: Bool; choose(_:) async; audition(); linger(); tick(); static func decibels(_ volume: Double) -> Float; static let silence: Float }`.

- [ ] **Step 1: Write the failing tests**

`Tests/T2SAppTests/GainRampTests.swift`:

```swift
import Foundation
import Testing
@testable import T2SApp

@Suite struct GainRampTests {
    @Test func aRampIsAStraightLineInDecibelsThatEndsOnItsTarget() {
        let start = Date(timeIntervalSince1970: 0)
        let ramp = GainRamp(from: -80, to: -24, start: start, duration: 2)
        #expect(ramp.value(at: start) == -80)
        #expect(abs(ramp.value(at: start.addingTimeInterval(1)) - (-52)) < 1e-4)
        #expect(ramp.value(at: start.addingTimeInterval(2)) == -24)
        #expect(ramp.value(at: start.addingTimeInterval(9)) == -24)             // never past
        #expect(!ramp.isDone(at: start.addingTimeInterval(1.9)) && ramp.isDone(at: start.addingTimeInterval(2)))
        #expect(GainRamp(from: -80, to: -24, start: start, duration: 0).value(at: start) == -24)
    }
}
```

`Tests/T2SAppTests/SoundscapeModelTests.swift`:

```swift
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
        run(rig, seconds: 1.5)
        #expect(abs((rig.bed.volumes.last ?? 0) - heard) < 1e-4)
        rig.voice.playing = false
        run(rig, seconds: 1.5)
        #expect(rig.bed.volumes.last == 0)
    }

    @Test func aFadeInRisesWithoutAStepBack() async {
        let rig = make()
        await rig.model.choose(Soundscape.named("ocean"))
        run(rig, seconds: 10)
        rig.voice.playing = true
        let before = rig.bed.volumes.count
        run(rig, seconds: 1.5)
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
        run(rig, seconds: 1.5)
        #expect(abs((rig.bed.volumes.last ?? 0) - heard) < 1e-4)
    }

    @Test func changingTheChoiceFadesOutSwapsAndFadesIn() async {
        let rig = make()
        await rig.model.choose(Soundscape.named("rain"))
        rig.voice.playing = true
        run(rig, seconds: 10)
        await rig.model.choose(Soundscape.named("stream"))
        #expect(rig.bed.loops.count == 1)                                      // not yet: it is still up
        run(rig, seconds: 0.85)
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
        run(rig, seconds: 0.85)
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
        let next = SoundscapeModel(bed: FakeBed(), loader: FakeLoader(), preferences: ReaderPreferences(defaults: rig.defaults),
                                   isVoicePlaying: { false }, clock: { rig.clock.now })
        #expect(next.choice?.id == "pink" && next.volume == 0.7)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter "GainRampTests|SoundscapeModelTests" 2>&1 | grep -E "error:" | head -5`
Expected: `GainRamp` and `SoundscapeModel` not found.

- [ ] **Step 3: Write `GainRamp`**

```swift
import Foundation

/// A straight line in decibels from one level to another over a duration (soundscape design
/// §4.2): a fade that is linear in dB sounds even from start to end, where one linear in gain
/// would be all over in its first tenth.
public struct GainRamp: Equatable, Sendable {
    public var from: Float
    public var to: Float
    public var start: Date
    public var duration: TimeInterval

    public init(from: Float, to: Float, start: Date, duration: TimeInterval) {
        self.from = from
        self.to = to
        self.start = start
        self.duration = duration
    }

    public func value(at now: Date) -> Float {
        guard duration > 0 else { return to }
        let t = min(1, max(0, now.timeIntervalSince(start) / duration))
        return from + (to - from) * Float(t)
    }

    public func isDone(at now: Date) -> Bool {
        now.timeIntervalSince(start) >= duration
    }
}
```

- [ ] **Step 4: Write `SoundscapeModel`**

```swift
import Foundation
import Observation
import T2SAudio
import T2SCore

/// The soundscape's behaviour (soundscape design §4.2): what the bed holds, and how loud it is
/// right now. The bed follows the voice — up while the book plays, down when it pauses — with two
/// exceptions and no third: the audition window after a tap on the picker, and the linger after
/// the sleep timer. Driven by the app's ticker; the clock is injected so tests do not wait.
///
/// Levels are decibels throughout and only become a linear gain at the player's door, so every
/// fade is a straight line the ear hears as even. A swap waits for silence: the old bed is told
/// to fall, the new loop goes in at the floor, and it rises if it is wanted.
@MainActor
@Observable
public final class SoundscapeModel {
    /// The floor: below anything audible, and told to the player as zero.
    public static let silence: Float = -80
    static let auditionSeconds: TimeInterval = 8
    static let lingerSeconds: TimeInterval = 20
    static let fadeSeconds: TimeInterval = 1.5
    static let swapFadeSeconds: TimeInterval = 0.8

    public private(set) var choice: Soundscape?
    /// The slider, 0…1, written through to the preference (which clamps it).
    public var volume: Double {
        didSet {
            preferences.soundscapeVolume = volume
            volume = preferences.soundscapeVolume
        }
    }
    /// True while a fade is in flight, for the ticker to tick faster.
    public private(set) var isRamping = false

    private let bed: any BedPlaying
    private let loader: any SoundscapeLoading
    private let preferences: ReaderPreferences
    private let isVoicePlaying: @MainActor () -> Bool
    private let clock: @Sendable () -> Date
    /// What the bed holds now; nil when it holds nothing.
    private var loaded: Soundscape?
    /// A choice waiting for the bed to fall silent before it goes in; a nil soundscape is Off.
    private var pending: (soundscape: Soundscape?, loop: PCMAudio?)?
    private var auditionUntil: Date?
    private var lingerUntil: Date?
    private var ramp: GainRamp?
    /// The level the bed is at, in dB; `silence` when off.
    private var level: Float = SoundscapeModel.silence
    private var generation = 0

    public init(bed: any BedPlaying, loader: any SoundscapeLoading, preferences: ReaderPreferences,
                isVoicePlaying: @escaping @MainActor () -> Bool,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.bed = bed
        self.loader = loader
        self.preferences = preferences
        self.isVoicePlaying = isVoicePlaying
        self.clock = clock
        choice = Soundscape.named(preferences.soundscapeID)
        volume = preferences.soundscapeVolume
        // The remembered choice is loaded on the first tick that wants it, through `choose`'s
        // path, so a launch does not decode a file nobody is listening to yet.
        if let choice { Task { await self.choose(choice, auditioning: false) } }
    }

    /// The bed the reader wants. Persists at once and auditions; the audio follows — the current
    /// bed fades out, the new loop goes in when it is silent, and it rises if it is wanted.
    public func choose(_ soundscape: Soundscape?) async {
        await choose(soundscape, auditioning: true)
    }

    private func choose(_ soundscape: Soundscape?, auditioning: Bool) async {
        preferences.soundscapeID = soundscape?.id
        choice = soundscape
        if auditioning { audition() }
        guard soundscape != loaded || pending != nil else { return }
        generation += 1
        let mine = generation
        let loop: PCMAudio? = if let soundscape { await loader.load(soundscape) } else { nil }
        guard mine == generation else { return }                              // a later choice won
        pending = (soundscape, loop)
        tick()
    }

    /// Eight seconds of the bed whatever the voice is doing: a choice heard where it is made.
    public func audition() {
        auditionUntil = clock().addingTimeInterval(Self.auditionSeconds)
    }

    /// The sleep timer has stopped the voice: take twenty seconds to go, not one and a half.
    public func linger() {
        guard loaded != nil else { return }
        lingerUntil = clock().addingTimeInterval(Self.lingerSeconds)
    }

    public func tick() {
        let now = clock()
        if let pending {
            if level <= Self.silence, ramp == nil {
                bed.setBed(pending.loop)
                loaded = pending.loop == nil ? nil : pending.soundscape
                self.pending = nil
            } else {
                aim(at: Self.silence, over: Self.swapFadeSeconds, now: now)
                advance(now)
                return
            }
        }
        let auditioning = auditionUntil.map { now < $0 } ?? false
        let wanted = loaded != nil && (isVoicePlaying() || auditioning) ? Self.decibels(volume) : Self.silence
        if wanted > Self.silence {
            lingerUntil = nil                                                  // a play cancels the linger
            if level > Self.silence, ramp == nil {
                set(wanted)                                                    // a slider move: at once
            } else {
                aim(at: wanted, over: Self.fadeSeconds, now: now)
            }
        } else if let lingerUntil, now < lingerUntil {
            aim(at: Self.silence, over: lingerUntil.timeIntervalSince(now), now: now)
        } else {
            aim(at: Self.silence, over: Self.fadeSeconds, now: now)
        }
        advance(now)
    }

    /// The slider's position as a level: −36 dB at the bottom, −6 dB at the top, −24 dB at 0.4.
    public static func decibels(_ volume: Double) -> Float {
        -36 + 30 * Float(min(1, max(0, volume)))
    }

    /// Starts a ramp from the current level to `target`, unless one is already headed there.
    private func aim(at target: Float, over seconds: TimeInterval, now: Date) {
        if let ramp, ramp.to == target { return }
        if level == target { ramp = nil; return }
        ramp = GainRamp(from: level, to: target, start: now, duration: seconds)
    }

    /// Moves the level along the ramp and tells the bed.
    private func advance(_ now: Date) {
        guard let ramp else { isRamping = false; return }
        level = ramp.value(at: now)
        if ramp.isDone(at: now) {
            level = ramp.to
            self.ramp = nil
        }
        isRamping = self.ramp != nil
        bed.setBedVolume(level <= Self.silence ? 0 : Loudness.linear(level))
    }

    private func set(_ target: Float) {
        guard level != target else { return }
        level = target
        bed.setBedVolume(Loudness.linear(level))
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter "GainRampTests|SoundscapeModelTests" 2>&1 | grep -E "error:|Suite|Test run|failed"`
Expected: both suites pass, 9 tests. If `theChoiceAndVolumeComeBackOnTheNextLaunch` fails because the second model's `init` task loads on a `FakeBed` it was not given time for: the assertion reads `choice` and `volume` only, which are set synchronously — check the failure message before touching the model.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SApp/Soundscape/GainRamp.swift Sources/T2SApp/Soundscape/SoundscapeModel.swift Tests/T2SAppTests/GainRampTests.swift Tests/T2SAppTests/SoundscapeModelTests.swift && git commit -F - <<'MSG'
SoundscapeModel: the bed follows the voice, auditions on a tap, lingers after the timer

Levels are decibels until the player's door, so every fade is a straight
line the ear hears as even; a swap waits for the floor; a play cancels
the linger; the slider moves a playing bed at once. Driven by tick()
with an injected clock, so the tests walk twenty seconds in a moment.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

---

### Task 6: Wiring — one `AudioPlayer` by name, the model in the environment, the tick

**Files:**
- Modify: `App/T2SReader/AppEnvironment.swift` (stored properties near line 53; `init` signature line 95–99 and its body; `static func live()` line 196–260, the coordinator at ~245)
- Modify: `App/T2SReader/System/PlaybackTicker.swift`
- Modify: `App/T2SReader/Root/RootPager.swift:156`

**Interfaces:**
- Consumes: `SoundscapeModel` (Task 5), `BundleSoundscapeLoader` (Task 4), `AudioPlayer: BedPlaying` (Task 3).
- Produces: `AppEnvironment.soundscape: SoundscapeModel`; `AppEnvironment.init(..., coordinator:, bed: any BedPlaying, ...)`.

- [ ] **Step 1: The environment**

Stored property, after `let sleepTimer: SleepTimer`:

```swift
    /// The Reader-wide soundscape (soundscape design §4.2): one for the app, like the sleep timer.
    let soundscape: SoundscapeModel
```

`init` gains a parameter after `coordinator: PlaybackCoordinator,`: `bed: any BedPlaying,`.

In `init`'s body, after `sleepTimer = SleepTimer(player: player)`:

```swift
        soundscape = SoundscapeModel(bed: bed, loader: BundleSoundscapeLoader(bundle: .main), preferences: preferences,
                                     isVoicePlaying: { [player] in player.isPlaying })
```

If the compiler objects that `self` is used before all stored properties are initialised, move the line to the end of `init` (after `voicePreview = VoicePreviewModel(...)`, which is there for the same reason) — every stored property but `soundscape` must be set first, and `soundscape` is then the last.

At the very end of `init`, after `voicePreview`:

```swift
        sleepTimer.onFire = { [soundscape] in soundscape.linger() }
```

In `static func live()`, replace `player: try AudioPlayer(),` in the `PlaybackCoordinator(...)` call with `player: audioPlayer,` and put, on the line before that call:

```swift
        // One player by name: the coordinator drives its voice, the soundscape its bed.
        let audioPlayer = try AudioPlayer()
```

and pass `bed: audioPlayer,` after `coordinator: coordinator,` in the `return AppEnvironment(...)` call.

- [ ] **Step 2: The ticker**

`PlaybackTicker.swift`: `PlaybackTicking` gains `let soundscape: SoundscapeModel` after `sleepTimer`; in the loop, after `sleepTimer.tick()`: `soundscape.tick()`; the sleep becomes

```swift
                // 20 Hz while a fade is in flight: the bed's ramp is stepped by this loop, and at
                // 1 Hz a fade behind a paused book would be three steps.
                try? await Task.sleep(for: .milliseconds(soundscape.isRamping ? 50 : playing ? 100 : 1000))
```

The extension's signature gains `soundscape: SoundscapeModel` after `sleepTimer:` and passes it through; `RootPager.swift:156` becomes

```swift
        .playbackTicking(env.player, sleepTimer: env.sleepTimer, soundscape: env.soundscape, continuation: env.continuation, nowPlaying: env.nowPlaying)
```

- [ ] **Step 3: Build the app**

Run: `while pgrep -x xcodebuild >/dev/null; do sleep 5; done; scripts/build-app.sh 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`, no errors. (The package tests do not cover the app target; the build is the check.)

- [ ] **Step 4: Commit**

```bash
git add App/T2SReader/AppEnvironment.swift App/T2SReader/System/PlaybackTicker.swift App/T2SReader/Root/RootPager.swift && git commit -F - <<'MSG'
The app carries one AudioPlayer by name, and the ticker drives the soundscape

The coordinator drives its voice and SoundscapeModel its bed; the sleep
timer tells the model when it fires; the ticker ticks the model and
runs at 20 Hz while a fade is in flight.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

---

### Task 7: `SoundscapePicker`, the last part of the Reader's Preferences sheet

**Files:**
- Create: `App/T2SReader/Preferences/SoundscapePicker.swift`
- Modify: `App/T2SReader/Preferences/ReaderPreferencesSheet.swift` (after the switches' `VStack`, line ~76, inside `if showsReaderControls`)

**Interfaces:**
- Consumes: `env.soundscape` (Task 6), `Soundscape.all` (Task 4), `FlowRow` (`App/T2SReader/Design/Primitives.swift:747`), `ReaderPalette` via `\.readerPalette`.
- Produces: `struct SoundscapePicker: View { var showsTitle: Bool = true }`.

- [ ] **Step 1: Write the picker**

```swift
import SwiftUI
import T2SApp

/// The Reader's soundscape (soundscape design §4.3): a wrapping row of pills, Off first, and the
/// bed's volume under them. One view with two hosts — the last part of the Preferences sheet,
/// where it is how the book *sounds* after how it looks and what it does, and alone on
/// `SoundscapeSheet` for the sleep sheet's row. A tap is the choice; every tap and every slider
/// move auditions the bed for a few seconds if the book is paused, so the choice is heard where
/// it is made. The pills are the sheet's own `modePill` form: the paper's colours, so they belong
/// to the sheet they sit on rather than arriving in the app's greys.
struct SoundscapePicker: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.readerPalette) private var palette
    /// The "Soundscape" label over the pills; off on the sheet that carries the word as its title.
    var showsTitle: Bool = true

    var body: some View {
        @Bindable var soundscape = env.soundscape
        let isOff = soundscape.choice == nil
        VStack(alignment: .leading, spacing: 12) {
            if showsTitle {
                Text("Soundscape").typeRole(.meta).foregroundStyle(palette.ink2)
            }
            FlowRow(spacing: Spacing.grid, lineSpacing: Spacing.grid) {
                pill("Off", glyph: "speaker.slash", isOn: isOff) {
                    Task { await soundscape.choose(nil) }
                }
                ForEach(Soundscape.all) { option in
                    pill(option.title, glyph: option.glyph, isOn: soundscape.choice == option) {
                        Task { await soundscape.choose(option) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Volume").typeRole(.meta).foregroundStyle(palette.ink2)
                Slider(value: $soundscape.volume, in: 0...1) { _ in soundscape.audition() }
                    .tint(palette.ink)
                    .accessibilityLabel("Volume")
            }
            .padding(.top, 8)
            .opacity(isOff ? 0.3 : 1)
            .disabled(isOff)
            .animation(.easeInOut(duration: 0.2), value: isOff)
            Text("Plays softly under the voice while the book is read.")
                .typeRole(.fine)
                .foregroundStyle(palette.ink2)
        }
    }

    private func pill(_ label: String, glyph: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: glyph).font(.system(size: 12, weight: .semibold))
                Text(label).typeRole(.pill)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isOn ? palette.page : palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isOn ? palette.ink : palette.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
```

- [ ] **Step 2: Put it in the sheet**

In `ReaderPreferencesSheet.swift`, directly after the switches' `VStack(alignment: .leading, spacing: 20) { ... }` (the one holding "Hold to change chapter" and "Bookmark positions"), still inside `if showsReaderControls`:

```swift
                    // How the book sounds, after how it looks and what it does (soundscape design
                    // §2.6): the third part, and the one a reader would look for here.
                    SoundscapePicker()
```

- [ ] **Step 3: Build and photograph**

Build: `while pgrep -x xcodebuild >/dev/null; do sleep 5; done; scripts/build-app.sh 2>&1 | grep -E "error:|BUILD"` → `** BUILD SUCCEEDED **`.

Photograph (the recipe in the memory `photographing-render-mode` and the sleep sheet's session): a private simulator `xcrun simctl create "T2S Sound" "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-26-3`; boot; `xcrun simctl spawn $U defaults write com.t2s.reader onboarding.completed -bool true`; install `.build/DerivedData-App/Build/Products/Debug-iphonesimulator/T2SReader.app`; launch once; copy `childrens-literature.epub` (from `.build/DerivedData-App/SourcePackages/checkouts/swift-toolkit/Tests/Publications/Publications/`) into the app container's `Documents/Inbox/` and `simctl openurl` it; then a one-line probe in `ReaderPage.swift` after the `.sheet(isPresented: $showAppearance)` line:

```swift
        .task { if ProcessInfo.processInfo.environment["T2S_PREFS"] != nil { try? await Task.sleep(for: .seconds(1)); showAppearance = true } } // PROBE-SOUND
```

and, for the photo only, the sheet's `.presentationDetents([.medium, .large])` changed to `[.large]` with `// PROBE-SOUND` on the line. Launch with `SIMCTL_CHILD_T2S_SILENT=1 SIMCTL_CHILD_T2S_OPEN=reader SIMCTL_CHILD_T2S_BOOK=Children SIMCTL_CHILD_T2S_PREFS=1`, `xcrun simctl io $U screenshot /tmp/sound-prefs-light.png`; `xcrun simctl ui $U appearance dark` before a second launch for the dark shot. Look at both: nine pills in three or four lines inside the margins, Off selected as an ink pill, the slider dimmed. Then `sed -i '' '/PROBE-SOUND/d' App/T2SReader/Reader/ReaderPage.swift`, restore the detents line, `grep -rn PROBE- App Sources Tests` must be empty, shut down and delete the simulator.

- [ ] **Step 4: Commit**

```bash
git add App/T2SReader/Preferences/SoundscapePicker.swift App/T2SReader/Preferences/ReaderPreferencesSheet.swift && git commit -F - <<'MSG'
The Preferences sheet's third part: how the book sounds

Nine pills in the sheet's own form — Off first, then the six recordings
and the two noises — with the bed's volume under them, dimmed while Off,
and one line saying what it is for. A tap chooses and auditions; the
setting is the Reader's, not the sleep timer's (owner, 2026-09-18).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

---

### Task 8: `SoundscapeSheet`, and the sleep sheet's row to it

**Files:**
- Create: `App/T2SReader/Player/SoundscapeSheet.swift`
- Modify: `App/T2SReader/Player/SleepTimerSheet.swift` (`ChapterEndRow` and its use in `body`; a new `@State`)

**Interfaces:**
- Consumes: `SoundscapePicker(showsTitle:)` (Task 7), `env.soundscape.choice` (Task 6).
- Produces: `struct SoundscapeSheet: View { var wearsPaper: Bool }`.

- [ ] **Step 1: Write the sheet**

```swift
import SwiftUI
import T2SApp

/// The soundscape picker alone on a sheet, for the sleep sheet's row (soundscape design §4.3): the
/// setting lives in the Reader's Preferences; this is a second door to the same room, not a
/// second room. Wears the book's paper as the sleep sheet does.
struct SoundscapeSheet: View {
    @Environment(AppEnvironment.self) private var env
    var wearsPaper = true

    private var palette: ReaderPalette { wearsPaper ? ReaderPalette(env.preferences.readerPaper) : .app }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Image(systemName: "cloud.rain")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(palette.ink3)
                    Text("Soundscape").typeRole(.sectionHeader).foregroundStyle(palette.ink)
                }
                .padding(.top, Spacing.margin)
                .padding(.bottom, Spacing.row)
                SoundscapePicker(showsTitle: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.margin)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .presentationBackground(palette.sheet)
        .appTheme()
        .environment(\.readerPalette, palette)
        .presentationDetents([.fraction(0.5), .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}
```

- [ ] **Step 2: The sleep sheet's two-row group**

In `SleepTimerSheet`, add `@State private var showSoundscape = false` under `dismiss`. Replace the line `ChapterEndRow(isOn: $preferences.sleepsAtChapterEnd)` in `body` with:

```swift
                        // One slab, two rows: the switch, and the way to the soundscape (soundscape
                        // design §4.3) — a second door to the Reader's own setting, here because
                        // a bed is most wanted at bedtime.
                        VStack(spacing: 0) {
                            ChapterEndRow(isOn: $preferences.sleepsAtChapterEnd)
                            Rectangle().fill(palette.ink3).frame(height: 1).opacity(0.7)
                                .padding(.horizontal, 16)
                            SoundscapeRow(title: env.soundscape.choice?.title ?? "Off") { showSoundscape = true }
                        }
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
```

Add, after `.presentationCornerRadius(Spacing.sheetCorner)` in `body`:

```swift
        .sheet(isPresented: $showSoundscape) { SoundscapeSheet(wearsPaper: wearsPaper) }
```

Change the detent line to `.presentationDetents([.fraction(0.7)])` and its comment's last sentence to: "the fraction the content actually asks for, with the air the key needs — raised again for the soundscape row (2026-09-18)."

In `ChapterEndRow`, remove the `.background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))` line (the group paints the slab now) and change its doc comment's first line to `/// The other answer, as a switch: the whole row is the switch's label, so a tap on the words`.

Add after `ChapterEndRow`:

```swift
/// The second row of the slab: the soundscape's name, and the way to change it.
private struct SoundscapeRow: View {
    @Environment(\.readerPalette) private var palette
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("Soundscape").typeRole(.settingsRow).foregroundStyle(palette.ink)
                Spacer(minLength: 12)
                Text(title).typeRole(.meta).foregroundStyle(palette.ink2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.ink3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Soundscape, \(title)")
    }
}
```

- [ ] **Step 3: Build and photograph**

Build as in Task 7. Photograph the sleep sheet with the probe from the sleep-timer session on `ReaderPage.swift` after the `.sheet(isPresented: $showSleepTimer)` line:

```swift
        .task { if ProcessInfo.processInfo.environment["T2S_SLEEP"] != nil { try? await Task.sleep(for: .seconds(1)); showSleepTimer = true } } // PROBE-SOUND
```

launched with `SIMCTL_CHILD_T2S_SLEEP=1` and the rest as Task 7; and the soundscape sheet by a second probe on the sleep sheet's root, `.task { if ProcessInfo.processInfo.environment["T2S_SOUND"] != nil { try? await Task.sleep(for: .seconds(2)); showSoundscape = true } } // PROBE-SOUND`, launched with both variables. Check: the slab holds the switch and the row with a hairline between, the key still has air above it, the soundscape sheet shows the glyph, the title, the pills and the slider. Remove every `PROBE-SOUND` line, `grep -rn PROBE- App Sources Tests` empty, shut down and delete the simulator.

- [ ] **Step 4: Run every suite once**

Run: `swift test 2>&1 | grep -E "error:|Test run|failed"`
Expected: `Test run with N tests in M suites passed`.

- [ ] **Step 5: Commit**

```bash
git add App/T2SReader/Player/SoundscapeSheet.swift App/T2SReader/Player/SleepTimerSheet.swift && git commit -F - <<'MSG'
The sleep sheet's slab has two rows, and the second opens the soundscape

The reference put a soundscape under its timer, and bedtime is where a
bed is most wanted; so the switch's slab gains a row naming the choice,
which opens the same picker on its own sheet — a second door, not a
second room (soundscape design §4.3).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

---

### Task 9: Docs — the hand-off, the spec's changelog

**Files:**
- Modify: `docs/HANDOFF.md` (a section at the top, before "## The sleep timer is a ruler and a switch (2026-09-18)")
- Modify: `docs/superpowers/specs/2026-09-18-soundscapes-design.md` (a "Changelog" section at the end)

- [ ] **Step 1: The hand-off**

Insert before the sleep-timer section:

```markdown
## Soundscapes under the narration (2026-09-18)

Design: `docs/superpowers/specs/2026-09-18-soundscapes-design.md`; plan:
`docs/superpowers/plans/2026-09-18-soundscapes.md`. A soft ambient bed under the voice — six CC0
recordings (Rain, Fire, Ocean, Stream, Forest, Night; `scripts/fetch-soundscapes.sh` fetches them
from the ambiently repository at a pinned commit, no key) and two noises made in code (Brown, Pink)
— as a Reader-wide setting: the last part of the Reader's Preferences sheet (`SoundscapePicker`),
with a row under the sleep sheet's switch opening the same picker alone (`SoundscapeSheet`).

`AudioPlayer` carries the bed as a second node straight into the mixer (`BedPlaying`), looping one
mono buffer whose seam (`LoopSeam`) and loudness (`Loudness`) are baked at load
(`BundleSoundscapeLoader`). `SoundscapeModel` follows the voice through the ticker: up while the
book plays, down when it pauses, an eight-second audition after a tap, a twenty-second linger after
the sleep timer (`SleepTimer.onFire`). Levels are decibels until the player's door. Off by default;
choice and volume in `ReaderPreferences` (`soundscapeID`, `soundscapeVolume`).

**Not done, by design (spec §8):** mixing beds, per-book choices, a bed that outlives the book,
stereo, an overflow item, a copy in Settings' Appearance sheet.
```

- [ ] **Step 2: The spec's changelog**

Append to the spec:

```markdown
## Changelog

- 2026-09-18: written; the owner's review moved the setting from the overflow into the Reader's
  Preferences sheet (§2.6) and made the audition a window (§2.7). The recordings are 48 kHz; the
  bed's default connection is 48 kHz and a loop's own rate wins (§4.1).
- 2026-09-18: implemented per `docs/superpowers/plans/2026-09-18-soundscapes.md`.
```

- [ ] **Step 3: Commit**

```bash
git add docs/HANDOFF.md docs/superpowers/specs/2026-09-18-soundscapes-design.md && git commit -F - <<'MSG'
HANDOFF and the spec's changelog: soundscapes are in

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
```

---

## Self-review

**Spec coverage.** §1 behaviour → Tasks 5 (follows the voice, audition, linger), 7 (the setting), 8 (the sleep sheet's row); §2.1 free/CC0 → Task 1; §2.4 seam and loudness → Task 2 and the loader in Task 4; §2.5 mono → Task 4's `decodeMono`; §2.6–2.7 placement and audition window → Tasks 5 and 7; §4.1 `BedPlaying` and the node → Tasks 2 and 3; §4.2 catalogue, loader, model, ramp, preferences, `onFire` → Tasks 4 and 5; §4.3 wiring and views → Tasks 6, 7, 8; §4.4 pipeline → Task 1; §5 edges: interruption and document end follow the voice's state (Task 5), media-services rebuild (Task 3), missing resource (Task 4's loader returns nil and the model swaps in nothing), VoiceOver (Tasks 7, 8); §6 tests → every task; §7 order → this plan's order.

**Type consistency.** `BedPlaying.setBed(_:)`/`setBedVolume(_:)` (Task 2) are what `AudioPlayer` adopts (Task 3), `FakeBed` records (Task 5) and `AppEnvironment` passes (Task 6). `SoundscapeLoading.load(_:) async -> PCMAudio?` (Task 4) is what `FakeLoader` implements (Task 5). `SoundscapeModel.choose(_:) async`, `audition()`, `linger()`, `tick()`, `isRamping`, `choice`, `volume` (Task 5) are what the picker (Task 7), the ticker (Task 6) and the sleep timer's `onFire` (Task 6) call. `Soundscape.all`/`named(_:)`/`title`/`glyph` (Task 4) are what the picker and the sleep sheet's row read.
