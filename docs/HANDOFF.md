# t2s_reader — hand-off and next steps

_Last updated 2026-09-09 (Plan 17 — the rest of the audit — on `plan-17-rest-of-audit`, in the worktree `.worktrees/plan-17-rest-of-audit`, off `origin/dev` @ 7dc7498 and rebased onto the voice-picker pass at 1e23c1a). Written for whoever picks up the coding next._

## Resume here (2026-09-09, latest) — Continue Listening row round 2

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
