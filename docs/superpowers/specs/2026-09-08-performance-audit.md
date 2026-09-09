# t2s_reader — performance audit

_2026-09-08. A desk audit of the code on `dev` @ 3bca4b1 against the owner's goal: "run as smoothly as it
would with a cloud model". Nothing here was profiled on a phone; every number is either measured
elsewhere (cited) or an estimate from the code (marked). Input to the next plan, not a plan._

## 1. What "as smooth as a cloud voice" means here

A cloud voice (ElevenReader) feels smooth because of three things, none of which is voice quality:

| What the listener feels | Cloud today | t2s_reader today (A13, Release, engine warm) | Where the time goes |
|---|---|---|---|
| Tap play → first sound | ~0.5–1 s (the first streamed chunk) | **~2.5–4.5 s** on an unrendered position; 0 s inside the 60 s play-ahead window | one whole 160-character utterance is synthesized (1–2 Core ML calls of ~2 s each in the 15 s bucket), AAC-encoded through a temp file, read back through another temp file, then enqueued (§3.1, §3.3) |
| The very first sentence of a session | same | the above **plus** building the G2P: two 3 MB JSON lexicons parsed and merged, a BART network loaded (§3.2) | the launch warm-up loads Core ML only |
| Skip / chapter jump / tap a word / bookmark → sound | ~0.5–1 s | same 2.5–4.5 s whenever the target is outside the window | nothing is streamed inside an utterance |
| Open a book | instant | O(n) main-actor work and n actor hops before `play()` is allowed to fill (§5.4); after this update, **~3–12 s** more (estimate) while the whole book re-derives (§5.1) | render keys, chapter hashes, one `store.contains` per rendered utterance; normalizer 3 re-derivation |
| Launch | instant | 3–5 s before Kokoro is ready (A13, measured), 206 s on the first launch after install; plus a synchronous sweep of the old codec cache directory on the main thread and every queued book's timeline decoded for its progress (§4) | eight stages loaded one after another; `App.init` does disk work |
| Steady listening | never stalls | fine at 1–2x; **4x on an A13 will hit "catching up" when the phone is hot** (RTF p90 0.24, max 0.335 vs the 0.2 the rule needs) | throttling raises RTF but the current rate is never lowered (§3.5) |
| Scrolling and battery while playing | — | ~20 Now Playing snapshot builds per second, the root view's body at 10 Hz, an XPC call 4×/s while idle (§7) | timer-driven UI work that is not coalesced |

The engine's raw throughput is not the problem: RTF 0.18 means a minute of speech costs eleven seconds of
CPU, and render-ahead hides that completely once playback is running. **Latency at every start and
restart, and work done in the wrong place or at the wrong time, are the problem.** The fixes below are
ordered by what the listener will notice.

## 2. Ranked recommendations

Effort: S = a task, M = a plan of 2–4 tasks, L = a plan plus a measurement on a phone first.

**Progress (Plan 13, 2026-09-08):** #1 done (Release on the Phone scheme); #3 done (G2P in the
warm-up, prime after import and at launch); #4 done as `RecentAudioStore` (the temp-file encode and
decode paths stay); #5 partly (one store hop per load, cheaper keys — the `play()` gate,
"stop hashing every chapter twice per open" and `LibraryModel.refresh` are all untouched); #8 done;
#11 done (`rateLoweredTo`, and the rate is raised again as the RTF recovers; the Reader's line is the
UI plan's). Open (after Plan 16): #6, #7, #9, #10, #14, and the rest of #12.

