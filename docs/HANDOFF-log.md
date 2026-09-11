# t2s_reader — hand-off log

_The dated "Resume here" entries that `docs/HANDOFF.md` carried at its top, one per session, newest
first, moved here verbatim on 2026-09-11 so the hand-off itself stays the state and what is next. Each
entry was written for whoever picked up the coding next, at that moment; later entries supersede earlier
ones where they disagree._

## Resume here (2026-09-11, small hours) — the 11 Pro test of Harsh's branch, the merge, seven fixes, the phone, and the research

The owner asked whether Harsh's `phone-warmup-download-cloud` could be tried on the 11 Pro without
disturbing the working app. It was: a worktree, a second bundle id (`com.t2s.reader.harsh`, its own
app group, no share extension — a free team's three device slots), the model pushed over USB when
the download would not finish. Everything found is in **`crashreport.md`** at the repo root (the
thirteen `.ips` in `crashreport-ips/`), checked against the source by an adversarial pass; the
web research the owner asked for is `docs/research/2026-09-10-on-device-models-on-old-and-new-phones.md`
(seven sweeps, 78 sources; its deduplication figure was verified here).

**What the phone said.** The working `t2s` had crashed eight times that day, all off-screen: six
Prepare launches dying in the `BGTaskScheduler` handler, one `cpu_resource_fatal`, two MLX-on-Metal
aborts. Harsh's branch, locked ~30 s during warm-up: survived (in-flight plan builds keep the CPU
at 100 % through a lock — a > 60 s lock there is still the one `cpu_resource_fatal` shape open on
the A13). Locked four minutes during playback: no crash, the `CPUBudget` bursting ~70 s of audio
then sleeping ~60 s against a 60 s play-ahead, so the audio ran dry once a minute. The GPU path
(`-kokoro.computeUnits cpuAndGPU`) aborted in Core ML's plan compiler — `std::bad_alloc` in
MPSGraph — on the 4 GB phone. A fresh install could not download the model at all: Hugging Face
429s to the 72-request burst, and the installer gave up on the first one.

**On dev now** (his branch merged at 01f7560; the four unmerged commits were the A19 GPU policy,
the front-GPU/back-CPU split, the screen staying awake, and his HANDOFF):
- `abb3875` — `CPUBudget.record()` after every render, so the first background render after a lock
  is charged for the trailing minute, not for everything since the last background wait.
- `5d40ac8` — the download retries: `HTTPStatusError(status:retryAfter:)`, `Retry-After` or
  2/4/8/16 s up to five attempts for 429/408/5xx and dropped connections, a 404 failing at once,
  `Failure.download(path, status:)`, a `.retrying` progress the veil shows over a held bar.
