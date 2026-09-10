# t2s_reader — hand-off and next steps

_Last updated 2026-09-10 evening (the empty shelf on Home and the Collection — three covers fanned, a raised button; before that an import ends on a done step — Play or Done — and shows on Home and the Collection at once; before that the 17 Pro's two crashes, the model download, the warm-up and the cloud route on `phone-warmup-download-cloud`; before that the glow as a bezel, the Voice page's seam; before that the tail click removed by place on every voice, the Reader's voice chip; before that the glow concave and higher, the Voice page's cut, web ≠ text, PDF in cloth; before that generated covers — cloth for books, a sheet for links and text; before that one warm-up glow; before that the Collection's title is its filter; before that the share-sheet book bug, the veil moved behind the page and hushed while sound plays, the skip pill on unnumbered books; before that the warm-up veil with real stage progress, the signing team in Local.xcconfig, picker round 7; before that voice picker round 6 from the phone: subpages own the screen, no Default row, waveform + heart + radio per row, a bar that rises on a choice; before that round 5 — a radio per row, the avatar plays, a Change voice bar in the Reader's sheet; before that top fade, no Autoplay row, Collection tabs with Text and Links, ElevenReader-style import steps; before that books on one shelf height and slot on Home and in the Collection; before that the book sheet's tilt eased back a step after being made bolder, then book sheet rework + no queue, then chapter sheets, skip pill, bookmark toggle on `dev`; before that Plan 17 — the rest of the audit — on `plan-17-rest-of-audit`, in the worktree `.worktrees/plan-17-rest-of-audit`, off `origin/dev` @ 7dc7498 and rebased onto the voice-picker pass at 1e23c1a). Written for whoever picks up the coding next._

## Resume here (2026-09-10, latest) — the empty shelf: three covers fanned, one raised button

The owner, with Klarna's "Nothing saved" screen and a blue "Join school" key as references: "create
empty states on home and collections page similar to the reference, use 3 book covers from online
(popular, beautiful covers), stagger them with a nice animation and show a CTA below. Use a
skeuomorphic button for the CTA." And: "don't plan, directly implement."

- **`EmptyShelf`** (`Design/EmptyShelf.swift`): the one empty state Home (`rows.isEmpty`) and the
  Collection (`all.isEmpty`) share — a fan of three real covers over a pool of light, a headline
  in `playerTitle`, one line in `rowTitle`/`ink2`, and the button. Home says "Nothing playing yet /
  Import a book, PDF or article and it plays right away."; the Collection "Your shelf is empty /
  Books, PDFs, links and text you import live here." Both buttons open the Import cover. The
  header's Import pill / `+` stay: the owner asked for a CTA below, not for the header to change.
- **The fan** (`CoverFan`): The Midnight Library and The Song of Achilles behind at ±13°, 136 pt,
  70 pt out and 16 pt down; Circe in front, upright, 158 pt. Each is a `BookCover` — hinge, sheen,
  shadow, the proportion rule — through a new `BookCover.asset` (a bundled image name; wins over
  `relativePath`, keys the backlight cache). The covers are Open Library's ISBN scans
  (`Assets.xcassets/EmptyCovers/*`, ~330 × 500, 190 KB for the three), chosen from fifteen for
  clean scans and a gold / navy / teal trio. The pool is a `Circle` of `accentSoft → accentFaint →
  clear` squashed to 0.68 — a plain `RadialGradient` in a rectangular frame showed its frame as a
  faint hard-edged patch at the first look.
- **The entrance**: each book starts 44 pt low, at 0.9, a third of its tilt, clear, and springs
  (response 0.68, damping 0.74) to its place — the two behind first (0 s, 0.15 s), the hero last
  (0.32 s). After 1.3 s the hero breathes: ±5 pt, 2.8 s each way, forever. Reduce Motion: nothing
  moves, the three fade in together in 0.35 s and there is no breath. Verified with a burst of
  screenshots on a warm launch: one frame with the first book alone mid-rise, the next with all
  three landing.
- **`RaisedButton`** (`Design/RaisedButton.swift`): the skeuomorphic key, in the accent. A capsule
  filled `accent`, a gloss-to-shade gradient over it (light from above), a bevel hairline bright on
  the top rim and dark on the bottom, and two shadows — a tight contact one in `shade` and a wide
  one in the accent's own hue (radius 18, y 10). Pressed: a shade wash, the shadows tighten, 0.965
  scale, `.snappy(0.18)`. `Pill(.accent)` is still the flat one-word header action; this is for an
  empty page's one "do this first".

`scripts/build-app.sh` → `** BUILD SUCCEEDED **`. Seen in the simulator (iPhone 16 Pro): Home and
the Collection, light and dark, and the burst. Root `swift test` not run: nothing under `Sources/`
changed in this round. Not seen on a phone. Owed: the owner's look at the fan and the key there —
whether 500 px covers hold up at 158 pt on a 3× screen, and whether the accent shadow under the
key is too much on the OLED black.

A second session was rebasing `dev` onto PR #16 (92fd0ac) with its import-done commit while this
was built in the same folder; it briefly swept these files into that commit with `git add -A`,
then took them back out. This round was committed on top once that rebase had finished.

## Resume here (2026-09-10, evening) — an import stops to ask, and shows up at once

Two reports from the owner: "when I import a file, weblink, text, don't play it immediately — give
me the option to play or exit", and "I imported a doc, but could not see it in collections or
home, till I exited and reentered the app".

- **The done step** (`ImportDonePage`): every path used to end by closing the Import page and
  opening the Reader on the first document, which loads and plays. Now `ImportPage` switches to a
  done step whenever the model's phase is `.done`: the documents on their shelf slots (`BookCover`
  / `SheetCover`, as Home draws them) with the title and one line — author, site, or PDF/Book/Text,
  and the length — a **Play** bar at the foot and **Done** in plain text under it (`ImportFrame`
  gained `secondary`), and the circle closes. Play writes the first document through `imported`
  and dismisses, so the Reader still opens from the cover's `onDismiss` and plays; Done and the
  circle only dismiss. A file batch that half worked lists its failures under the rows. The paths'
  bars say **Import** now, not Listen (they no longer listen); "Import anyway" on a thin page.
- **The missing document**: nothing refreshed `LibraryModel` after an import. The Reader's first
  play called `notePlaying`, which looked the book up in the stale `summaries`, found nothing and
  returned without a refresh — so the book was on neither page until the scene came back to the
  foreground. Two fixes: `notePlaying` refreshes first when it does not know the id (test
  `LibraryModelTests.notePlayingReadsInADocumentImportedSinceTheLastRefresh`), and
  `AppEnvironment`'s `afterImport` refreshes the lists before priming, so the pages behind the done
  step already show the new document whether or not it is played.

`swift test` 477/87 green (one new), on `dev` after PR #16 (the phone warm-up, download and cloud
route) was merged under it. `scripts/build-app.sh` → `** BUILD SUCCEEDED **`. Not seen in the simulator: the done step needs a
real import (typing, or a file), which a scripted simulator cannot do — look at it on the phone:
import a link, a text and a PDF; each should end on "Added to your library" with Play and Done, and
be on the Collection (and Home, until three others are played) after Done.

## Resume here (2026-09-10, evening) — the 17 Pro's two crashes, the model download, the warm-up, the cloud route

Branch `phone-warmup-download-cloud` off `dev` @ d849036; spec
`docs/superpowers/specs/2026-09-10-phone-warmup-download-cloud-design.md`. Harsh's asks: the app
crashing after three lines on the 17 Pro, the warm-up, "decouple the model from the app install",
"are we leaving performance on the table", "does the cloud integration work".

**The crash, from the phone's own reports** (pulled with `xcrun devicectl device copy from
--domain-type systemCrashLogs`; the two `.ips` are worth keeping beside this file):

- **15:14 on 2026-09-09, `cpu_resource_fatal`** — "48 seconds cpu time over 48 seconds (100% cpu
  average), exceeding limit of 80% cpu over 60 seconds. Process killed." Non-Frontmost App, on
  battery. Symbolicated against the iOS 26.6.1 device-support symbols, the heaviest stack is
  `MLModel.load` → `MLE5ProgramLibraryOnDeviceAOTCompilationImpl` → `E5RT::E5CompilerImpl::Compile`
  → `bnns::GraphCompile`: the warm-up building Core ML compute plans, after the phone locked (or the
  app was switched away). `AudioPlayer` started its `AVAudioEngine` at launch, which is what kept
  the process alive in the background instead of suspended. The 11 Pro never hit it because the
  owner sat through the first warm-up in front of the phone.
- **03:33 on 2026-09-09, `EXC_BREAKPOINT`** in `closure #1 in static PrepareTask.register()` on
  `com.apple.BGTaskScheduler (com.t2s.reader.prepare)`, 0.4 s after a launch: the launch handler
  inherited main-actor isolation and trapped on the scheduler's queue. Every overnight Prepare
  launch died this way, on every phone.

**What changed:**

- `ForegroundGate` (T2SCore), set from `scenePhase` in `RootPager`: the stage loader awaits it
  before each compute-plan build (`KokoroCoreMLModels.loadStages(admission:)`), the installer
  before each compile, the warm-up before it starts, the launch prime before it runs. A process
  launched for a background task never opens it.
- `CPUBudget` (T2SCore): `RenderScheduler` waits, while the app is not frontmost, until the trailing
  60 s window holds under 36 s of CPU before a synthesis; logs under `render.pacing` when it engages.
  Shared by the coordinator and `PrepareRunner`.
- `AudioPlayer` starts the live engine on `play()`, not in `init`.
- `PrepareTask.register`'s handler is `@Sendable`; a background Prepare pass skips until a
  foreground warm-up has built this install's plans (`KokoroWarmUpRecord`, keyed on bundle path,
  OS build, model path and revision).
- **The model is downloaded, not bundled.** `KokoroCoreMLManifest` (72 files, 619,234,624 bytes,
  the fetch script's pins) and `KokoroCoreMLInstall` (Wi-Fi only, resumable per file, SHA-256
  verified, compiled on the phone under the foreground gate, into
  `Application Support/KokoroCoreML/2e878c6a/`). `App/project.yml` no longer bundles
  `Resources/KokoroCoreML`; the bundle is still looked in first. The veil says "Downloading the
  voice · 120 of 619 MB", then "Preparing the voice · 3 of 14", then warms up as before.
- **Ready after eight stages:** the duration models plus the 3 s and 15 s buckets; the 7 s and
  10 s buckets load behind on the engine's own task and swap in as they land. Nothing rendered
  meanwhile is split or seamed differently — the 15 s bucket holds every piece.
- **Timing log:** `kokoro.timing` — every stage load (its seconds say whether the plan came from
  the cache or was built), every pipeline call's stage split, every utterance's G2P/pieces/RTF.
  `kokoro.computeUnits` user default (`cpuAndNeuralEngine`, `cpuAndGPU`, `all`) for the audit's
  §3.7 experiment; `scripts/compute-probe.sh` runs it on a Mac.
- **The cloud route speaks OpenAI's contract** (`response_format: "pcm"`, raw 16-bit PCM back;
  a proxy's JSON with word timings still accepted). It never worked against a real provider
  before: it sent `pcm_f32le`, `sample_rate` and `timestamps`, which OpenAI rejects. Not tried
  against the live API (no key here); tests cover both shapes.
- **Per-Mac identity:** `T2S_BUNDLE_ID`, `T2S_APP_GROUP`, `DEVELOPMENT_TEAM` in `App/Local.xcconfig`
  (defaults in `project.yml`; `AppPaths` reads the group from Info.plist). Harsh's Mac has
  `com.antarlabs.t2sreader` / `group.com.antarlabs.t2sreader` / `6U8JR7LCRZ` there — what his
  installed app already used — instead of edits to tracked files.

**Compute units, decided 2026-09-10 (Harsh: "as fast as possible", the recommended path):** the app
ships CPU-only until the phone says otherwise. This Mac's probe (`scripts/compute-probe.sh`,
`spikes/findings/compute-probe/report.md`) on the 90-word Dickens passage:

| policy | load, all buckets | first render | second render | RTF (second) |
|---|---|---|---|---|
| coreml-cpu | 96 s (cold plans) | 3.6 s | 3.5 s | 0.131 |
| coreml-cpu+gpu | 126 s | 26.2 s | 3.8 s | 0.142 |

The Neural Engine policies (`cpuAndNeuralEngine`, `all`) were stopped: every generator stage
spends five to nine minutes failing `ANECCompile() FAILED` before Core ML falls back — the audit's
§3.7 finding, reproduced. So `all` would lengthen the first launch by half an hour and win nothing.
**The one measurement left:** the 17 Pro with `-kokoro.computeUnits cpuAndGPU` against the
default; if the GPU wins there by more than noise, wire `.cpuAndGPU` for Apple GPU family 7 and
up in `KokoroComposition.make` (the family check is `KokoroAvailability.Probe`'s) and keep the A13
on CPU, where the GPU policy measured twice as slow.

**Why the 11 Pro and the 17 Pro differ:** not the silicon. The 17 Pro's launches were being killed
mid-warm-up and restarted from a cold plan cache, then it played at whatever the last kill left; a
CPU-only Core ML pipeline scales with one or two performance cores, not with the A19 Pro's Neural
Engine, so the raw speed-up over an A13 is 2–3×, no more. The `kokoro.timing` lines on the next
launches answer the two open questions: does the plan cache survive a reinstall now that the model
lives in the data container, and what does `.cpuAndNeuralEngine` do to the generator's share.

**The phone run** (Harsh; the branch is built for it): Phone scheme, Release, run from Xcode with the
phone in front; the first launch downloads (Wi-Fi) and compiles, then warms up — watch
`log stream --predicate 'subsystem == "com.t2s.reader"' --style compact`. Lock the phone during the
warm-up on purpose: the loads must pause (no `kokoro stage … loaded` lines) and resume on unlock,
and the app must survive. Play a book, lock the phone, listen for a minute. Then kill the app,
relaunch, and read the `kokoro stage` seconds: under a second each means the cache survived. Then
`-kokoro.computeUnits cpuAndNeuralEngine` in the scheme's arguments and compare `kokoro call` lines.
Charge overnight: `Prepare skipped` or a pass in the log, no crash report.

**Verified here:** `swift test` 476/87; `scripts/test-kokoro.sh` — every suite but one test:
`streamsALongPassageInPiecesThatFoldToTheSameTimings` fails on the original sources as well (a
constant ~180 ms shift between the streamed and whole renders' word starts, from the streamed
48-id first piece's seam — Plan 15 owed this test and never ran it); the new
`KokoroCoreMLInstallTests` and `KokoroCoreMLLoadTests` pass; the simulator and device builds
compile. Not verified: the phone itself.

## Resume here (2026-09-10, afternoon) — the glow as a bezel, and the Voice page's seam

The owner, from the phone: "the corners are more prominent than the top — can we implement some
sort of bezel glow in the top part?"

- **The bezel** (`WarmRamp`): the two elliptical corner glows are gone. The light is one stroke
  along the screen's edge — a continuous `RoundedRectangle` (`WarmRamp.bezelRadius`, 55 pt: the
  iPhone 14–16's; `UIScreen` does not say, and the rim is blurred enough to hide the few points
  the 12/13 (47) and the 16 Pro (62) differ by) the width of the host and three ramps tall, so its
  bottom edge is clipped away, stroked on the edge itself (half the line off-screen) twice: a
  36 pt halo blurred 14 at alpha 0.38 (about 30 pt in), and a 10 pt rim blurred 4 at alpha
  0.78 — over a breath of wash from the top (0.08 → 0 by 0.20 of the height). The owner's second
  word, from the simulator: "reduce intensity so that the glow is mostly confined to the bezel
  edges" — the first cut (a 72 pt halo blurred 26 at 0.50, wash 0.26 to a third of the way down)
  lit the whole top of the page. A vertical mask lets the sides fade from a third of the height
  and be gone by 0.85 of it. The stroke is the same the whole way round, so
  the top and the corners are one lit edge and the corners are only where it turns. Height 240,
  the pulse, the dither and the opaque composite are unchanged.
- **The Voice page's seam was not the glow's** (`SettingsSubpage`): measured against the Settings
  root (a Swift tool sampling columns of two screenshots), the pushed page was more orange in the
  rows 62–92 pt down — with the old cut too. Logged: the reader in the page's `.overlay` sits
  inside the safe area and reports its inset as zero, so `TopFade(inset: 0)` was a 30 pt bar at
  the status bar's foot, a copy of the ramp one inset low fading over the right one. The bar is
  now anchored like the page's background, by measurement (`TopFade(inset: top).offset(y:
  -top)`, `top` the content's top in the window). After: the two pages' columns agree within the
  dither.

`swift test` 456/82 green. `scripts/build-app.sh` → `** BUILD SUCCEEDED **`. Seen in the
simulator (iPhone 16 Pro, `T2S_WARMUP=1`): Home light and dark, the Reader, Settings and the
pushed Voice page (`T2S_PAGE=preferences T2S_OPEN=voices`). Not seen on a phone — the corner
radius fit is the thing to look at there.

## Resume here (2026-09-10) — the click on every voice, and the Reader's voice chip

Two reports from the owner after a voice change in the Reader: "the reader voice UI does not
update", and "does changing voice reintroduce the click sounds in the playback? I am getting them
when I change voice."

- **The chip** (commit 7eb243d): `ReaderPage` named the voice from the `summary` the root pager
  handed it when the cover opened — a snapshot a voice change never touches (the change updates
  the store and reloads the player). `PlayerModel.routedVoiceID` is the route resolved at every
  load, cleared by `unload`, and the page names it through `onChange` whenever it moves
  (`resolveVoiceName` no longer routes for itself; the catalog is built per `voices()` call and
  the body runs at 10 Hz, so the name stays in `@State`). Test:
  `PlayerModelTests.routedVoiceFollowsLoadsAndVoiceChanges`.
- **The click was never the voice change's — it was the voice's.** `KokoroCoreMLTailClick`
  (Plan 11) looked for the burst's *shape*: an island under 30 ms between two runs of ≥ 10 ms under
  −80 dBFS. That is Heart's tail. A new probe, `scripts/voice-tail-probe.sh`
  (`KokoroVoiceTailProbe`, enabled while `spikes/findings/voice-tail-probe/` exists, ~9 min),
  rendered three of the Dickens utterances through all 28 voices with the pieces plain-appended,
  sliced every pipeline call by the trace, and ran the shipped rule over each: **it left the burst
  standing in 45 of 113 calls on 22 voices**, at up to −5 dBFS (George, Daniel, Alloy). On Alloy
  a −60 dBFS floor laps at the burst, so there is no 10 ms of −80 dBFS silence before it; on
  Jessica the last word decays straight into it. What every voice shares is the *place*: the burst
  ends where the call's final 36–45 ms of exact zeros begin (the generator's output for the
  bucket's zero padding, pulled inside the kept audio by its ~40 ms look-ahead) and begins at most
  66 ms before the end — the generator's pre-echo of the step into the padding. The rule now goes
  by place: the last 70 ms of every call are zeroed and the 10 ms before ramp down to meet them.
  What the window held besides the burst is the EOS token's single 25 ms frame, shifted the same
  way. Rerun: **0 of 113 calls** keep a burst; the streamed first pieces (the app's path, which a
  voice change forces because it evicts every clip and Prepare has not run ahead) go from 8 voices
  with a burst to none; joins unchanged (largest step 0.0048). The measurement is the 2026-09-10
  section of `spikes/findings/2026-09-08-ticks-and-hyphens.md`; `report-before.md` and `report.md`
  in the probe directory are the two runs, with WAVs of every flagged tail, raw and after.
- **Every Kokoro clip re-renders once** (spec §5: audio changed, key must change). The engine
  identity cannot carry it — an unknown identity re-routes a stored Bella to Heart — so, like the
  delivery, the finishing revision rides on the voice route: `kokoro:<engine>:<voice>@1.25#2`
  (`KokoroVoiceID.finish`, written after the spread; `Delivery.finish` = 2, bump it whenever the
  engine's post-processing changes what it renders). Stored voice choices never carry it; the
  engine ignores it. `KokoroCoreMLTailClickTests` rewritten for the three tail shapes and the ramp;
  `KokoroVoiceIDTests` and `DeliveryTests` cover the tag.
- **Not done**: listening — every number is a proxy, and the phone renders in fp16 where the Mac
  renders fp32, so the zeros' scatter may differ there (the window has 4 ms over the widest start
  seen). The pause at a voice change itself is `AVAudioPlayerNode.pause()` mid-waveform, as every
  pause in the app is; not touched. Spec rev 19.

`swift test` 456/82 green; T2SKokoro `KokoroCoreMLTailClickTests` + `KokoroCoreMLSeamTests` 14/14
(`xcodebuild`, `-only-testing:`); `scripts/build-app.sh` → `** BUILD SUCCEEDED **`. This Mac's disk
is at 99 % (≈1–2 GB free): both probe runs logged BNNS "No space left on device" during the Core ML
compile and finished anyway, and one app build died on it while a probe held the caches — run them
one at a time, and sweep `$TMPDIR/kokoro_*.mlmodelc` once the private copy under
`Packages/T2SKokoro/.build/compiled-stages-*` exists.

**The phone listen.** Change a book to Alloy, Jessica, George or Onyx and press Play: no tick after
"Humbug!" or before "and his breath smoked again"; the chip in the Reader's tool row shows the new
name the moment the sheet closes. Every Kokoro book renders afresh on its first play after the
update.

## Resume here (2026-09-10) — the glow made concave, the Voice page's cut, web ≠ text, PDF in cloth

Six asks from two phone crops (the Voice screen while warming, and the text sheet). The first four
are the warm-up glow — the cut is the Voice page's alone, the shape, height and pulse are the
shared `WarmRamp` every host draws — the last two are the covers from the section below.

- **Cut on the Voice page.** `VoiceListPage` (and the other pushed Settings pages) painted a plain
  opaque `ground`, so under the root bar's slice of the glow the page hid the veil: the glow
  stopped at the bar's foot. `settingsSubpage()` now paints `WarmGround` as the page's background
  and the four pages dropped their own ground (`VoiceChangeSheet` adds a plain one for the sheet).
  Two things measured on the way, not guessed: (1) `.background(WarmGround().ignoresSafeArea())`
  left the page's copy of the ramp **one status-bar height low** (a column scan down the left
  edge: 30 levels more orange than Home from the bar's foot down), so the background is anchored
  by `geo.frame(in: .global).minY` and offset up by it instead; (2) the subpage's own `TopFade`
  was plain and lightened the fade zone a shade under the warm root bar, so it is `warm: true`
  too. After both, a 24 pt grid of the green channel over the top 300 pt of the Voice page matches
  Home's within ±3 everywhere.
- **Concave, higher, breathing almost out** (`WarmRamp`): `height` 320 → 240; the ramp is no
  longer a top-to-bottom band but a lit edge (0.46 alpha at the top, gone by 0.34 of the height —
  raised from a first cut the owner called "too side heavy") plus two elliptical glows anchored at the top corners, each in its own half of the
  width so it dies exactly at the centre line — corners strongest, light carried down the sides,
  the middle of the screen clear right under the status bar. The colours are the accent at an
  alpha over `ground`, composited into one opaque layer inside the dither group (the earlier
  `mix` stops assumed one vertical gradient); the pulse floor is 0.05 (was 0.38), so the low of
  each breath is all but invisible. `T2S_WARMUP=1` still pins the pulse at 1 for screenshots.
- **Web page ≠ text** (`SheetCover`, supersedes the sheet description in the section below): a
  web page is a small browser window — a `surface` chrome strip with an address pill holding a
  globe and the host, the title, a picture block, two lines — on white; a text is a notepad —
  cream `notePaper`, a `noteBinding` strip with a dashed perforation, a "TEXT" tag beside the text
  glyph, the title, ruled lines. The date masthead is gone (`SheetCover` no longer takes
  `addedAt`). `CoverMark` (mini-player) follows: globe on white / text glyph on cream.
- **PDF in the cloth design**: `ClothCover` takes its cloth and ink (`pdfCover`/`pdfInk` for a
  PDF) and a `badge` lettered at the foot in place of the rule — title and author on the red,
  "PDF" below; under 64 pt the badge is the mark. The owner's "light red PDF cover" rule stands.

`scripts/build-app.sh` → `** BUILD SUCCEEDED **`; nothing under `Sources/` moved (452/82 stands).
Seen in the simulator, light and dark: the Voice page warming (no seam; `T2S_WARMUP=1
T2S_PAGE=preferences T2S_OPEN=voices` — the page hook is needed too, `T2S_OPEN=voices` alone opens
Home), Home warming, Home and both Collection layouts with the browser window, the notepad and the
red cloth PDF. Not seen on a phone.

## Resume here (2026-09-10) — generated covers: cloth for books, a sheet for links and text

The owner's two asks from a phone crop of Home: a better placeholder for URLs and pasted text that
aligns with the books, and a better placeholder cover for books with no cover. Commit 33d771f.

- **Books with no cover** (`ClothCover`, private to `BookCover` in `Design/Primitives.swift`): a
  cloth binding in one of eight palette colours (`Tokens.coverInk/coverTint/coverGlow`,
  `coverText` cream), dealt by the title through `CoverStyle.paletteIndex` (FNV-1a over the
  lowercased title — stable across launches and devices, unlike `hashValue`), a hairline frame
  stamped in from the edge, the title top-left in InterDisplay-ExtraBold with the author under it
  (new `BookCover.author`, passed from Home, both Collection layouts and the book sheet), a short
  rule at the foot. Lettering is `fixedSize` to the book's height — it is a cover, not UI text.
  Under 64 pt it carries the title's first letter (`CoverStyle.monogram`). The book sheet's
  backlight uses `coverGlow` for a placeholder (was `ink3`). PDFs keep their red "PDF" cover.