**Progress (Plan 15, 2026-09-08):** #2 done — the head streams; first sound after the first ~3 s piece
(~1 s on an A13 in the 7 s bucket). The 3 s bucket (#9) would halve that.

**Progress (Plan 16, 2026-09-08):** the gap Plan 15 left closed — a streamed head that runs dry between
its pieces pauses on "catching up" and resumes on the next piece (`AudioPlaying.queuedSeconds`). #5
done but for the `play()` gate, which now costs one batched store hop: the coordinator reports the
chapters its renders changed and the player model writes those (no hash pass over the book); a saved
playhead carries its chapter and seconds into it (schema V2), so `LibraryModel.refresh` decodes no
timeline for a row the coordinator has played. #13 done: one alternation for the abbreviations, one for
the dictionary, the number rule skipped without a digit. #12 in part: the harmonic source computes its
nine sine passes over the voiced prefix only (bit-identical) and runs beside decoder-pre in the vendored
executor; the OOV phoneme cache, the G2P/generator overlap and the AAC encode off the critical path are
still open, and want the §8 measurement first.

| # | Recommendation | Listener-visible effect | Effort | Section |
|---|---|---|---|---|
| 1 | Ship the phone build as **Release** (`run: config: Release` on the Phone scheme; xcodegen regenerates the scheme, so the by-hand flip in HANDOFF does not stick) | every Swift-side stage (hn-NSF DSP, seam/tail-click scans, crossfade, tokenizer, segmentation, TextKit) runs `-O` instead of `-Onone`; the measured RTF 0.18 was a Release harness | S | §6.1 |
| 2 | **Stream the first sound**: render the head utterance's first sentence/clause first in a small bucket and hand pieces to the player as they finish, instead of one whole utterance | tap → sound in ~0.5–1 s instead of 2.5–4.5 s, on every start, skip, tap and jump | L | §3.1 |
| 3 | **Warm up the G2P with the stages, and prime on import and on open** — tier 2 of spec §3.4.1 is never planned (`primes: []`); the G2P is built on the first sentence | the first sentence of a session and a newly imported document's first tap both play at once | S | §3.2 |
| 4 | **Keep just-rendered PCM in memory** for the live path; the AAC cache is for later | removes an encode→write→read→decode round trip (two temp files) from the start-of-sound path; the listener hears the render, not the 64 kbps cache | S–M | §3.3 |
| 5 | **Take the open path off the main thread's critical path**: don't gate `play()` on the store reconcile, batch the `contains` checks, stop hashing every chapter twice per open, hex render keys without `String(format:)`, stop decoding every book's timeline for its progress row | opening a book and tapping play is immediate; launch does not decode the library | S–M | §5.4, §4.3 |
| 6 | **Re-derive stale timelines per chapter, in the background, from retained text** — today the whole book is re-read through Readium and re-normalized on the first tap after any version bump, and the same reprocess is also triggered from the Book sheet, Bookmarks and Prepare | first open after an update no longer blanks for seconds | M | §5.1 |
| 7 | **Coalesce the UI's timer work**: one `update()` per tick not two, no `nowPlayingInfo = nil` 4×/s while idle, write `highlight` only on change, cache `isFullyRendered` and the chapter list against `timelineRevision`, one `rects(for:)` pass per word, one font per paragraph kind | steadier scrolling and lower energy while playing | S–M | §7 |
| 8 | **Stop rewriting the whole chapter blob per rendered utterance** in Prepare (100–300× write amplification, serialised with every other store call) | less flash wear, less contention with position saves and refresh; nothing audible | S | §5.2 |
| 9 | **Add the 3 s and 10 s buckets** (upstream ships 3/7/10/15/30). Packed utterances (~10 s) run in the 15 s bucket, headings in the 7 s bucket: 13–85 % of generator work is padding | 15–25 % less synthesis CPU and heat (estimate); with the 3 s bucket, #2's first piece renders in ~0.4 s | M (+bundle size) | §3.4 |
| 10 | **Load stages concurrently and bucket-lazily** at warm-up (7 s bucket first, 15 s after); sweep the old codec directory off the main thread | every launch: 3–5 s → ~2 s; first launch: first Kokoro audio at ~100 s instead of 206 s (A13) | S–M | §4.1, §4.3 |
| 11 | **Degrade rate, don't stall**: when measured RTF makes the current rate unsustainable, drop to the highest sustainable rate and say so, instead of pausing on "catching up"; widen the window at high rates | 3–4x on a hot A13 keeps playing | S | §3.5 |
| 12 | **Trim the per-utterance Swift work**: cache out-of-vocabulary phonemes (the BART fallback re-runs for every name on every page), run the harmonic source beside decoder-pre and over the predicted frames only, overlap G2P of N+1 with the generator of N, take the AAC encode off the scheduler's critical path | ~10–25 % per-utterance wall time (estimate; measure §8 first) | M | §3.6 |
| 13 | Fold the normalizer's ~30 regex passes per utterance into fewer, pre-screened passes | faster import and re-derivation (1–3 s per novel, estimate) | S | §5.3 |
| 14 | MLX: nothing to fix at launch (the probe short-circuits); never fetch the 342 MB weights into a phone build; long-term, replace MisakiSwift's BART fallback with Accelerate so mlx-swift leaves the graph entirely | ~20 MB smaller Release binary and no Metal library; no per-op MLX dispatch in the G2P | S / L | §4.2 |

Not recommended: moving stages to the GPU or the Neural Engine (§3.7) — CPU-only is the right policy on
phones, and the generator cannot be admitted to the ANE as exported.

## 3. The render path

### 3.1 Nothing streams inside an utterance — the head of every start is a whole 160-character utterance

`KokoroCoreMLEngine.synthesize` (`Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLEngine.swift`)
cuts the utterance into pieces, renders every piece, joins them, folds the timings and only then returns
one `SynthesisResult`. `RenderScheduler` then encodes and stores it, emits `.rendered`, and
`PlaybackCoordinator.fill()` reads it back and enqueues it. The player (`AudioPlaying.enqueue(_:tag:)`)
fires one completion per tag, so it cannot take a partial utterance today.

On an A13, a packed utterance is ~10 s of speech in the 15 s bucket: ~2 s of synthesis (the generator is
75–87 % of a call, `spikes/findings/2026-09-04-pre-a14-runtime.md`), plus G2P, plus the store round trip
(§3.3). Sentences past 176 ids are two calls. That is the 2.5–4.5 s the listener waits at every start,
skip, tap and chapter jump outside the window — the single largest gap to a cloud voice.

**Fix.** A streaming render for the *head* utterance only (the rest of the window is rendered whole, as
now):

- The engine gains `synthesizeStreaming(_:) -> AsyncThrowingStream<Piece>`: each rendered piece's PCM
  (after tail-click removal and seam trim against the previous piece) is yielded as it finishes; the
  final element carries the full `SynthesisResult` for the store and the timeline. The piece cutter
  already exists; the first piece of the head utterance should be cut at its first sentence-final or
  clause boundary (a ≤ 3 s piece where possible), so the first sound needs one small call.
- The player takes several buffers per utterance: `enqueue(_:tag:isFinal:)`, completion only on the
  final buffer; `consumedSeconds` is unchanged.
- The coordinator's `fill()` treats "head utterance in flight" as playable once its first piece has
  arrived; `.catchingUp` becomes rare.
- Word timings for the head arrive with the final element, so the highlight for the first piece comes
  from the estimate for a second or two — the Reader already tolerates estimated timings.

With the 7 s bucket the first piece costs ~1 s on an A13; with a 3 s bucket (#9) ~0.4 s. On an A14+
phone roughly half that (estimate). Measure with the probe in `scripts/quality-probe.sh` first: the
seam budget (`KokoroCoreMLSeam`) was tuned for pieces cut at 176 ids, and a deliberately short first
piece makes one more seam.

### 3.2 The first sentence pays for the G2P, and the prime tier is never planned

`KokoroCoreMLEngine.preload()` loads the Core ML stages only; `g2p(british:)` is first called from
`synthesize` (`KokoroCoreMLEngine.swift:258`, `:505-510`). `EnglishG2P.init` then parses `us_gold.json`
(3.0 MB) and `us_silver.json` (3.1 MB) with `JSONSerialization`, builds a second dictionary of
capitalised variants and merges the two (MisakiSwift `Lexicon.swift:44-63`, "inefficient but correct"),
and loads `us_bart.safetensors` into an MLX `BARTModel`. Hundreds of milliseconds on a phone (estimate;
the spike CSV had a G2P column but no number was ever transcribed) — on the first sentence the reader
hears, after the tap.

Spec §3.4.1 tier 2 — "the first ~30 s of audio of a newly imported document, immediately on import" —
exists in `RenderPolicy.plan` (`Sources/T2SCore/Render/RenderPolicy.swift:126`) but nobody asks for it:
`PlaybackCoordinator.replan` passes `primes: []` (`Sources/T2SAudio/PlaybackCoordinator.swift:349`)
and `PrepareRunner` keeps `.prepare` jobs only. A newly imported document has no audio until its first
tap. Opening a document does plan play-ahead (`load()` → `replan()` with `playing` set), so a document
opened and then played a few seconds later is fine; one tapped straight away is not.

**Fix.** Build the American G2P at the end of `load()` so the launch warm-up pays it. After
`ImportModel` finishes, run a foreground prime pass through `PrepareRunner`'s scheduler (one
`RenderScheduler` with `.prime` jobs, any power state — ~6 s of CPU for 30 s of audio on an A13); on
launch, prime the continue-document from its resume position so the mini-player's first tap is instant.
Both are cache, so nothing else changes.

### 3.3 The live path plays the cache, not the render

`RenderScheduler.renderWhileHoldingLease` discards `result.audio` after `store.write`. `AACCodec.encode`
(`Sources/T2SAudio/AACCodec.swift`) writes a temporary `.m4a` with `AVAudioFile`, reads it back into
`Data`, strips the `free` atom, and `FileAudioStore.write` writes that `Data` atomically — the bytes
hit the disk twice. `PlaybackCoordinator.fill()` then calls `store.read`, which loads the file, writes
it to a *second* temporary file, opens it with `AVAudioFile`, decodes, copies into `[Float]`, and
`AudioPlayer.enqueue` copies again into an `AVAudioPCMBuffer`. Cache hits in the scheduler decode the
whole clip only to learn its duration. And every second heard has been through 64 kbps AAC (24 dB SNR,
`spikes/findings/2026-09-05-coreml-audio-quality.md` — the "robotic, underwater" finding).

**Fix.** A small in-memory PCM tier in front of the file store — the last N utterances rendered
(10 s at 24 kHz mono float is ~1 MB; eight of them cover the window) — that `fill()` consults first;
the scheduler keeps writing AAC for the persistent cache. Then: encode straight to the final path
(`AVAudioFile(forWriting:)` on the destination, then strip the padding in place or accept it), decode
straight from the store's URL, and store the clip's duration beside the key so a cache hit never
decodes. The encode is also on the scheduler's critical path — it awaits `store.write` before the next
`render` — see §3.6.

### 3.4 Two buckets waste generator time

`KokoroCoreMLResources.buckets = [7, 15]` and `selectBucket` pads every call to the smallest bucket that
holds the predicted audio. Since Plan 9 packs sentences to 160 characters (~10–11 s at 15 chars/s), the
typical utterance renders in the 15 s bucket at 8–13 s of speech — 13–47 % of the generator's work is
padding; a heading or a one-line paragraph renders in the 7 s bucket at 1–3 s — 60–85 % padding. The
harmonic source (`HarmonicSource.swift`) is computed over the full padded bucket too (§3.6). Upstream
exports 3, 7, 10, 15 and 30 s buckets (M1: 3 s in 157 ms, 7 s in 511 ms, 15 s in 691 ms, 30 s in
1,229 ms — cost is close to linear in bucket seconds).

**Fix.** Stage the 3 s and 10 s buckets (`scripts/fetch-kokoro-coreml.sh`, `KokoroCoreMLResources`,
tests). Costs: ~+120 MB of bundle per bucket (decoder-pre 64 MB + har-post 38 MB + f0ntrain 20 MB) and
a longer first-launch plan build on an A13. Two of the three weight files are byte-identical across
buckets, so the right long-term shape is an upstream re-export with enumerated shapes — one weight
blob, one compute plan per shape — which would also make the 30 s bucket (a whole 300-character
utterance in one call, the deferred cure for the sentence-final tune at a seam) affordable.

### 3.5 Rate and heat: the app knows a rate is unsustainable and keeps playing at it

`RateLimits` gates the rates *offered* from the rolling RTF, and `PlaybackCoordinator.setRate` clamps
when the listener changes rate — but when RTF worsens mid-book (the A13 reached thermal state 2 after
150 s of continuous 4x synthesis and its RTF rose to 0.335, above the 0.2 that 4x needs), the current
`rate` stays, the window drains, and playback pauses on "catching up". `availableRates` is refreshed on
`.idle` only.

**Fix.** When `measuredRTF` moves the sustainable cap below the current rate, step the rate down to the
cap (and tell the listener once); size the window in synthesis seconds rather than a flat 60 s × rate so
higher rates buffer proportionally more; render the window in one burst then idle, which the policy
already does. The unplugged 20-minute run at 4x (a spike follow-up) is the measurement this needs.

### 3.6 Everything Swift-side is serialised with Core ML on one queue

Per utterance, on `KokoroCoreMLEngine`'s serial `DispatchSerialQueue`: G2P → tokenize → cut → for each
piece: duration → alignment → F0 → decoder-pre → harmonic source (Swift/vDSP) → generator → trim →
tail click → seam → crossfade; then fold timings, then return; then the scheduler awaits AAC encode and
the file write before the next request starts. Core ML's CPU stages are multi-threaded inside (BNNS);
everything else is single-threaded and waits. Specific items, in order of certainty:

- **The harmonic source waits for decoder-pre although it needs only `f0Padded`**, which exists before
  decoder-pre runs (`KokoroSynthesisExecutor.swift:260` vs `:277-291` vs `:299-325`).
  `StageTimings.decoderPreHnsfOverlap` is declared and subtracted from `total` but never assigned — the
  overlap was designed upstream and not implemented. Start `buildHar` on another thread before
  `decPreModel.prediction` and join after: hides the whole hn-NSF stage (≤ 40 ms per call on the A13
  for the 7 s bucket, about double for 15 s).
- **The harmonic source runs over the full padded bucket**: `fullF0Len = bucket × 80` frames → 360,000
  samples × 9 harmonics for a 15 s bucket, each harmonic a scalar Double interpolation loop plus
  `vvsin`; then 3.24 M Gaussian draws through a scalar xorshift loop; then scalar padding and concat
  loops (`HarmonicSource.swift:317-435`, `:456-467`, `:593-603`, `:727-755`). Past the predicted
  frames f0 is 0, the voiced mask is 0 and the sine term is multiplied away — so the nine sine passes
  can stop at `predictedFrames × 300` with identical output (keep the noise over the full length, as
  the reference does). Roughly halves hn-NSF for a 4 s utterance in the 15 s bucket (estimate).
- **No phoneme cache for out-of-vocabulary words.** `EnglishG2P.phonemize` is stateless; a word not
  in gold/silver after case-folding and stemming goes to the BART fallback — every character name,
  place name and rare word, on every page. One call is an encoder pass plus up to 50 decoder steps that
  each re-run the decoder over the growing prefix (no KV cache) with a synchronous `.item()` eval, on
  MLX's CPU stream with compilation disabled: 5–30 ms per name (estimate), 25–150 ms for a page with
  five names. The fallback reads only `word.text`, so a `[String: (String, Int)]` in front of it is
  exact; a book's OOV vocabulary is a few thousand strings. (`preprocess` also compiles a
  `NSRegularExpression` per call — `EnglishG2P.swift:141` — worth an upstream one-liner.)
