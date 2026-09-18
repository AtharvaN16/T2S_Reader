# Soundscapes under the narration — design (2026-09-18)

A soft ambient bed under the voice — rain, a fire, the sea — chosen in the Reader, remembered, and
played only while the book is read. Free in every sense the owner asked for: CC0 recordings and
synthesised noise, no service, no purchase, no gate.

Feasibility: `docs/research/2026-09-18-soundscapes-under-the-narration.md`. The reference is Tide's
focus sheet ("Ocean · Soundscape" under the timer); the layout is borrowed, the paint is ours.

## 1. What it does

- **A Reader-wide setting** (owner, 2026-09-18: "not just restricted to the sleep timer"). The
  Reader's Preferences sheet gains a third part after how the book looks and what it does: how it
  sounds — "Soundscape", a wrapping row of nine pills (Off, Rain, Fire, Ocean, Stream, Forest,
  Night, Brown noise, Pink noise) and a Volume slider under them. Tapping a pill chooses it and
  plays it at once for a few seconds if the book is paused, so the choice is heard where it is made.
- The sleep sheet shows the choice under its switch — "Soundscape · Rain" with a chevron — and
  opens the same picker on its own sheet.
- **The bed follows the voice.** It fades in when the book plays and out when it pauses, whether
  the pause is the listener's, an interruption's, or the end of the document. It never plays on
  its own, except while the Soundscape sheet is open (the audition) and for twenty seconds after
  the sleep timer stops the voice (the linger), so the room does not fall silent the instant the
  reading does. The audition is the third exception: eight seconds after a tap on a pill or a
  move of the slider while the book is paused, extended by each further tap, then a fade.
- The choice and the volume are remembered across books and launches. Off by default. One
  setting for the whole Reader, not per book.
- Speed does not change it; the bed does not pass through the time-pitch unit.
- The simulator's `T2S_SILENT=1` silences it, as it silences the voice.

## 2. Decisions the owner should read

Each was made so the work could proceed; any of them can be flipped in review.

1. **"Free" is read as: costs nothing to make or ship, and every reader gets it.** The recordings
   are CC0 (public domain) field recordings from Freesound, taken from the `ambiently` project's
   already-cut 30 s loops; two noises are synthesised in code and weigh nothing. No paid SDK, no
   download service, and the feature is not part of any tier. If it is to be a Pro feature later,
   the gate goes on the sheet's tiles and nothing below the sheet changes.
2. **The bed plays only with the voice** (plus the audition and the linger). A reader is not a
   sound machine: a bed that ran on after the book stopped would keep the audio engine "playing"
   as far as iOS is concerned — background CPU, the lock-screen card, battery — for nothing being
   read.
3. **Six recordings + two noises, one at a time.** Rain, Fire, Ocean, Stream, Forest, Night are
   the ones that suit a book in the evening; Café, Thunder and Wind are in the same source if the
   owner wants a swap. No mixing of layers: one bed under one voice.
4. **Thirty-second loops, seamed in code, not edited by hand.** The seam is a two-second
   equal-power crossfade baked into the decoded buffer when it is loaded, so any cut loops cleanly
   and no audio editing is ever needed. All beds are normalised to the same loudness at load, so
   the one Volume slider means the same for Rain as for Fire.
5. **Mono.** Halves memory and bundle size; at −24 dB under a voice, stereo width is not heard.
6. **It is a setting of the Reader's Preferences sheet** — the owner's call (2026-09-18), replacing
   a first draft that hung it off the overflow and the sleep sheet. The sheet already divides into
   how the book looks and what it does; the soundscape is how it sounds, and it takes the place a
   reader would look for it. The sleep sheet keeps a row for it because the reference put one
   there and it is where a bed is most wanted; that row opens the same picker, not a second one.
   Settings' "Appearance" copy of the sheet (`showsReaderControls: false`) does not show it, by
   the sheet's own rule: nothing about a book being read appears where no book is.
7. **The audition is a window, not a mode.** A bed that started the moment the Preferences sheet
   opened would play rain at a reader who came to change the type size. Eight seconds after a
   tap, then out, is enough to hear a choice and never a surprise.

## 3. Approaches considered

**A. A second `AVAudioPlayerNode` on the engine we have — chosen.** `AudioPlayer.makeGraph()` gains
a `bed` node attached to the same `AVAudioEngine`, connected straight to `mainMixerNode` (so the
time-pitch unit never touches it), fed one mono buffer scheduled with `.loops`. Gain is the node's
`volume`, ramped by the model at 20 Hz. Everything else comes free: the engine's start, the
silenced mixer, the media-services rebuild. About a day of audio code, no audio-thread code at all.

