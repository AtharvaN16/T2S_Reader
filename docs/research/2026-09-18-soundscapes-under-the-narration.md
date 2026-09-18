# Soundscapes under the narration — feasibility (2026-09-18)

**Question (owner, 2026-09-18, from Tide's focus sheet):** can a soft ambient bed — rain, ocean, a
fire — play under the voice while a book is read, and how hard is it?

**Answer: easy to play, moderate to do well. The code is a day or two; the content is the work.**

## Playing it

Three ways, one recommended.

1. **A second player node on the engine we have** — *recommended.* `AudioPlayer.makeGraph()`
   already builds `AVAudioEngine → AVAudioPlayerNode → AVAudioUnitTimePitch → mainMixer`. A
   second `AVAudioPlayerNode` attached to the same engine and connected *straight* to
   `mainMixerNode` (not through the time-pitch unit, so a speed change never touches it) plays a
   PCM buffer with `scheduleBuffer(_:at:nil, options: .loops)`, which is gapless by construction.
   Its `volume` is the bed's gain. It follows `PlaybackCoordinator.state` — fade in on play, out on
   pause — and needs nothing from the coordinator's timing. Two things come free: `T2S_SILENT`
   already zeroes the mixer, so the bed is silent in every simulator photograph; and the
   media-services-reset path already rebuilds the graph, so the bed node is rebuilt with it.
   About 150 lines in `T2SAudio` plus a manual-rendering test that the bed's samples appear in
   the mix and stop when paused.
2. **A separate `AVAudioPlayer` with `numberOfLoops = -1`** (the onboarding's `SoloClipPlayer`
   pattern). Fewer lines, but a second clock, *not* muted by `T2S_SILENT`, and AAC and MP3 loops
   carry a small seam at the join (encoder priming frames); avoiding it means CAF/ALAC or WAV,
   which costs bundle size. Not recommended.
3. **Procedural** — an `AVAudioSourceNode` making filtered noise: rain is pink noise through a
   low-pass with slow modulation, ocean is brown noise under an 8–12 s amplitude swell, a fire is
   brown noise with random crackles. No assets, no seam, no licence, endless. Passable for rain,
   surf and the noise family; poor for anything with recognisable texture (a café, birds). A
   sound option to *add* to recordings for "brown / pink noise", not a substitute for them.

**Mixing.** No ducking: the bed sits at a fixed low gain — about −20 dB, 0.1 of full scale — and
the voice sits on top of it. Fade the bed over ~1.5 s at play and pause. When the sleep timer
fires, let the bed run on for twenty or thirty seconds and fade to nothing, so the room does not
fall silent the instant the voice does.

**Battery, background, the island.** An extra node in a running engine is negligible. The session
is already `.playback`/`.spokenAudio`, so the bed keeps playing in the background and under the
lock screen with the voice; Now Playing and the Live Activity are unaffected. One side-benefit:
the app's session does not `mixWithOthers`, so a reader who wants rain under a book cannot supply
their own today — a built-in bed answers that without changing the session.

## The content, which is the real cost

- **Sourcing.** CC0 field recordings: Freesound (through Openverse for the licence filter); the
  `ambiently` project on GitHub lists 24 CC0 Freesound recordings already cut to 30 s loops
  and encoded as AAC; Selekt Audio and Signature Sounds publish CC0 ambient packs with a licence
  certificate per file. Whatever is chosen goes in `docs/licenses.md` next to the fonts.
- **Size.** A 60 s stereo AAC loop at 96–128 kbps is 0.7–1 MB; mono halves it and a bed does not
  need stereo. Five beds ≈ 3–4 MB in the bundle — the onboarding's ten clips are 1.1 MB. Loop
  length matters more than bitrate: a 30 s rain loop with one distinctive drip is heard repeating
  within a minute; 60–90 s is safe. Decoded into one PCM buffer, 90 s mono at 24 kHz is 8.6 MB of
  RAM, which is fine.
- **The seam.** Cut on zero crossings and bake a short crossfade into the file, or crossfade two
  player nodes (more code, no editing). Baking it in is the right first version.

## Where it lives in the app

Not on the sleep sheet alone: a bed is for reading, not only for falling asleep. The natural home
is the Reader's overflow (or the Appearance sheet, as "how the book sounds" next to "how it
looks"): a picker of five or six names — Off first — with a volume slider, remembered in
`ReaderPreferences`, off by default. The sleep sheet can then show the current bed in a quiet row
under the ruler, the way Tide's shows "Ocean · Soundscape", and tapping it opens the same picker.

## What iOS already offers

Settings → Accessibility → Audio & Visual → **Background Sounds** plays rain, ocean, stream,
fire and three noises *under any app's audio*, with its own volume and a "Use When Media Is
Playing" switch (iOS 15; iOS 26 added more sounds). It is exactly this feature, for free, and it
mixes with our narration today. It is also five levels deep in Settings and system-wide, so it is
a stopgap to point people at from the picker's footnote, not the feature.

## Estimate

| Piece | Effort |
|---|---|
| Bed node in `AudioPlayer`, fades, coordinator hook, manual-rendering test | 1 day |
| Picker sheet, preference, row on the sleep sheet, photographs | 1 day |
| Five recordings sourced, trimmed to seamless loops, licensed and documented | 1–2 days |
| Procedural noise only (no recordings) | 1 day total |

Three to four days for a good first version with recordings; one for a noise-only version.