- G2P and tokenization of utterance N+1 could run while the generator renders N; the AAC encode of N
  could run while N+1 synthesizes (bounded in-flight writes; `.rendered` still after the write;
  `storeFull` unchanged).

Expected gain 10–25 % of per-utterance wall time (estimate). Measure first: `KokoroPipeline`'s
`StageTimings` are computed per call and dropped — log them and the G2P time once on a phone before
spending a plan here.

### 3.7 Compute units: keep CPU-only

Upstream's phone measurements (staged policy: duration CPU, F0 CPU+GPU, decoder-pre CPU+ANE, generator
CPU+GPU): iPhone 15 Pro Max 15 s in 3,272 ms (RTF 0.22), iPhone 12 Pro 6,250 ms (0.42). Our A13 on
CPU-only: 0.18. On the A13 the GPU policy measured 0.37 and 1.2 GB (`2026-09-04-pre-a14-runtime.md`).
The generator — the only stage that matters — is rejected by the iPhone ANE compiler as exported
(`ANECCompile() FAILED` on A14 and A17 Pro; per-axis tensor limit), and on an M2 Air `.all` was slower
than `.cpuAndGPU` at every bucket (upstream's `coreml-compute-unit-ablation.md`). So: CPU-only stays;
the two things worth one measurement each on an A14+ phone are CPU-only itself (should be roughly twice
the A13) and `MLOptimizationHints.specializationStrategy = .fastPrediction` (iOS 18) on the generator.

## 4. Launch

### 4.1 Warm-up loads eight stages one after another

`KokoroCoreMLModels.init` (`Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLModels.swift`)
loads the two duration models, two F0 models, two decoder-pre and two generators in a loop, on the
engine's serial queue: 3–5 s on every launch, 206 s on the first launch after install (A13; Core ML
builds its compute plans then). Until it finishes, every Kokoro render waits behind it.