**B. An `AVAudioSourceNode` with a lock-free reader — rejected for now.** Sample-accurate fades and
a live seam, but a render block on the audio thread with atomics for the buffer swap and the gain.
Better fades than A by a margin nobody will hear at −24 dB; twice the code and a class of bugs the
app does not have today.

**C. A separate `AVAudioPlayer` with `numberOfLoops = -1` — rejected.** A second clock, not muted by
`T2S_SILENT`, and a seam at the loop point with AAC. The onboarding uses one for a clip that plays
once; a bed is not that.

## 4. Architecture

### 4.1 T2SAudio — the bed in the player

The coordinator's `AudioPlaying` does not change: the coordinator has no business with a bed. A
second, narrow protocol is what the model talks to, and `AudioPlayer` adopts both:

```swift
/// What plays the ambient bed under the voice (soundscape design, 2026-09-18).
@MainActor public protocol BedPlaying: AnyObject {
    /// One mono loop, its seam already baked, or nil for none. A new loop starts from its start.
    func setBed(_ loop: PCMAudio?)
    /// 0…1 linear gain, applied at once. The model ramps; the player does not.
    func setBedVolume(_ volume: Float)
}
```

`AudioPlayer`:
- `makeGraph()` attaches `bedPlayer: AVAudioPlayerNode` and connects it to the mixer in the bed's
  own format (mono, the loop's sample rate — 44.1 kHz for the recordings and the noises). If a bed
  buffer is retained, it is rescheduled here, which is what makes the media-services rebuild carry
  the bed across.
- `setBed(_:)` converts the `PCMAudio` to an `AVAudioPCMBuffer`, stops the node, schedules the
  buffer with `.loops`, and plays the node if the volume is above zero. Nil stops the node and
  drops the buffer.
- `setBedVolume(_:)` sets `bedPlayer.volume`. Above zero: starts the engine if it is not running
  (`restartEngineIfNeeded()`, the audition before the first play) and plays the node if it is
  paused. At zero: pauses the node, so a silent bed costs nothing.
- Manual rendering (tests) works unchanged; the mixer converts the bed's rate to the engine's.
  `renderOffline(seconds:)` records the peak of what it rendered in an internal `lastRenderPeak`
  so a test can tell silence from sound.

Pure helpers in `T2SAudio`, each tested on its own:
- `LoopSeam.bake(_ audio: PCMAudio, crossfadeSeconds: 2) -> PCMAudio` — equal-power crossfade of
  the last X seconds into the first X, returning N − X samples. A constant signal comes out
  constant across the seam; the length is exact.
- `NoiseLoop.make(_ colour: NoiseColour, seconds: 30, sampleRate: 44_100, seed: UInt64) -> PCMAudio`
  — brown (leaky integrator over white) and pink (Kellet's filter). Deterministic for a seed;
  a 30 s loop of noise is indistinguishable from an endless one.
- `Loudness.normalised(_ audio: PCMAudio, toRMS dB: Float = -20) -> PCMAudio` — the equal-loudness
  step every bed goes through, recording or noise, with a peak ceiling of −1 dBFS.

### 4.2 T2SApp — the catalogue, the model, the preference

`Soundscape` (`Identifiable`, `Sendable`): `id`, `title`, `glyph` (an SF Symbol), and a `source`:
`.recording(resource: String)` or `.noise(NoiseColour)`. `Soundscape.all` is the catalogue, in
tile order; "Off" is `nil` everywhere rather than a tenth case.

| id | title | glyph | source |
| --- | --- | --- | --- |
| rain | Rain | cloud.rain | soundscape-rain.m4a |
| fire | Fire | flame | soundscape-fire.m4a |
| ocean | Ocean | water.waves | soundscape-ocean.m4a |
| stream | Stream | drop | soundscape-stream.m4a |
| forest | Forest | tree | soundscape-forest.m4a |
| night | Night | moon.stars | soundscape-night.m4a |
| brown | Brown noise | waveform | noise, brown |
| pink | Pink noise | waveform.path | noise, pink |

`SoundscapeLoader` (`Sendable`, injected so tests hand the model a ten-sample loop): decodes an
`.m4a` from the bundle with `AVAudioFile`, mixes to mono, then `LoopSeam.bake` and
`Loudness.normalised`; a noise is `NoiseLoop.make` then normalised. Runs off the main actor; a 30 s
loop decodes in well under a second and lives in about 5 MB.

`SoundscapeModel` (`@MainActor`, `@Observable`) owns the behaviour:
- `choice: Soundscape?` and `volume: Double` (0…1), both written through to `ReaderPreferences`.
- `audition()`, called by the picker on every tap and slider move: sets `auditionUntil` eight
  seconds from now (the injected clock). The bed is wanted while `now < auditionUntil`, whatever
  the voice is doing.
- `linger()`, called by the sleep timer when it stops the voice: the bed fades over 20 s instead of
  1.5 s. A play before it ends cancels it.
- `tick()` from `PlaybackTicker`, next to `sleepTimer.tick()`: the wanted gain is `volume`'s gain
  while the voice plays or the audition window is open, else zero; the ramp towards it runs at 20 Hz in
  its own short task for as long as a ramp is in flight (the ticker is 1 Hz while paused, too
  slow for a fade), driven by an injected clock so tests do not wait.
- Changing the choice: fade out over 0.8 s, `setBed(newLoop)`, fade in over 1.5 s. Choosing Off
  fades out then `setBed(nil)`.
- Gain from the slider: `dB = −36 + 30 × volume`, `gain = 10^(dB/20)`. The default 0.4 is −24 dB;
  the top is −6 dB, loud enough to be a choice and never a competitor. The ramp is in dB, not in
  linear gain, so a fade sounds even from start to end.

`GainRamp` (pure, tested): start value, target, duration, start time → `value(at:)`, `isDone(at:)`.

`ReaderPreferences`: `soundscapeID: String?` (`soundscape.id`, nil = off) and `soundscapeVolume:
Double` (`soundscape.volume`, default 0.4, clamped to 0…1), both reset by `reset()`.

`SleepTimer`: `public var onFire: (() -> Void)?`, called from `fire()` after the pause.

### 4.3 The app — wiring and the two sheets

`AppEnvironment` creates the `AudioPlayer` once, by name, and hands it to the coordinator as an
`AudioPlaying` and to `SoundscapeModel` as a `BedPlaying` (today it is made inline in the
coordinator's initialiser). It sets
`sleepTimer.onFire` to the model's `linger()`, and `PlaybackTicker` calls `soundscape.tick()`.

**`SoundscapePicker`** (`App/T2SReader/Preferences/`), one view with two hosts. "Soundscape" in
the meta role, `ink2`, as the sheet's other parts are labelled; under it a wrapping row of
capsule pills in the paper's own colours — the `modePill` the sheet already draws for light and
dark, each with its glyph and name, the chosen one `ink` on the page, Off first — laid out by the
app's `FlowRow` layout; under the pills, "Volume" in the meta role over a `Slider` tinted `ink`
(the text-size slider's form), dimmed to 0.3 and disabled while Off; under that, one fine line:
"Plays softly under the voice while the book is read." A tap is the choice; there is no key.
Every tap and slider move calls `soundscape.audition()`.

**`ReaderPreferencesSheet`**: the picker is the sheet's last part, after the two switches, only
when `showsReaderControls` is on. The sheet already scrolls and pulls to large.

**`SoundscapeSheet`** (`App/T2SReader/Player/`): the picker alone on a Reader sheet wearing the
paper, for the sleep sheet's row — a glyph (`cloud.rain`, `ink3`) over the title "Soundscape" in
the section-header role, the picker under it, a detent as the content asks.

**`SleepTimerSheet`**: the switch's slab becomes a two-row group — the switch, a hairline, then a
row "Soundscape" with the choice's title (or "Off") in `ink2` and a `RowChevron`, which presents
`SoundscapeSheet` over the sleep sheet. The detent grows to fit, measured on the simulator.

**`ReaderPage`**: no new overflow item; Preferences is the door.

### 4.4 The content pipeline

- `App/Resources/Soundscapes/soundscapes-manifest.json`: per recording, `id`, `file`, the
  Freesound sound id and author, the licence (`cc0`), and the source URL. One file is the whole
  truth of where each sound came from.
- `scripts/fetch-soundscapes.sh`: downloads each `file` from the `ambiently` repository at a
  pinned commit (`raw.githubusercontent.com/abhinandansharma/ambiently/<sha>/demo/public/sounds/`)
  into `App/Resources/Soundscapes/soundscape-<id>.m4a`, and `CREDITS.json` beside the manifest for
  the record. No key, no account, no processing: the seam and the loudness are done at load. A
  file already present is kept; `--force` fetches again. Six files, about 2.4 MB, committed as the
  onboarding covers are.
- `App/project.yml` already bundles `Resources` flat, so `Bundle.main.url(forResource:
  "soundscape-rain", withExtension: "m4a")` finds them; nothing to add.
- `docs/licenses.md`: a row per recording — CC0 needs no attribution, and the register records the
  provenance anyway.

## 5. Behaviour at the edges

- **Interruption or route change**: the session controller pauses the coordinator; the bed
  follows the state on the next tick and fades out. On resume it fades back in.
- **Media-services reset**: `rebuildAfterMediaServicesReset()` rebuilds the graph with the bed
  rescheduled; the model's next tick re-asserts the volume.
- **The document ends**: state is `.finished`; the bed fades out like a pause.
- **Voice previews** (`VoicePreviewModel`) pause the book first, so the bed fades out under them.
- **A missing resource** (the fetch script never ran): the loader returns nil, the model logs it
  and behaves as Off; the tile still shows, so a developer sees the gap.
- **Background**: nothing new. The engine already runs after the first play; a bed at zero
  volume has its node paused and adds nothing.
- **VoiceOver**: each pill is a button with its title and the selected trait; the slider is a
  slider named Volume; the sleep sheet's row reads "Soundscape, Rain, button".

## 6. Tests

T2SAudio:
- `LoopSeamTests`: a constant loop stays constant across the seam; the length is N − X; the seam
  of a sine at the loop frequency is continuous; a loop shorter than 2X is returned untouched.
- `NoiseLoopTests`: samples inside −1…1, non-zero, deterministic for a seed, brown has more
  low-frequency energy than pink (compare the RMS after a one-pole low-pass).
- `LoudnessTests`: output RMS within 0.1 dB of the target; the peak never exceeds the ceiling.
- `AudioPlayerBedTests` (manual rendering): bed set, volume 0 → `lastRenderPeak` is 0; volume
  0.5 → above 0; the voice's `consumedSeconds` is the same with and without a bed; rebuild after
  a reset keeps the bed sounding.

T2SApp:
- `GainRampTests`: the value at the end is the target, in between it is monotonic, never past.
- `SoundscapeModelTests` with a `FakeBed: BedPlaying` (in T2SAppTests, ten lines) that records
  `bedLoops` and `bedVolumes`:
  choose → loop set; voice plays → volume ramps to the mapped gain over 1.5 s; pause → to zero;
  an audition holds it up for eight seconds while paused and each tap extends it; `linger()`
  takes 20 s; a play cancels the linger; changing
  the choice fades out, swaps, fades in; Off drops the loop after the fade; the volume slider moves
  the gain while playing; preferences persist.
- `SoundscapeCatalogTests`: ids unique, every recording's resource name is `soundscape-<id>`,
  the manifest parses and names the same ids.
- `ReaderPreferencesTests`: the two new keys default, persist, clamp and reset.
- `SleepTimerTests`: `onFire` is called once when the timer fires, not on cancel.

The sheets are photographed on the simulator in light and dark, with a probe as the sleep sheet was.

## 7. Work, in order

1. Content: the manifest, the fetch script, the six files, the licence rows.
2. T2SAudio pure helpers: `LoopSeam`, `NoiseLoop`, `Loudness`, with tests.
3. T2SAudio: `BedPlaying`, the bed node in `AudioPlayer`, the manual-rendering test.
4. T2SApp: `Soundscape`, `SoundscapeLoader`, `GainRamp`, `SoundscapeModel`, preferences,
   `SleepTimer.onFire`, with tests.
5. App: `AppEnvironment` wiring and the ticker; `SoundscapePicker` in the Preferences sheet;
   `SoundscapeSheet` and the sleep sheet's row; photographs.
6. Docs: HANDOFF, README (the script), `licenses.md`, this spec's changelog.

About three days. Steps 1 and 2 have no dependency on each other or on 3; 4 needs 2 and 3; 5 needs 4.

## 8. Not in this design

Mixing several beds; per-book choices; a bed that outlives the book; downloading sounds on
demand; stereo; an overflow item; a copy in Settings' Appearance sheet; the reference's "Goal
timer" cell; a footnote pointing at iOS's own Background
Sounds (Settings → Accessibility → Audio & Visual), which does the same job system-wide and is
worth knowing about, but is not a thing to advertise inside our own sheet.