- `84e16f9` — `KokoroComputeUnits.permitted(_:physicalMemory:)`: the GPU needs 5 GB; the chip
  policy and the `kokoro.computeUnits` override both hold to it (the 11 Pro's abort).
- `b5b34fa` — the CPU path's play-ahead is 180 s (two budget cycles); the comments no longer call
  the window a foreground setting — it applies in every state.
- `1c29cec` — the G2P comment agrees with `mlxPinnedToCPU`.
- `b6548e6` — the installer copies a file whose bytes are staged under another path: the manifest
  is 619 MB, 238 MB unique (the bucket variants share weights), so a first launch fetches 238.
- `6bc589a` — one generation of compute plans per install, and a timing log that keeps the first
  launch's numbers (found on the phone, below): `KokoroPlanCache.prepare(for:)` at composition wipes
  `Library/Caches/<bundle>/com.apple.e5rt.e5bundlecache` when it was built for another warm-up
  identity (or before the record existed); `KokoroTimingLog` appends each launch under a header
  and moves a file past 256 KB to `.1`; `KokoroLoadTally` ends each set with one line —
  `kokoro main set loaded: 14 stages in 460.4 s, 4 rebuilt (a plan built, ≥ 5 s), slowest …`.

**What the phone said, second pass (2026-09-11, 00:55–01:25).** dev went onto the 11 Pro as `t2s`
(the signed Phone-scheme Release build, `devicectl device install app` over the old one; the
container survived). The first launch rebuilt three plans and then stage 8's BNNS compile failed with
"No space left on device" *inside the app's own Caches*: iOS keys Core ML's plan cache on the install
and never removes the last install's — `t2s` held 4.36 GB across 211 entries from a day of builds,
`t2s H` 3.11 GB from one warm-up — so a shipped user would keep ~1 GB per update too. `t2s H` was
deleted (his branch is merged; the third slot is free again). With `6bc589a` installed: the launch
wiped 4707 MB, and the owner locked the phone ~2.7 min during the first warm-up — no crash, the same
process, the four long plan builds paused while locked and resumed on unlock (222 s and 453 s for the
two concurrent pairs, against 59 s and 228 s unlocked at 00:56). The summary: `14 stages in 460.4 s,
4 rebuilt, slowest kokoro_duration_t256 452.97 s`; the plan cache afterwards 0.58 GB in 42 files. Only
`duration_t128`, `duration_t256`, `decoder_har_post_3s` and `_15s` ever need a long compile on the A13;
the other ten load in under 2 s even after a wipe, so an unlocked first launch is about five minutes.
The old launch, read from the log after the fact, had also finished: stage 8 compiled on the full
disk in 490 s and the warm-up closed at 494.6 s.

**The fresh install, over Wi-Fi (01:31–01:41).** dev at `38b40c5` as a third copy under
`com.t2s.reader.harsh` (the worktree, detached on dev, its identity edits kept), installed fresh and
launched with the console: `kokoro install finished: 63 files downloaded (227 MB), 9 copied from a
staged twin (363 MB), 0 retries, 14 stages compiled in 8.7 s, 45.7 s in all` — the dedupe is real
(a 39 MB weight fetched once, its three bucket twins copied in 60 ms each), the retry path did not
run because Hugging Face did not refuse this time. Then the warm-up: `14 stages in 517.2 s, 4
rebuilt, slowest kokoro_duration_t256 512.13 s` — the other three long plans took 60 s each, so on
the A13 a first launch *is* `duration_t256`'s plan build (453 s at 01:14, 490 s at 00:55, 512 s here).
It was in the ready set because a piece may run to 176 ids. The copy was deleted again afterwards.

**Readiness without t256 (`b8bc24b`, 02:04).** The ready set is seven stages (t128 and the 3 s and
15 s buckets); t256 loads on the later-bucket task after the 7 s and 10 s buckets and is swapped in
like a bucket (`install(durationTokenLength:stages:)`); until it lands pieces are cut at 126 ids
(`pieceCap(for:)`), the split the background set's t128 already forced staying as the backstop; the
GPU predictor warm-up warms t256 when it lands. Installed over `t2s` and launched: the wipe freed one
generation (596 MB); `kokoro warm-up finished in 57.5 s` (was 458–513 s); the 7 s and 10 s buckets
two seconds later; `kokoro_duration_t256 loaded in 235.19 s` at 02:08:55 — alone on the CPU it builds
in four minutes, not eight — and `main set loaded: 14 stages in 296.2 s, 4 rebuilt`. Between 02:05
and 02:09 a long sentence renders in pieces of up to 126 ids instead of 176: a seam more, nothing
else. The streamed-versus-whole timing test now waits for the full load (it had caught exactly this:
the whole render ran after t256 landed, cut elsewhere, the words 0.10–0.22 s apart).

**Verified:** `swift test` 478/87; `KokoroCoreMLInstallTests` 11, `KokoroComputeUnitsTests` 4,
`KokoroPlanCacheTests` 3, `KokoroTimingLogTests` 3, `KokoroLoadTallyTests` 2; simulator and device
builds; the phone as above.

**Owed:**
- Four minutes locked during playback with the 180 s window (the owner chose to skip it for now:
  the change is a constant and a budget bookkeeping fix, both unit-tested; a phone would confirm the
  budget cycle covers 180 s at the A13's speed). The download retry against a real 429 (only the
  fake network has produced one).
- Plan 18, `docs/superpowers/plans/2026-09-11-render-ahead-by-chapter.md` (written 02:07): render to
  the end of the chapter while frontmost and listening, so the background loop only tops up.

**The installer's three follow-ups (`7c0f1dc`, merged at `ab4617c`, 02:20).** One `URLSession` per
install (`KokoroCoreMLInstall.Session.wifi()`, closed before the compiles; the app's call site takes
the default); `Range` resume — the `.part` survives a drop, a 5xx, a 429 and a killed launch, the next
attempt asks `bytes=<size>-`, a 206 appends, a 200 replaces, a 416 restarts once — checked against
Hugging Face from the Mac: the resolve URL answers 302 and the CDN 206 with `content-range`; and the
wait on a 429 from `Retry-After`, `RateLimit-Reset`, `X-RateLimit-Reset` or `RateLimit` `t=`, clamped
to 120 s, quoted in the timing line (`asked 217 s (ratelimit: …)`) so the next phone 429 says quota or
blocklist. Nineteen installer tests. One lesson for the tests: a scripted `URLProtocol` that fails
after its response makes `URLSession.bytes(for:)` throw as a whole, so a mid-body drop cannot be
scripted — the live-session test starts from a part left by hand.
- Harsh, on the 17 Pro — everything short of pressing run is done (`68a3854`, 02:40):
  - **The `MLComputePlan` probe** (`KokoroComputePlanProbe`, `scripts/compute-plan-probe.sh`): per
    operation of a stage's MIL program, its estimated cost and the devices that support it, under
    `cpuAndGPU`, `cpu` and `all`; a summary table in `spikes/findings/compute-plan-probe/report.md`.
    On the Mac the 15 s generator's CPU plan loads in 1.1 s (1041 ops, every one CPU-supported,
    `conv` ×51 = 57 % of the cost; under cpu+gpu every op prefers the GPU) — so the A19's never-ending
    CPU build is not an unsupported op; the phone's per-op costs are what the probe is for. On the
    phone: from `Packages/T2SKokoro`, `xcodebuild test -scheme T2SKokoro -destination
    'platform=iOS,id=<UDID>' -only-testing:T2SKokoroTests/KokoroComputePlanProbe
    -allowProvisioningUpdates DEVELOPMENT_TEAM=<team> CODE_SIGN_STYLE=Automatic
    TEST_RUNNER_KOKORO_COMPUTE_PLAN_PROBE=1 2>&1 | grep 'kokoro compute plan'` (the probe downloads
    the stage's three files over Wi-Fi and caches them; the recipe is untried from this Mac).
  - **The review**, `docs/research/2026-09-11-gpu-path-locked-playback-review.md`: the lock flow on
    the GPU path step by step, eight races (R1–R8) and six improvements ordered by value. Landed with
    it: five timing lines (scene/gate changes in `RootPager`, a background-placed piece's wait and the
    set it ended in, the thermal hold, `; set main|background` on every `kokoro call`, a later bucket's
    failure) and the R5 fix (`37f79df`: a render cancelled while locked no longer spins on the gate).
  - Still open from the review, each small: the CPU budget's pacing and per-render CPU seconds in the
    timing log (improvement 1); cut a piece for the 3 s background set *before* rendering instead of
    discarding a third of the calls after (2); place by `.background`, not by the gate — Control
    Center or a banner must not park a streamed head (3); retry a failed background-set load (R6);
    whether serializing the GPU plan builds is worth its ~2× load time there.
- From the research, not started: read Hugging Face's `ratelimit` headers on a 429; one
  `URLSession` per install and a `Range` resume; a mirror (R2 or Background Assets) so the model
  does not depend on anonymous-IP policy; `MLComputePlan` on the 15 s generator to see why the
  A19's CPU compiler never finishes it. (Render by chapter while frontmost: done — Plan 18, the
  entry above; its phone protocol is what is owed now.)