**Fix.** Load the 7 s bucket's four stages first (concurrently — `MLModel.load(contentsOf:configuration:)`
is async and each build is independent), build the G2P (§3.2), mark the engine ready, and load the
15 s bucket's stages afterwards; `KokoroModelProvider.prepareForBucket` is already the hook for a
provider that loads lazily. The first launch's first Kokoro sound then comes at ~100 s instead of 206 s
on an A13, and a warm launch at ~2 s. Memory peaks briefly higher during concurrent plan builds —
measure on the A13.

### 4.2 The MLX route: cheap at launch, dead weight in the binary, and MisakiSwift needs it anyway

The launch probe (`KokoroAvailability.swift:90-115`) checks the simulator, then Metal GPU family 7, then
`guard let decision = probe.decision` — and `KokoroRuntimeDecision.current` is nil — before it would
ever hash the weights. So in a shipping build the probe costs one Metal device creation on a detached
task: nothing to fix (moving the `decision` guard first would make it free). Only a DEBUG phone with the
override set hashes 327 MB + 14.6 MB beside the warm-up. The MLX `KokoroEngine` is constructed lazily
from `synthesize` and never at launch.

What the route does cost: in the Debug phone bundle, `Cmlx.framework` 51 MB (unstripped; Release
~15–25 MB, estimate), `MLX`/`MLXNN` 4.3 MB, `KokoroSwift` 0.8 MB, a 3.6 MB `default.metallib`, seven
dynamic frameworks mapped at launch, and — if anyone runs `scripts/fetch-kokoro-model.sh` — 342 MB of
weights that never render (this Mac's `App/Resources/Kokoro` is empty and the current phone build has
none). Removing `KokoroSwift` alone saves under a megabyte: **MisakiSwift depends on `MLX`, `MLXNN` and
`MLXUtilsLibrary` directly** for its BART fallback (1 encoder + 1 decoder layer, d = 128, ~750 k
parameters), so mlx-swift ships with the G2P regardless. The durable saving is to port that tiny
network to Accelerate/BNNS: mlx-swift leaves the graph, the process-global `MLX.compile(enable: false)`
goes with it, and the per-op MLX dispatch in §3.6 becomes a few vDSP calls. Also 9 MB of British
lexicon ships for a `b*` voice most readers never choose.