- **Links and pasted text** (`SheetCover`, same file): a sheet of paper — `raised`, evenly rounded,
  hairline `ink3` edge, a thin shadow, no spine, no sheen — 0.72 of its height wide. Masthead in
  the title's palette colour beside the kind's glyph: the page's host without "www."
  (`CoverStyle.host`) or the day the text was written (`CoverStyle.dateLabel`, "10 Sep" / "Sep 10"
  by locale); a rule; the title in Inter-SemiBold, up to four lines; three ruled lines for the body.
  `.shelved` puts it on the books' slot (`BookCover.widestRatio` wide, bottom-leading), so the Home
  row's meta line, title and Play pill now start at one x whichever kind sits there — before, the
  article's 64 pt square pushed its text 32 pt left of the books'. `CollectionPage.ShelfArt` uses
  it too (its glyph-on-`surface` square is gone).
- **Mini-player**: `Artwork` takes an optional `document`; without an image it draws `CoverMark` —
  the cloth with the monogram, the PDF red, or the paper with the glyph — instead of a grey block.
- **`T2S_SEED=1`** (`RootPage.launchSeeds`, screenshots only, beside `T2S_OPEN`/`T2S_PAGE`): imports
  a pasted text and a web page (built in place, no network) once, matched by title after that, and
  notes both as played so they stand at the top of Home. A script-driven simulator cannot type
  into the Import steps, and the sheets needed something to stand for.

`CoverStyle` lives in `Sources/T2SApp/Formatting/` with `CoverStyleTests` (8 tests). `swift test`
452/82 green; `scripts/build-app.sh` → `** BUILD SUCCEEDED **`. Seen in the simulator (iPhone 16
Pro, `T2S_SILENT=1`), light and dark: Home with the two sheets and the cloth Mughal, the Collection
list and grid, the book sheet on the cloth cover with its glow, the mini-player's monogram and
link marks. Not seen on a phone. Left alone on purpose: fetching a page's real image for a link
(the extractor strips images; a placeholder was the ask), and the row's meta line for articles,
which still shows only the ring and percent.

## Resume here (2026-09-10) — one glow: the bars paint it, Settings gets it, it hugs the top

The owner saw the glow "split in 2" at the status bar, wanted it higher, and asked why Settings had
none. Three causes, three fixes, all in `Design/WarmUpVeil.swift` and the bars that use it:

- **The split was arithmetic.** The strip drawn over the status bar was a second, translucent copy
  of the wash, and two layers at opacity *p* stacked do not make one layer at *p*: the band was
  always a shade stronger than the page under it, and pulsed against it. Gone. There is one view,
  `WarmRamp` — **opaque**, its pulse a `Color.mix` fraction rather than an alpha — and everything
  that shows the glow draws that same view: `WarmUpVeil` at the back of a stack, and every ground
  bar through **`WarmGround`** (ground normally, the ramp while warming, a 0.6 s crossfade between).
  `TopFade` takes a mask over a fill now (`shape(solidThrough:fade:)`) and paints `WarmGround` when
  its host says `warm:`; the Reader's header does the same with its own `groundShape`. A bar
  painting the ramp over the veil shows the pixels the veil would have shown, so there is nothing to
  line up. `WarmUpLine` is the message alone. Measured: averaged over 60 empty columns, the old
  build stepped 6.5 (G) / 10.3 (B) levels at exactly the inset edge; the unified one's largest steps
  are 2.0 / 3.2, at a different row on each page — the ramp's own slope, no seam.
- **Then a second, inverted band**: the bar showed a *paler* slice. The 320 pt ramp was a fixed-height
  child inside the bar's 90 pt frame, SwiftUI centred it, and the bar drew the ramp from 115 pt
  down. The ramp is an `.overlay` on the ground now — no part in layout — so it starts at the top
  of any frame. Worth remembering: a fixed-size child inside a smaller frame is centred, not
  top-aligned, whatever the stack's alignment says.
- **Higher**: the glow is a fixed 320 pt from the top (`WarmRamp.height`) instead of 58 % of the
  screen, plateau to 15 %, out by 55 %. Same on every phone.
- **Settings had no glow** because its `NavigationStack` paints an opaque container background over
  the pager's ground; `.containerBackground(Color.clear, for: .navigation)` clears it, and the page
  is as transparent as Home and the Collection.

`scripts/build-app.sh` → `** BUILD SUCCEEDED **`. Seen in the simulator (`T2S_WARMUP=1`, pulse
pinned): Home, Settings and the Reader lit from the very top with no join, dither still clean
(longest flat run 4 px). Not seen on the phone.

## Resume here (2026-09-10) — the wash dithered, and the white band fixed properly

(Another session landed the Collection's title-as-filter in the section below while this was going
on; the two do not overlap — the three root pages still hand their ground to `RootPager`, which is
what the wash needs, and the Simulator scheme builds with both in.)

- **Banding** (owner saw steps in the orange). Measured, not guessed: a script walked a column of
  the screenshot and reported per-channel run lengths, and the wash held one value for up to 23 px
  before stepping. Two causes, both fixed in `WarmUpVeil`:
  - The ramp was **translucent accent over ground**, so noise blended over it had almost nothing to
    act on — the first dither barely moved the numbers. Each stop is now the colour that
    combination *makes* (`Color.mix(with:by:)`, resolved per theme — checked in dark, where it
    reads as warm brown), the last stop being `ground` itself so the layer ends invisible against
    the page. The pulse is applied to the finished layer, so the dither is mixed at full strength.
  - The noise tile is drawn at **scale 3, one cell per device pixel**. Point-for-point it was a
    3 × 3 px speckle that read as grain; at pixel scale it disappears and dithers harder.
  Result, same column, same pinned pulse: green's longest flat run 9 px → 3 px and blue's 7 px →
  3 px, mean run 1.0–1.1 px (a dithered ramp has no flat runs at all). Red barely varies in this
  ramp — 248 → 252 across the whole thing — so its long runs are inherent and invisible.
  `T2S_WARMUP=1` now also pins the pulse, so two screenshots are comparable.
- **The white band across the top came back on the phone**, though the simulator was fine. The
  `.chrome` strip took its height from the key window's safe-area inset, and on the owner's phone
  that read zero, so the strip had no height and `TopFade`'s solid ground showed through. The host
  passes the inset in now (`WarmUpVeil(band:)`) — `RootPager` from the same `geo.safeAreaInsets.top`
  it already gives `TopFade`, so the two bands cannot disagree, and `ReaderPage` from a
  `GeometryReader` of its own. The window read stays as a fallback, and a plain iPhone's 47 pt
  behind that, so the strip is never nothing again.
- **"about 220 s"** is now "about 4 min": past ninety seconds the line counts in minutes.

`scripts/build-app.sh` → `** BUILD SUCCEEDED **`; `swift test` 444/81 green (nothing under
`Sources/` moved this round). Seen in the simulator, light and dark: no banding, no grain, the wash
running from the very top. **Not seen on the phone** — which is where both the banding and the white
band were reported, so this needs the owner's eye.

## Resume here (2026-09-10) — the Collection title is the filter

One ask from the phone, with a reference (a podcast app's "Queue ⌄" dropping a Queue / Favorites
card): rename the Collection's title to **All**, give it an up-and-down chevron, and let a tap on
it choose the kind — replacing the row of filter tabs under the header.

- **`Design/TitleMenu.swift`** (new, and `Design/FilterTabs.swift` is gone with nothing left
  referencing it): **`TitleChevron`**, `chevron.up.chevron.down` at 16 pt bold pulled off the
  baseline onto the word's x-height (`alignmentGuide(.firstTextBaseline) { center + 12 }`) so it
  reads as part of the title; **`TitleMenuCard`**, a `raised` card at radius 20 with a row per
  option, the chosen one on `Tokens.ink.opacity(0.07)` with the voice list's `RadioMark`. The film
  is `ink` at low opacity rather than `surface` because in the dark theme `surface` and `raised`
  are four values apart — the row would not read as chosen. **`TitleAnchorKey`** carries the
  title's bounds up as an `Anchor<CGRect>`.
- **Why an anchor and not a frame.** First cut measured the title with a `GeometryReader` into a
  coordinate space named on the `ScrollView`; the value arrived as 0 every time (the card landed
  under the status bar). `anchorPreference(value: .bounds)` + `overlayPreferenceValue` +
  `proxy[anchor]` resolves through the scroll view. Worth remembering — the named-space trick is
  the one that looks right and silently is not.
- **The menu only exists while it is down.** The `GeometryReader` lives inside the `if`, not
  around it: an open-ended reader over a closed menu is a page-wide view with no content, and a
  page-wide nothing over the shelf is exactly what must not eat a tap on a book. `T2S_OPEN=kinds`
  opens the menu at launch — a scripted simulator cannot tap a title.
- **The freed row.** With the tabs gone the layout switch joins `+` and Search on the header line,
  and it still only appears when the collection has something in it.
- **A `Pill` no longer wraps** (`Primitives.swift`): `lineLimit(1)` + `fixedSize` horizontally. At
  accessibility-extra-large "Search" was breaking to three lines inside its capsule — this was
  already true before this pass, with the longer title "Collection". What gives now is the title,
  which takes `lineLimit(1).minimumScaleFactor(0.6)` and scales down; checked with the widest kind
  ("Books") selected at that size, everything holds one row.

Seen in the simulator: light and dark, grid and list, menu open and closed, at medium and
accessibility-extra-large. `swift test` → 444 passed; `scripts/build-app.sh` → `** BUILD
SUCCEEDED **`. **Not seen: any of it under a real finger** — the Mac's screen capture is blocked
here, so no tap could be driven; the open/pick/dismiss path is reasoned, not exercised. First
thing to check on the phone: that a tap on the shelf still opens a book with the menu closed.

## Resume here (2026-09-10) — the share bug, the veil behind the page, the skip pill on any book

Five things from the phone.

- **A shared EPUB was being read as a web link** (owner: "why is it confusing book upload with url?").
  `ShareImportService.importItems` asked `hasItemConformingToTypeIdentifier(UTType.url)` **first**,
  and a file shared out of Files declares `public.file-url`, which *conforms to* `public.url` — so
  every shared book went down the link path and `ImportModel.fetch(link:)` rejected its `file://`
  scheme with "That doesn't look like a web address." Now EPUB and PDF are asked about before URL,
  and a file URL that still reaches the link branch is imported as a file when its extension is
  `epub`/`pdf`. **Kind before container.** Not yet retested from a phone's share sheet.