## Resume here (2026-09-10, night) — the kind title pops with the menu it opens

The owner: "I want the kind frame to also scale with a pop" — the trigger itself (the "All ⌄"
title), not only the card it drops.

- **`TitleTriggerStyle`** (`Design/TitleMenu.swift`): the title-and-chevron button's own style now.
  Two motions share it. A finger on it shrinks it to 0.95, sprung back on release
  (`.snappy(0.15)`) — felt the moment it is touched, before the menu has even started to move.
  Independent of that, while the menu it opens is up the settled scale sits at 1.035 rather than 1
  — the title reads as pulled out, not merely labelled "open". Both are one multiplied
  `scaleEffect`, so a press during the open state shrinks from 1.035, not from 1.
- **One state, one transaction.** The 1.035 is driven by the same `isPickingKind` the card's
  presence is driven by, inside the same `withAnimation(TitleMenuMotion.toggle(opening:))` block at
  the tap site — so the title and the card move on the exact spring together: the same overshoot,
  the same 0.34 s open and 0.22 s damped close, confirmed for the card in the previous round's
  recording. There is nothing to add on the timing side; the trigger simply joined the transaction
  the card was already in.
- **Fixed a doubled scale while wiring this**: the first cut set `.scaleEffect(isPickingKind ?
  1.035 : 1)` on the label *and* gave the button the same factor through the new style, compounding
  to about 1.07 while open. Caught before commit; the scale lives only in `TitleTriggerStyle` now.