### 4.3 `App.init` does disk work on the main thread

`AppEnvironment.live()` runs inside the `@State` initialiser (`App/T2SReader/T2SReaderApp.swift:7-16`),
before the first frame:

- `FileAudioStore.init` → `removeStaleCodecDirectories` (`Sources/T2SCore/Render/FileAudioStore.swift:14-37`):
  a synchronous `contentsOfDirectory` and `removeItem` of any old codec directory. After the 32 → 64
  kbps change that is up to the whole old cache — thousands of files — deleted on the main thread on
  one launch (seconds, estimate). Move it to the store's actor, after first paint.
- `AudioPlayer()` starts the `AVAudioEngine` in `init`, before `AudioSessionController` sets the
  category in `RootPager.onAppear` — a route/format negotiation that may be repeated.
- The SwiftData container and migration plan (`LibraryStore.swift:72-78`) — necessary, but it need not
  precede the first frame.
- `RootPager.onAppear`: `DeviceMonitor.start()` → `stats()` → `ensureIndexed()` enumerates the audio
  directory with `resourceValues` per file (off main; 100 ms–1 s at capacity, estimate), then
  `LibraryModel.refresh()` — which decodes every queued and finished book's timeline (§5.4).

## 5. Import, persistence and the open path

### 5.1 A version bump re-derives the whole book on the first tap, and from three other places