- **The warm-up veil sits behind the page now**, in two layers (`Design/WarmUpVeil.swift`):
  `.behind` is the whole wash at the back of the host's stack — over the ground, under the text —
  and `.chrome` redraws the same gradient in front of the ground bars that mask the status bar
  (`TopFade` on the root, the Reader's header fade), clipped to the status band and faded out over
  `TopFade.fadeHeight` so the two meet without a seam; the message and progress hairline ride on
  `.chrome`. Both layers take their pulse from the wall clock (`pulse(at:)`, a 3 s cosine, 0.38 → 1)
  rather than their own `@State`, so they breathe in step. **For any of that to show, the three root
  pages gave up their own `Tokens.ground`** — `RootPager`'s `.background` is the one ground for all
  three now, and `QueuePage`'s rows are `.listRowBackground(Color.clear)`. Verified in the simulator
  that an unwarmed Home and Collection are pixel-alike to before.
- **The veil was landing in the middle of the Reader's text** (owner). Cause: `GeometryReader` +
  `.ignoresSafeArea(edges: .top)` on the *inner* stack measured a box that began below the status
  bar. `.ignoresSafeArea()` is on the GeometryReader itself now. Its proxy then reports zero insets,
  so the status band's height comes from the key window instead (`statusBandHeight`).
- **The veil goes when sound does** (owner: "my book is playing sound and the glow is still
  happening"): `isVisible` is `isWarming && !(isPlaying && !isCatchingUp)` — a tapped Play still
  stalled keeps the wash, a book actually speaking loses it. `T2S_WARMUP=1` bypasses that, since a
  faked warm-up has to show over the fixture book for screenshots.
- **Colour and motion** (owner: start higher, more orange up top, a plainer pulse): coverage 0.5 →
  0.58 of the screen, the top stop 0.26 → 0.55 held near-peak (0.42) to 20 % before it falls away,
  and the pulse 1 ↔ 0.5 over 1.8 s → 1 ↔ 0.38 over 3 s.
- **The chapter picker sits lower**: the gap under it went from the bottom bar's 10 pt stack spacing
  to 2 pt (the stack is `spacing: 0` with explicit 10 pt gaps elsewhere).
- **"Skip to Chapter 1" now finds the body in books that never number a chapter** (owner uploaded
  *Thinking in Systems* and saw no pill). `ChapterLabel.bodyStart` returns `(index, number: Int?)`
  and reads two ways: a numbered heading as before, now also "Part One", "Section 2", a bare
  "One: …" or "I. …"; failing that, it walks the **front matter** (`frontMatterTitles`, matched on
  the whole title or the head before a colon/dash, so "Introduction: The Systems Lens" counts and
  "Contents of the Vault" does not) and points at the first title past it with `number` nil — the
  pill then reads **"Skip the front matter"**. "Prologue" is deliberately not front matter.

`swift test` 444/81 green (six new `ChapterLabelTests` cases; the old "no numbered chapter at all"
nil case is now the fallback's job and was rewritten). `scripts/build-app.sh` → `** BUILD SUCCEEDED
**`. Seen in the simulator (`T2S_WARMUP=1`): the wash from the very top of Home behind the title and
covers with the line and bar under the status bar, the same in the Reader behind the text, the
picker lower, and both pages unchanged unwarmed. Not seen: the real warm-up on a phone, the share
sheet with a book, the pill on the owner's book.

## Resume here (2026-09-10) — the warm-up veil, the team that kept resetting, picker round 7

Three asks from the phone, plus one mid-turn ("remove the heart from the Reader's voice sheet").

- **The warm-up veil** (`Design/WarmUpVeil.swift`, from Tabby's launch gradient): while
  `KokoroStatusModel.status.isWarming`, a soft accent wash over the top half of every root page
  (opacity 0.26 → 0, breathing 0.5 ↔ 1 over 1.8 s, still under Reduce Motion) and, under the
  status bar, one line — "Warming up the voice · about 7 s" / "· a few minutes the first time" /
  "· almost there" — over a 120 × 3 pt progress hairline. The Reader gets the wash only
  (`showsMessage: false`; its transport already says "preparing the voice…"). Nothing is
  hit-tested. **The progress is real**: `KokoroCoreMLModels.loadStages` takes an `onProgress`
  `(loaded, total)`, `KokoroCoreMLEngine.setLoadProgress` installs it, `GatedKokoroCoreMLEngine
  .preload(onProgress:)` passes it, and `warmUp` writes it to `KokoroStatusModel.updateWarmUp`.
  **The estimate is remembered**: `recordWarmUp(seconds:)` stores the last warm-up in
  `UserDefaults` (`kokoro.lastWarmUpSeconds`; a value over 4× the previous is ignored as a stall,
  and a first launch after install — no stored value — is what "a few minutes the first time"
  means). The bar is the larger of stages/8 and elapsed/expected (capped at 0.92). So: yes, the
  time can be estimated (from the last run) and the stages give a true progress; the first launch
  after install is the one that can't be predicted, and says so. `T2S_WARMUP=1` fakes a warm-up
  in the everyday build for screenshots (12 s remembered, a stage every 1.5 s).
- **Why the team kept going back to None**: `scripts/build-app.sh` runs `xcodegen generate`, which
  rewrites the git-ignored `project.pbxproj` from `project.yml`; a team picked in Xcode's Signing
  panel lives only in that file, so every build-script run (every code change from here) lost
  it. The pin in `project.yml` was dropped on 2026-09-09 because Xcode showed it red while not
  signed in. Now: `App/Local.xcconfig` (git-ignored) holds `DEVELOPMENT_TEAM`, `project.yml`
  wires it into every target with `configFiles`, both build scripts create it from
  `Local.xcconfig.example` if missing, and this Mac's copy already carries `5HZ38K43M9`. A
  regenerate keeps it. Not verified from Xcode's panel (no Xcode GUI here) — if the panel still
  shows None after the next regenerate, the setting is still applied at build time from the
  xcconfig; check `xcodebuild -showBuildSettings | grep DEVELOPMENT_TEAM`.
- **Picker round 7**: `RadioMark`'s ring is `ink2` at 2 pt and its check 12 pt heavy (the heart
  outline's weight); the "Default" tag is `Tokens.tagBlue` / `tagBlueInk` (light blue, dark blue
  text); `GenderMark`'s Venus is redrawn on a taller canvas (ring 0.3 w, a stem as long as the
  ring, the bar at 58 % down it); the pause glyph is `ink`, not accent; and `VoiceListPage
  .showsFavorites` is false from `VoiceChangeSheet`, so the Reader's sheet is hear + choose.

`scripts/build-app.sh` → `** BUILD SUCCEEDED **`; `scripts/build-device.sh` (the Phone scheme,
which is what compiles the `T2SKokoro` changes) → `** BUILD SUCCEEDED **`. Seen in the simulator
(`T2S_WARMUP=1`): the veil on Home with the line and the bar advancing, the wash alone in the
Reader, the sheet without hearts. Not seen: the real warm-up on the phone, the stage count
arriving, the remembered estimate, the redrawn ♀ (system voices carry no gender).

## Resume here (2026-09-10) — voice picker round 6, from the first phone look: twelve asks

The owner installed round 5 on the phone (Kokoro rows visible at last) and sent twelve items. All
on `dev`:

1. **Settings subpages own the screen.** No page swipe under them, no mini-player. First cut
   wrapped the whole pager in one `NavigationStack` so a push covered everything — but a paged
   `TabView` inside a stack hands its pages 20 pt less top inset than the screen has (measured:
   root titles 17 pt higher than the pushed page's; `safeAreaPadding` back made it worse), so that
   is reverted. Instead: `Root/Chrome.swift` — an `@Observable` `Chrome` (`subpageDepth`) in the
   environment; `.settingsSubpage()` (`Design/SettingsSubpage.swift`) counts itself in and out on
   appear/disappear; `RootPager` drops the bottom fill, mini-player and page dots while it is
   open; and **`PagerLock`**, a `UIViewRepresentable` in `PreferencesPage`'s background, walks up
   to the nearest `UIScrollView` — the page controller's queuing view — and sets
   `isScrollEnabled` false. Introspection, but small and re-applied on every update.
2. **Subpage titles at the root titles' height**: `.settingsSubpage()` hides the system bar and
   draws its own back circle (top-left, 12 pt under the safe area); `PageTitle` then sits at
   `titleTop` exactly as on the root pages (measured 126 pt on all three). The edge swipe back
   survives the hidden bar through a `UINavigationController` extension in the same file
   (`interactivePopGestureRecognizer.delegate`, allowed past the root only). Applied to Voice,
   Storage, Cloud voices, Pronunciation.
3. "On-device voices" group header gone (System / Cloud headers stay).
4. Voice filter chips are `Pill`s again (the tabs stay on the Collection).
5. **No "Default" row.** `VoiceListPage` filters `isDefault` rows out and puts a "Default" tag
   after the name of the voice that plays by default (`preferences.defaultVoiceID`, else the
   device's resolved default). In the Reader, choosing the tagged voice stores `nil` — the
   document follows Settings again, which is what the row used to mean.
6. **Heart** (`HeartButton`, `Design/GenderMark.swift`): 24 pt like the radio, red top-lit
   gradient with a gloss and a shadow when filled, outline `ink2` when not, and a spring pop
   (×1.3) on filling.
7. **The bar rises on a choice.** `VoiceListPage` now owns `pending`; a radio (or the name) sets
   it, and a `BarButton` slides up from the foot — "Make default" in Settings, "Change voice" in
   the Reader — with an optional note line ("Replaces 12m of rendered audio…"). New signature:
   `VoiceListPage(current:confirmLabel:note:onConfirm:)`; `onConfirm` is async and returns whether
   it applied. `VoiceChangeSheet` is that plus the dismiss.
8. **Personalities de-warmed**: `KokoroVoiceCatalog.personalities` had "Warm" in 12 of 28 lines;
   now none, each reworded from the same listener profiles (Heart "Breathy, Intimate and Tender",
   Emma "Inviting, Rounded and Gracious", Santa "Deep, Jolly and Grandfatherly"…). Tests updated.
   Still not heard by anyone here.
9. **A waveform button** before the heart plays the voice (pause glyph in accent while playing, a
   spinner while rendering).
10. **No avatar discs.** A drawn ♀ / ♂ (`GenderMark`, `Canvas` strokes, pink / blue) sits after the
    name. Only voices with a gender (Kokoro) get the heart.
11. Accent headers ("American English") at `groupTitle` weight, a section's air above and 20 pt
    below.
12. Cloud: answered in the summary to the owner, nothing built — one row per configured provider
    voice, no gender, no traits, no filter; a provider library would need its own list.

`scripts/build-app.sh` → `** BUILD SUCCEEDED **`; `swift test --filter KokoroVoiceCatalogTests`
6/6. Seen in the simulator (system voices only): the Voice subpage with the back circle, no bar
underneath, waveform + radio per row; titles measured equal on Home, Settings and Voice. Not seen:
the pager lock (cannot swipe by script), the Kokoro rows with marks, tags, hearts and pills, the
bar rising, the heart's pop. Owed a phone look.

## Resume here (2026-09-10) — voice picker round 5: a radio per row, the avatar plays, no "Change" mode

The owner sent two Mobbin references (Beside's "Choose Voice": name, language chips, traits, a radio
per row; Uptime's "Change your default voice": name, play + waveform per row, a radio, one
"Select voice" bar) and asked for ways to make voice selection better in Settings and in the Reader.
What both references do that rounds 1–4 never did: **each row shows its two verbs as two controls**,
so nothing has to be a mode. Done on `dev`:

- **`VoiceListPage`**: the avatar (44 pt, initial, gender tint) carries a small ink **play badge** at
  its foot and is the *hear* button — pause while that voice plays, a spinner while it renders. The
  name through to the end of the row is the *choose* button, ending in a **`RadioMark`** (new in
  `Primitives.swift`: an `ink3` ring, or an ink disc with a check) — Beside's mark in this palette.
  The heart stays between them, Kokoro or not. The "Change" / "Done" pill, `isChanging` and the
  hint line are gone. The Kokoro filter chips were `FilterTabs` (since deleted with the Collection's tabs; nothing references it now).
  New parameter `confirm: Confirm?` — nil applies on the radio's tap (Settings); set, the radio
  moves and a `BarButton` at the foot applies, with an optional note line above it.
- **`VoiceChangeSheet`** is one screen: the picker with `confirm` — "Change voice", grey until the
  radio is off the document's current voice, "Replaces 12m of rendered audio; it renders again
  with the new voice." above it when there is audio to lose — and the sheet's grabber to leave.
  The second "Rendered audio will be replaced" page, its Keep/Change pills and the toolbar Done are
  gone. `pending` is the radio's choice; `apply` writes it through `env.voiceChange.apply`.
- **`BarButton`** (`Primitives.swift`) is the pinned bar from the import steps, extracted;
  `ImportFrame` uses it.
- Screenshot hooks: `T2S_OPEN=voices` (Settings with the list pushed, `PreferencesPage.showVoices`
  via `navigationDestination`) and `T2S_OPEN=voice` (the Reader with the sheet up).
- Left alone on purpose: the system blue "Back" on the Settings page (every Settings subpage uses
  it); the reference's bar-with-back-circle would be a Settings-wide change.

`scripts/build-app.sh` → `** BUILD SUCCEEDED **`. Seen in the simulator (system voices only, no
Kokoro rows, no filter tabs): the Settings list with radios and play badges, the Reader's sheet with
the grey "Change voice" bar. Not seen: a radio moving and the bar turning ink, a preview playing,
the Kokoro tabs. Still nothing on a phone — and this picker is now five rounds blind.

## Resume here (2026-09-10) — top fade, no Autoplay row, Collection tabs with Text and Links, ElevenReader-style import steps

The owner's four-item batch after the shelf change, with ElevenReader (via the Mobbin MCP,
flow "Importing an article (website link)") as the reference for the last one.

- **Top fade** (`Design/TopFade.swift`): the root pages' content scrolled up under the status bar
  and was cut dead by it — a row's title under the clock. Now solid ground through the top inset
  and a 30 pt eased fade below it (`fadeHeight`, a sixth of the bottom bar's; the same
  smoothstep-squared ramp as `RootPager.bottomFill`, mirrored), drawn over the pager in
  `RootPager` and over the Import cover's hub and steps. Owner's word: "not very intense or
  tall". Cannot be seen in a script-driven screenshot (nothing scrolls); the code is the same
  shape as the bottom fill that was seen.
- **Autoplay next** is gone from Settings (owner's call). `ReaderPreferences.autoplayNext` and
  `QueueContinuation` are untouched underneath — default `true`, so a finished book still hands
  over to the next on Home. Take the preference out too if the owner never wants it back.
- **Collection: everything imported, five tabs, no pills.** `LibraryModel.collection` is every
  summary now (spec §2.3 kept articles on Home; with Home down to three there is nowhere else for
  an article to live). `CollectionPage.Filter` gained `text` (an article with no `sourceURL`,
  i.e. pasted text) and `links` (one with a URL). The chips were `Design/FilterTabs.swift` — words with a
  sliding 2 pt bar, after the owner found pills "too similar to search"; superseded on 2026-09-10
  by the title's own kind menu, and the file is gone. `ShelfArt` (private, in
  `CollectionPage.swift`) puts an article on the shelf slot as a flat square — its image, else
  `link` / `text.alignleft` on `surface` — the way the Home row draws one; books unchanged.
  **Not seen with an article in it**: the simulator library has none and a script cannot type
  one; the book sheet still opens for an article and draws it as a placeholder book — worth a
  flat hero or a straight-to-Reader tap, not done.
- **Import steps** (`Import/ImportFrame.swift`, `ImportAction`): each path is its own step — a
  back circle (an × when files came in from another app and there is no hub), the step's title
  centred in a bar, the path's field bare on the ground, and one full-width bar pinned to the
  foot as a `safeAreaInset` (so it rides the keyboard): ink when it can be pressed, `surface` +
  `ink2` while there is nothing to act on, a spinner with "Fetching…" / "Importing…" while the
  model works. `PasteLinkPage` ("Paste website link"): address prefilled from the clipboard, a
  hairline tip card ("open any page in Safari and use Share" — the extension is "Add to t2s"),
  and Listen fetches then **imports straight away** unless the extraction is thin
  (`isThinPreview`), in which case the title, word count and warning show and the bar says
  "Listen anyway". The Reader that opens on the result plays it — that is ElevenReader's flow.
  `PasteTextPage` ("Write text"): bare title line, `TextEditor` with a placeholder, grows with the
  page (`scrollDisabled`). `FileImportPage` ("Upload a file") wraps the rows with "Choose files"
  at the foot. The hub's third tile is "Write text" now. Screenshot hooks: `T2S_OPEN=import`,
  `link`, `text`, `files` (`RootPage.launchImportPath`, opened from the Collection page).

Tests: `swift test --filter LibraryModelTests` 8/8 green. `scripts/build-app.sh` → `** BUILD
SUCCEEDED **`. Seen in the simulator (iPhone 16 Pro, `T2S_SILENT=1`): Collection with the five
tabs, Settings without the row, the Import hub, the link, text and file steps. Not seen: a fetch
or an import going through the new bar (no network on the script), an article on the shelf, the
fade over scrolled content. Nothing on a phone.

## Resume here (2026-09-09) — books stand on one shelf on Home and in the Collection

The owner put the Collection grid and Home side by side and asked whether the books were the
same size — they were not, and it looked like inconsistency. Two real causes: the grid's cover
height came from its column width (~130 pt on a 16 Pro) while Home's was 112, so the same book was
a different size on the two pages; and the Home row had no fixed slot for the book, so a wider
cover pushed its whole text column right and the rows' left edges went ragged. The owner asked
whether making every book one identical rectangle would be better; the push-back (cropping cuts
cover lettering, padding looks broken, and Apple Books / Kindle / Libby all keep real proportions
on a fixed-height shelf) was accepted. So, in `Design/Primitives.swift`: `BookCover.shelfHeight`
(120) is the one height for Home and the grid, and `BookCover.shelved` puts the book bottom-leading
in a slot `widestRatio` (0.8) wide — the widest a real cover is ever let be, so nothing shrinks —
which the Home row (`Queue/QueueRow.swift`), the grid tile and the 88 pt list row
(`Collection/CollectionPage.swift`) all use. `maxWidth` on `BookCover` and the tile's
`GeometryReader` + `aspectRatio` slot are gone with it. Covers keep their own proportions; only the
fore-edge moves. `scripts/build-app.sh` → `** BUILD SUCCEEDED **`. Seen in the simulator (iPhone
16 Pro, `T2S_SILENT=1`; `T2S_PAGE=collection`, `-collection.layout list`): Home's three rows share
one text-column x and one baseline; the grid's books are the same height as Home's; the list's
text column holds still. Not seen on a phone.

## Resume here (2026-09-09) — the tilt made bolder, then eased back a step

The owner tried the book sheet's gyro tilt (added the round before) and called it "too subtle".
`System/MotionTilt.swift`: `TiltFilter.scale` 0.35 → 0.9 and `limitDegrees` 3 → 10, with matching
bumps in `Design/Primitives.swift`'s `BookCover` (shadow lean multiplier 0.4 → 0.5,
`rotation3DEffect`'s `perspective` 0.5 → 0.7). The owner then said "slightly less intense" without
having seen either cut on a phone — both were tuned blind, so this is a compromise, not a
measurement. Settled at `scale` 0.65, `limitDegrees` 7 (a 10° tip of the phone now turns the book
6.5°), shadow multiplier 0.45, perspective 0.6 — roughly midway between the original and the bold
cut. No test exercises `MotionTilt` (it wraps `CMMotionManager`, which reports nothing on the
simulator), and the simulator cannot show a tilt at all — this whole three-step tuning is
unverified until the owner is back on a phone. `scripts/build-app.sh` → `** BUILD SUCCEEDED **`.

## Resume here (2026-09-09) — Book sheet rework, no queue, chapter list spacing

The owner's second batch of the evening, on `dev`, straight after the chapter-sheet round below.

- **There is no queue any more, as the reader sees it.** Home ("Continue Listening") is the books
  played most recently, latest on top, three at most: `LibraryModel.notePlaying(_:)`
  (`recentLimit = 3`) puts a book on top — back out of finished if it was — and archives whatever
  falls past the limit; a no-op with no refresh when the book is already on top. `RootPager` calls
  it whenever `player.state` becomes playing/catching up with a current document. The store's
  queue calls (`setQueued`, `moveInQueue`, `finish`) are unchanged underneath — an import still
  appends to Home, and the Reader that opens on it plays, which trims. Gone from the UI: the Book
  sheet's In Queue / Add to Queue pill, the Collection menu's Add to / Remove from Queue, the Home
  row's Move to top (recency is the order now). Home's Archive (swipe and menu) stays as the way
  to drop a book from Home. Wording: "Nothing playing yet." (`EmptyQueue`), "Home keeps the ones
  you played last" (Collection's empty text). Tested in
  `LibraryModelTests.notePlayingKeepsTheThreeLatestOnTop`. `LibraryModel.queue`, `move`,
  `enqueue`, `QueueContinuation` and Now Playing's queue count are still there for the model and
  the lock screen; the spec's §2.3 queue wording is now behind the app.
- **Book sheet** (`Collection/BookSheet.swift`): the book at 200 pt (was 240) over a **backlight**
  — an ellipse of the cover's own colour, blurred 44 pt at 0.7 — from `BookCover.backlight`: the
  cover's `CIAreaAverage`, lifted in saturation and brightness so a dark or greyish cover still
  glows, cached per path; `pdfCover` for a PDF, `ink3` for the placeholder. **The gyro tilt is
  back, on this sheet only**: `System/MotionTilt.swift` restored from 46432a4 unchanged (relative
  baseline, ±3°, 30 Hz), owned by the sheet as `@State`, on while the sheet shows and the scene is
  active, off under Reduce Motion, thermal or Low Power, and on `onDisappear`; `BookCover.tilt`
  (rotation3D + leaning shadow) is back for it — the Home rows do not pass one and must not
  (owner's earlier ruling). Title and author centred; the "7 chapters · ~59m · Rendered 2%" row is
  gone; one **Play pill in the Home row's form**, centred — `soft`, "Play  17m" with the resume
  chapter's time left (duration × (1 − fraction), so no glimpse needed), "Pause" while this book
  plays, "Starting…" while resuming a paused current one.
- **`ChapterListView`** (`Player/ChapterList.swift`): the "Chapters" heading and its rows as one
  component — heading role per caller (`playerTitle` in the sheet, `sectionHeader` in the Book
  sheet), 24 pt under the heading, rows 10 pt of vertical padding (was 8), 4 pt between title
  and time (was 2). `ChapterList` and `BookSheet` both use it.

Tests: `swift test` 442/81 green. `scripts/build-app.sh` → `** BUILD SUCCEEDED **`. Seen in the simulator (`T2S_OPEN=book`, `T2S_BOOK=children` and `mughal`;
`T2S_OPEN=chapters`): the book sheet on a real cover and on the placeholder, the chapter sheet's
spacing. The first cut of the backlight pushed a near-white cover into pink — an average with almost
no saturation lifted to 0.35 lands on whatever hue its noise leans — so a near-grey average now
stays neutral. The tilt cannot show on the simulator (no device motion); `notePlaying` is tested,
not watched on Home. Still nothing seen on a phone this week.

## Resume here (2026-09-09) — Chapter sheets, the skip pill, and a bookmark that keeps its sentence

The owner's six asks from two phone crops (the Book sheet and the Reader's chapter list), done on
`dev`, plus a mid-turn ruling: **a bookmark saves the playhead position and the block of text**.

- **One chapter row everywhere** — `ChapterRow` (`Player/ChapterList.swift`): the title in
  `settingsRow` (16) over the length in `pill` (15, `ink2`) — the title a step down and the time a
  step up from before, 2 pt apart, rows 8 pt tall in padding with no gap between them; the current
  chapter on a `surface` fill with the 18 pt ring, chapters before it a **`positive` green check**.
  The Reader's `ChapterList` heading is `playerTitle` now (26 ExtraBold, the Bookmarks sheet's).
  `BookSheet` draws the same rows instead of its play-circle + progress-bar rows: the chapter the
  book would resume in (`first { fraction < 1 }`) wears the ring, the ones before it the check, and
  a tap still loads, seeks, plays and opens the Reader. Its "Chapters" header stays `sectionHeader`
  — it is a section of a page, not a sheet's title.
- **Chapter picker row** (`ReaderPage.chapterRow`): the up-arrow is an `HStack` sibling 8 pt off
  the title, centred on its height, in `ink` — no longer a text-run glyph on a baseline offset.
- **"Skip to Chapter 1"** — `ChapterLabel.bodyStart(titles:)` finds the first chapter whose title
  starts with a number or reads "Chapter 1 / One / I" (any case; "Chapters of My Life" does not
  count); nil when none, or when it is the first chapter. `ReaderPage` reads it once per document in
  `open()` and, while `player.chapterIndex` is before it, shows a `selected` pill in the
  Back-to-current slot ("Back to current" wins when both apply). It goes with the chrome, so a tap
  on the text dismisses it; a tap seeks to that chapter and it disappears on its own. Tested in
  `ChapterLabelTests`.
- **The bookmark button moved to the tool row's right**, where the contents circle was (the
  chapter row already opens the list; the overflow menu still has "Chapters"). The header is back
  · title · overflow, the title clear of one circle each side. It is a **toggle**:
  `PlayerModel.toggleBookmark()` removes the bookmark on the utterance under the playhead when
  there is one, adds one otherwise; `isBookmarkedAtPlayhead` (from `bookmarkedUtterances`, read
  from the store at `load`, kept by add/toggle, cleared by `unload`, refreshed after a delete in
  `BookmarkListModel`) fills the glyph while the playhead is inside a bookmarked sentence, so it
  shows filled again when you scrub back to one. Before, the glyph filled on save and cleared on
  the next playhead tick, and every tap added another bookmark.
- **What a bookmark is now.** `addBookmark` stores the utterance's `source` — the sentence the
  playhead is in — in the bookmark's `note` column (present since schema V1, never used, so no
  migration). `BookmarkListModel` shows that block from its start; an older bookmark without it
  still shows the timeline's text from the bookmark's own word. Answered the owner's question on
  the way: the Reader has no text selection (`ReaderTextView` sets `isSelectable = false`), so a
  bookmark could never have saved "selected text"; it was the playhead position alone.
- **`T2S_OPEN`** (`RootPage.launchOpen`, screenshots only, beside `T2S_PAGE`): `reader`, `chapters`
  (the Reader with its list up) or `book` (the Collection's book sheet) on the first document whose
  title contains `T2S_BOOK`, else the first. The fixture used for this round is generated, not
  committed: a seven-section EPUB (title page, dedication, reviews, introduction, "1 A Chessboard
  King" …) so the skip pill has front matter to skip — a real book with the same shape is the
  owner's *The Last Mughal*.

Tests: `swift test` 441/81 green (three new `PlayerModelTests`, two new `BookmarkListModelTests`,
three new `ChapterLabelTests`). `scripts/build-app.sh` → `** BUILD SUCCEEDED **`. Seen in the simulator (iPhone 16 Pro, the generated fixture imported with the
`openurl` recipe, `T2S_SILENT=1`): the Reader with the skip pill, the chapter row and the bookmark
at the bottom right; the chapter sheet; the book sheet. The bookmark toggle's fill and removal are
covered by `PlayerModelTests`, not tapped — still nothing seen on a phone this week.

## Resume here (2026-09-09, latest) — Collection round: books, a list, menus, a kind filter

The owner's four asks for the Collection page, done on `dev` in `Collection/CollectionPage.swift`:

- **The grid's tiles are books.** Each cell is the Home row's `BookCover` (the Figma softcover with
  hinge, sheen and shadow) at the foot of a cover-proportioned slot — `BookCover.ratio` is internal
  now and the cell's `aspectRatio` is it, cells are top-aligned so every book in a row stands on
  the same shelf line, and `BookCover` gained `maxWidth`: a cover wider than the placeholder's
  proportion shrinks to the cell width keeping its own, so it is shorter, not clipped. No progress
  bar under a tile; the title (`meta`, `ink`, two lines) and the author (`meta`, `ink2`, one line)
  are. PDFs get the red PDF book. The book sheet's hero is the same `BookCover` at 240 pt, so a tap
  on a book opens onto that book, not a square of it.
- **Grid or list** (`ReaderPreferences.collectionLayout`, `CollectionLayout` grid / list, key
  `collection.layout`, default grid, tested). The switch is a 36 pt `surface` circle at the right
  of the chip row showing the layout a tap switches to (`list.bullet` / `square.grid.2x2`). A list
  row is an 88 pt book, the title in `rowTitle`, author, and "12 chapters · ~5h 10m" in the book
  sheet's words, with the Home row's `⋯` circle at the trailing edge.
- **One menu three ways**: long-press on a tile (with a `preview:` of the book alone at 240 pt, so
  the shadow is not cut off at the cell's edge), the row's `⋯`, and long-press on a row. Items:
  Play (resumes a paused current book before opening the Reader, as the Home row does), Add to /
  Remove from Queue, Mark as finished / unfinished, Details (`DetailsSheet`), Change voice, Render
  whole document, Delete. **Every delete now goes through `AppEnvironment.deleteDocument`** and asks
  first (`confirmationDialog`, `AppEnvironment.deleteMessage`) — the Details sheet's pill too, which
  used to delete on the spot. If the document is the loaded one, `PlayerModel.unload()` (new) drops
  it first: `PlaybackCoordinator.unload()` resets the player, clears the plan with the same idle
  accounting as `replan`, and returns to `.idle` with no document or timeline, saving nothing — the
  playhead row goes with the document. Before, a deleted book stayed in the mini-player and a tap
  played it from memory, then `persistRenderedChapters` threw on the missing row. Tested in
  `PlayerModelTests.unloadForgetsTheDocument`. Known gap: a delete that lands while that same
  document's `load` is still awaiting its timeline is not caught (`current` is set only after).
  Home's context menu still calls the same action "Archive" where the Collection says "Remove from
  Queue" — one word app-wide is owed.
- **`CircleGlyph`** (`Design/Primitives.swift`): the 36 pt `surface` circle with a 15 pt semibold
  glyph, as a label so a `Button` and a `Menu` can both wear it. The Collection uses it for `+`, the
  layout switch and the rows' `⋯`; `ReaderPage.icon`, `QueueRow`, `MiniPlayer` and `ImportPage`
  still inline the same circle and could move onto it. `Spacing.artworkLarge` is gone (no users).
  Tiles have `.contentShape(Rectangle())` and `.accessibilityActions` with the menu's items, so
  VoiceOver reaches what a long press does.
- **Kind chips** — All · Books · PDFs — in the voice picker's filter-chip style, above the grid.
  Articles are not in the Collection (spec §2.3, they live on Home) so there is no chip for them.
  Search now matches the author too. The "N books" subtitle under the title is gone (owner's
  call): the chips and the shelf say what is here.
- **`T2S_PAGE`** (`RootPage.launchPage`): `SIMCTL_CHILD_T2S_PAGE=collection` (or `preferences`)
  opens the app on that page — a script-driven simulator cannot tap the indicator, and this is how
  the screenshots for this round were taken. A preference can be forced for one launch as an
  argument: `xcrun simctl launch <udid> com.t2s.reader -collection.layout list` (`defaults write`
  through `simctl spawn` did not reach the app's `UserDefaults.standard` this time).

Seen in the simulator (iPhone 16 Pro, two EPUBs and a PDF) in both layouts; the menus, the
dialog and the chips' tap paths were reviewed, not tapped. `scripts/build-app.sh` → `** BUILD
SUCCEEDED **`; `swift test --filter ReaderPreferencesTests` passes.

## Resume here (2026-09-09) — Reader round: fades in the bars, Apple Music scrubber, sizes, chapter row, title, highlight themes

**Footnote numbers are no longer spoken (2026-09-09, normalizer 3 → 4).** The owner noticed
sentences ending "me'.18" — an EPUB's superscript footnote reference flattened into the text. Two
problems: the number was read aloud, and `NLTokenizer` sees no sentence boundary in
"Daryaganj.14 The presence", so the pause vanished too. `StripCitationsRule` (rule 3, the "[14]"
rule) gained a `footnotes` pattern: one to three digits straight after sentence-final punctuation
(closing quotes/brackets allowed between), followed by a capital or the end of the utterance. A
digit *before* the punctuation ("3.14 dollars", "v2.0 The") or a lowercase word after ("p.14 for",
"Fig.3 shows") is left alone. Known miss: a year before the footnote ("in 1857.18 Then") keeps the
number, by the same digit-before guard. Tests in `StripCitationsTests` and `TextNormalizerTests`.
**`Versions.normalizer` is bumped to 4**, unlike Plan 16's dictionary change: every footnoted chapter
of a book says these numbers, so the fix has to reach the owner's current book, and a bump is the
only path there. The cost is the designed one — each document re-derives from its retained chapters
on next open (fast; no Readium pass) and its cached audio is removed in the background
(`Library.reprocess`, `keysChange`), then re-rendered on play or by Prepare. Resume positions
survive (they are `Position`s, not utterance indices). **Gotcha when bumping a version:** after
the bump, `swift test` failed three `LibraryStoreTests` with stored timelines still at normalizer 3
even after deleting `T2SCore.build` — `Timeline.init`'s default argument `normalizerVersion: Int =
Versions.normalizer` is a generator SwiftPM's incremental build did not recompile, so
`Timeline(chapters:)` kept returning the old number while `Versions.normalizer` read 4 in the same
process. `swift package clean` and a full rebuild fixed it (431 tests, 80 suites). Run the clean
after any `Versions` change before trusting the suite.


The owner's Reader pass, from a phone screenshot plus three references (an Apple Music scrubber,
Speechify's highlight-theme swatches, a podcast app's "Intro ▾ … →" chapter row). Six asks, done on
`dev` with two agents (scrubber + transport; highlight themes) and the page itself by hand:

- **The fades moved into the bars** (`Reader/ReaderPage.swift`). Before, the header was a solid
  150 pt block with a fade hanging below it over the text, and the bottom block had 40 pt of fade
  above the controls; the owner read that as "the fade is in the text". Now each bar's `ground`
  fade lives inside its own band: the header is solid at the status bar and clear by the circles'
  foot; the bottom block is clear at the chapter row and solid by the transport (`groundFade(
  solidAtTop:span:)` — smoothstep over twelve stops, the Home bar's lesson, so neither edge draws a
  line). `ReaderTextView.insets.bottom` 240 → 304 for the taller block.
- **Scrubber** (`Reader/ThinScrubber.swift`): no knob; one 6 pt capsule that springs to 12 pt while
  pressed (`dragFraction != nil`). Played part `ink`; ahead of it the render-frontier ticks survive
  as `ink2` (rendered) / `ink3` (not yet). Only the height animates — the seek is async, so on
  release the fill would otherwise spring back to the stale fraction and jump.
- **Transport sizes** (`Reader/ReaderControls.swift`): play 34 pt glyph in 64 (was 26 in 56), skips
  26 in 52 (was 20 in 44), sleep timer unchanged at 20 in 44, speed label on a new `TypeRole.speed`
  (Inter-Bold 17, tabular digits) instead of footnote mono. Row height 56 → 64.
- **Chapter row** above the scrubber: "Chapter title ▾" (opens the existing `ChapterList` sheet) on
  the left, "→" (next chapter, `player.seek(toChapter:)`) on the right, hidden when the document
  has one chapter or none — the reference's row.
- **Document title** centred in the header (`.pill` role, one line, 92 pt clear of the circles on
  each side); the spec's "no title in the header" note is superseded.
- **Highlight themes** (`ReaderPreferences.highlightTheme`, `HighlightTheme` amber / sky / fall /
  marker / mint, key `reader.highlightTheme`, default `.amber` = the accent pair so nothing changes
  for existing readers; tested in `ReaderPreferencesTests`). Colours are `Tokens.highlightTint(_:)`
  / `highlightWord(_:)` — `Tokens.swift` now imports `T2SApp` for the enum. `ReaderTextView` takes
  `highlightTheme` after `highlight` and redraws the tint/word layers when it changes. The
  Appearance sheet gained a "Highlight" row of `HighlightSwatch` previews (three capsule "lines",
  the middle one under a tint band with a word box), 2 pt `ink` ring on the selected one, in a
  horizontal scroll that bleeds under the margin; the sheet scrolls and allows `.large`. The row
  shows in the Settings presentation too — it is an app-wide preference like Theme.

Verification: `scripts/build-app.sh` → `** BUILD SUCCEEDED **`; `swift test` → 428 tests in 80 suites passed. Not
seen on a phone — same standing gap.

**Back-to-current pill (2026-09-09):** it sat inside the bottom block's upward fade and under it —
the block is a later sibling in the page's `VStack`, so its background (hung 64 pt above itself)
painted over the pill. Now `.padding(.bottom, 32)` and `.zIndex(1)` on the pill: higher, and drawn
over the fade.

**Commit `43c9678` carries more than its message says.** It was staged with `git add App Sources
Tests` in the shared checkout and swept in another session's uncommitted Collection redesign
alongside the Reader fourth cut: `Collection/CollectionPage.swift` (kind chips All / Books / PDFs,
a grid ⇄ list switch, `CollectionTile` / `CollectionRow`, a Delete confirmation, author search),
`Collection/BookSheet.swift` (the sheet's art is now `BookCover` at 240 pt), `Design/Primitives.swift`
(`BookCover.maxWidth` so a wide cover fits a grid cell; `ratio` internal), `Root/RootPager.swift`
(`RootPage.launchPage` from a `T2S_PAGE` environment variable for scripted simulator screenshots),
`Sources/T2SApp/Preferences/ReaderPreferences.swift` (`CollectionLayout` + `collectionLayout`,
key `collection.layout`, tested). It built and the full suite passed (433/81), so nothing is
broken — but that work's author should know it is on `origin/dev` under a Reader message, and
whether it was finished is theirs to say. Not rewritten: `dev` is shared and pushed. Rule from
here: stage with explicit paths, never a directory, in this checkout. _Answered by the Collection
session: that sweep was the finished first pass; the review-fix pass on top of it (delete goes
through `AppEnvironment.deleteDocument` with `PlayerModel.unload`, `CircleGlyph`, the menu's Change
voice / Render whole document, tap shapes, VoiceOver actions) is its own commit after this one._

**Fourth cut (2026-09-09, four crops incl. Apple Podcasts' chapter list):** (1) The chapter row's
chevron is a filled up-arrow (`arrowtriangle.up.fill`, 10 pt bold) inside the text run with
`.baselineOffset(3)`, so it sits up by the cap height — the inline chevron still hung at the foot.
(2) Skips huddle with play as one unit (`HStack(spacing: 12)` in the middle of `ReaderControls`);
the sleep timer and speed label keep the ends. (3) Times sit 2 pt under the bar — `ThinScrubber`
aligns its bar to the *bottom* of a 40 pt hit area (finger lands above it) — in `.meta` Inter with
tabular digits, not the system mono; the right side is time *left* as "-14:22:21", no "~".
(4) The top bookmark button stays: it saves a bookmark at the playhead (`player.addBookmark()`),
listed under the overflow's "Bookmarks" — the owner asked what it does. (5) `ChapterList` rebuilt
after Podcasts: no dots, no progress bars; name over length ("1h 8m", no "~") with 12 pt inside
each row and 8 pt between; the current chapter on a `surface` fill (the reference's highlighted
row — an owner's ask, not a card) with an 18 pt `CircularProgress` of its fraction at the right
end; chapters already heard get `checkmark.circle.fill` in `ink2`; later ones nothing. Titles go
through `ChapterLabel`, whose rule changed: an unnumbered name ("Title Page", "Dramatis Personae")
is left as written — front matter is not "Chp 1". Tests updated.

**Third cut (2026-09-09, two phone crops):** (1) `ThinScrubber` draws each chapter as a flat
bar (square ends, 3 pt gaps — the Podcasts look); only the pressed chapter rounds and rises, and it
now also *widens* to at least 45 % of the bar (`activeShare`) while the others shrink in proportion
and dull, so the finger's travel across that widened bar maps onto that chapter alone (`scrub(to:
width:)`: pick the chapter under the finger from the current layout, switch, then map the local
position into the chapter's span). Precise in-chapter scrubbing for a 27-chapter book; still one
bar for PDFs and texts. (2) Chapter row: the chevron is now part of the text run (`Text(Image(…))`
concatenated), so it sits on the type's centre line; the label is `ChapterLabel.text(for:ordinal:)`
(`Sources/T2SApp/Player/ChapterLabel.swift`, tested) — "7 A Precarious Position" → "Chp 7: A
Precarious Position", a bare number or empty title → "Chapter 7", a name with no number → "Chp N:
name" from the ordinal, and a title that names itself ("Chapter 7", "Part Two", "Prologue") is left
as written. The regexes are built per call: `Regex` is not `Sendable`, so a static fails strict
concurrency. (3) Transport: play 44 in 72 and skips 28 in 52, both `.regular` so size ranks them,
not heft; the sleep timer (20 in 36) and the speed label (`rowTitle`, tabular digits, `minWidth`
36) are the small pair at the ends, both `ink2`, and the row has no side padding so their centres
line up with the tool row's circles below. `TypeRole.speed` is gone. (4) The header band is taller
(16 pt above and below the circles); `ReaderTextView.insets.top` 96 → 112.

**Second cut (2026-09-09, from a phone screenshot):** (1) the header's fade was invisible — it ran
from solid at the status bar to clear at the bar's own foot, so behind the title it was already ~13 %
ground. `groundFade` now takes `span` on both sides: the header is solid through the circles and
eases to clear over a fade that hangs 48 pt *below* the bar (`.padding(.bottom, -48)` in a
top-aligned background), and the bottom block's fade hangs 64 pt *above* it and is solid by the
chapter row's foot (`span: 0.25`), so the chapter picker sits on ground as asked.
`ReaderTextView.insets.bottom` 304 → 336. (2) The chapter row lost its "→" and its chevron sits on
the title's baseline (`HStack(alignment: .firstTextBaseline)`) instead of below the text's centre.
(3) `ThinScrubber` is chapter-segmented: `segments: [Range<Double>]` (from `ReaderPage.
chapterSegments`, chapter start/duration over `player.total`), one capsule per chapter with a 3 pt
gap, one unbroken bar for a document with fewer than two (PDF, text). Pressing thickens the chapter
under the finger to 12 pt and dulls the rest to half opacity through the mask's alpha; the drag
still maps 1:1 across the whole, the seek fires on release. (4) Transport: play 44 pt *regular*
weight in 72 (bigger, lighter), skips 32 in 56, row 72.


## Resume here (2026-09-09) — Home round 5: chapter time on Play, ring by the chapter, no gyro, bottom fill fixed

**Type pass (2026-09-09, after the Settings pass):** the Home row's title now uses `rowTitle`
(Inter-Medium 17 pt) — the owner wanted the Settings rows' face on the Continue Listening titles — so
`TypeRole.cardTitle` (its only user) is gone. Settings then stepped down a notch on its own: headings
`groupTitle` Inter-Bold 22 → 20 pt (relative `.title3`), and row titles moved off `rowTitle` onto a
new `TypeRole.settingsRow` (Inter-Medium 16 pt, relative `.callout`) so the two dozen other `rowTitle`
rows in the app did not shrink with them. Pills and subtitles on the page are unchanged.

**Settings pass (2026-09-09, after round 5):** from three phone crops. (1) The bottom fill's fade is
taller — `RootPager.fadeHeight` 120 → 180, `Spacing.bottomClearance` 168 → 232 to match. (2) The
Preferences page is titled **"Settings"** (`PageTitle`, and `RootPage.preferences.title` for the
indicator's label; the type stays `PreferencesPage`); its section headings use a new
`TypeRole.groupTitle` — **Inter-Bold 22 pt**, relative `.title2`. Inter-Bold was not bundled, and
the owner's call was to bundle it rather than substitute the Display ExtraBold: `scripts/fetch-fonts.sh`
now lists six faces, `App/Resources/Fonts/Inter-Bold.ttf` is committed (Inter 4.1, same OFL), the
shared `targetTemplates` entry in `App/project.yml` registers it under `UIAppFonts` (both
`Info.plist`s are generated from there and git-ignored — editing them directly is undone by the next
`xcodegen generate`, which is exactly what happened on the first try), and `docs/licenses.md` says
six TTFs. The explanatory row
subtitles are gone ("Seconds" ×2, "New documents start here", "Continue with the next queued item",
"Theme for the whole app", "Your provider, your API key"); subtitles that carry a value stay (the default
voice's name, the dictionary's word count, the storage size, "Coming later" under the disabled iCloud
toggle), and `row(_:subtitle:)`'s subtitle defaults to "". (3) A row title that wraps ("Rendered audio
and prepare on charge") was centred by SwiftUI's multi-line default; `row()` now sets
`.multilineTextAlignment(.leading)`. (4) The Appearance sheet did not follow a theme change made from
inside it: `preferredColorScheme` is applied to the root pager and full-screen covers, but a `.sheet`
is its own presentation and only takes the scheme when it opens. `AppearanceSheet` now carries
`.appTheme()` itself; other sheets open after the theme is set and inherit it, so they were left alone.

**Round 5 follow-ups (2026-09-09):** a "·" now separates "Chapter 7" from the ring and percent
(`QueueRow` meta line); and the bottom fill's opacity ramp is eased — smoothstep squared over twelve
stops (`RootPager.bottomFill`) — because the linear ramp that stopped dead at solid drew a visible
line across the screen (a Mach band), which the owner read as a "sharp cutoff". The title role the
owner asked about is `cardTitle`, then made "a bit smaller" on request: Inter-SemiBold 21 → 19 pt
(tracking stays −0.02 em), relative to `.title3`; only the Home row uses it.

**Signing note (2026-09-09, after round 5):** `DEVELOPMENT_TEAM: 5HZ38K43M9` is no longer pinned in
`App/project.yml` (either target) — the owner saw Xcode's Signing & Capabilities show it in red as
"Unknown Name (5HZ38K43M9)" and asked for it to go. The ID is the owner's own personal team (the one
`Apple Development: shubham123nayak@gmail.com (5HZ38K43M9)` identity on this Mac); the red name only
means Xcode is not signed in to that Apple ID. Consequence: a device build now needs the team picked
in Xcode's Signing & Capabilities, and because `xcodegen generate` rewrites `project.pbxproj` from
`project.yml` on every `scripts/build-app.sh` / `build-device.sh` run, that pick has to be made again
after each regenerate. The simulator script signs ad hoc and is unaffected (verified after the change).

The owner's fifth pass, from two phone crops (a "▶ Play  2h 28m" pill reference, and Preferences
showing a row's text visible *under* the page indicator). Done on `dev`:

- **Time on the Play pill** (`Design/Primitives.swift` `Pill.detail`, `Queue/QueueRow.swift`):
  "Play  2h 28m" — the label, then the time in the same type at 55 % of the pill's foreground (so it
  dims correctly on every style). Just the time: `DurationFormatter.remaining(_, approximate: false)`,
  no "left", no "~". Books with more than one chapter show **the chapter's** time left; an article
  or a single-chapter file shows the file's. Hidden while "Starting…".
- **Progress ring and percent moved beside the chapter**: the meta line is now
  "Chapter 7  ◔ 41%  ✓" and the separate "◔ 5% · 23 hrs left" line under the excerpt is gone. Same
  chapter-vs-file rule as the pill. For a chaptered book both stay hidden until its glimpse loads,
  rather than flashing the whole book's number first.
- **`LibraryModel.glimpse(for:)`** replaces `excerpt(for:)` as the row's one chapter decode and
  returns `RowGlimpse` (`excerpt`, `chapterElapsedSeconds`, `chapterTotalSeconds`, plus
  `chapterFraction` / `chapterRemainingSeconds`): the resume position resolved in a one-chapter
  `Timeline` gives chapter-relative times through `TimeIndex` for free. `excerpt(for:)` survives
  as a wrapper. Same cache, renamed. `LibraryModelTests` asserts the chapter numbers.
- **Gyro tilt removed** at the owner's request (round 4 had added it): `System/MotionTilt.swift`
  deleted, `AppEnvironment.motionTilt` and `RootPager`'s `shouldTilt`/`isUnderLoad` gone,
  `BookCover` lost its `tilt` parameter and both `rotation3DEffect`s; the shadow is fixed again.
- **Bottom fill fixed and softened** (`Root/RootPager.swift` `bottomFill(inset:)`). The round-3
  gradient — a fixed 210 pt frame under `ignoresSafeArea(.bottom)` — sat at the *top* of the
  safe-area-expanded region, so the home-indicator strip under the page row was left bare and a
  page's text showed through there. Now: a `GeometryReader` supplies the inset, the gradient's
  height is `120 + page row 32 + padding 8 + inset`, and it fills a `maxHeight: .infinity`
  frame aligned `.bottom` under `ignoresSafeArea`, which pins it to the screen bottom. Solid from the
  top of the page row down; above that a gentler fade (0 → 0.3 at 55 % of the fade → 1 at the page
  row) so the page stays visible behind the mini-player. `PageIndicator.height` is now a static.
  `Spacing.bottomClearance` 184 → 168 to match.

Verification: `scripts/build-app.sh` → `** BUILD SUCCEEDED **` (pre-existing `ShareViewController`
warnings only); `swift test` → 427 tests in 80 suites passed. Not seen on a phone — same standing gap.

## Resume here (2026-09-09) — Home round 4: Figma mockup cover, gyro tilt, progress line

The owner's fourth pass, from a phone screenshot of round 3 plus a Figma community file ("6 Elegant
Book Mockups", node `10:6366`, mockup no. 3) read through the Figma MCP (`get_design_context` +
`get_screenshot` + its layer assets). Done on `dev`:

- **`BookCover` is now mockup no. 3** (`Design/Primitives.swift`): a softcover lying flat, seen
  straight on — square spine corners, fore-edge corners at `height × 0.03`, a hinge crease a few
  points in from the spine (bright sliver, then a darker band, gone by 8 % of the width), a soft
  shadow cast down-right, a faint sheen from the top-left and at the foot, a 0.5 pt edge. The
  mockup's paper texture and blurred-scene shadow are raster layers that vanish at 112 pt, so the
  shadow is SwiftUI's and the texture is left out on purpose. Round 3's page-sheet stack and −6°
  base tilt are gone (the mockup is front-facing). Proportions: the mockup's 0.667 for placeholders,
  the image's own for real covers.
- **Placeholders**: a cover whose ratio is outside 0.55…0.8 (landscape, banner, page scan) or a
  document with no image gets a plain `surface` cover with the title in a `ground` band across the
  lower third (the mockup's title box). **Every PDF** gets the light red cover that says "PDF"
  (`Tokens.pdfCover` / `pdfInk`, new) — read as the owner's categorical call ("for pdf we will use a
  light red book"), so a PDF's rendered first page is never used as its cover on Home. Flip
  `isPDF` handling in `BookCover.image` if that was meant only for weird/missing PDF covers.
- **New lighting tokens** `Tokens.shade` (black) and `Tokens.gloss` (white), the same in both
  themes: round 3's `ink`-based shadow became a glow in dark mode. Alpha is set per use.
- **Progress line moved** (`Queue/QueueRow.swift`): "◔ 5% · 23 hrs left" (12 pt ring, `.meta`,
  `ink2`) now sits between the excerpt and the buttons; the button row is Play + "…" only, with 6 pt
  extra above it. Book-to-text gap 14 → 20 pt, VStack rhythm 10 → 8 pt, cover 96 → 112 pt.
- **Gyro tilt** (`System/MotionTilt.swift`, new; `AppEnvironment.motionTilt`): `CMMotionManager`
  device motion at 30 Hz, `.xArbitraryZVertical` (gravity only, no magnetometer). Relative, not
  absolute: a 3 s exponential baseline makes the resting angle neutral, a 0.2 low-pass smooths the
  delta, ×0.35, clamped ±3°, published only on a > 0.05° move. `BookCover` adds `tilt.x` about the
  vertical axis and `−tilt.y` about the horizontal one, and slides its shadow with it. **Gating**
  (`Root/RootPager.swift`, `shouldTilt` → `motionTilt.setEnabled`): only while the scene is active,
  Home is the page, no Reader is up, Reduce Motion is off, and the device is not under load —
  thermal serious / Low Power Mode, or Kokoro present (`.checking`/`.preparing`/`.available`) with
  playback, a Prepare pass, the warm-up, or a voice preview (`VoicePreviewModel.isRendering`)
  running. A system/cloud voice playing on a Kokoro build counts as load too (documented; not worth
  the route plumbing). No `NSMotionUsageDescription` is needed for `CMMotionManager`; CoreMotion is
  autolinked from the `import`. The simulator reports no device motion, so `tilt` stays `.zero`
  there by design.

**Owed on a phone**: the tilt's sign (whether covers lean with or against the hand — a one-character
flip in `BookCover`'s two `rotation3DEffect`s), the shadow strength in dark mode, and the PDF red.

Verification: `scripts/build-app.sh` → `** BUILD SUCCEEDED **`; `swift test` → 427 tests in 80
suites passed. Not seen on a phone — same standing gap.

## Resume here (2026-09-09) — Home round 3: excerpt, 3D cover, Import page, bottom fade

The owner's third pass on the Home page, from a phone screenshot plus an Apple Books "Continue" cell
and an ElevenReader Import screen (Mobbin) as references. Six asks, all done on `dev`:

- **Row meta line** (`Queue/QueueRow.swift`): "EPUB · 3d · Chapter 7 of 27" is now just "Chapter 7"
  (plus the ready check when fully rendered), and the whole line is omitted when neither applies.
  `sourceName` and the `DurationFormatter.age` use are gone from the row.
- **Story excerpt under the title**: two lines of the text at the resume position, `.meta`/`ink2`,
  tail-truncated. Source is the new `LibraryModel.excerpt(for:) async -> String?`
  (`Sources/T2SApp/Library/LibraryModel.swift`): decodes only the resume chapter via
  `store.chapter(_:of:)`, resolves the position inside a one-chapter `Timeline`, joins utterance
  `source` strings to ≥240 chars, collapses whitespace, and caches per document against
  (chapter, resume position, staleness, utterance count). The row loads it in `.task(id:)` keyed on
  the same fields, so a refresh that moves nothing costs nothing. Tested in `LibraryModelTests`.
- **Ring and time left moved to the bottom row**, trailing Play + "…": `CircularProgress` at 12 pt
  and `DurationFormatter.coarseRemaining` — "22 hrs left", "1 hr left", "42 min left",
  "<1 min left", never a "~" (the ring already says how sure we are). Tested in
  `DurationFormatterTests`. The `~`-aware `remaining(_:approximate:)` is untouched and still used
  elsewhere.
- **3D book cover at its own aspect ratio**: new `BookCover` primitive (`Design/Primitives.swift`,
  next to `Artwork`, which now exposes its image cache as internal `Artwork.image(at:)`). Fixed
  96 pt height, width from the decoded image (clamped 0.55–0.85 × height), square spine corners,
  two `raised` page sheets offset behind the fore-edge, a spine-gutter gradient overlay, one
  compositing-group shadow, and a −6° y-axis tilt anchored at the spine. Articles keep the flat
  64 pt `Artwork`. **Eyeball on the phone**: the shadow/gutter use `Tokens.ink`, which is near-white
  in dark mode (a glow, not a shadow) — there is no "always dark" token; and the tilt sign (fore-edge
  toward the reader) may want flipping.
- **Import page replaces the Add sheet**: `Import/ImportPage.swift` (new) / `Import/AddSheet.swift`
  (deleted). Same contract (`imported` binding, `initialFiles`, `Path`, file importer, `.onChange`
  → dismiss, `.onDisappear` → `model.reset()`), now a `.fullScreenCover` with `PageTitle("Import")`,
  a close circle, and a two-column grid of three 128 pt tiles — Paste a link / Upload a file / Paste
  text. A "Back" pill (hidden when opened on files from another app) returns to the grid and clears
  the model so one path's failure never shows under the next. All three presenters switched:
  `QueuePage`, `CollectionPage`, and `RootPager`'s `openedFiles`.
- **Home header is one "Import" pill** (`Pill("Import", "plus")`); the Search pill, field, and
  "No matches." moved to `Collection/CollectionPage.swift` (title filter; subtitle still counts the
  whole collection). `RootPage.queue` is titled "Home" with the `house` glyph.
- **Bottom bar fade** (`Root/RootPager.swift`): a `LinearGradient` layer between the pager and the
  mini-player/indicator stack — `ground` at 0 opacity → solid from 34 % of a 210 pt band that
  ignores the bottom safe area, so it is opaque through the bar (≈138 pt) and fades ~70 pt above it.
  Hit testing off. New `Spacing.bottomClearance = 184` replaces the six `Color.clear.frame(height:
  120)` trailers (Home, Collection, Preferences, Pronunciation, Storage, Cloud voices) so the last
  row scrolls fully clear of the fade.
- **Bug fixed on the way — `typeRole` swallowed every caller's `lineLimit`.** `typeRole` ended in
  `.lineLimit(role.lineLimit)`, and the environment modifier nearest the text wins, so every
  `.typeRole(x).lineLimit(n)` in the app was a no-op (Collection titles were unlimited, the
  mini-player title could wrap to two lines, `FileImportRows`/`ChapterList`/`BookSheet` "one-line"
  titles were two). `Design/Typography.swift` now sets the role's limit through
  `transformEnvironment(\.lineLimit)` only when nothing else has, so either modifier order works
  and all fourteen call sites now do what they say. Expect some rows to look tighter than before.

Verification: `scripts/build-app.sh` → `** BUILD SUCCEEDED **` (only the pre-existing
`ShareViewController` async warnings); `swift test` → 427 tests in 80 suites passed. Still not seen
on a phone — same standing gap as every UI round this week.

## Resume here (2026-09-09) — Continue Listening row round 2

The owner's second pass on the same row, on `dev` commit `6987a75`: four small corrections to round 1
below, all in `QueueRow.swift` / `Design/Typography.swift`.

- **Archive removed as a standalone pill** — the row's button row is now just Play + "…". Archiving
  still works: swipe-to-archive (`QueuePage.swift`'s `.swipeActions`) and the "Archive" context-menu
  item are both untouched, since round 1 already established it's a real, distinct action (unqueue
  without delete) — the owner's ask this round was about decluttering the row, not the feature.
- **Cover art is back on the left** — `Artwork(relativePath: summary.document.coverImagePath, paths:
  env.paths, size: 64, radius: Spacing.artworkSmall)`, the same primitive Collection/BookSheet/
  MiniPlayer already use, in place of round 1's source-glyph-in-a-ring badge.
- **The circular progress ring and remaining time shrank into the meta line** — 14pt ring (`lineWidth:
  2`), trailing the existing "EPUB · 3d · Chapter 7 of 27 [✓]" text at `.meta` size, instead of their
  own leading block.
- **Title role**: a new `TypeRole.cardTitle` (`Design/Typography.swift` — Inter-SemiBold 21pt,
  between `rowTitle`'s 17pt Medium and `playerTitle`'s 26pt ExtraBold) replaces `playerTitle` on the
  row's title button — smaller and semibold per the owner's ask, not extrabold.

Simulator scheme builds clean. Still not seen on a phone — same standing gap.

## Resume here (2026-09-09) — Home page: Queue renamed, Continue Listening ring

The owner sent two phone screenshots (Queue page, Voice picker) with five UI asks. Done on `dev`,
commit `8194e11`:

- **Queue → Home**: `PageTitle` is now a fixed "Home" (`App/T2SReader/Queue/QueuePage.swift`), no
  item-count subtitle (`LibraryModel.queueSubtitle` stays — the model property is still tested —
  the view just stopped rendering it), and the chevron `Menu` that switched to the Finished list is
  gone. Asked the owner directly since it was the *only* entry point to Finished anywhere in the
  app: their call was "drop it entirely," not move it elsewhere.
- **Title bigger/bolder**: `QueueRow`'s title `Button` now reads `.typeRole(.playerTitle)` (26pt
  ExtraBold) instead of `.rowTitle` (17pt Medium) — the same role `BookSheet`/`DetailsSheet`/
  `VoiceChangeSheet` already use for a single prominent title, not a new one invented for this.
- **Play pill** dropped its "~22h 39m" suffix — just "Play" / "Pause" / "Starting…" now.
- **Archive, investigated and kept**: `LibraryModel.archive(_:)` calls `store.setQueued(id, false)`
  — it unqueues a document without deleting it (stays in Collection, can be re-enqueued). Real,
  distinct purpose from delete, so it stayed.
- **New**: a `SectionHeader("Continue Listening")` above the row list when not searching and not
  empty (`QueuePage.swift`); each `QueueRow` gained a leading `CircularProgress` ring (new
  primitive, `Design/Primitives.swift` — a stroked/trimmed `Circle`, `Tokens.accent` over
  `Tokens.ink3`) at 48pt with the row's source-type glyph centred in it. The "~22h 39m" that used to
  live on the Play pill now sits under the ring as "~22h 39m left" (`remainingText`, `QueueRow.swift`).

Simulator scheme builds clean (`xcodebuild -scheme Simulator`); `swift test --filter
LibraryModelTests` green (6/6) — the only suite touching the `LibraryModel` surface this pass reads.
Not seen on a phone yet — same standing gap as every UI round this week; owed once the owner
re-authenticates the Apple ID in Xcode (see the 2026-09-08 "Not available on this device" section
below) and can Cmd+R.

## Resume here (2026-09-09) — Plan 17

Plan 17 (`docs/superpowers/plans/2026-09-09-plan-17-rest-of-audit.md`) took what remained of the
performance audit that this Mac can build:

- **Re-derivation never touches the reader again** (Task 1, audit #6): import keeps the reader's
  chapters beside the source (`chapters.json.lzfse`, `RetainedChapters`); a re-derivation after a
  version bump reads them (a document imported before this build reads its source once more, then
  keeps the result); the old audio is removed in the background from the raw old blobs, after the
  load has its timeline — except when the re-derivation leaves the versions alone (a dictionary
  change from Details, a schema-only bump): the keys are then the old bytes, so the removal runs
  first. Bookmarks and a Prepare pass read `currentTimeline` and never re-derive; a prime may (one
  document, at launch or after an import). Not taken: per-chapter lazy re-derivation (the
  coordinator's indices span the document). `BookSheet.loadChapters` (another session's file) still
  calls `timelineForPlayback` and so still re-derives a stale book from the sheet — and the Bookmarks
  list relies on that running first; switch both to `currentTimeline` when that file is free.
- **The timer work coalesces** (Task 2, audit #7): the highlight is written only when the word
  changes; `PlayerModel` caches the rendered flag, the chapter axis and the chapter index against
  `timelineRevision`; the chapter axis is one pass; the ticker idles at 1 Hz; an idle `clear()`
  writes the Now Playing centre once. Not taken: `RootPager`'s second `update()` per tick (another
  session's file). The two `App/T2SReader/System` edits were checked by reading — no simulator build
  fit the disk.
- **Launch** (Task 3, audit #10): the old-codec sweep starts from the store's first use on a task of
  its own, not on the main thread in `init` and not on the first cache probe; the Core ML stages load
  four at a time under one shared task (`KokoroCoreMLModels.loadStages`, `loadWindow`). Not taken:
  bucket-lazy readiness (7 s first, the rest after) — the engine's readiness gating would change;
  measure the windowed load's peak memory on the A13 first (audit §4.1) before widening the window.
- **The 3 s and 10 s buckets** (Task 4, audit #9): `scripts/fetch-kokoro-coreml.sh` pins them (run
  it: the main checkout's staging has all 14 stages, 591 MB); `KokoroCoreMLResources.buckets` is
  `[3, 7, 10, 15]`. Every weight file is byte-identical across buckets, but the bundle duplicates
  them: **about +250 MB on the phone**. To drop the 10 s bucket, remove it from `buckets` and from
  the script's pins. The first launch after install builds fourteen compute plans, not eight. The
  render key is unchanged (the plan records why): clips cached at the old geometry play beside new
  ones, and the only cross-bucket difference is the overtones' noise realization — the same kind as
  another seed. If a seam ever sounds different after this update, that is the first suspect.

**Not taken, and why:** the OOV phoneme cache (audit #12) — MisakiSwift's fallback network is private
to `EnglishG2P`; it needs an upstream hook or a vendored copy. The G2P/generator overlap and the AAC
encode off the render path (#12) — the audit asks for the §8 stage-timing measurement first, and
the encode is a few percent of a render. #14 — nothing runs at launch, the MLX weights are not
staged, and the BART-to-Accelerate port is its own project.

**Owed:** the model-backed Kokoro tests (still disk-bound: the 14 stages compile to ~600 MB per copy
and Core ML's own cache runs to gigabytes); a simulator build; the phone. **The phone listen:** tap
play on an unplayed sentence — the first sound should come a beat sooner than Plan 15's (the 48-id
first piece renders in the 3 s bucket when it predicts under 3 s); a long packed sentence should
sound exactly as before (the 10 s bucket is the same weights, a smaller plan). Open the app after
this update: every book re-derives once on its first open, in one to three seconds instead of the
old five to twelve, and the Queue's rows keep their progress meanwhile. Launch on a cold phone: the
warm-up should be noticeably shorter than before, and the first launch after install shorter still.

While paused, the ticker now samples once a second: if the sleep timer's countdown skips a displayed
second while paused, that is the 1 Hz idle tick (`PlaybackTicker`), and a 250 ms idle tick is the
one-line revert.

**Next:** the §8 measurement on a phone (StageTimings and the G2P time, logged once), then whichever
of #12's remaining items it justifies; bucket-lazy readiness if the windowed load's memory peak
is a problem on the A13.

## Resume here (2026-09-08, latest) — voice picker round 4: one tap target, a "Change" mode

Picked back up the interaction model the owner asked for two rounds ago (after the Kokoro on-device
bug detour): the row is one tap target now, not the avatar/text split from round 3.

- **Unarmed (the normal state)**: tapping anywhere on a row previews that voice. The avatar is purely
  visual now (`avatarGlyph`, no longer its own `Button`) — it still swaps to a pause glyph or spinner
  while that row's voice is the one playing, but the whole row triggers it.
- **"Change" / "Done"**: a `Pill` living on the Default row (in place of where a heart would sit,
  since the Default row was never favoritable either). Tapping it arms `isChanging`; while armed,
  tapping any row — Default included — calls `onSelect` and disarms itself, so picking is one tap, not
  tap-then-remember-to-back-out. A visible hint line ("Tap a voice below to make it your default")
  appears above the rows while armed, spelled out rather than left to the pill's label alone — this
  exact "does tapping a row do anything" ambiguity is what got flagged three rounds running.
- The heart (favorite) is untouched by any of this: still its own button, still independent of
  `isChanging` and of the checkmark.

Simulator build verified clean. No Sources/ changes this round, so nothing to re-run there. Still not
seen on an actual phone — that's the same standing gap as every prior round, and the fixed on-device
Kokoro build (previous section) is what finally makes an actual look possible once the owner
re-authenticates in Xcode.

## Resume here (2026-09-08, latest) — "Not available on this device" was a real, fixed bug

The owner installed the Phone build on their iPhone 11 Pro (Cmd+R from Xcode) and hit "Not available
on this device" in the Voice picker, after it had reportedly worked before. Traced with the device
connected via `xcrun devicectl` and a command-line build against it (`xcodebuild ... -destination
'platform=iOS,id=...'`), not by guessing:

- **Root cause**: `App/T2SReader.xcodeproj` (generated by `xcodegen generate`, never hand-edited, not
  git-tracked) had `Resources/KokoroCoreML` sitting in the tree only as a plain `PBXGroup` — not
  wired into any target's Resources build phase at all. The 591 MB on disk (verified complete against
  `scripts/fetch-kokoro-coreml.sh --app`'s pinned digests) was never being copied into the built app,
  so `KokoroCoreMLResources.locate(in:)` correctly reported the files missing at launch. A built
  `.app` was inspected directly (`Build/Products/Release-iphoneos/T2SReaderKokoro.app`) to confirm:
  no `KokoroCoreML` directory in it at all.
- **Fix**: ran `xcodegen generate` again. The regenerated project wires every file under
  `Resources/KokoroCoreML` into the Kokoro target's Resources phase individually (verified in
  `project.pbxproj` — every `.mlpackage`, `.bin`, and the two runtime `.json` files each carry their
  own `in Resources` build entry now).
- **A regenerate side effect, also fixed**: regenerating silently dropped `DEVELOPMENT_TEAM`, which
  had only ever been set by hand in Xcode's Signing & Capabilities panel (never in `project.yml`, so
  never survives a regenerate). Pinned it (`5HZ38K43M9`, the one valid `Apple Development` identity
  on this Mac, matching the owner's Apple ID) in both the `T2SReaderApp` template and
  `T2SReaderShare`'s settings — commit `58d5439`, pushed.
- **Where this stopped**: a command-line build for the connected device (`-allowProvisioningUpdates`)
  now gets past resources and signing config to one last wall: "Unable to log in with account
  'shubham123nayak@gmail.com'. The login details ... were rejected." Xcode's automatic-provisioning
  path needs to (re)authenticate that Apple ID — almost certainly 2FA — which cannot be done
  headlessly from here. **Owed**: the owner opens Xcode itself (not Cmd+R yet) and checks Settings →
  Accounts for that Apple ID; if it shows an error or needs a code, clear it there, then Cmd+R the
  Phone scheme as normal. Xcode's own GUI sign-in flow is very likely to succeed where the bare
  `xcodebuild` CLI path could not, since it can actually show the system sign-in prompt.

If Cmd+R still shows "Not available on this device" after that, the fetch/wiring fix above is already
confirmed correct on this Mac, so the next thing to check is whether Xcode actually rebuilt the
Kokoro target fresh (a plain Cmd+R sometimes reuses a resource-copy step it thinks is unchanged;
Product → Clean Build Folder first rules that out).

## Resume here (2026-09-08, latest) — voice picker round 3

A third pass, still on `dev`, still unseen on a phone. Two of the five asks were UI polish; the fifth
was a real design question worth recording here.

- **Avatar is the preview control now.** Tap the disc to hear the voice, tap again to stop; it swaps
  its initial for a pause glyph while playing (`avatarButton`, replacing the separate `previewButton`
  circle the owner asked removed). The "Default" pointer row has no voice of its own, so its avatar
  stays the plain, non-interactive disc it always was.
- **The name/detail block is the selection target** — tapping the text (not the avatar, not the
  heart) is what calls `onSelect` and sets this voice as the default (or the per-document override in
  `VoiceChangeSheet`). This is the fix for "tapping a voice does not make it default": before this
  round the whole row shared one purpose and the tap area sprawled past what was visible (the row's
  own `Spacer` filled blank space up to the heart/play icons), which is a plausible source of the miss
  the owner hit even though `preferences.defaultVoiceID` itself is straightforward `UserDefaults`
  state with nothing else touching it. Splitting the row into three explicit buttons — avatar
  (preview), text (select), heart (favorite) — removes the ambiguity outright rather than patching a
  bug that couldn't be reproduced by reading the code alone; worth confirming on the phone that the
  checkmark now visibly follows a tap.
- **What "default" is for, recorded for whoever is asked this again**: `ReaderPreferences.defaultVoiceID`
  is the fallback voice for any document with no per-document override — `ReaderPage.swift`,
  `PrepareRunner`, and `PlayerModel` all read it that way. Removing the concept would mean every new
  book starts on the hard-coded system fallback until changed one book at a time. Recommended keeping
  it (and did) rather than removing it unasked — a persisted, load-bearing setting is not something to
  delete on a UI-fix pass without the owner confirming that's really what they want.
- **Personality lines shortened to three-word tags** ("Warm, Breathy and Intimate" — the ElevenReader
  row the owner pointed at reads "Expressive, Deep and Emotive"), condensed from the same grounded
  write-ups as round 2, not reworded from scratch. `.lineLimit(1)` was already there for the ellipsis
  truncation the owner asked to match.
- **More space between name and detail** (`VStack` spacing 2 → 6) and **a bigger heart** (17pt → 22pt
  glyph, 32pt → 40pt frame, now the row's only trailing control).

Simulator scheme still builds clean; still no Kokoro rows outside the Phone build, so none of round 2
or round 3 has been seen on any screen. This is the one most worth an actual phone install before
another round of screenshots — three rounds of blind UI iteration is enough.

## Resume here (2026-09-08, later) — voice picker round 2

The owner sent a second phone screenshot with five more asks, done on `dev` @ (this commit) and
pushed:

- **Personalities were guessed and wrong** (owner: "the personalities don't match the voices"). This
  Mac has no audio path to check by ear, so the table in `KokoroVoiceCatalog.personalities` is now
  grounded in independent listener write-ups (voicerankings.com's Kokoro-82M profiles) instead of a
  name-based guess — still not first-hand verified, still worth re-checking on the phone, but no
  longer invented from nothing.
- **Play button colour reverted** — the owner only asked for it larger last time, not recoloured; it
  reads `Tokens.ink2` again (only the glyph grew, to 32pt in a 44pt target).
- **Favoriting exists now**: a heart per row, `ReaderPreferences.favoriteVoiceIDs` (a `Set<String>`
  in `UserDefaults`, independent of `defaultVoiceID`). Setting the default is what it always was —
  tap the row; the checkmark follows it. The heart is a separate, multi-select "keep track of these"
  list, matching what the ElevenReader Mobbin flow showed under its own Favorites pill.
- **Pill filters**: All / Favorites / Female / Male above the Kokoro rows, reusing the existing `Pill`
  primitive (`Primitives.swift`) rather than a new component — this app already had the exact
  selected/soft chip style the reference screenshot wanted. Scoped to Kokoro only: System and Cloud
  rows carry no gender or favorite state to filter by.
- **Row spacing increased** — `Spacing.grid` (8pt) added top and bottom per row, on top of the
  existing 56pt tap-target minimum.

Checked the ElevenReader voice-selection flow via the Mobbin MCP for reference (Voices tab: Explore /
Recents / Favorites pills, a heart per row; the separate Filters sheet has Sort by / Languages / Best
for / Age / Gender — we have no data for "Best for" or "Age", so only Gender + Favorites made the
cut). Simulator scheme still builds; still no Kokoro rows outside the Phone build, so none of this is
seen on screen yet — the phone listen owes a look at this alongside the personality lines.

## Resume here (2026-09-08, late) — the voice picker

A UI-only pass on Preferences → Voice from the owner's phone screenshot, on `dev`: the row's second
line is now the voice's character ("Warm and intimate", "Sensual, low and slow", "Whispered, close to
the ear" — `KokoroVoiceCatalog.personalities`, one per voice, written from listening; adjust any that
read wrong on the phone) instead of "American · Female"; the accent is the sub-section (🇺🇸 / 🇬🇧
headers at `sectionHeader` weight with `Spacing.row` above) and the gender is the avatar's tint
(`VoiceOption.gender`, `Tokens.voiceFemale` pink / `Tokens.voiceMale` blue, the initial in `onAccent`);
the preview glyph is the filled 32 pt circle in a 44 pt target. The Preferences row's subtitle now
reads "Heart · Warm and intimate". Tests updated and green; the Simulator scheme builds. Not seen on
a phone yet — the everyday build lists no Kokoro rows, so this needs the Phone scheme to look at.

## Resume here (2026-09-08) — Plan 16

Plan 16 (`docs/superpowers/plans/2026-09-08-plan-16-open-path.md`) took the audit's remaining items
that need no model files and no UI files:

- **A streamed head that runs dry pauses** (Task 1): `AudioPlaying.queuedSeconds`; the coordinator's
  10 Hz tick pauses on "catching up" while a stream is live and the player holds nothing, and the next
  piece resumes it. This is the in-utterance hole Plan 15's listen list asked you to listen for; the
  remedy is in, and the listen still applies (below).
- **The normalizer folds its passes** (Task 2): one alternation for the abbreviations, one for the
  dictionary (each entry keeps its case rule; entries no longer chain), the number rule skipped for
  text without a digit. Output identical for every existing test.
- **The harmonic source** (Task 3, vendored `KokoroPipeline`): the nine sine passes stop one frame past
  the last voiced frame, bit-identical to the full computation (`HarmonicSourceTests`); the hn-nsf
  build runs on another core beside the DecoderPre prediction, and `StageTimings.decoderPreHnsfOverlap`
  is set at last. `Packages/KokoroPipeline/README.md` lists the patches.
- **The open path** (Task 4): the coordinator reports the chapters its renders changed
  (`changedChapters` / `takeChangedChapters()`) and `PlayerModel.persistRenderedChapters` writes
  those — no SipHash pass over the book per pause. A saved playhead carries its chapter and the
  seconds into it (`SavedPlayhead`; `PlayheadStore.save` changed), stored on the document row
  (`LibrarySchemaV2`, a frozen `LibrarySchemaV1` copy of the models, a lightweight stage — verified
  once against a V1 store file written by the previous build), so `LibraryModel.refresh` decodes no
  timeline for a row the coordinator has played. Rows saved before this build decode once more, then
  never again.

**Owed:** model-backed Kokoro tests (`preloadBuildsTheG2P()`,
`streamsALongPassageInPiecesThatFoldToTheSameTimings()`) and a simulator app build on the merged
branch — this Mac had no disk for either (the model caches need ~10 GB); the phone is the test. The
T2SKokoro package's own non-model suites were not rerun on this branch: its sources are untouched, and
the vendored pipeline's public API is unchanged.

**The phone listen (adds to Plan 15's).** Tap play on an unplayed book on a hot phone and listen to the
first sentence: a hole inside it should now come with the play glyph's "catching up…" ring and no jump
in the highlight afterwards. Open the Queue after a few minutes of listening: the row's remaining time
and chapter should be right without a beat's delay on first show.

**Next:** the 3 s bucket (audit #9) to halve the first sound again; then per-chapter lazy re-derivation
(#6), the tick churn (#7, the other session's files), lazy warm-up (#10), and the rest of #12 after the
§8 measurement.

## Resume here (2026-09-08) — Plan 15

Plan 15 (`docs/superpowers/plans/2026-09-08-plan-15-streaming-first-sound.md`) streams the head
utterance: `SynthesisEngine.synthesizeStreaming` (Task 2; default wraps `synthesize`),
`RenderRequest.stream` + `RenderEvent.piece` (Task 3), `AudioPlaying.enqueue(_:tag:isFinal:)` (Task 1),
`PlaybackCoordinator` enqueuing pieces as they arrive and starting playback on the first (Task 4), and
the Kokoro engine rendering a 48-id first piece and finalizing each piece before emitting it (Task 5).
Only the utterance the player is waiting on streams — at load as well, so a book opened and played a
moment later starts at once; the cache, Prepare and the prime are unchanged. Tasks 3–6 were written by
the controller directly, at the owner's request for speed; one whole-branch review precedes the merge.

**Owed:** the model-backed streaming test (`streamsALongPassageInPiecesThatFoldToTheSameTimings()`)
and the quality probe on the streamed join — this Mac cannot run either (disk); the phone is the test.

**The phone listen.** Tap play on a book you have never played, skip forward 30 s twice, jump to a
late chapter, tap a word far down the page: sound should start within about a second each time, and
the first sentence after a tap should flow into its second piece without a hole or a tick. If the
first sentence sounds cut in two, the streamed join's tail budget (`KokoroCoreMLSeam.budgetSamples`)
is the knob; if the highlight drifts in the first sentence only, the fold's `offsetSeconds` for the
streamed pieces is.
Also listen for a hole *inside* the first sentence after a tap on a hot phone: Plan 15 left a streamed
utterance without a "catching up" of its own between its pieces; Plan 16 added it (above).

**Next:** the 3 s bucket (audit #9) to halve the first sound again; then the open path (#5) and the
tick churn (#7).

## Resume here (2026-09-08) — Plan 14

The owner asked, after Plan 11: "we cannot change the model — are there other ways to improve the
sound quality?" Plan 14 (`docs/superpowers/plans/2026-09-08-plan-14-quality-levers.md`, branch
`plan-14-quality-levers` in `.worktrees/plan-13-quality-levers` — the folder and the first commits say 13;
the other session's Plan 13 merged first — off `dev` after Plan 12) measured the
levers first (`spikes/findings/2026-09-08-quality-levers.md`; WAVs in `spikes/findings/lever-probe/`,
copies in the owner's Desktop folder "Kokoro voice test") and shipped what the owner's ears chose:

- **Delivery 1.25, fixed** (`Delivery.spread`): the F0Ntrain stage's pitch contour widened by a
  quarter about its log-mean before decoder-pre and the harmonic source
  (`KokoroSynthesisRequest.f0Spread`). Measured on Heart: spread 4.2 → 4.8 semitones, range 9.9 →
  12.4, duration identical to the sample, every pause the same, no new clicks; the owner: "feels more
  alive". Not a setting — three presets were "unnecessarily complicated". It rides on the voice route
  of every render (`kokoro:<engine>:<voice>@1.25`, `KokoroVoiceID.spread`, attached in `PlayerModel`,
  `PrepareRunner` and `VoicePreviewModel`) so every render key changed and **every book re-renders on
  its next play**, while stored voice choices stay plain and untouched.
- **A crash fixed**: the vendored pipeline's DEBUG assertion on an overflowing prediction took down
  debug builds (the Phone scheme is Debug) on slow voices — `af_nicole` predicts 16.7 s for one packed
  utterance in the 15 s bucket. The engine's re-split handles it; the assertion is gone, with a
  model-backed regression test.
- **Test hygiene**: `KokoroTestSupport` keeps a private, revision-keyed APFS clone of the compiled
  stages under the package's `.build` and reuses it across runs — two sessions' test runs were
  compiling onto and sweeping the same paths in the shared temporary directory.
- **Not taken, by the listen**: blends ("all good, too subtle to tell apart" — the mechanism is in the
  lever probe only); Opus (the system encoder ignores the bitrate and writes larger files than AAC);
  speech-enhancement models (they remove noise and reverb; Kokoro's output has neither). Optional and
  open: the voice list ordered by the author's grades (Heart A, Bella A-, Nicole B-, Emma B-; Emma
  measured the flattest voice, Bella the widest — Plan 9's "the British voices move more" is wrong).

- **The owner's A/B, and why the app still clicked**: the passage rendered as Plan 9 left it clicks
  after "Humbug", "sparkled" and "poor enough" — the three tail bursts Plan 11 measured — and the
  fixed renders do not. The clicks the owner heard in the app ("The Last Mughal") were audio the
  current engine never rendered: the render key's engine component is `RoutedEngine.engineID`, the
  constant `routed-v1`, and no Plan 11 fix changed any key component, so a build without the fix and
  a build with it share the cache. The delivery tag changes every Kokoro key, so this update
  re-renders every book; the rule is now in spec §5 — a change that alters an engine's audio must
  change the key.

**The phone listen** (same install recipe as below; every book re-renders once): does the book sound a
touch more alive than before, with no shrillness on high phrases? The clicks after sentences must be gone
once the book has re-rendered (the first play after the update renders afresh). Bella, Michael, Emma and Nicole were
rendered at 1.0 and 1.25 before the value became the default for every voice (the spread check in the
finding).

**Folding Plan 14 back** (from the main folder; the worktree keeps its old name):
`git merge --ff-only plan-14-quality-levers && git push && git worktree remove .worktrees/plan-13-quality-levers && git branch -d plan-14-quality-levers`.
A second worktree, `plan-14-streaming`, was opened under the same number while this branch was being
verified; whichever of the two merges second renumbers (as Plan 12/13 did), spec revisions included.

## Resume here (2026-09-08) — Plan 13

The owner said "you decide" after the performance audit; Plan 13
(`docs/superpowers/plans/2026-09-08-plan-13-first-sound.md`, branch `plan-13-first-sound` off `dev`
@ b951d86, worktree `.worktrees/plan-13-first-sound`) took the audit's single-task items while
another session ran Plan 12 (the Player sheet retired) in the main checkout:

- **Task 1** — the Phone scheme's Run action is Release (`App/project.yml`); the install recipe below
  no longer needs the by-hand flip. Every listen before this may have been `-Onone`. For a debugging
  session on the phone, set the Run action back to Debug (Edit Scheme → Run → Info): breakpoints and
  `po` are degraded under Release, and incremental phone builds are slower.
- **Task 2** — `KokoroCoreMLEngine.load()` builds the American G2P after the stages, so the launch
  warm-up pays it, not the first sentence.
- **Task 3** — the prime tier runs: `RenderPolicy` primes from the resume index;
  `PrepareRunner.prime(_:)` after every import (`ImportModel.afterImport`, wired in `AppEnvironment`)
  and `primeContinueDocument()` from `T2SReaderApp`'s scene task at launch.
- **Task 4** — `RecentAudioStore` keeps the last eight renders in memory in front of `FileAudioStore`
  (`SharedLibraryFactory`); `AudioStore.contains(_ keys:)` makes the coordinator's and Prepare's
  reconcile one hop; `RenderKey` hexes by table.
- **Task 5** — Prepare writes a chapter when it leaves it, every 10 s inside it, and at the end.
- **Task 6** — `PlaybackCoordinator.refreshRates()` on every render: a rate above the sustainable cap
  steps down and `rateLoweredTo` is set for the Reader to show (deferred to the UI plan).
- **Task 2's model-backed test did not run on this Mac.** `preloadBuildsTheG2P()` was started twice and
  each time Core ML's compute-plan cache for the eight stages ate ~6 GB of the ~8 GB free within three
  minutes, so the run was stopped before it filled the volume (`scripts/test-kokoro.sh`'s ~0.9 GB
  estimate is stale by a factor of six). The change is three lines behind the existing `loadCount`
  pattern and was reviewed on its diff; the captured RED (the compile failure without `isG2PLoaded`)
  is in the plan's ledger. To run it: free ≥ 10 GB on the volume (it sits at 96 %), make sure no other
  Kokoro test is running (`ps aux | grep '[x]codebuild' | grep -c T2SKokoro` → 0), then from the
  checkout root `scripts/test-kokoro.sh '-only-testing:T2SKokoroTests/KokoroCoreMLEngineTests/preloadBuildsTheG2P()'`
  (the parentheses matter: without them xcodebuild matches no test and still reports SUCCEEDED), then
  the same for `loadsTheStagesOnceWhenAPreloadAndARenderArriveTogether()`. On the phone, a broken
  warm-up shows as "The Kokoro voice could not be prepared." in Preferences → Voice, never as silence.
- **Naming collision:** the other session's second worktree is also numbered 13 (`.worktrees/plan-13-quality-levers`, a Kokoro probe); this plan kept its name. The next plan is 14 either way.

**The phone listen.** Install with the Phone scheme (Release now). Listen for: a new import's first
tap starting at once; the mini-player's first tap after a launch starting at once; a book that has
never been played starting within ~2–3 s (that wait is Plan 15's — streaming the first sound);
word-level highlighting in the first 30 s after an import.

**Next (Plan 15):** streaming the head utterance's first piece to the player — audit #2 — with the
quality probe on the seam a short first piece makes. Then the open path's `play()` gate and
`LibraryModel.refresh` (#5), and, once the UI plan has merged, the tick churn (#7).

## Performance audit (2026-09-08)

`docs/superpowers/specs/2026-09-08-performance-audit.md` — a desk audit of `dev` @ 3bca4b1 against
"as smooth as a cloud voice", with fourteen ranked recommendations and the measurements still missing.
Headlines: the phone scheme runs Debug (`run: config: Debug` in `App/project.yml`; the by-hand flip to
Release does not survive `xcodegen`); tap-to-first-sound is 2.5–4.5 s on an A13 because nothing streams
inside an utterance and the live path plays the AAC cache back through two temp files; the prime tier
(spec §3.4.1) is never planned and the G2P is built on the first sentence, not in the warm-up; a version
bump re-derives the whole book on the first tap (and from the Book sheet, Bookmarks and Prepare);
Prepare rewrites a whole chapter blob per rendered utterance; the UI updates Now Playing ~20×/s and
writes `nowPlayingInfo = nil` 4×/s while idle. The MLX launch probe was checked and is cheap (it
short-circuits on the nil decision). Next: pick the first plan from its §2 table — #1 (Release) and #3
(G2P warm-up + prime) are single tasks; #2 (streaming the first sound) is the one that closes the gap.

## Resume here (2026-09-08) — Plan 12

The owner's report after Plan 10: "If I play a document from the queue page, there is no way to see
the text … There should not be 2 separate UIs for playback. Keep only one, with the text
read-along." Approved in conversation ("ok"). Plan 12
(`docs/superpowers/plans/2026-09-08-plan-12-one-playback-ui.md`, branch `plan-12-one-playback-ui` off
`dev` @ b951d86, after the second session's Plan 11) retires the Player sheet from Plan 4a: the
Reader already has everything the sheet had (scrubber with the render frontier, transport, sleep
timer, speed, chapters, bookmarks, voice, details), so every way of starting playback now opens it
instead.

- **Task 1** (`d839f59`): every playback entry opens the Reader; the Player sheet, its tick
  scrubber and control pill retire.
  - `App/T2SReader/Queue/QueueRow.swift` — the row's Play pill: Pause on the playing row toggles
    play and stays put; on the current-but-paused row it resumes first, then opens the Reader; on
    any other row it just opens the Reader, which loads and plays the document itself.
  - `App/T2SReader/Root/MiniPlayer.swift` — `onExpand` now carries the shown `DocumentSummary`;
    tapping the title or the capsule opens the Reader on whichever item the mini-player is
    showing (the playing one, or the next queued item when idle). Its accessibility hint changed
    from "Opens the player" to "Opens the reader".
  - `App/T2SReader/Root/RootPager.swift` — dropped the `showPlayer` state and the `.sheet` that
    presented `PlayerSheet`; `MiniPlayer`'s tap now feeds `readerDocument` instead. The
    `ReaderRoute` doc comment now lists the mini-player as an entry point in place of
    `PlayerSheet`.
  - `App/T2SReader/Collection/BookSheet.swift` — dropped `showPlayer` and the `PlayerSheet` sheet;
    the Play pill resumes a current-but-paused document, dismisses the book sheet, and calls
    `readerRoute.open(live)` (chapters already opened the Reader, from Plan 10).
  - `App/T2SReader/Reader/ThinScrubber.swift` — doc comment only: it is now "the app's only
    scrubber" rather than a contrast with `TickScrubber`.
  - Deleted entirely: `App/T2SReader/Player/PlayerSheet.swift` (137 lines), `TickScrubber.swift`
    (47 lines), `ControlPill.swift` (67 lines). `ChapterList`, `SleepTimerSheet`, `SpeedPicker`,
    and `VoiceChangeSheet` stay under `App/T2SReader/Player/` — the Reader still presents them, and
    moving them would be churn with no behaviour change.
  - `swift test` 365 tests / 78 suites green; `scripts/build-app.sh` green.

**Rulings taken without the owner** (each costed in the plan; ledger
`.superpowers/sdd/2026-09-08-plan-12-one-playback-ui/progress.md`):

- Play in the Queue navigates to the Reader rather than playing in place — the owner's own
  expectation when they tapped it. Pause on the playing row stays in place. Cost if wrong: two
  lines in `QueueRow`.
- The Reader loads and plays a non-current document itself (`ReaderPage.open()` already does), so
  the entry points only open it; a current-but-paused document is resumed before opening. Cost:
  none.
- The shared sheets stay under `App/T2SReader/Player/` (chapter list, sleep timer, speed picker,
  voice change) — moving them is churn with no behaviour. Cost: a folder name that reads oddly.

**The phone checklist** (not yet run — no device is attached to this Mac):

1. Play on a Queue row opens the Reader and starts playback.
2. Pause on the playing row's pill pauses in place — it does not navigate anywhere.
3. Tapping the mini-player's title or capsule opens the Reader on the item it shows —
   if nothing is playing, this also starts the next queued document playing.
4. Play in a book sheet opens the Reader (a chapter already did, from Plan 10).
5. The Reader's own controls (scrubber, transport, sleep timer, speed, voice, chapters) cover
   everything the Player sheet had — check that nothing feels missing now that it is gone.

**Deferred** (the plan's own list): the Reader shows no artwork or source/age line — the Details
sheet has them; add to the page only if missed. `PlayerModel` may keep a property or two that only
the sheet read — a later tidy.

**Dev rule from the owner: never play audio on the Mac.** Simulator runs only as
`SIMCTL_CHILD_T2S_SILENT=1 xcrun simctl launch <udid> com.t2s.reader` (the app mutes every player
when `T2S_SILENT` is set). Never change the Mac's volume.

## Resume here (2026-09-08) — Plan 11

The owner's second listen (2026-09-08) reported two things: "sometimes mid sentence I can hear a tick
or a clap, before the sentence resumes", and "commander-in-chief, cost-cutting: it pauses instead of
reading it like a full word — solve it once, or is there a standard?". Plan 11
(`docs/superpowers/plans/2026-09-08-plan-11-voice-quality-2.md`, branch `plan-11-voice-quality-2` off
`dev` in `.worktrees/plan-11-voice-quality-2`) measured both and fixed them:

- **Diagnosis** (`spikes/findings/2026-09-08-ticks-and-hyphens.md`; probe `scripts/quality-probe.sh`
  → `spikes/findings/quality-probe/`, git-ignored). The tick: every Core ML call ends with ~40 ms
  of digital silence and, 60–40 ms before the end, a 20 ms burst bounded by silence — −10 to −15 dBFS
  when speech ended just before the call (a comma, a closing quote, a bare-word cut), inaudible after a
  long pause; the MLX reference never produces it. Any sentence past ~176 phoneme ids is two calls, so
  the click lands mid-sentence: "…his eyes sparkled, [click] … and his breath smoked again". The hyphen:
  `NLTagger` tags every hyphen `Dash` and MisakiSwift maps every `.dash` token to Kokoro's `—`, a
  clause pause — `kəmˈændəɹ—ˈɪn—ʧˈif`, a 150 ms hole inside "cost—cutting", "in" stressed as its own
  word. The Python reference keeps an intra-word hyphen silent. Neither is the model's.
- **Task 1** (`c79f00d`): `SplitHyphenatedCompoundsRule` — a hyphen with a letter or digit on each side,
  at least one a letter, becomes a space, after URLs collapse and before numbers expand; spaced dashes,
  `--`, em/en dashes and digit–digit ranges stay; the dictionary matches a term typed with a hyphen
  against the spoken form. `Versions.normalizer` **3**: every stored timeline re-derives on its next
  play and its rendered audio is orphaned cache (spec §3.7.3), as with the Plan 5 bump.
- **Task 2** (`3dbdda5`): `KokoroCoreMLTailClick.removed(from:)` zeroes the island — the last non-silent
  stretch when it is under 30 ms, bounded by ≥ 10 ms of silence (under −80 dBFS) on both sides, within
  the final 120 ms — on every pipeline call, behind `Options.removeTailClick` (`.default` true). The
  probe's A/B: island gone from every packed utterance, zero samples changed where there was none.
  The engine gained a test-only `UtteranceTrace` (tokens, ids, per-piece frames and offsets) that the
  probe uses to place every sample on its token.
- **Task 3** (the seam): with the click gone the probe measured 740 ms across a bare-word cut and
  400–820 ms across comma cuts — every call ends with the model's end-of-input pause. `KokoroCoreMLSeam`
  trims both sides of a seam to a budget by cut kind (word 60 ms, clause 320 ms, sentence 500 ms, the
  model's own pauses inside one call, at −50 dBFS): the next piece's lead-in first, never past its BOS
  frames (the fold offset moves back with it), then the previous piece's tail (the fold clamps its last
  word's end to the audio left — `KokoroCoreMLTimingFold.Piece.trimmedTailSeconds`). Behind
  `Options.trimSeams` (`.default` true). Probe after: 740 → 60 ms, 820 → 320 ms, 400 → 310 ms; the
  long sentence 24.52 → 23.34 s.
- **On "a standard".** SSML is what cloud voices accept; Kokoro takes phonemes and MisakiSwift's only
  markup is the inline `[word](/phonemes/)` form. The normalizer (spec §4.1) is this app's markup
  layer, and it is where hyphens are now resolved for every book. The pronunciation dictionary fixes
  one term at a time. MisakiSwift's dash rule (map `.dash` to `—` only when the dash stands alone, as
  the reference does) is worth an upstream patch; the app does not wait on it.

**Folding it back — done.** This has since happened: Plan 11 merged into `dev` (commit `3bca4b1`)
and the worktree and branch were removed; `git worktree list` no longer shows them. The instructions
below are kept as the record of how.

Plan 10 was being committed in the main checkout while this ran, so Plan 11
lives in the worktree `.worktrees/plan-11-voice-quality-2`; it has since been rebased onto `dev` @
6344993 (Plan 10 merged, spec rev 11; this plan is rev 12). From the main folder:
`git merge --ff-only plan-11-voice-quality-2 && git push && git worktree remove
.worktrees/plan-11-voice-quality-2 && git branch -d plan-11-voice-quality-2`. The worktree holds
clone copies (`cp -Rc`) of the model files and the build caches; `.build`'s PCH module cache had to be
deleted after cloning (it is path-bound).
`scripts/test-kokoro.sh` and both probes sweep Core ML's runtime cache and `$TMPDIR/kokoro_*.mlmodelc`,
which are shared across checkouts: two sessions running them at once slow each other's model loads to
many minutes.

**The phone listen.** Same install recipe as below. Fresh play re-segments every document (normalizer
3). Listen for: no tick before a sentence resumes or before a new sentence; "commander-in-chief",
"cost-cutting", "well-known" read as one phrase; a long two-piece sentence flowing through its seam
with a beat, not a stop. `spikes/findings/quality-probe/packed-1-unfixed.wav` at 10.9 s is the
click as it was.

**Deferred:** the 30 s Core ML bucket (a whole 300-character utterance in one call — the only cure for
the sentence-final tune at a seam); the mechanism of the burst (a tensor dump at the trim point; the
lead-in shortfall of 30–45 ms at every seam suggests the generator runs ahead of its frames); upstream
patches to MisakiSwift and kokoro-coreml.

## Resume here (2026-09-08) — Plan 10

The owner's report on 2026-09-07: the Reader page was a black page under light chrome — "it looks
like pages from a PDF, not our UI"; ElevenReader was the reference ("beautiful text UI … they don't
display a page"); and "I want theme app wide". Reproduced in the simulator: the Reader-only Theme
preference themed only Readium's web view and nothing else —
`xcrun simctl spawn <udid> defaults write com.t2s.reader reader.theme -string dark` turns the
Reader black while the rest of the app stays light. Plan 10
(`docs/superpowers/plans/2026-09-07-plan-10-native-readalong.md`, design
`docs/superpowers/specs/2026-09-07-native-readalong-design.md`) answered both: the Reader now draws
the timeline's text itself, after ElevenReader, and the theme choice applies to the whole app.

- **Task 1** — `Sources/T2SApp/Reader/ReaderText.swift` (new): a pure model that turns a `Timeline`
  into paragraphs (document title, byline, chapter titles, headings, body) with exact UTF-16
  offsets into one flattened string, plus `hit(at:)` for taps and `wordRange`/`tintRange` for
  highlighting. `ReaderModel.swift` gained `seek(toUtterance:sourceOffset:)`, the new tap entry
  point, alongside the old `playhead(for:in:)` kept for now as a thin wrapper.
- **Task 2** — `App/T2SReader/Reader/ReaderTypesetter.swift` and `ReaderTextView.swift` (new): the
  Reader draws its own text on a `UITextView` backed by TextKit 2 — paragraph and word tints as
  rounded rectangles from `NSTextLayoutManager` segment rects, taps mapped through
  `textLayoutFragment(for:)`, following that re-centres the active word. `ReaderPage.swift` builds
  `ReaderText` off the coordinator's timeline instead of opening a Readium publication. Removed:
  `EPUBReaderView.swift`, `PDFReaderView.swift`, `ReaderScripts.swift`, `PublicationCache.swift`,
  `ReaderError.swift`, `AppEnvironment.publications`, and the `ReadiumNavigator` /
  `ReadiumAdapterGCDWebServer` products from `App/project.yml` — Readium's navigators leave the
  app; `T2SReadium` itself (import, positions, `LocatorMapping`) is untouched.
- **Task 3** — `App/T2SReader/Design/Theme.swift` (new): `ReaderTheme.colorScheme` and an
  `.appTheme()` modifier applied to the root pager and to the Reader page, so System/Light/Dark now
  covers every screen, sheet and the Reader's UIKit text view together. The Appearance sheet and
  Preferences page captions say so.
- **Task 4** — deleted the tap-matching path Plan 9 built, once the new view no longer needed it:
  `SourceHit.swift`; `ReaderModel`'s `activeSentence`, `seek(to: SourceHit)`, the old
  `playhead(for:in:)`, `normalized(_:)`, `utteranceIndex(for:in:)`, `locate(_:in:)`,
  `rawOffset(forCollapsed:in:)`, `pageCount(from:)`; `Highlighter.sentence(at:in:)`; their tests
  (11 fewer, 371 → 360).

Three rulings from Task 2's review amend the design spec
(`docs/superpowers/specs/2026-09-07-native-readalong-design.md`), each a line or two in place:
the top inset is 96 pt measured from the safe-area top, not 72 from the view's own top (the view
ignores only the bottom safe area); every text run carries `ink`/`ink2` as an explicit colour
attribute, because `UITextView.textColor` applies to the whole string and flattened the byline;
and an empty timeline shows the message only, not the title. Two more amendments landed with
Task 2's fix round: a superseded typeset now stops at the next paragraph boundary and the
coordinator cancels its build on disappearance; and the first centre after content arrives is
never animated even when the first highlight lands later, because audio is usually still
rendering at open.

**Deferred** (the plan's own list, plus the minors the ledger recorded along the way):

- Import-time block roles (headings, quotes) once Readium or our own HTML pass provides them;
  images inline; text selection, notes, sharing a quote; removing
  `LocatorMapping.locator(for:in:)` and its tests from `T2SReadium`.
- `syncOverlay()` isn't called on a pure bounds change (rotation while paused).
- `redrawHighlight` bridges the two tint colours from SwiftUI on every word tick, and calls
  `rects(for:)` three times per tick where one pass could feed both the redraw and the centring —
  hoist and share when next in the file; `view.textColor = UIColor(Tokens.ink)` in `makeUIView` is
  now dead code.
- Every `open()` failure reads "This document has no readable text.", including a load failure
  that isn't really that.
- The tap anchor and TextKit's own line samples use slightly different offsets into an element
  that happen to coincide for `NSTextContentStorage`.
- A newline inside a raw document/chapter title would split the paragraph element (untested,
  Task 1 territory); the typesetter's length-invariant `assert` traps the Debug app if it's ever
  wrong, on the open path.
- `ReaderText`: a spoken paragraph promoted to the document title keeps its chapter index (the doc
  comment's "nil" is for the drawn title only), and paragraph assembly re-counts `utf16.count` per
  span.
- An unused `import T2SLibrary` in `Sources/T2SApp/Reader/ReaderModel.swift` and
  `Tests/T2SAppTests/ReaderModelTests.swift`.
- The paragraph tint runs to the container edge on every wrapped line but the last (`.highlight`
  segments carry selection geometry) — check on the phone; intersect with the line's typographic
  bounds if disliked.
- Latent: an EPUB resource whose blocks carry neither a selector nor a progression would collapse
  into one paragraph.

**Dev rule from the owner: never play audio on the Mac.** Simulator runs only as
`SIMCTL_CHILD_T2S_SILENT=1 xcrun simctl launch <udid> com.t2s.reader` (the app mutes every player
when `T2S_SILENT` is set). Never change the Mac's volume.

**Incident, morning of 2026-09-08.** The simulator's `coreaudiod` deadlocked for about forty
minutes — every launch aborted inside `AVAudioEngine` init on a `coreaudiod` RPC timeout,
reproduced across a full `simctl erase`, so the fault was the host daemon, not app or guest state.
It cleared by itself. Nobody restarted it: `coreaudiod` is the Mac's shared audio service, and
restarting a shared system daemon on the owner's Mac was not this task's call to make — leave it
to the owner if it recurs.

**The phone checklist.** Install with scheme **Phone**, your team on both targets (the recipe
under "The iPhone 17 Pro run" below still applies). Open a book and check:

1. Open a book you are an hour or more into, and jump to a late chapter from the contents sheet:
   the page should appear without a stall and the tint should sit on the right words (every check
   on the Mac was a book opened at page one).
2. The page is off-white in light mode, the document title at the top, and the paragraph and word
   tints visible as the audio plays.
3. Appearance → Text size and Line height change the page live while it is open.
4. Theme → Dark darkens the whole app, including the Queue — not just the Reader.
5. A tap on a word starts playback there.
6. A drag stops following, and `Back to current` returns to the playhead.
7. The contents sheet jumps chapters.
8. A PDF reads along at the word, the same as an EPUB.

Two things the Mac cannot verify at all and needs the phone for: **taps** (does a tap land on the
word actually tapped) and **drags** (does a drag suspend following, and does `Back to current`
return correctly). If taps land one line off, the fix is in
`App/T2SReader/Reader/ReaderTextView.swift`'s `handleTap`: drop the `- line.typographicBounds.minY`
term from the point conversion.

**The simulator recipe, for the next person who needs to look at the Reader without a phone.**

```bash
U=<simulator-udid>
xcrun simctl boot $U; xcrun simctl bootstatus $U -b
xcrun simctl install $U .build/DerivedData-App/Build/Products/Debug-iphonesimulator/T2SReader.app
SIMCTL_CHILD_T2S_SILENT=1 xcrun simctl launch $U com.t2s.reader
C=$(xcrun simctl get_app_container $U com.t2s.reader data)
cp <fixture>.epub "$C/Documents/Inbox/"
xcrun simctl openurl $U "file://$C/Documents/Inbox/<fixture>.epub"
```

Open the `file://` path into the app container's `Documents/Inbox/` with `openurl`, not the
`t2s://` scheme — the scheme shows a confirmation sheet nobody can tap on a script-driven
simulator. The Inbox file is consumed per import, so copy it in again for a second run.

## Resume here (2026-09-06) — Plan 9

The owner's first listen on the iPhone 11 Pro (2026-09-05) reported three things: the voice list
should be Kokoro-only with previews; the Reader looked wrong (one word filling a black page); and the
voice sounded cut off, abrupt between sentences, and flat — "is this Kokoro, or how we set it up?"
Plan 9 (`docs/superpowers/plans/2026-09-05-plan-9-voice-quality-readalong.md`) answered and fixed:

- **Diagnosis** (`spikes/findings/2026-09-05-coreml-audio-quality.md`; probe `scripts/audio-probe.sh`,
  analyzer `scripts/analyze-wav.swift`): four of five causes were ours — upstream's punctuation
  silencing removed ~1 s of speech per 30 s; one Kokoro call per sentence left ~800 ms of dead air after
  each (identical on MLX: the model's behaviour for short inputs); long sentences were cut at a word and
  butted together; every second played went through a 32 kbps AAC cache at 13 dB SNR. The fifth, an even
  delivery, is Kokoro's own — the Core ML port is not flatter than the MLX reference.
- **Task 1** engine: `KokoroCoreMLEngine.Options.default` = no punctuation silencing + 5 ms crossfade;
  pieces cut at sentence/clause boundaries; an overflowing piece is re-split instead of dropped to
  silence; `AACCodec` 64 kbps (`aac-64k-mono-24k`; `FileAudioStore` removes the old codec directory);
  the model-backed tests share one compile; `scripts/test-kokoro.sh` sweeps Core ML's runtime cache.
- **Task 2** segmenter: consecutive sentences pack into one utterance up to 160 UTF-16 units
  (`Segmenter.appPackLength`, passed by `Library`); `Versions.segmenter` 2 — every stored timeline
  re-derives on its next play; `ReaderModel.playhead(for:in:)` seeks to the tapped word.
- **Task 3** voices: Kokoro-only list wherever a Kokoro route is listed (the Simulator build keeps the
  system voices — it links no engine); rows show name, accent, gender; `VoicePreviewModel` previews any
  row through the routed engine on its own player, pausing the book.
- **Task 4** Reader: Readium's `fontSize` is a ratio and was set to 18 (1800 %) — now 1.125 × scale;
  publisher styles off; sentence tint + word tint; ElevenReader chrome (floating circles, thin
  scrubber, transport row, voice chip, contents). Screenshot in the ledger (`task-4-reader.png`).
- **Dev rule from the owner: never play audio on the Mac.** Simulator runs only as
  `SIMCTL_CHILD_T2S_SILENT=1 xcrun simctl launch <udid> com.t2s.reader` (the app mutes every player
  when `T2S_SILENT` is set). Never change the Mac's volume.

**The phone listen (deferred — the phone is unplugged).** Same install recipe as the 2026-09-04
section below (scheme **Phone**, your team on both targets). Fresh documents re-segment on first play
(the segmenter version changed); already-rendered audio is discarded (new codec namespace). Listen for:
word endings intact; sentences flowing into each other with short pauses; no mid-sentence seam; a
cleaner, less "underwater" tone (64 kbps); Preferences → Voice showing 28 Kokoro rows, no System
section, previews playing on tap and pausing the book; the Reader readable with the sentence and word
tints. Delivery that still feels flat is the model — try Bella, Nicole, Sarah or the British voices.

**Deferred:** a 30 s Core ML bucket (whole paragraphs in one call, as the MLX reference does — needs the
30 s decoder pair and the 512-token duration model staged; bigger bundle, longer first-launch plan
build); the Player sheet's styling (retired in Plan 12); Kokoro in the Simulator build (needs a
phonemizer without MLX).

## What this is

An iOS app that turns EPUBs, web articles, and text PDFs into read-along audiobooks
synthesized on the phone. The design spec is the source of truth:
[docs/superpowers/specs/2026-09-01-t2s-reader-design.md](superpowers/specs/2026-09-01-t2s-reader-design.md)
(rev 13). Work is organised as numbered plans under
[docs/superpowers/plans/](superpowers/plans/), each a list of tasks with the exact code, tests,
and commit message per task. The roadmap is
[2026-09-02-t2s-reader-roadmap.md](superpowers/plans/2026-09-02-t2s-reader-roadmap.md).

## Branches

| Branch | State | Notes |
|---|---|---|
| `dev` | integration branch | Plans 1–6, 8–12 merged (root `swift test` 365 tests / 78 suites; `Packages/T2SKokoro` 93 / 14; `scripts/test-readium.sh` not re-run since Plan 10 — the Readium package is untouched). Earlier notes: Plan 5 Tasks 5–6 were fast-forwarded from `plan-5-task-5-kokoro` on 2026-09-03 (`938c8b8 … ba207ed`, twelve commits, every task reviewed plus a whole-branch review). Root package: **309 tests in 72 suites** (`swift test`). `Packages/T2SKokoro`: **56 tests in 7 suites** (`scripts/test-kokoro.sh`; seven of them are gated on the real model files being installed — four load the 327 MB model and two of those synthesize audio). `Packages/T2SReadium`: **12 tests in 3 suites** (`scripts/test-readium.sh`, on the iPhone simulator). The everyday app builds, launches, imports an EPUB, and plays it on the simulator and on an iPhone 11 Pro. |
| `main` | stale: only the initial spec commit | Not used for integration yet; fast-forward it to `dev` when you want a release point. |

Plan branches are short-lived: each plan runs on its own branch off `dev` (locally in a git
worktree under `.worktrees/`, git-ignored) and is merged and deleted when its final review is clean.

## Toolchain

- Xcode 26.6 (Swift 6.2), macOS 15+. CI uses that single pinned toolchain, restores both SPM and Xcode package caches, and retries transient package resolution. `brew install xcodegen`. An iPhone simulator installed. The Plan 5 Task 5/6 pass on this branch was run locally on **Xcode 26.3** (iPhoneSimulator 26.2 SDK), not on CI's 26.6 — every build and test result quoted below is from that toolchain.
- `swift test` — the root package on macOS (everything except Readium).
- `scripts/test-readium.sh` — the iOS-only Readium package on the simulator (`SIMULATOR_ID=<udid>` to pick one).
- `scripts/build-app.sh` — regenerates `App/T2SReader.xcodeproj` from `App/project.yml` and builds the app for the simulator. Then `open App/T2SReader.xcodeproj` to run it.
- `scripts/check-licenses.sh` — fails on any copyleft dependency (CI runs it).
- `scripts/fetch-kokoro-coreml.sh --app` — stages the Core ML Kokoro model files (8 `.mlpackage`
  stages, 28 English voices, 2 runtime JSONs; 54 files, 347 MB) into `App/Resources/KokoroCoreML`
  (git-ignored, sha256-verified). Run it once per machine: it is what the default voice needs.
- `scripts/fetch-kokoro-model.sh` — installs the MLX Kokoro weights and voice styles into
  `App/Resources/Kokoro` (git-ignored, checksum-verified). Run it once per machine if you are
  working on the MLX route; without it the MLX package tests skip and a device build bundles no
  MLX voices. The app does not need it.
- `scripts/test-kokoro.sh` — `Packages/T2SKokoro` with `xcodebuild` on macOS. Not `swift test`: MLX
  loads a compiled Metal library that only a full Xcode build stages next to the binary. Runs
  `-parallel-testing-enabled NO` on purpose (see the script header).
- `scripts/build-device.sh` — Release, `generic/platform=iOS`, unsigned: the compile proof for the
  `T2SReaderKokoro` target. The first run compiles mlx-swift for iphoneos (10–15 min, ~2 GB).

CI runs the test and build scripts (not the fetch ones): a `kokoro-macos` job for
`scripts/test-kokoro.sh`, added by Task 5a with a 45-minute timeout, and an `app-ios` job that runs
`scripts/build-app.sh` then `scripts/build-device.sh` — its timeout went 30 → 45 minutes because it
now compiles MLX for iphoneos on a cold cache. The model files are absent in CI, so the
model-backed Kokoro tests report as skipped there.

Never commit generated files (`*.xcodeproj`, `App/T2SReader/Info.plist`, `App/T2SReader/Info-Kokoro.plist`, `.build/`); one `.gitignore` at the root.

## What exists

Everything here is on `dev`.

- **T2SCore** — text pipeline: normalizer with span mapping, sentence segmenter, two-phase timeline (estimated → actual durations), per-chapter codec, `Position` resolution, highlight projection, render policy tiers, render scheduler, audio cache with LRU. Plan 1 + Plan 2.
- **T2SAudio** — `AudioPlayer` on `AVAudioEngine` with pitch-corrected rate, `PlaybackCoordinator` (owns the playhead), `AACCodec`, and `SystemSpeechEngine` (AVSpeechSynthesizer; the engine until Kokoro lands). Plan 2 + Plan 4a.
- **T2SStore** — SwiftData store (`LibraryStore`): documents, per-chapter timeline blobs, queue order, resume positions as flattened columns, bookmarks, pronunciation dictionary; versioned schema; `PlayheadStore` conformance. Plan 3.
- **T2SLibrary** — `Library` facade (import file / article, delete, re-derive stale timelines, evict audio), `PDFDocumentReader` (PDFKit), stored-only ZIP writer, `ArticleEPUBWriter`, container layout `LibraryPaths`. Plan 3.
- **Packages/T2SReadium** (iOS only) — `ReadiumDocumentReader` (EPUB → chapters with stable `Position`s) and `LocatorMapping` (`Position` ↔ Readium `Locator`, word-highlight quotes). Plan 3.
- **T2SApp** (root package target, testable on macOS) — the app's models: `LibraryModel`, `PlayerModel`, `ScrubberModel`, `ImportModel`, `DurationFormatter`, `AppPaths`, `DeviceStateMapping`. Plan 4a.
- **App/** — the SwiftUI app `T2SReader`: design tokens and type roles (Inter, bundled), composition root, three-page pager with mini-player, Queue page, Collection page + book sheet, player sheet with the tick scrubber (retired in Plan 12), Add sheet (paste a link → WKWebView + Readability.js extraction preview, open a file, paste text), audio session + device monitor. Plan 4a. Plan 5 added the Now Playing controller and remote commands, Preferences → Cloud voices, the Prepare task boundary, and the `T2SReaderShare` Share Extension.
- **Packages/T2SKokoro** (tested on macOS, links only into the device target) — `KokoroResources`
  (the checksummed model-file contract), `KokoroEngine` (an actor over kokoro-ios/MLX; identity
  `kokoro-4e9ecdf0-mlx-misaki1.0.6`), `KokoroTokenTimingMapper`, `KokoroRuntimeDecision` and
  `KokoroAvailability`. Plan 5 Task 5.
- **Packages/MLXUtilsLibrary** — a vendored copy of `mlalma/MLXUtilsLibrary` 0.0.6 with our own
  `NpzArchive` in place of ZIPFoundation. Plan 5 Task 5; see "Known issues" for why and for the
  exit plan.

## Where things are right now

The integration branch carries Plan 5 in full: its last commit, `ba207ed`, sits on top of
`153af2a` (the approved Task 5 adjustments) and `499d3fa` (the spike findings and the PR #14/#15
merges). The completed work is:

- **Plan 4a** is complete.
- **Plan 4b Tasks 1–8** are merged: PR #2 (Reader models and preferences), PR #3 (pronunciation,
  storage, and voice-change models), PR #4 (Reader and appearance UI), and PR #7 (Preferences and
  voice-change UI). PR #10 is the Reader review-fix wave; PR #11 is the Preferences review-fix wave.
  They include safe destructive audio-change APIs, no-op unchanged voices, session-owned voice
  previews that stop on disappearance, robust Readium/PDF handling, and publication cleanup.
- **Documentation and CI**: PR #5 documented the Reader controls; PR #6 made CI deterministic on a
  single Xcode 26.6 toolchain and added SPM/Xcode package caches plus package-resolution retries.
- **Plan 5** is written in PR #8. Task 1 (Now Playing, remote controls, and media-services recovery)
  merged in PR #9, Task 3 (multi-document Prepare and `BGProcessingTask`) in PR #12, Task 4
  (BYO-key cloud engine) in PR #13, and Task 2 (Share Extension) in
  [PR #15](https://github.com/AtharvaN16/T2S_Reader/pull/15).

The app has been built and launched on the simulator. CI reruns every script below on each push.

**Plan 5 Task 5 (Kokoro) landed on `plan-5-task-5-kokoro`, commits `938c8b8 … 647fad6`**, in the
order the approved "Task 5 adjustments" set out. What is now in the tree:

- `Packages/T2SKokoro`: `KokoroResources` (the checksummed model contract), `KokoroEngine` (an
  actor; `identity` = `kokoro-4e9ecdf0-mlx-misaki1.0.6`), `KokoroTokenTimingMapper` (returns `[]`
  until the 17 Pro fixture exists), `KokoroRuntimeDecision` (`current == nil`; a `DEBUG`-only
  override), `KokoroAvailability` + `KokoroAvailabilityModel`.
- Root package: `KokoroVoiceID`, the `kokoro:` route in `RoutedEngine`, the `VoiceRouteResolving` /
  `KokoroVoiceRouting` seam that substitutes the whole document's voice *before* planning,
  `VoiceOption.group`, `KokoroVoiceCatalog` (28 voices, cross-checked against `voices.npz`), and
  the `NumberWords` compound-number spacing fix with a normalizer version bump. **That bump has an
  upgrade cost:** `Versions.normalizer` becomes 2, so on first play every document already in a
  library is stale — it is re-normalized and re-segmented (spec §3.7.3), and the audio rendered
  under normalizer 1 becomes orphaned cache that only LRU pressure removes. Positions survive:
  `PositionResolver` re-resolves them against the new segmentation.
- App: **two targets from one xcodegen template** — `T2SReader` (simulator and any phone, no MLX)
  and `T2SReaderKokoro` (`SUPPORTED_PLATFORMS: iphoneos`, links the engine, compiles with
  `KOKORO_ENGINE`). `KokoroComposition` is the only `#if`. Preferences → Voice shows a "Kokoro
  (beta)" section with an availability footer. New scripts `fetch-kokoro-model.sh`,
  `test-kokoro.sh`, `build-device.sh`; `build-app.sh` now signs ad hoc locally.
- Why two targets: mlx-swift 0.30.2 cannot link for the iOS Simulator — the iPhoneSimulator SDK's
  Metal framework does not export `_MTLIOErrorDomain` / `_MTLTensorDomain`, on both architectures —
  and Xcode resolves packages per project, not per target.

**Plan 5 Task 6 is this documentation commit.** The whole suite is green on this branch:
`swift test` 309 tests / 72 suites; `scripts/test-kokoro.sh` 56 tests / 7 suites
(`** TEST SUCCEEDED **`); `scripts/test-readium.sh` 12 tests / 3 suites (`** TEST SUCCEEDED **`, on
the iPhone simulator); `scripts/check-licenses.sh` exit 0; `scripts/build-app.sh` and
`scripts/build-device.sh` both `** BUILD SUCCEEDED **`.

**Real Kokoro synthesis has run — on this Mac, not on a phone.** Task 5b's model-backed test
synthesized one 3.25 s sentence with `af_heart`: model load 1.14 s and RTF 0.456 warm; 1.54 s /
RTF 1.633 cold, with Metal kernel compilation inside that first call. These are Mac numbers and
set no thresholds; they do suggest a warm-up synthesis may be worth it on device, since the first
utterance pays the kernel compile.

**Playback crash, found and fixed 2026-09-03 (afternoon).** Playing any document crashed the app
(`EXC_BREAKPOINT` on MediaPlayer's `accessQueue`) the moment `MPNowPlayingInfoCenter` pushed the
first Now Playing dictionary: the `MPMediaItemArtwork` request handlers were formed inside the
`@MainActor` `NowPlayingController`, so Swift 6 inferred main-actor isolation and inserted an
executor check that MediaPlayer's queue fails. Nobody had played a document on an iOS runtime
before (Task 9 was never run), which is how it survived. Reproduced on the iPhone 16 Pro
simulator; the five crash reports later pulled off the iPhone 11 Pro (iOS 26.6.1) with
`xcrun devicectl device copy from --domain-type systemCrashLogs` carry the identical frames. Fixed
(merged to `dev` as 2540e1c, confirmed on the phone):
`NowPlayingArtwork.make(_:)` in `T2SApp` forms the handler in a nonisolated context, with a test
that calls it from a global queue. After the fix an EPUB was imported through `onOpenURL` and
played in the Reader for 45 s+ on the simulator without incident.

## Manual validation matrix

Nothing below was run on a phone for this commit: no device is attached to this Mac and the
iPhone 17 Pro is Harsh's. Every row says what the *best available* evidence actually is. A row
marked **pending hardware** has never run on a device — treat it as untested, not as a footnote.
Plan 6's rows say **pending the owner's listen**: the code is built and the app bundle inspected,
but nothing on that branch has been installed on the owner's iPhone 11 Pro. The recipe for that
install is under "Resume here" below, and it is the last thing between Plan 6 and a merge.

| Scenario | Best evidence today | Status |
|---|---|---|
| Kokoro whole-document fallback in a build without the engine | iPhone 16 Pro simulator, iOS 18.5 (Task 5f): the log carries `Kokoro engine not linked in this build` and `voice route fallback: kokoro → default` while the Reader plays; no `KokoroRouteError` and no render error in the 37 s to the screenshot. Plan 6 renamed that line — it now reads `voice route resolved: kokoro → default`, because it fires on the happy path too | **passes (simulator)** |
| Kokoro synthesizes real audio through kokoro-ios/MLX | this Mac (Task 5b + `scripts/test-kokoro.sh`): seven tests are gated on the real files, four of them load the 327 MB model and `voices.npz`, and two synthesize audio; one 3.25 s sentence at RTF 0.456 warm | **passes (macOS)** |
| `T2SReaderKokoro` links MLX, embeds `KokoroSwift.framework`, bundles the ~342 MB of model files | `scripts/build-device.sh` — `** BUILD SUCCEEDED **`; `Frameworks/` contains `KokoroSwift.framework` and `otool -L` resolves into the bundle. The spike harness's missing-framework gotcha does not reproduce for this target | **passes (compile + link)** |
| `T2SReaderKokoro` bundles the Core ML stages | `scripts/build-device.sh` — `** BUILD SUCCEEDED **`; the built `.app` carries the eight `.mlmodelc` bundles, the 28 `*.bin` voices and both runtime JSON files at its root and weighs 433 MB with no MLX weights staged (Plan 6 Task 5) | **passes (compile + bundle)** |
| Core ML Kokoro speaks by default on a fresh document | wired in Plan 6 Tasks 4–5 and covered by root-package tests; no phone has played it | **pending the owner's listen** |
| The first-launch warm-up footer, and how long it stays up | the string is compiled in; the 206 s it warns about is the A13 spike harness, not this app | **pending the owner's listen** |
| Read-along highlight follows the Core ML word timings | Task 3's fold is unit-tested against synthetic frames and the §7.4 gate is open; nothing has watched a highlight move | **pending the owner's listen** |
| 2x and 4x offered, and 4x sustained | `maxSustainableRate` is 4.0, derived from the measured RTF 0.181; the derivation is tested, the playback is not | **pending the owner's listen** |
| The `.available` / `.unavailable(reason)` Preferences footer strings, and `GatedKokoroEngine`'s construction path | compiled only. On a simulator the probe answers `.unavailable(.simulator)` before any GPU check, and the everyday target does not link the engine, so neither has ever executed | **pending hardware** |
| Now Playing dictionary pushed without crashing | iPhone 11 Pro, iOS 26.6.1: the artwork main-actor crash was reproduced there and the fix (`2540e1c`) confirmed on the phone | **passes (hardware, this path only)** |
| Lock Screen and Control Center transport controls | Plan 5 Task 1 verified the software seams (PR #9); step 7 of the first listen below covers them on the Kokoro build | **pending hardware** |
| AirPlay route selection | — | **pending hardware** |
| Wired route change (headphones unplugged mid-playback) | — | **pending hardware** |
| Bluetooth route change (AirPods connect / disconnect) | — | **pending hardware** |
| Phone-call interruption and resume | — | **pending hardware** |
| `mediaServicesWereReset` recovery (force it from the debugger) | PR #9 seams only | **pending hardware** |
| Share sheet payloads: link, plain text, EPUB, PDF — and each failure string | Task 2 merged in PR #15; import through `onOpenURL` works on the simulator | **pending hardware** |
| App-group hand-off: extension writes `ShareInbox`, host finishes the import | the entitlement is why `scripts/build-app.sh` now signs ad hoc, and the ad-hoc-signed simulator app does open its library | **pending hardware** (partial) |
| Prepare stops on unplug, Low Power Mode, and thermal pressure | Plan 5 Task 3 (PR #12) verified the runner and the visible state on a simulator | **pending hardware** |
| `BGProcessingTask` forced from the debugger | the simulator rejects the request outright — `BGTaskSchedulerErrorDomain error 1`, seen again in the Task 5f capture | **pending hardware** |
| `BGProcessingTask` overnight on charge | — | **pending hardware** (§7.7 asks for three nights) |
| Cloud voice: missing key, 401, 429, network loss, configuration change | Plan 5 Task 4 (PR #13) unit coverage inside `swift test` | **pending hardware** — no real provider key has been exercised end to end |
| Plan 0 Kokoro metrics §7.3, §7.4, §7.5 — Core ML route | iPhone 11 Pro (A13): CPU-only Core ML, RTF 0.18 flat out and 0.16 over 20 min at 4x, 119 MB flat, word-onset error ≤ 55 ms; thermal state 2 after 150 s at 4x on charge with no speed collapse (`spikes/findings/2026-09-04-pre-a14-runtime.md`) | **passes (hardware)**; unplugged thermal/battery run pending |
| Plan 0 Kokoro metrics §7.2, §7.3, §7.5, §7.7 — MLX route | needs an A14+ phone; nothing measured | **pending hardware** (the 17 Pro, protocol below) |
| Bookmarks: add in the Reader, list in Book sheet and overflow, jump, swipe-delete | wired in Plan 8 Tasks 2–3; `BookmarkListModelTests`/`BookmarkSnippetTests` cover the model, the Book sheet section is hidden until a document has a bookmark, `scripts/build-app.sh` — `** BUILD SUCCEEDED **`; nobody has tapped it | **pending simulator** |
| App icon on the home screen | `scripts/make-app-icon.swift` draws it deterministically (byte-identical shasum across two runs), `Assets.car` is produced and `CFBundleIconName` resolves to `AppIcon` in the built Info.plist (Plan 8 Task 1); no home screen has been looked at | **pending simulator** |
| VoiceOver: Queue row / Collection cell / bookmark row / mini-player title read as one element each | wired in Plan 8 Task 4 — `.accessibilityElement(children: .combine)` on the Queue row's meta line, a combined label on the Collection cell, `BookmarkRow`'s own combined label, the mini-player title wrapped in an activatable `Button`; `scripts/build-app.sh` — `** BUILD SUCCEEDED **`; never run under VoiceOver | **pending hardware** |

## The iPhone 17 Pro run (for Harsh)

**This visit is optional now.** Core ML is the baseline runtime on every phone (Plan 0 Task 8, and
Plan 6 shipped it), so nothing in the app waits on these numbers any more. The reason to do the run
is a comparison: if MLX on an A14+ phone beats Core ML's RTF 0.181 by enough to change an offered
rate or battery life, the routing already has a place for it — `KokoroVoiceRouting` holds one route
per engine identity, and both engines are linked into `T2SReaderKokoro` today. If it does not, the
MLX route simply stays wired, gated and unmeasured.

Two halves. The **spike harness** produces the Plan 0 numbers; the **app** proves the MLX route
end to end. Do the harness first — its CSV is what unblocks the code.

**1. The spike harness.** `spikes/README.md` is the complete protocol: the exact `xcodebuild` /
`devicectl` commands, the launch environment for each spec section (§7.3/§7.5 `SPIKE_AUTORUN_SECONDS=300`
at rate `0`, then `1200` at rate `3` for thermals; §7.2 with `SPIKE_BACKGROUND_AUDIO=1` for 15
minutes screen-off, repeated in Low Power Mode; §7.7 three nights on charge), how to pull the CSV
back, and every tooling gotcha — Release with `ENABLE_DEBUG_DYLIB=NO`, the `KokoroSwift.framework`
copy-and-re-sign step, the free-team three-app limit, and which of the two device identifiers each
tool wants. Write one findings file per section into `spikes/findings/` from `TEMPLATE.md`.

**2. The app.** This is what has never run:

```
scripts/fetch-kokoro-coreml.sh --app   # the Core ML files: the app's default voice needs them
scripts/fetch-kokoro-model.sh          # the MLX weights, or the build bundles no MLX voices
open App/T2SReader.xcodeproj           # generated by scripts/build-app.sh or scripts/build-device.sh
```

- Scheme **Phone** (the `T2SReaderKokoro` target; not **Simulator**). It is device-only by design; the simulator cannot
  link MLX.
- Signing & Capabilities → your own team, on **both** `T2SReaderKokoro` and `T2SReaderShare`. The
  app group `group.com.t2s.reader` must stay on both or the app cannot open its library. A free
  personal team allows three apps on a device and an app with an extension counts twice.
- Edit Scheme → Run → Arguments → Environment Variables: `T2S_KOKORO_DEBUG_OVERRIDE` = `1`. That
  flag is the **MLX** route's alone. Without it `KokoroRuntimeDecision.current` is `nil`, the MLX
  route reports itself unavailable, and every document plays on the Core ML route instead — correct
  behaviour, just not what you came to test. (The `kokoro.debugOverride` user default does the same
  thing.) The override is compiled out of Release builds; with it on, the Preferences footer gains a
  second line, "MLX route: development override active.", and the picker gains a second set of 28
  voices whose rows end in " · MLX". With the override on, Kokoro also runs in Prepare and in
  background play-ahead — that is the §7.2/§7.7 experiment, not an enforced policy yet: the
  decision's `backgroundInferencePermitted` and `idleInferencePermitted` flags are recorded but read
  nowhere.
- Build and run on the phone from Xcode. `scripts/build-device.sh` builds the same target unsigned
  from the command line — useful for a compile check, useless for installing.
- In the app: Preferences → Voice → the **On-device voices** section. Read the footer first: the
  first line is the Core ML route, the second the MLX one. Pick a voice whose detail line ends in
  " · MLX", then play a book and let it run.
- What to report back: does the second footer line appear; does the first sentence play; how long
  the first utterance takes versus later ones (MLX compiles Metal kernels during the first
  synthesis); whether the read-along highlight tracks at word level (Plan 6 opened the §7.4 timing
  gate for both runtimes); and anything in the log under subsystem `com.t2s.reader`.

If a `devicectl` install is used instead of Xcode, build Release with `ENABLE_DEBUG_DYLIB=NO` —
Xcode's debug-dylib layout leaves the package frameworks in DerivedData and the installed app
aborts at launch with `Library not loaded: @rpath/KokoroSwift.framework`. The app target itself
does embed `KokoroSwift.framework` correctly, so the spike harness's manual copy-and-re-sign step
is **not** needed here.

## Resume here (2026-09-04) — superseded by the 2026-09-06 section above; the install recipe still applies

Plan 6 (`docs/superpowers/plans/2026-09-04-plan-6-coreml-kokoro-engine.md`, the Core ML Kokoro
engine) is **finished on branch `plan-6-coreml-engine`** — Tasks 1–6, each committed and reviewed —
checked out in the git worktree `.worktrees/plan-7-coreml-engine` (the directory kept the name it was
created with, before the plans were renumbered; `git worktree list` tells; since the morning of
2026-09-04 that worktree has `plan-8-bookmarks-icon-voiceover` checked out, which contains every
Plan 6 commit). It is **not merged**: the one thing left is the first listen on the owner's
iPhone 11 Pro, written out below. Do that, fix whatever it turns up, then merge to `dev` — Plan 6
first, Plan 8 after it; `dev` fast-forwards through both. Later that morning the owner asked for one
folder and one obvious build: both branches fold into `dev`, the worktree is removed, and the Xcode
schemes are now **Phone** (the `T2SReaderKokoro` target, the app for an iPhone) and **Simulator**
(the `T2SReader` target, the Mac-only build). The recipe below runs from the main checkout.

The first listen happened that morning and found one crash: the first chapter died in MLX with
"[Compiled::eval_cpu] CPU compilation not supported on the platform". MisakiSwift's fallback network
for words outside its lexicon applies MLXNN's `gelu`, an MLX *compiled* function, and the CPU backend
compiles those at run time with a C compiler that iOS does not have. The spike corpus never contained
an unknown word; a book has a name on every page. `KokoroCoreMLEngine` now calls
`MLX.compile(enable: false)` once before the first G2P exists — process-global, so the MLX route loses
its fused kernels too (a benchmark-only cost on A14+ phones) — and
`KokoroCoreMLEngineTests.speaksWordsTheLexiconDoesNotKnow` walks the fallback with two invented names.
The rest of the checklist below is still to be reported.

State of this Mac on the morning of 2026-09-04, for whoever runs the recipe:

- **Disk.** The night ended at about 1.4 GB free. The regenerable Xcode caches under
  `~/Library/Developer/Xcode/DerivedData` (`ModuleCache.noindex` and the two older `T2SReader-*`
  trees from GUI builds) were deleted on the owner's instruction that morning. `.build/DerivedData-App`
  in the worktree is the app build tree the recipe's signed build reuses; keep it. Any cold MLX build
  needs about 2 GB and a full `scripts/test-kokoro.sh` run about 2 GB more (see the leak below).
- **What has not run.** The model-backed `KokoroCoreMLEngineTests` suite was skipped in Plan 6's
  final fix wave for lack of disk (it was green at f1513a6); run the full `scripts/test-kokoro.sh`
  once space allows. Nothing has run on a phone. App Store upload validation of the icon has not run.
- **The build tree was rebuilt once.** A Plan 8 subagent ran `rm -rf .build` in the worktree, which
  also removes `.build/DerivedData-App`; it has since been rebuilt by the Plan 8 device build. Never
  delete `.build` in this worktree to "clean" the SwiftPM products.
- **Rulings.** Every decision taken without the owner is in the two ledgers named below and was
  listed in the session's final message; each names what it costs if wrong.

What landed:

- **Task 1** — `Packages/KokoroPipeline`, a vendored copy of `mattmireles/kokoro-coreml` @
  `66d8cf51` (Apache-2.0; the upstream repository keeps its `Package.swift` in a `swift/`
  subdirectory, which SwiftPM cannot consume by URL), and `scripts/fetch-kokoro-coreml.sh --app`,
  which stages the eight Core ML stages, the 28 English voices, the vocab and the hn-NSF weights
  into the git-ignored `App/Resources/KokoroCoreML` — 54 files, 347 MB, every one sha256-verified.
- **Task 2** — `KokoroCoreMLResources` (the file contract), `KokoroCoreMLDecision` (the A13
  measurement: RTF 0.181, so every rate up to 4x is offered, and a 119 MB footprint) and
  `KokoroTokenizer`.
- **Task 3** — `KokoroCoreMLEngine`: an actor, every stage on the CPU, identity
  `kokoro-coreml-2e878c6a-misaki1.0.6`. It produces real per-word timings folded from the
  pipeline's duration frames, which is what opened the spec §7.4 gate in `KokoroTokenTimingMapper`
  for both runtimes, and it chunks an utterance longer than the pipeline's 15 s bucket into pieces
  of at most 176 tokens, cut at word boundaries.
- **Task 4** — `RoutedEngine` holds several Kokoro engines keyed by identity; `KokoroVoiceRouting`
  holds one route per identity plus a default-voice rule ("default" → Kokoro Heart on the Core ML
  route while that route is available, leaving the stored document voice untouched);
  `KokoroVoiceCatalog` lists every linked runtime, MLX rows ending in " · MLX".
- **Task 5** — the app. `T2SReaderKokoro` bundles `Resources/KokoroCoreML` (Xcode compiles the
  `.mlpackage`s into `.mlmodelc`; the `.app` is 433 MB), `GatedKokoroCoreMLEngine` and a
  first-launch warm-up shown in the Preferences footer, the MLX route kept beside it with its
  voices listed only once its probe answers `.available` (A14+, weights staged, development
  override on), the "Default voice" row resolving through the routing, and both build scripts plus
  CI's "Generate app project" step creating the two git-ignored resource directories before
  `xcodegen` — it refuses a missing source path.
- **Task 6** — this documentation.

The ledger with every ruling is
`.superpowers/sdd/2026-09-04-plan-6-coreml-kokoro-engine/progress.md` inside that worktree, with a
report per task beside it.

Two things Task 3 learned that will bite anyone who runs the package tests. The engine's
*development* path (raw `.mlpackage` staging, which `scripts/test-kokoro.sh` uses) compiles the
eight stages into `$TMPDIR` on every engine instance and never removes them, so each model-backed
engine test leaks about 350 MB — 4.7 GB was found and deleted here in one night, and
`rm -rf "$TMPDIR"/kokoro_*.mlmodelc` is the reclaim. The app bundle is precompiled, so it compiles
nothing and leaks nothing. And `preload()` is `async` with a shared compile, so a render cancelled
during a cold load waits the compile out rather than returning promptly.

### The first listen, on the owner's iPhone 11 Pro

Prerequisite, once per machine: `scripts/fetch-kokoro-coreml.sh --app` must have staged
`App/Resources/KokoroCoreML` (it has, on this Mac — 347 MB). `scripts/fetch-kokoro-model.sh` (the
MLX weights) is **not** needed and is deliberately absent here.

Phone on USB, **unlocked** (`devicectl` refuses a launch on a locked device), and trusted.

**1. Find the two device identifiers.**

```bash
xcrun devicectl list devices        # CoreDevice UUID — what devicectl wants
xcrun xctrace list devices          # UDID (00008030-…) — what xcodebuild -destination id= wants
```

**2. Signed Release build.**

```bash
cd ~/Developer/t2s_reader/.worktrees/plan-7-coreml-engine/App
mkdir -p Resources/Kokoro Resources/KokoroCoreML
xcodegen generate --quiet
xcodebuild build -scheme Phone -destination 'generic/platform=iOS' \
  -configuration Release -derivedDataPath ../.build/DerivedData-App \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=V69PL7U8EX ENABLE_DEBUG_DYLIB=NO
```

`ENABLE_DEBUG_DYLIB=NO` is not optional for a `devicectl` install: Xcode's debug-dylib layout leaves
the package frameworks in DerivedData and the installed app aborts at launch with `Library not
loaded: @rpath/…`.

If automatic signing has never run for this team from the shell it will fail, because the profile
has to exist first. Two ways out: add `-allowProvisioningUpdates` (which works only if Xcode is
already signed in), or do the whole thing in the GUI instead —

> `open App/T2SReader.xcodeproj` → scheme **Phone** (not **Simulator**) → Signing &
> Capabilities → the team on **both** `T2SReaderKokoro` **and** `T2SReaderShare`, keeping the
> `group.com.t2s.reader` app group on both → build configuration Release — the Phone scheme's Run action is Release since Plan 13 (`App/project.yml`), so nothing to set
> → Run on the phone. A free personal team allows three apps on a device and an app with an
> extension counts twice; `MIFreeProfileValidatedAppTracker … ApplicationVerificationFailed` means
> remove one.
>
> Do **not** set `T2S_KOKORO_DEBUG_OVERRIDE` this time. That flag is the MLX route's development
> escape hatch; the Core ML route needs nothing from it, and on the 11 Pro it would change nothing
> anyway — the A13 fails the GPU-family gate whatever the override says.

**3. Install and launch from the command line.**

```bash
WT=~/Developer/t2s_reader/.worktrees/plan-7-coreml-engine
APP=$WT/.build/DerivedData-App/Build/Products/Release-iphoneos/T2SReaderKokoro.app
xcrun devicectl device install app --device <CoreDevice-UUID> "$APP"
xcrun devicectl device process launch --device <CoreDevice-UUID> --terminate-existing com.t2s.reader
```

**4. Watch the log** in a second terminal, started *before* the launch.

```bash
log stream --predicate 'subsystem == "com.t2s.reader"' --style compact
```

Lines to look for, in order:

- `Kokoro Core ML route available (coreml-cpu, RTF 0.181)` — the bundle's files were found.
- `Kokoro MLX unavailable: …` — expected on the 11 Pro (the A13 fails the GPU-family gate, and no
  MLX weights are staged in this build anyway). It is silent in the UI by design.
- **`Kokoro Core ML warm-up finished in <N> s`** — the number this whole run is for. The A13 spike
  measured **206 s** to build the compute plans on a *first* launch; later launches should be
  seconds. `Kokoro Core ML warm-up failed, retrying: …` means the first attempt threw and a second
  starts two seconds later; `… failed, route closed: …` means both did and the phone will speak
  this book with the system voice. Capture either message.
- `voice route resolved: default → kokoro:kokoro-coreml-2e878c6a-misaki1.0.6:af_heart` when a
  document loads.

**5. The checklist.**

1. **First launch, before anything else:** Preferences → Voice → the **On-device voices** footer
   should read *"Preparing the Kokoro voice (one-time, up to a few minutes on the first launch)…"*. Note
   how long it stays there — expect around 206 s on this phone the first time, seconds afterwards —
   then it must flip to *"Runs on this device."*. There should be **no** second "MLX route:" line.
2. **Stop during the warm-up** — the first launch is the only chance, so do it while that footer
   still says "Preparing…". Open any book, press play, wait a few seconds, then press stop. The
   render does *not* cancel promptly: the stage load is shared, and a waiter cancelled during a cold
   load sits out the whole compile before it comes back. So what is being checked is that the app
   survives it — the transport goes back to stopped, nothing spins forever, and playback works
   normally once the warm-up line lands in the log. Note whether an error banner appears (it may;
   what matters is that the app is not wedged), and report a stuck transport or a spinner that
   never clears.
3. Preferences → the **Default voice** row's grey subtitle should read **"Heart · American · Female"**,
   not "System default", once the page has appeared.
4. Preferences → Voice: only the **On-device voices** and **Cloud** sections appear — no **System**
   section at all. On-device voices lists **28** rows, each named "Heart", "Bella", and so on, with a
   detail line like "American · Female" — **one** set, with no " · MLX" suffix.
5. Import a **fresh** EPUB (share sheet, or the `t2s:` URL). Fresh matters: a document imported
   before this build already has a stored `voiceID`. Press play without choosing a voice —
   **Kokoro Heart should speak**, not the system voice. Time the wait from tap to first audio.
6. **Read-along:** the highlight should follow **individual words**, not whole sentences.
   Sentence-level highlighting means the word timings did not arrive, and is worth reporting.
7. **A long sentence, listened to at the seam.** Find or paste one of about **60 words or more**
   (Dickens and Melville oblige; so does a pasted paragraph with the full stops taken out). The
   duration model tops out at 256 tokens, so the engine cuts anything longer into pieces of ≤ 176
   phoneme ids, synthesizes them separately and concatenates the audio — about 13 seconds a piece.
   Listen at the joins for a click, a swallowed or doubled word, or a gap, and watch that the
   highlight keeps tracking across them. A prosody dip at the seam is expected and fine; a missing
   word is not.
8. **Speed:** the picker should offer **2x and 4x** (`maxSustainableRate` is 4.0, from RTF 0.181).
   Play at 4x for a minute and listen for dropouts.
9. **Lock screen:** lock the phone mid-playback. Play/pause, skip back, skip forward, the title and
   the artwork should all work from the Lock Screen and Control Center.
10. Report back: the warm-up seconds, whether stopping during the warm-up left the app usable, the
    tap-to-first-audio latency at 1x, whether word highlighting tracks, how the seam in a long
    sentence sounds, whether 4x sustains, whether the Lock Screen controls work, and anything in the
    `com.t2s.reader` log that is not in the list above.

**Plan 8 is also complete**, on branch `plan-8-bookmarks-icon-voiceover`, stacked on
`plan-6-coreml-engine` in this same worktree — merge it after Plan 6. It adds a bookmark list
(add from the Player or the Reader's overflow, browse it from the Book sheet or from either
overflow's **Bookmarks** item, tap to jump, long-press to delete anywhere and swipe too in the
Bookmarks list), a drawn app icon on
both app targets, and VoiceOver fixes that fold the Queue row, the Collection cell, a bookmark
row and the mini-player title into one element each instead of several separate stops. One
deferred minor worth knowing: `scripts/make-app-icon.swift`'s default output path is relative to
the repo root, so running it from elsewhere writes a nested tree instead of overwriting the
catalog. The final whole-branch review's fixes have landed — an opaque app icon, a bookmark
snippet clamp that survives fallback resolution, the Queue row's "·" separators hidden from
VoiceOver, and the rendered check reading "Ready to play offline" — and the deferred minors it
left (a jump error that is set but never shown, the timeline decoded twice on the Book sheet's
reload, an unbounded inline bookmark section) are recorded in that review's ledger,
`.superpowers/sdd/2026-09-04-plan-8-bookmarks-icon-voiceover/progress.md`.

## What comes after

The product owner decided on 2026-09-03 that Kokoro is the app's main engine (the system voice is
a placeholder), and Plan 6 made that true on the Core ML route: measured constants, real word
timings, and Kokoro Heart as the default voice on the phone build.

**Where that runtime decision came from.** Plan 0 Task 8, 2026-09-04,
`spikes/findings/2026-09-04-pre-a14-runtime.md`: `mattmireles/kokoro-coreml`'s `KokoroPipeline`
(Apache-2.0) with **every stage on the CPU** gives median RTF 0.18 flat out and 0.16 over 20 minutes
at 4x on the A13, a flat 119 MB footprint, and word-onset timing within 55 ms — so every rate up to
4x is offered and the rate-cap / prepare-the-whole-book idea is not needed on this phone (it stays
the design for any slower device). The GPU-assisted policy is slower there (0.37) and needs 1.2 GB;
MLX on the CPU is dead (RTF 15). The desk research behind the choice is
`spikes/findings/2026-09-03-pre-a14-runtime-options.md`; the harness arm and its fetch script are
`spikes/SpikeHarness/SpikeHarness/CoreMLBench.swift` and `scripts/fetch-kokoro-coreml.sh` (see
`spikes/README.md`, "Core ML arm", for the stale-manifest fix and the launch switches). That task's
word-end fold follow-up was fixed in Plan 6 Task 3: the trailing pause is charged to the
punctuation, not to the word.

**One correction, because it shaped Plan 6 and was wrong.** The owner's direction as recorded here
on 2026-09-04 said that Core ML also runs in the simulator, so the engine belonged in the everyday
`T2SReader` target and would make Kokoro testable on the Mac. It cannot: MisakiSwift — the G2P both
runtimes need — links mlx-swift, which cannot link against the iOS simulator SDK. The Core ML engine
therefore lives in the device-only `T2SReaderKokoro` target and in the macOS test bundle, and
`T2SReader` stays the simulator and CI build, with the system voice and no engine linked.

What remains, in order:

1. **The first listen on the iPhone 11 Pro, then merge Plan 6.** The recipe is under "Resume here"
   above. Nothing on that branch has spoken on a phone, and every "pending the owner's listen" row
   in the matrix turns on it.
2. **The unplugged 20-minute run at 4x on the 11 Pro** — the number Plan 0 Task 8 left open.
   Thermal state 2 was reached on charge at 4x with no speed collapse; the unplugged thermal curve
   and the battery drain are unmeasured. The protocol is `spikes/README.md`, "Core ML arm", and the
   finding to extend is `spikes/findings/2026-09-04-pre-a14-runtime.md`.
3. **Plan 0 measurements on the iPhone 17 Pro (Harsh) — optional now.** Core ML is the baseline on
   every phone, so nothing waits on these; do them when a comparison is worth having (see "The
   iPhone 17 Pro run" above for when it is). The plan is
   [2026-09-02-plan-0-spikes.md](superpowers/plans/2026-09-02-plan-0-spikes.md); the exact no-taps
   command-line protocol and every tooling gotcha are in `spikes/README.md`. Done so far:
   - §7.1 (`spikes/findings/2026-09-03-g2p-coverage.md`): all Kokoro-path licences permissive
     (MisakiSwift is Apache-2.0, not MIT); MisakiSwift accepted as the only G2P, English-only, with
     two mitigations (join compound numbers with a space in `NumberWords`; heteronyms lack POS).
   - §7.3/§7.5 on the iPhone 11 Pro (`2026-09-03-runtime-benchmark.md`): **kokoro-ios/MLX cannot
     run on the A13** — MLX's steel GEMM needs `simdgroup_matrix` (Apple GPU family 7, A14+), so
     the first `generateAudio` traps. The MLX route has an A14 floor.
   Pending, all on the 17 Pro: §7.3/§7.5 (one 5-minute run + a 20-minute 3x run), §7.4 (the three
   WAVs from that run against the CSV `timing` rows), §7.2 (15 minutes screen-off with
   `SPIKE_BACKGROUND_AUDIO=1`), §7.7 (three overnight runs). Findings go in `spikes/findings/`
   and a `RESOLVED` line under each spec §7 subsection. The app half of that visit is written out
   under "The iPhone 17 Pro run" above.
4. **Wire the 17 Pro numbers into the code, if that visit happens.** The MLX engine, probe, route,
   catalog, fallback and UI all exist (Plan 5 Task 5, kept alive by Plan 6); only the measured
   constants are missing. When the findings files land, in this order:
   - Fill `KokoroRuntimeDecision.current` from the finding file — measured RTF, the rate threshold
     derived from it, and the memory limits. It is `nil` today and the engine refuses to be
     selected while it is; there is a `DEBUG` override precisely so nobody is tempted to guess.
     `debugOverride` is the shape the real value must take.
   - Wire `backgroundInferencePermitted` into the render policy and `idleInferencePermitted` into
     `PrepareRunner` / `PrepareTask`. Neither flag is read anywhere today: they are recorded on the
     decision and nothing consumes them, so filling `current` alone does **not** enforce the
     §7.2/§7.7 policy — a decision that says "no background inference" would still render in the
     background. Do this before, or with, the fill.
   - Add the `RESOLVED` lines under spec §7.2, §7.3, §7.4, §7.5 and §7.7, each pointing at its
     findings file, the way §7.1 and §7.6 read now.
   - The `KokoroTokenTimingMapper` work is **done**: Plan 6 Task 3 opened the §7.4 gate against the
     A13 measurement, for both runtimes, so the MLX route already returns real word timings. Two
     caveats the Task 5b review recorded still stand and would be settled by a 17 Pro fixture rather
     than by reasoning: (a) `candidateTimings` does not advance `searchFrom` past a skipped token,
     so adjacent repeated words can bind to the wrong range; (b) `MToken.tokenRange` may be a better
     alignment source than searching the text at all.
   - Making a Kokoro voice the default is **done** too, on the Core ML route (Plan 6 Task 4). The
     product cost it carries is unchanged and applies to any later route change: the render key
     carries the engine identity, so a document that switches route re-derives its audio
     (spec §3.7.3).
5. **The hardware matrix above.** Every row marked *pending hardware* — the Lock Screen and route
   changes, the Share Extension payloads, Prepare's power and thermal stops, `BGProcessingTask`,
   and the cloud error paths — plus Plan 4b Task 9's remaining EPUB/PDF fixture and UI test. A
   failing row is a fix round, not a footnote.
6. **Plan 7** (renumbered 2026-09-04; Plan 6 is the Core ML engine) is unchanged: CloudKit sync behind `SyncProvider`, Live Activity, App Intents, and
   Spotlight. Its constraints from Plan 5: sync stays behind `SyncProvider`; the app-group store is
   the only local source of truth; a Live Activity or App Intent may *read* `NowPlayingSnapshot` /
   `PlayerModel` but must not become a second playback owner; CarPlay stays deferred even though
   the MediaPlayer remote commands now work.

## Known issues and parked items

0. **Build and disk gotchas found on 2026-09-06.** (a) After changing a `static let` such as
   `Versions.segmenter`, SwiftPM's incremental build kept the old value baked into a default argument
   through several edits; only removing `.build/arm64-apple-macosx` (SwiftPM intermediates — never
   `.build/DerivedData-App`, the app build tree) fixed it. (b) Core ML's runtime cache under
   `~/Library/Caches/com.apple.dt.xctest.tool` grows ~0.9 GB per loaded engine and filled the disk
   three times; the Kokoro scripts now sweep it. (c) The Bash working directory persists between
   commands in an agent session — a `cd` into a subfolder once made every relative path fail.

1. **Plan 4b Task 9 is open:** the EPUB read-along has now passed once on the simulator (see
   above), but the pass on hardware, the EPUB/PDF fixture, and the UI test are still not done.
   A usable fixture already sits in Readium's checkout
   (`Tests/Publications/Publications/childrens-literature.epub` under `swift-toolkit`).
2. ~~**`scripts/build-app.sh` produces an app that cannot open its library.**~~ **Fixed** in Task 5f:
   the script now signs ad hoc locally (`CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO
   CODE_SIGN_IDENTITY=-`) and stays unsigned only under `CI`, so the simulator app gets the
   `application-groups` entitlement and opens its library. Kept here because the symptom — "The
   library could not be opened." — is what you see if that signing is ever removed again.
3. **Physical-device validation remains open:** audio through phone-call interruption and AirPods
   route changes; Lock Screen and Control Center controls; and debugger-forced
   `mediaServicesWereReset` recovery. PR #9 verified the software seams, not these hardware paths.
   The matrix above is the full list.
4. **Background processing remains device-only:** PR #12 verified the runner and visible state on a
   simulator, but the simulator rejects the opportunistic request outright
   (`BGTaskSchedulerErrorDomain error 1` — expected there, not a bug). Validate `BGProcessingTask`
   scheduling and a simulated launch while the device is on charge.
5. **Share Extension remains unverified on hardware:** Task 2 merged in PR #15. Verify the share
   sheet on a physical device for link, text, EPUB, and PDF input, each failure string, and the
   app-group hand-off into the host.
6. **Kokoro's gate: the Core ML route is open, the MLX route is not.** Core ML runs on measured
   constants — `KokoroCoreMLDecision.current` carries the A13's RTF 0.181 and 119 MB, every rate up
   to 4x is offered, `KokoroTokenTimingMapper` returns real word timings, and Kokoro Heart is the
   default voice on the phone build (Plan 6). The MLX route still has **no** constants:
   `KokoroRuntimeDecision.current` is `nil` and the engine refuses to be selected while it is, so
   its voices appear only behind the `DEBUG` override. The 17 Pro numbers (§7.2–§7.5, §7.7) decide
   its rate threshold, memory limits and background policy. The iPhone 11 Pro cannot run that route
   at all (Plan 0 Task 8), which is why the Core ML one exists.
7. **A Kokoro engine failure after the probe has passed leaves the book playing silence.** The
   availability probe runs once, at configuration time (adjustment 3 scopes the fallback there), so
   a failure inside `KokoroEngine.load()` or `generateAudio` — a corrupted weight file, an MLX
   allocation failure, jetsam pressure — throws per utterance from then on. The coordinator does
   what spec §6 asks: it surfaces the message as `lastRenderError` and fills 200 ms of silence, so
   the book does not halt. But there is no re-route after the probe, so it plays silently with an
   error showing until the reader changes the voice by hand. Follow-up: on the first
   `KokoroEngineError` out of `GatedKokoroEngine`, flip `KokoroAvailabilityModel` to unavailable
   (a new reason, e.g. `.engineFailed`) so the next load falls back to the system voice and the
   Preferences footer says why. **Plan 6 closes this on the Core ML route.**
   `GatedKokoroCoreMLEngine` no longer remembers a failed load, so a transient failure costs one
   utterance instead of the session; and the launch warm-up now decides the *route*, not just the
   footer — it tries `preload()` twice, two seconds apart, and a second failure closes the Core ML
   route for the rest of the launch, so every document opened from then on falls back for its whole
   length (spec §6) instead of failing utterance by utterance. The footer then reads "Not available
   on this device: The Kokoro voice could not be prepared. …" — a constant, because
   `error.localizedDescription` for a plain Swift error reads "The operation couldn't be
   completed."; the real error goes to the log (`Kokoro Core ML warm-up failed, route closed: …`).
   What is left: a document already routed to Kokoro when the route closes keeps failing per
   utterance until it is reloaded, a cancelled warm-up neither retries nor closes anything, and a
   route closed by two unlucky transient failures stays closed until the app is relaunched.
   Whether the route falls back to the *system* voice or to another Kokoro voice is the resolver's
   business, not this one's: an unavailable `kokoro:` ID resolves to the app's default voice
   (Kokoro Heart on Core ML where that route is open), and only to the system voice when no Kokoro
   route is left — which is how a model-revision bump re-routes old documents to the new default.
   **One engine failure is by design and worth recognising in the log:** a piece of an utterance
   whose predicted speech still overruns the 15-second bucket throws
   `KokoroCoreMLError.audioTruncated(predictedSeconds:bucketSeconds:)` rather than return speech
   clipped to fit, so that sentence is dropped and filled with 200 ms of silence like any other
   engine failure, and the reader sees "The on-device voice could not fit this passage into one
   breath." The chunker aims at about 13 seconds a piece, so it should be rare — but it means
   "a sentence went silent" is diagnosable rather than mysterious: look for `audioTruncated` and
   its two second-counts in the log.
8. **`Packages/MLXUtilsLibrary` is vendored, and SwiftPM warns about it on every resolve.**
   `readium/ZIPFoundation` (3.0.1+, via the Readium toolkit) and `weichsel/ZIPFoundation` (0.9.x,
   via `kokoro-ios` → `MLXUtilsLibrary`) share the SwiftPM identity `zipfoundation` with disjoint
   version ranges, so adding Kokoro to the app project broke resolution for the *whole* project —
   `xcodebuild -list` failed. The fix (Task 5f) vendors `MLXUtilsLibrary` 0.0.6 (Apache-2.0, ~64 KB
   of Swift, revision `41f6cfd5`) as a local package with its one ZIPFoundation call replaced by
   our own `NpzArchive` — a stored+deflate npz reader on the Compression framework. Zip leaves the
   Kokoro path entirely; Readium is untouched. **The accepted cost:** the local package's identity
   `mlxutilslibrary` overrides the remote that both `kokoro-ios` and `MisakiSwift` reference, so
   SwiftPM prints, twice per resolve, `Conflicting identity for mlxutilslibrary … This will be
   escalated to an error in future versions of SwiftPM`. If a future Xcode makes good on that, the
   app build breaks — not just the Kokoro path. **Exit plan:** open a PR against MLXUtilsLibrary
   dropping ZIPFoundation (it is used for exactly one call, `Archive(data:accessMode:pathEncoding:)`
   in `NpyzReader.swift`); once that is released and `kokoro-ios` picks it up, delete
   `Packages/MLXUtilsLibrary` and go back to the remote. The fallbacks if that stalls are an
   owner-hosted fork or prebuilt XCFrameworks, both costed in `task-5f-report.md`.
9. **The full suite needs disk, and this machine keeps running out.** A cold `scripts/test-kokoro.sh`
   or `scripts/build-device.sh` compiles mlx-swift (~2 GB); `scripts/test-readium.sh` resolves the
   Readium toolkit (~1 GB). Reclaim before a cold run rather than during one: `.build` (~4 GB here,
   SwiftPM output plus `DerivedData-App`), `Packages/T2SKokoro/.build` and
   `Packages/T2SReadium/.build` all regenerate from the scripts that use them. Plan 6 adds two
   appetites. `App/Resources/KokoroCoreML` is 347 MB, a device build now leaves about 3.3 GB in
   `.build/DerivedData-App` and produces a 433 MB `.app`. And the Core ML engine's *development*
   path compiles the eight `.mlpackage` stages into `$TMPDIR` on every engine instance and never
   removes them, so each model-backed test leaks about 350 MB — 4.7 GB accumulated here in one
   night. `scripts/test-kokoro.sh` now sweeps `"$TMPDIR"/kokoro_*.mlmodelc` before it starts, so the
   leak is one run's worth rather than every run's; the same command reclaims it by hand, macOS
   clears them on reboot, and the app bundle is precompiled and leaks nothing on the phone.
10. **Deferred minors from the Task 5 reviews**, in the order a reader is likely to hit them:
    - `VoiceListPage` maps the `.notLinked` status to "Checking this device…" — unreachable in
      either shipped target, but the wrong text if it ever is reached.
    - A `kokoro:`-prefixed voice ID that fails to parse passes the route resolver and falls through
      `RoutedEngine`'s bare-ID path to the system engine silently. Only reachable from a corrupted
      row; it should throw `KokoroRouteError`.
    - Fallback-rendered audio is keyed to `"default"` and is not evicted when Kokoro later becomes
      available, because the stored `document.voiceID` never changed. Left to size-managed eviction.
    - `NpzArchive` does not check the walked entry count against the EOCD total, and allocates
      whatever uncompressed size an entry header declares before bounds-checking it. It only ever
      reads a checksum-verified file we ship.
    - `KokoroResources.Located`'s public memberwise init lets a caller bypass `locate()`'s size gate;
      `KokoroAvailability`'s catch-all reports the model file's name even when `voices.npz` was the
      file that failed to read; `MLX.Memory.cacheLimit` is process-global and the test that sets it
      never restores it.
    - Three mlx-swift manifest warnings are visible in `scripts/test-kokoro.sh` output. They are
      upstream and carry no path, so the script's checkout filter cannot catch them.
    - Readium's pre-existing `GCDHTTPServer` deprecation warnings now also surface in CI's device
      build step.
11. **The phone app is `T2SReaderKokoro`, not `T2SReader`.** The two-target split is no longer only
    about MLX. `T2SReader` is the simulator, CI and everyday build: it links no engine and speaks
    with the system voice. `T2SReaderKokoro` is device-only, links both runtimes, bundles the
    347 MB of Core ML files, and is the only target where Kokoro is the default voice. Core ML on
    its own would not have needed a device-only target, but MisakiSwift — the G2P it uses — links
    mlx-swift, which cannot link against the simulator SDK. So anything a reader is meant to *hear*
    has to be built and installed from `T2SReaderKokoro`; a simulator screenshot shows the system
    voice by design, not by accident.
12. **The MLX voices appear a few seconds into a launch, not at launch.** `KokoroVoiceCatalog` asks
    a closure for the linked runtimes on every `voices()` call, and that closure reads a flag the
    MLX probe sets when it answers; `VoiceListPage` re-evaluates its body because it also reads
    `kokoroStatus.mlxLine`, which is written immediately after the flag, and the re-evaluation
    re-asks `voices()`. So the second set of 28 rows (" · MLX") arrives on that redraw. `PreferencesPage`
    does not observe `mlxLine`, so its "Default voice" subtitle picks up the fuller catalog on its
    own next redraw — cosmetic, and it only ever shows a Core ML voice anyway. All of this is
    reachable only on an A14+ phone with the MLX weights staged and the override on.

Other retained review items:
- Same bug class as the artwork crash, unproven: `MainActor.assumeIsolated` inside the
  `MPRemoteCommand` handlers in `NowPlayingController.start()` and in the `deinit`s of
  `NowPlayingController` and `AudioPlayer`. They hold as long as MediaPlayer delivers commands on
  the main thread and those objects are only ever released on it; the Lock Screen / AirPods pass on
  hardware is where they would show.
- ~~No app icon / asset catalog yet — blocking for TestFlight, fine for development.~~
  **Resolved**: the icon exists (`scripts/make-app-icon.swift`, opaque RGB — no alpha channel, so
  App Store Connect's ITMS-90717 icon-alpha check does not reject it) and draws a deterministic
  CoreGraphics icon (accent (#FF7A1A) ground, three rounded white bars, a play triangle) into
  `App/T2SReader/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`; both app targets pick it
  up through `ASSETCATALOG_COMPILER_APPICON_NAME` in the shared `targetTemplates` entry.
  Regenerate the PNG after editing the script with `swift scripts/make-app-icon.swift`. App Store
  upload validation itself has not yet run — pending an upload.
- `LibraryModel` progress is still computed per queued document on refresh (cached per summary);
  lazy per-row computation and an explicit, cancellable stale-timeline migration are the next step
  if the library grows large.
- Test temp directories under `t2s-app-<uuid>` are not removed after the suite.
- `LocatorMapping.locator(for:)` defaults the media type to XHTML; PDF positions need `.pdf`.
- `Library.store` is public, so the facade can be bypassed; `Library.delete` is not idempotent.
- PDF: outline traversal is top-level only; `PDFCover` upscales narrow pages.
- `PlaybackCoordinator.fill()` runs outside its serial chain (a seek during a fill can leave a stale clip); the ~76 ms time-pitch look-ahead is a calibration item (`AudioPlayer.outputLatencySeconds`); `TimeIndex` is rebuilt on every `.rendered` event; a `.failed` event without a `.rendered` leaves `.catchingUp` with no UI escape.

## Working conventions

- Every plan task ends with its own commit using the message given in the plan; tests first, then code.
- Keep `Position` as the only persisted location; never persist utterance indices or Readium types.
- Tokens only in views (no literal colors), one `accent` element per screen, no cards or dividers.
- Run `swift test` and `scripts/build-app.sh` before every commit that touches the app;
  `scripts/test-readium.sh` when `Packages/T2SReadium` changes; `scripts/test-kokoro.sh` when
  `Packages/T2SKokoro` or `Packages/MLXUtilsLibrary` changes, and `scripts/build-device.sh` when
  anything the Kokoro target links changes.
- Commit trailer used for AI-written commits: it depends who wrote them. `Co-Authored-By: Codex
  <noreply@openai.com>` through `c533290`, the last commit written by that tool;
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` from `2540e1c` onward, which is where
  the switch happened on `dev` — not at the start of this branch. Merge commits carry no trailer.
  Match whichever tool you are actually using.
- Two app targets now come from one `targetTemplates` entry in `App/project.yml`. Anything that
  applies to the app — a setting, a source path, an entitlement — belongs in the template, or the
  two targets drift apart silently.