`scripts/build-app.sh` → `** BUILD SUCCEEDED **`. **Not filmed**, and said plainly why: the
screenshot method used for the menu (`T2S_OPEN=kinds`) sets `isPickingKind = true` at the view's
`@State` initializer, before the view ever renders — so there is no false→true transition for
`withAnimation` to animate, and a frame-by-frame measurement of the title's pixel width came back
flat at 185 px from the first fully-drawn frame on. A tap that starts closed and opens live is what
would show it, and neither `simctl` nor a UI-test harness is wired up here to script one — the
options were an XCUITest target (not part of this app) or driving the Mac's own mouse over the
Simulator window, which risks the mouse mid-task on a Mac the owner may be using for something
else, so it was not attempted. The mechanism is the one already proven: the trigger's scale is
computed inside the identical `withAnimation` call whose overshoot the previous round's recording
already measured on the card. `swift test` not run: nothing under `Sources/` changed. Not seen on
a phone.

## Resume here (2026-09-10, night) — the kind menu's spring pop

The owner: "add a nice animation when clicking filter in collection page, like spring pop, we have
in latest iOS."

- **`TitleMenuMotion`** (`Design/TitleMenu.swift`) holds the whole thing, so the card and its call
  site cannot drift apart. Opening is a spring with real overshoot (response 0.34, damping 0.66);
  closing is critically damped and two-thirds the length — a menu that springs shut feels
  undecided. The transition is asymmetric: in, the card grows from 0.82 at its top-left corner and
  drops 12 pt; out, it leaves from 0.94 without the offset, so a close reads as a dismissal rather
  than a rewind.
- **The rows stagger.** `TitleMenuCard` flips a `rowsIn` state on appear; each row rises 10 pt,
  scales from 0.96 and fades, delayed 32 ms per row from the top. This is the part that reads as
  iOS — a card that only fades in reads as a web dropdown. Reduce Motion starts `rowsIn` true and
  passes a nil animation, so the rows are simply there with the card.
- **Rows press.** A `MenuRowStyle` button style now owns both films — the chosen row's `ink` at
  0.07 and a finger's at 0.07 over it (0.13 when both) — with the row giving to 0.97 under the
  press. One surface, so the two states cross into each other instead of stacking; the label's own
  `.background` is gone.
- **Two haptics**, the app's first: a light knock (intensity 0.7) as the menu drops, and the
  selection tick when a kind is taken. Nothing on a close by tapping outside — there is nothing to
  confirm. `.sensoryFeedback` needs iOS 17; the target is 18.
- The title's word crossfades to the new kind (`.contentTransition(.opacity)`) instead of snapping.
- `AnyTransition` is not `Sendable`, so `TitleMenuMotion.transition` is a computed `static var`, not
  a `let` — a stored one is a Swift 6 concurrency error.

`scripts/build-app.sh` → `** BUILD SUCCEEDED **`. Measured from a screen recording of the simulator
(`xcrun simctl io <udid> recordVideo`, frames pulled with an `AVAssetImageGenerator` tool — a burst
of `simctl io screenshot` is far too slow to catch a 450 ms animation, about one frame per 300 ms):
at 60 fps the card is up at 50 ms with only "All" legible, "Books" and "PDFs" arrive by 100 ms,
"Text" by 150, "Links" by 200, and the overshoot has settled by 300. `T2S_OPEN=kinds` opens the
menu at launch, which is how it was filmed; the press film and the close were not filmed (a script
cannot press). `swift test` not run: nothing under `Sources/` changed. Not seen on a phone.