`Library.timelineForPlayback` → `reprocess` (`Sources/T2SLibrary/Library.swift:89-118`), awaited by
`PlayerModel.load` before `coordinator.load`: a full Readium parse of the EPUB, segment + normalize
every chapter, decode every *old* chapter blob to collect its audio keys, one `audioStore.remove` actor
hop and file delete per rendered key, then encode and replace every chapter. Off the main thread, but
the UI shows nothing and cannot cancel. Estimate for a 500 k-character novel on an A13: 3–12 s (Readium
1–3 s, segment + normalize 1–4 s, old-audio GC 1–5 s if the book was prepared). It is also triggered by
`BookSheet.loadChapters` (every sheet `.task` and player dismiss), `BookmarkListModel.load`, and
`PrepareRunner.loadDocuments` — which runs at every scene activation while charging, so the first charge
after an update re-derives every queued document serially. Normalizer 3 (Plan 11) makes every book in
the library stale right now.

**Fix.** (a) Keep the reader's per-chapter text (`ChapterInput` blocks) at import, so re-derivation
never touches Readium or PDFKit again; (b) re-derive per chapter, lazily, when a chapter is first
needed — `TimelineCodec` already stamps the versions into each chapter header and chapters are separate
rows; (c) let stale audio keys age out of the LRU instead of decoding old blobs to delete them;
(d) make the remaining reprocess a cancellable background task with a progress line, and have the Book
sheet, Bookmarks and Prepare read `currentTimeline` (which never reprocesses).

### 5.2 Prepare rewrites the whole chapter blob per rendered utterance

`PrepareRunner.render` (`Sources/T2SApp/Playback/PrepareRunner.swift:216-238`) calls `store.saveChapter`
on every `.rendered` event; `LibraryStore.saveChapter` re-encodes the chapter (JSON + LZFSE,
`TimelineCodec.encode`), replaces the external-storage blob, recounts `renderedCount`/`durationSeconds`
and commits — every 1–3 s for the whole prepare budget (1,500–3,000 utterances for 3 h). A
~170-utterance chapter with word timings is ~300–500 KB of JSON: ~10–30 ms per write and 100–300×
write amplification (estimates), all on the `ModelActor`, ahead of position saves, `summaries()` and
`refresh`. Playback already does this right: `PlayerModel.persistRenderedChapters` hashes chapters and
writes the changed ones on pause, dismiss and background.

**Fix.** Save when a chapter completes, every ~10 s, and on `.idle`/cancel/`storeFull`; a lost write is
self-healing because `reconcileWithStore` re-derives `rendered` from the audio store on load.

### 5.3 Import CPU: ~30 regex passes per utterance

`TextNormalizer.normalize` runs eight rules, each one or more `NSRegularExpression` passes: 14 for
abbreviations, 8 for numbers, plus one per pronunciation-dictionary entry — ~30 + D passes per
utterance, ~150 k calls for a 5,000-utterance novel (1–3 s, estimate), paid at import and at every
re-derivation. Patterns are compiled once; nothing is quadratic. Fold the abbreviation and dictionary
patterns into one alternation each and pre-screen the number passes on "contains a digit". The import
itself is structurally fine — off the main thread, O(total characters), one commit — but shows no
progress and cannot be cancelled.

### 5.4 The open path: O(n) on the main actor and n actor hops before the first sound

`QueueRow` tap → `ReaderPage.open()` → `PlayerModel.load` (`Sources/T2SApp/Player/PlayerModel.swift:143-172`):

- `persistRenderedChapters()` hashes every chapter of the *previous* book (`chapter.hashValue` — SipHash
  over every utterance's strings, spans and timings) on the main actor, then `timeline.chapters.map(\.hashValue)`
  does it again for the new one: a few MB hashed, 5–20 ms (estimate), repeated on every pause, Reader
  dismiss and backgrounding.
- `library.timelineForPlayback` decodes every chapter (`LibraryStore.timeline(for:)`, `:218-227`;
  `chapter(_:of:)` has no callers). Off main, but the `ModelActor` is serial: if `LibraryModel.refresh`
  is mid-flight, the tap waits behind every other book's decode.
- `coordinator.load` (`PlaybackCoordinator.swift:105-114`): per utterance a SHA-256 *plus* 32 ×
  `String(format: "%02x")` (`RenderKey.swift:15-16`, ~30–40 µs each, estimate) and two O(chapters)
  timeline subscripts — 150–200 ms synchronous on main for a 4,000-utterance book (estimate).
- `reconcileWithStore` (`:134-150`): one `await store.contains` per rendered utterance, and `play()`
  awaits that whole chain (`:159`) before `fill()` — for a fully prepared book, thousands of main↔actor
  hops before the first `store.read`. `fill()` already self-heals a missing clip, so the gate is
  unnecessary.
- `LibraryModel.refresh` (`Sources/T2SApp/Library/LibraryModel.swift:74-99`) decodes the whole timeline
  of every queued or finished document whose progress key changed, to compute `DocumentProgress` — and
  the key changes on every position save and every `saveChapter`, so every cold launch decodes every
  book, and the playing book re-decodes on every refresh (launch, each `.active`, every list action,
  pull-to-refresh, continuation, after Prepare). `PrepareRunner.loadDocuments` decodes each document
  twice (`timelineForPlayback`, then `renderSnapshot`), then builds a render key and does one
  `audioStore.contains` hop per utterance whether or not the `audioRef` matches.
- `segmentFinished` → `save()` → `savePosition` fetches and commits a row every utterance (~10 s).

**Fix.** Don't gate `play()` on the reconcile chain; skip the key when `audioRef` is nil and hex via a
lookup table (or cache the SHA prefix per document/voice/engine/versions and hash only the index); add
`contains(_ keys: [RenderKey]) -> [Bool]` to `AudioStore`; track chapter dirtiness from `.rendered`
events instead of hashing; persist the resume utterance index and elapsed seconds with the position so
`DocumentProgress` needs no decode; return the timeline from `renderSnapshot`; debounce position saves
to ~30 s plus pause/seek/background.

What is fine: SwiftData is a `@ModelActor` with predicates and fetch limits, blobs are external
storage so summaries never fault them, staleness reads version columns only; playback-time `.rendered`
events are applied in memory and persisted in one coalesced pass; `ReaderText` is built once per
document off the main thread and the typeset is cached by style key — neither is rebuilt per timeline
revision.

## 6. Build and bundle

### 6.1 The phone runs the Debug configuration

`App/project.yml` gives the Phone scheme `run: config: Debug`. HANDOFF's install recipe tells the owner
to switch it to Release in Edit Scheme, but `scripts/build-app.sh` regenerates the project, so the
switch is lost on the next generate — and Xcode's Run button after that installs `-Onone` code: the
harmonic source's per-sample loops, `KokoroCoreMLTailClick`/`KokoroCoreMLSeam` scans, `PcmJoiner`,
`alignValuesToFrames` (640 × 600 scalar writes), the tokenizer, Readium's parser, the segmenter's
`NSString` slicing and the Reader's typesetting all run unoptimised (10–50× slower for tight Swift
loops; Core ML itself is unaffected). The spike's RTF 0.18 came from a Release harness. The Debug phone
bundle built today is 475 MB with a 51 MB unstripped `Cmlx.framework`. Every listen since Plan 6 may
have been a Debug build.

**Fix.** `run: config: Release` for the Phone scheme (keep Debug for Simulator). The MLX development
override is compiled out of Release, which is fine: it is the route's escape hatch, not the owner's.

### 6.2 Bundle

Eight `.mlmodelc` stages are 335 MB of the bundle: decoder-pre 7 s and 15 s (64 MB each) and F0 7 s /
15 s (20 MB each) carry byte-identical weights, so ~84 MB is duplicated by the static-shape export, and
adding buckets (§3.4) duplicates more. MisakiSwift's resource bundle is 18 MB (9 MB of it the British
lexicon). Enumerated-shape stages upstream are the durable answer for the models; not bundling MLX
weights and not linking mlx-swift (§4.2) are the app-side ones.

## 7. Playback UI

Everything below is certain from the code; magnitudes are estimates unless cited.

- **`NowPlayingController.update()` runs ~20×/s while playing**: `PlaybackTicker` calls it every tick
  (`App/T2SReader/System/PlaybackTicker.swift:21`) and `RootPager` calls it again from
  `.onChange(of: env.player.elapsed)` (`Root/RootPager.swift:119`). Each call builds a snapshot —
  `libraryModel.queue` (filter + sort), `chapterIndex` (O(chapters)), an artwork lookup. The
  `MPNowPlayingInfoCenter` write itself is deduplicated to ≤ 1 Hz (`NowPlayingController.swift:193-206`)
  — good — **but with nothing loaded `update()` → `clear()` sets `nowPlayingInfo = nil` on every tick**,
  and the idle loop sleeps 250 ms, not the 1 s the comment claims: a MediaRemote XPC call 4×/s for as
  long as the app is in the foreground with no document.