## Resume here (2026-09-10, night) — the black buttons raised, and the dark-mode pass

Two asks from the owner: "replace the black buttons with skeumorphic versions of black buttons,
and in dark mode idk what the color should be"; "a lot of UI does not have dark mode equivalent,
voices page for e.g, fix this". And: "start directly, skip superpowers planning".

- **`RaisedButton` grew a tone and a size.** `.blue` is the reference key (the empty shelf);
  `.ink` is the app's black button raised: the same gloss-to-shade face, bevel and two shadows over
  `Tokens.keyInkTop` → `keyInkBottom`. Sizes: `.bar` (full width, 56 — what `BarButton` is now, a
  one-line wrapper), `.key` (hugs, 56), `.compact` (hugs, 40 — the Reader's "Back to current" and
  "Skip to Chapter" pills, which were `Pill(.selected)`). Disabled it is the flat `surface` slab it
  always was, and `busyLabel` still puts a spinner before the words: a key that cannot be pressed
  is not drawn as one.
- **In the dark the ink key is graphite, not white.** `ink` inverts to near-white in dark mode,
  which is what "Choose files" had become: a white bar on a black page — the thing the owner did
  not want to decide. The answer taken: a key is an object and keeps its colour in a dark room;
  `keyInkTop`/`keyInkBottom` are 0x3E3E3E → 0x1E1E1E there (the foot is `surface`'s own grey), and
  since a shadow on black is nothing, the lift comes from the top rim (`keyInkRim`, gloss at 0.42
  in dark, 0.30 in light) instead. Words in `onKeyInk`.
- **The dark-mode audit** (26 screenshots, every page, both routes — system dark, and the in-app
  theme set dark over a light system with `defaults write com.t2s.reader reader.theme -string
  dark`): every page adapts, the Voice page included, in both routes. What did not hold up: the
  ink bar (above); surfaces that a shadow lifts in the light and nothing lifted in the dark — the
  kind menu's card and the mini-player's capsule now carry a hairline `Tokens.edge` (0.05 black in
  light, 0.11 white in dark); and the favorite heart's three literal colours, now `heartTop`,
  `heartBottom`, `heartShade` with a lighter red in the dark. No other literal colour is left in
  the app's views — the grep finds only the mask gradients (`.black`/`.white` in `TopFade`, the
  Reader's fades, the ramp's mask), which are alpha shapes, not colours.
- **Not found: what on the Voice page.** On the simulator the Voice page is dark in both routes and
  every element on it has a dark token (rows, marks, the Default tag, the heart, the chips, the
  confirm bar). Whatever the owner saw is either on the phone build's Kokoro section or something
  the simulator cannot reach; a screenshot from the phone is the fastest way to it.

`scripts/build-app.sh` → `** BUILD SUCCEEDED **`. `swift test` not run: nothing under `Sources/`
changed. Seen in the simulator: the ink bar on the Files step, light and dark, at full
resolution; the kind card and the mini-player in the dark with their rims; Home in both. Not
seen: the compact pills in the Reader (they need a scroll or front matter, which a script cannot
give) and the Voice page's "Make default" bar (needs a tap) — same component, same code path.
Not seen on a phone.

## Resume here (2026-09-10, night) — the glow in blue, green when the voice lands, and the fan re-cast

Three words from the owner, with the blue "Join school" key as the palette: "make the warm-up and
the skeuomorphic button glow blue, see the palette from the reference, also account for dark mode";
"in the warm-up glow just as the model is ready, change the glow to green before ending the
animation"; and "use our book mockup for the covers, don't include 2 books from the same author,
also include 2026 popular books".

- **The glow is blue** (`Tokens.glow` 0x2F5BFF / dark 0x5F84FF, with `glowSoft` and `glowFaint`).
  Not the accent, and it says so in the token: the accent marks the app's own things — progress,
  the read-along, the one primary pill — and the glow is a state of the engine. `WarmRamp`'s wash
  and both bezel strokes take the colour as an argument now rather than naming `Tokens.accent`.
  Dark mode gets a lighter blue: the light one on near-black read as a dim navy. The warm-up's two
  other marks followed it — `WarmingDot` and the Reader's two "preparing the voice…" lines.
- **It ends on green** (`Tokens.glowReady`, `KokoroStatusModel.readyAt` / `readyBeat` = 0.55 s).
  When a warm-up ends, the model stamps `readyAt`, and a task clears it half a second later; that
  clearing is what takes the glow off the screen. One date on one model, so the veil and every
  ground bar turn on the same frame — the same rule the pulse follows. On the beat the breath stops
  at full, the light crossfades to green over 0.28 s, and `WarmUpLine` says "Voice ready" with its
  bar filled instead of holding the estimate it had reached.
- **The fan re-cast**: Alex Aster's *Starside* and Kate Quinn's *The Astral Library* — both 2026,
  both popular (Open Library's 2026 reading-log ranking, picked from sixteen candidates on a
  contact sheet) — behind Madeline Miller's *Circe*. Three authors, one each: the first cut had
  *Circe* and *The Song of Achilles*, both Miller's. Each book now carries a `BookCover.tilt`, the
  3D turn the book sheet's hero uses, so the fan reads as three objects standing at angles rather
  than three pictures laid flat. They stand 82 pt out, not 70: at 70 the hero cut both their titles
  in half.
- **The key is the reference's blue** (`Tokens.keyTop` → `keyBottom`, royal blue falling to indigo),
  its wide shadow in `Tokens.glow`. The empty shelf's pool of light went blue with it, so the page's
  one colour is the same as the warm-up's.
- **`T2S_WARMUP` takes a word now** (screenshots): `1` holds the warm-up as before, `ready` runs the
  green beat through once and ends, `green` stops on the beat and holds it.

`scripts/build-app.sh` → `** BUILD SUCCEEDED **`. `swift test` not run: nothing under `Sources/`
changed. Seen in the simulator (iPhone 16 Pro), light and dark: Home, the Collection, the blue
warm-up, the green beat, and a burst through the real transition — blue, "Voice ready", green,
gone. Measured on the top 120 rows: warming R137 G149 B194, the beat R129 G169 B146, and after it
R193 G193 B192 — the plain ground's own value to the digit, so the glow leaves nothing behind.
Not seen on a phone.