- **The root view's body runs at 10 Hz** because of that `elapsed` `onChange`; each run recomputes
  `queue` twice, `summaries.map(\.id)`, `deviceState` and `chapterIndex`; `.onChange(of: state)` is
  registered twice; `MiniPlayer` re-bodies every time (closure inputs are never equal).
- **`highlight` is written every tick whether or not the word changed** (`PlaybackCoordinator.tick()`
  → `refreshHighlight()`, `:423-426`), so `ReaderPage.body`, `PlayerSheet` and `ChapterList` are
  invalidated 10×/s; `ReaderTextView.updateUIView` runs each time (its `setHighlight` deduplicates, so
  the redraw is per word). `Highlighter.highlight` allocates an array slice per call.
- **O(n) inside 10 Hz bodies**: `PlayerModel.isTotalApproximate` → `Timeline.isFullyRendered`
  (`allSatisfy` over every utterance once a book is rendered), read by `totalText` in the Reader, the
  Player sheet and every chapter row; `PlayerModel.chapters` → `ChapterEntry.entries` is O(chapters²)
  (a reduce per chapter), evaluated in `PlayerSheet` just for `.count > 1`; `chapterIndex` computed
  ~5× per tick; `ThinScrubber`/`TickScrubber` diff 48 `ForEach` children per tick for a knob.
- **Reader typesetting**: `ReaderTypesetter.attributedString` creates a `UIFont` and an
  `NSMutableParagraphStyle` *per paragraph* (10 k+ per typeset; re-run per Appearance slider step);
  `redrawHighlight` bridges two `UIColor(Color)`s and calls `rects(for:)` twice per word change, and
  `centreIfNeeded` a third time, each with `ensureLayout`; following uses `setContentOffset(animated:)`
  per line change. The whole document sits in one `UITextView` on TextKit 2 (viewport-lazy layout;
  `attributedText =` is O(length) once per open — fine).
- `LibraryModel.queue/finished/collection` filter + sort on every access (microseconds; cache on
  `summaries` didSet).

**Fix.** Delete the `elapsed` `onChange` (the ticker already updates Now Playing); clear once when
`current` becomes nil; park the ticker while idle/paused with no sleep timer; `if new != highlight`;
cache `isFullyRendered` and the chapter entries against `timelineRevision` like `tickCache` already
does for the rendered ticks; add a chapter-start prefix array to `TimeIndex`; give the tick strip and
the text view child views that observe only what they draw; one font and paragraph style per paragraph
kind; one `rects(for:)` pass shared by the redraw and the centring; resolve the tint colours on trait
change. Then look once with Instruments (§8).

## 8. Measure before spending: the numbers this audit could not get

No G2P timing, no per-stage 15 s-bucket timing and no phone load time for the precompiled `.mlmodelc`
staging exist anywhere in the repo (the engine test prints one measurement line that no saved log
contains).

1. **Per-stage timings on a phone.** `KokoroPipeline.SynthesisResult.timings` and the G2P time (with
   and without OOV words), logged once per utterance in a Release build on the A13 and on an A14+
   phone, for the 7 s and 15 s buckets. Decides §3.6 and §3.7.
2. **Background rendering** (spec §7.2, still "pending hardware"): 15 minutes screen-off at 1x and 3x,
   watching `measuredRTF` and `.catchingUp`. The smoothness goal depends on it.
3. **Unplugged thermals at 3–4x** for 20 minutes (spike follow-up). Decides §3.5's numbers.
4. **First-launch and warm-launch time** with concurrent, bucket-lazy loading (§4.1), on the A13.
5. **Open time** of a stale novel (§5.1) and of a prepared novel (§5.4), before and after.
6. **Instruments — Time Profiler and Core Animation** on the Reader while playing, for §7.

## 9. Checked and fine

- The scheduler/arbiter design: serial, one lease, play-ahead preempts Prepare at utterance granularity.
- `TimeIndex` prefix sums; `Timeline` subscripts are O(chapters); `@Observable`'s `_modify` keeps
  in-place timeline mutation free of copies; per-`.rendered` cost in the app layer is milliseconds.
- `AVAudioUnitTimePitch` at 1.0x is transparent (141 dB, measured); the player's clock is exact.
- Memory: 119 MB flat over 20 minutes on the A13 (measured); the post-processing copies of the running
  buffer (tail click, seam, join — three per piece) are a few MB of memcpy per utterance, nothing
  quadratic.
- `FileAudioStore`: lazy index, atomic writes, LRU eviction; O(n) `order` scans are fine at thousands
  of entries.
- The launch MLX probe short-circuits on the nil runtime decision; the MLX engine is never constructed.
- The audio session and remote-command wiring; `MPNowPlayingInfoCenter` writes are rate-limited to
  1 Hz while playing.