## Resume here (2026-09-10, evening) — the empty shelf: three covers fanned, one raised button

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
**The phone answered (2026-09-10, 15:23–16:03, Harsh's 17 Pro, iOS 26.6.1).** His first run on
the branch — the download and the on-device compile done by 15:23 — then sat "stuck at half" for
thirty minutes with the phone hot and lagging. The phone's own Core ML plan cache
(`Library/Caches/<bundle>/com.apple.e5rt.e5bundlecache/23G83/`, listed with
`devicectl device info files --domain-type appDataContainer`) held seven finished plans and one
that never finished: under `.cpu` the A19 Pro's plan compiler took under a minute for both
f0ntrain and decoder-pre stages, 2–5 min for the 3 s generator, 5 min for duration t128, 10 min
(across a relaunch) for t256, and never finished the 15 s generator — two attempts, one per
launch, twenty minutes and counting. Same iOS build as the owner's 11 Pro, where the A13 builds
all eight of its plans in 206 s. Relaunched from the Mac with `-kokoro.computeUnits cpuAndGPU`:

| stage | CPU policy (from the cache) | GPU policy (console) |
|---|---|---|
| f0ntrain t120 / t600, decoder-pre 3 s | under a minute | 0.4–0.9 s |
| decoder-pre 15 s | under a minute | 34 s |
| duration t128 | ~5 min | 34 s |
| duration t256 | ~10 min | 158 s |
| generator 3 s | 2–5 min | 157 s |
| generator 15 s | **never** | 125 s |
| ready (8 of 14) | never | **159 s** from a cold cache |
| 7 s and 10 s buckets, after readiness | — | 0.2–1.3 s each (the Metal kernels are already compiled) |

So `KokoroComputeUnits.defaultPolicy(machine:)` decides by chip: `iPhone18,*` (the A19
generation) and later get `.cpuAndGPU`; the A13 keeps `.cpu`; the A14–A18 phones between them,
measured on neither, stay on the measured CPU path (upstream's mixed-unit runs on an iPhone 12
Pro were slower than the A13 on CPU). `kokoro.computeUnits` still overrides for a session. Two
more things from that run: the screen now stays awake while the one-time setup runs
(`isIdleTimerDisabled`; the gate would otherwise stop the builds at the first auto-lock), and the
timing lines mirror to stderr under `-kokoro.timingConsole YES`, because `devicectl`'s console
carries stderr but not `os_log` and the phone refuses a network syslog connection.

**Watching the phone from the Mac** (the phone paired and on the network; `log collect --device`
needs root, `idevicesyslog -n` is refused):

```bash
xcrun devicectl device install app --device <CoreDevice-UUID> .build/DerivedData-App/Build/Products/Release-iphoneos/T2SReaderKokoro.app
xcrun devicectl device process launch --console --terminate-existing --device <CoreDevice-UUID> \
  com.antarlabs.t2sreader -- -kokoro.timingConsole YES        # add -kokoro.computeUnits cpu|cpuAndGPU|all to try a policy
```

The `--` matters: without it `devicectl` reads `-kokoro…` as its own `-t` flag. The console drops
when the phone locks; the plan cache and the timing lines survive.

**Then the afternoon's runs (16:00–17:00), each from the phone's own log** — the numbers that shaped
the rest of the branch:

- **Steady state on the GPU:** RTF 0.042–0.07 across the 7, 10 and 15 s buckets (calls of 0.27 s
  for 6 s of audio, 0.49 s for 9 s), against 0.18 on the 11 Pro's CPU.
- **A relaunch of the same build loads all fourteen stages in 1.3 s**; a reinstall pays the cold
  build again (the plan cache is keyed to the install), so every app update is a ~3 min first launch.
- **The first prediction on each stage costs once per launch, cached or not:** 4–5 s for the t128
  duration model, 14–15 s for t256, 1–2 s per generator; the load-time `fastPrediction` hint changed
  nothing. The engine now warms every stage on zeros right after readiness, t128 and the 3 s bucket
  first (4.9 s), t256 next (14.6 s), the buckets in under a second each — the whole set 20 s after
  readiness, with renders interleaving between steps.
- **iOS refuses GPU work from a backgrounded app.** Two crashes and then the real thing: at 16:07 the
  timing mirror's `FileHandle` write raised when the console pipe died with the lock (POSIX writes
  now, and a per-launch `Library/Caches/kokoro-timing.log`); at 16:16 MisakiSwift's fallback network
  crashed in MLX's Metal completion handler with "Insufficient Permission (to submit GPU work from
  background)" — the task-local CPU pin had not held, so MLX's global default device is the CPU
  now; and at 16:38, with the phone locked, every Core ML render failed with the same permission
  error as a plain `stageFailed` — the Reader's "utterance 233: stageFailed" banner, and 200 ms of
  silence per utterance.
- **So the phone renders in front on the GPU and behind on a small CPU set** (spec §2 decision 12):
  the 3 s bucket and t128, the four CPU plans this chip's compiler does build, loaded after the main
  set one stage at a time and only while the phone is cool; a piece placed in the background waits
  for the foreground until that set exists; a GPU call refused as the app left the foreground is
  rendered again where it is allowed; the live player renders ten minutes ahead while in front.

- **The background CPU set, measured (16:48–16:50):** loaded after the predictor warm-up, one stage
  at a time — the t128 duration model's CPU plan built in 134 s alone (5 min this morning under
  four concurrent builds), f0ntrain t120 in 0.18 s, decoder-pre 3 s in 0.44 s and the 3 s
  generator in 0.55 s, those three from the morning's plan cache; the set was ready 2¼ min after
  readiness, the whole one-time setup on this phone about 5½ min after a fresh install. A play on
  an unplayed chapter then filled the ten-minute window in ten seconds on the GPU (27 calls, RTF
  0.04–0.06, every bucket, no failures).

**Still unmeasured:** the background set's own RTF on the 17 Pro (a locked phone reaches it only
once the ten-minute window drains), and the A14–A18 phones, on neither policy.

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
