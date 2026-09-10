# t2s_reader

An iOS app that turns EPUBs, web articles, and text PDFs into a read-along
audiobook experience, synthesized on-device. Design spec:
[docs/superpowers/specs/2026-09-01-t2s-reader-design.md](docs/superpowers/specs/2026-09-01-t2s-reader-design.md).

## Repository layout

```
Package.swift          Swift package "T2S". Targets: T2SCore (text pipeline), T2SAudio
                       (playback), T2SStore (SwiftData), T2SLibrary (ingest + library facade),
                       T2SApp (models, formatters).
Sources/<Target>/      library code, one directory per target
Tests/<Target>Tests/   Swift Testing suites; run with `swift test` on macOS
Packages/T2SReadium/   iOS-only package wrapping the Readium toolkit (EPUB import, positions,
                       Locator mapping). Readium does not build for macOS, so it is tested on the
                       iOS simulator with scripts/test-readium.sh.
Packages/T2SKokoro/    the Kokoro engines, two runtimes side by side. Core ML (the default):
                       KokoroCoreMLResources, KokoroTokenizer, KokoroCoreMLEngine and the
                       measured KokoroCoreMLDecision; CPU-only, so it runs on every phone the
                       app supports. MLX: KokoroResources, the KokoroEngine actor, the device
                       probe and KokoroRuntimeDecision, which need an A14 or newer GPU. MLX
                       needs a compiled Metal library, so the package is tested with xcodebuild
                       on macOS (scripts/test-kokoro.sh) and stays out of the root package,
                       which must keep working under plain `swift test`.
Packages/KokoroPipeline/
                       vendored mattmireles/kokoro-coreml @ 66d8cf51 (Apache-2.0): the low-level
                       Core ML pipeline the Core ML engine drives. Upstream keeps its
                       Package.swift in a swift/ subdirectory and SwiftPM cannot consume a
                       subdirectory by URL, which is the whole reason for the copy; its README
                       records the revision and the manifest edits.
Packages/MLXUtilsLibrary/
                       vendored mlalma/MLXUtilsLibrary 0.0.6 with its ZIPFoundation dependency
                       replaced by our own npz reader. Readium's ZIPFoundation fork and the
                       upstream one share the SwiftPM identity `zipfoundation` with disjoint
                       version ranges, so Kokoro and Readium could not resolve together; the
                       local copy takes zip off the Kokoro path entirely. docs/HANDOFF.md
                       carries the accepted cost and the exit plan.
App/                   the iOS app: project.yml → T2SReader.xcodeproj (generated, ignored)
                       with two app targets from one template, T2SReader (simulator + any
                       phone, no Kokoro) and T2SReaderKokoro (device only, and the app on a
                       phone: it runs on any iPhone the app supports, because Core ML is
                       CPU-only — only the MLX route inside it needs A14+); T2SReader/
                       (SwiftUI views, composition root; T2SReader/Reader/ draws the
                       read-along text itself (ReaderTextView, TextKit 2)), T2SReaderShare/
                       (the Share Extension), Resources/Fonts (Inter, OFL),
                       Resources/Readability/ (Readability.js), Resources/Kokoro/ (the MLX
                       weights and voice styles — ~342 MB, git-ignored, installed by
                       scripts/fetch-kokoro-model.sh), Resources/KokoroCoreML/ (the Core ML
                       stages, the 28 English voices and the runtime JSON — 347 MB,
                       git-ignored, installed by scripts/fetch-kokoro-coreml.sh --app)
scripts/               build and CI helpers (check-licenses.sh, test-readium.sh, test-kokoro.sh,
                       build-app.sh, build-device.sh, fetch-kokoro-model.sh,
                       fetch-kokoro-coreml.sh, fetch-fonts.sh, fetch-readability.sh)
spikes/                throwaway experiments — never imported by shipping code
  SpikeHarness/        iOS harness for spec §7; project.yml → generated .xcodeproj (ignored)
  findings/            one markdown file per spike result, from findings/TEMPLATE.md
docs/superpowers/
  specs/               design specs (the source of truth for what gets built)
  plans/               implementation plans, one file per plan, plus the roadmap
.github/workflows/     CI: swift test + license guard; Readium package on the simulator;
                       T2SKokoro on macOS; the app for the simulator and for the device
```

Ignored and regenerated, so they may appear in an editor but never in git:
`.build/` (SwiftPM and xcodebuild output, in every package), `.swiftpm/`,
`.superpowers/` (planning-tool scratch),
`spikes/SpikeHarness/SpikeHarness.xcodeproj/` (from `project.yml`), the
model files under `spikes/SpikeHarness/Resources/`, `App/Resources/Kokoro/`
and `App/Resources/KokoroCoreML/` (see `spikes/README.md`,
`scripts/fetch-kokoro-model.sh` and `scripts/fetch-kokoro-coreml.sh`), and
`App/T2SReader.xcodeproj/`, `App/T2SReader/Info.plist` and
`App/T2SReader/Info-Kokoro.plist` (from `App/project.yml`).

## Rules that keep this tidy

- One `.gitignore`, at the root.
- Generated files are never committed: project files come from `project.yml`,
  build output from SwiftPM and xcodebuild.
- New code goes in a target under `Sources/` with its tests under `Tests/`;
  code that needs a dependency the root package cannot take — iOS-only, like
  Readium, or MLX, which needs a compiled Metal library — goes in a package
  under `Packages/`; `spikes/` is for experiments only.
- Every plan lives in `docs/superpowers/plans/`; every spec in
  `docs/superpowers/specs/`. Spike results go in `spikes/findings/`.
- A vendored third-party package under `Packages/` (only when an upstream
  dependency cannot be used as-is, like `Packages/MLXUtilsLibrary`) records the
  upstream URL, the exact revision it was copied from, and every local patch in
  that package's README; it keeps the upstream LICENSE file; and it gets a row
  in `docs/licenses.md`.

## Working on it

```bash
scripts/fetch-kokoro-coreml.sh --app  # once: the Core ML model files into App/Resources/KokoroCoreML
scripts/fetch-kokoro-model.sh  # once, MLX route only: weights + voices into App/Resources/Kokoro
swift test                     # the root package, on macOS
scripts/test-readium.sh        # Packages/T2SReadium on an iPhone simulator
scripts/test-kokoro.sh         # Packages/T2SKokoro with xcodebuild on macOS (MLX needs Metal)
scripts/check-licenses.sh      # fails on any copyleft dependency, in every package
cd spikes/SpikeHarness && xcodegen generate && open SpikeHarness.xcodeproj
scripts/build-app.sh           # regenerate App/T2SReader.xcodeproj and build for the simulator
swift scripts/make-app-icon.swift  # regenerate the app icon PNG after editing the script
scripts/build-device.sh        # compile proof of the Kokoro target for a device (Release, unsigned)
scripts/audio-probe.sh         # render one passage nine ways (Core ML variants + MLX control) into spikes/findings/audio-probe/
swift scripts/analyze-wav.swift spikes/findings/audio-probe/*.wav   # pitch spread, pauses, impulses per WAV
scripts/quality-probe.sh       # place every impulse on its token, measure seams, tails and hyphens, into spikes/findings/quality-probe/
# the lever probe (voices, blends, pitch spread) is a test: mkdir spikes/findings/lever-probe, then run T2SKokoroTests/KokoroLeverProbe with xcodebuild
open App/T2SReader.xcodeproj   # after scripts/build-app.sh has generated it
scripts/fetch-readability.sh   # re-vendor Readability.js (committed under App/Resources/Readability)
```

Run `scripts/fetch-kokoro-coreml.sh --app` once per machine before running the
Core ML tests: it stages the fourteen Core ML stages, the 28 English voices and
the two runtime JSON files into `App/Resources/KokoroCoreML` (72 files, 619 MB,
git-ignored, every file verified against a published SHA-256). Without them the
Core ML tests in `Packages/T2SKokoro` skip. **The phone build does not bundle
them** (since 2026-09-10): the app downloads the same 72 files from the pinned
Hugging Face revision on its first launch, over Wi-Fi, verifies each against
the hashes in `KokoroCoreMLManifest`, compiles the stages on the phone and keeps
them under its own Application Support (`KokoroCoreMLInstall`), so an install
is about 60 MB instead of 676 MB and a reinstall never downloads again. A
developer who would rather bundle them adds `Resources/KokoroCoreML` back to the
`T2SReaderKokoro` target in `App/project.yml`; the bundle is looked in first.

`scripts/fetch-kokoro-model.sh` is for the MLX route only, and is not needed to
run the app: it installs `kokoro-v1_0.safetensors` (327,115,152 bytes) and
`voices.npz` (14,629,684 bytes) into `App/Resources/Kokoro`, verifying both
SHA-256s, and reuses the spike harness's copies if they are already on the
machine. The two files are git-ignored; without them the MLX package tests skip
and a device build bundles no MLX voices. The first `scripts/test-kokoro.sh` or
`scripts/build-device.sh` compiles mlx-swift (10–15 minutes, ~2 GB of
DerivedData — the cold builds measured here were 1 min 51 s on this Mac and
3 min 17 s for the Release device build); later runs are incremental.

`scripts/test-kokoro.sh` and `scripts/audio-probe.sh` need disk. The
model-backed tests share one compile of the staging (about 350 MB in
`$TMPDIR`), and Core ML's own runtime cache under
`~/Library/Caches/com.apple.dt.xctest.tool` grows by roughly 0.9 GB per loaded
engine; both scripts sweep both before and after a run. Budget about 2 GB free.
The app bundle is precompiled by Xcode and is unaffected.

**Never play audio on the owner's Mac.** Opening a book in the simulator starts
playback through the Mac's speakers; launch the app with
`SIMCTL_CHILD_T2S_SILENT=1 xcrun simctl launch <udid> com.t2s.reader` — the app
zeroes every player's gain when `T2S_SILENT` is set — and never touch the Mac's
volume.

**Running the app.** Open the generated `App/T2SReader.xcodeproj` and pick a
scheme — **Phone** for an iPhone, **Simulator** for the Mac:

- **Simulator** (the `T2SReader` target) — the everyday build, and the one CI builds. Runs on the
  iPhone simulator and on any phone, does not link Kokoro, and speaks with the
  system voice. mlx-swift cannot link against the iOS simulator SDK (the SDK's
  Metal framework does not export `_MTLIOErrorDomain` or `_MTLTensorDomain`),
  and Xcode resolves packages per project rather than per target, so the only
  way to keep "open the project and run on a simulator" working was a second
  target. The Core ML engine cannot rescue the simulator either: MisakiSwift,
  the G2P both runtimes use, links mlx-swift. A document whose stored voice is
  a Kokoro voice plays through the system default here, and the log says so
  (`voice route resolved: kokoro → default`).
- **Phone** (the `T2SReaderKokoro` target) — device only (`SUPPORTED_PLATFORMS: iphoneos`),
  the app you install on a phone. It links `Packages/T2SKokoro`, compiles with
  `KOKORO_ENGINE`, and bundles `Resources/KokoroCoreML` — Xcode compiles the
  eight `.mlpackage` stages into `.mlmodelc`, which is most of the 433 MB app.
  Core ML is CPU-only, so it runs on any iPhone the app supports. The MLX route
  inside it needs an A14 or newer phone (iPhone 12+): MLX's fused GEMM kernels
  need `simdgroup_matrix`, which Metal provides from Apple GPU family 7 upward,
  and the app probes for that at launch. Both targets come from one
  `targetTemplates` entry in `App/project.yml`, so they cannot drift apart.
  Its Run action builds Release: the app you listen to is the optimised one, and the RTF the app
  measures is the one the spike measured (`docs/superpowers/specs/2026-09-08-performance-audit.md`
  §6.1). The Simulator scheme stays Debug. For a debugging session on the phone, set the Run action
  back to Debug (Edit Scheme → Run → Info): breakpoints and `po` are degraded under Release, and
  incremental phone builds are slower.

Import a document with the `+` button on the Queue page.

**Kokoro is the default voice on the phone build, after a one-time download and
warm-up.** On `T2SReaderKokoro` a document with no voice of its own plays
through Kokoro Heart on the Core ML route; `KokoroCoreMLDecision.current`
carries the A13 measurement (RTF 0.181, 119 MB —
`spikes/findings/2026-09-04-pre-a14-runtime.md`), so every rate up to 4x is
offered. The first launch downloads and compiles the model (the glow across the
top says "Downloading the voice · 120 of 619 MB", then "Preparing the voice · 3
of 14"), then builds Core ML's compute plans — 206 s on the A13 in the spike —
and later launches take seconds: the engine is ready once the two duration
models and the 3 s and 15 s buckets have loaded (eight of fourteen stages), and
the 7 s and 10 s buckets follow behind. The everyday `T2SReader` target links no
engine and keeps the system voice.

**Keep the app in front while it warms up.** iOS kills a process that is not
frontmost and holds 80% of a core for a minute, and a compute-plan build is
exactly that (the iPhone 17 Pro's `cpu_resource_fatal` of 2026-09-09). So the
app builds plans and compiles the download only while the scene is active
(`ForegroundGate`): lock the phone or switch away and the warm-up pauses until
you come back; a background launch (the overnight Prepare task) never builds
them, and a Prepare pass waits for a foreground warm-up on a fresh install.
Renders made while the app is in the background — play-ahead with the screen
off, Prepare on charge — are paced by `CPUBudget` under 60% of a core over a
minute, and the log (`render.pacing`) says when that engages.

**Measuring on a phone.** Every stage load, every pipeline call and every
utterance writes its seconds to the unified log under subsystem
`com.t2s.reader`, category `kokoro.timing`:

```bash
log stream --predicate 'subsystem == "com.t2s.reader"' --style compact   # everything
log stream --predicate 'subsystem == "com.t2s.reader" AND category == "kokoro.timing"' --style compact
```

A stage load well under a second means Core ML found its compute plan in its
cache; many seconds means it built one. The compute units are a per-session
switch for the experiment the performance audit's §3.7 asks for: set the user
default `kokoro.computeUnits` to `cpuAndNeuralEngine`, `cpuAndGPU` or `all`
(Xcode → Edit Scheme → Run → Arguments: `-kokoro.computeUnits cpuAndNeuralEngine`)
and compare the `kokoro call` lines; unset is `cpu`, the measured policy.
`scripts/compute-probe.sh` runs the same comparison on this Mac.

The MLX route stays wired beside Core ML, gated on the iPhone 17 Pro
measurements (spec §7.2–§7.5, §7.7): `KokoroRuntimeDecision.current` is `nil`
and the engine refuses to run on guessed constants. For development on an A14+
phone you can switch that gate on by hand in a `DEBUG` build, which yields an
explicitly labelled decision (`isDebugOverride`) rather than a measured one.
Set either the `T2S_KOKORO_DEBUG_OVERRIDE` environment variable to `1` (Xcode →
Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables, on
the **Phone** scheme) or the `kokoro.debugOverride` user default to
true. Once the MLX probe answers available the Preferences footer gains a
second line ("MLX route: development override active.") and the picker gains a
second set of 28 voices, each row suffixed " · MLX". The override is compiled
out of Release builds, it does nothing for the Core ML route, and it does
nothing on the simulator, which reports the route unavailable before any GPU
probe.

### Sharing into the app

`App/T2SReaderShare` is a Share Extension: from Safari, Files, or any share
sheet, "T2S Reader" accepts a link, plain text, an EPUB, or a PDF, copies it
into a `ShareInbox` inside the app group, and opens the host app on a hand-off
URL to finish the import. Both targets are members of one app group
(`group.com.t2s.reader` by default) and the library lives in that group's
container, so **the app will not open its library without the
`application-groups` entitlement**. `scripts/build-app.sh` signs ad hoc for
exactly this reason (unsigned only under `CI`); an unsigned build shows "The
library could not be opened."

**Another team, another Mac.** A team that is not the owner's cannot register
the owner's app group, so the bundle id, the app group and the team are
per-Mac settings in `App/Local.xcconfig` (git-ignored; the build scripts copy
`Local.xcconfig.example` there): `DEVELOPMENT_TEAM`, `T2S_BUNDLE_ID` and
`T2S_APP_GROUP`, with the defaults in `App/project.yml`. The Share Extension
takes `$(T2S_BUNDLE_ID).share`, the entitlements take `$(T2S_APP_GROUP)`, and
`AppPaths.appGroupIdentifier` reads the group back out of the bundle's
`T2SAppGroupIdentifier`. Nothing tracked changes.

### Prepare, on charge

Tier-3 Prepare renders ahead while the phone is idle. It is *opportunistic*,
not scheduled: `PrepareTask` submits a `BGProcessingTaskRequest` with
`requiresExternalPower = true` and an earliest-begin 15 minutes out, and iOS
decides whether and when to run it. It may not run at all on a given night,
and the simulator rejects the request outright — `BGTaskSchedulerErrorDomain
error 1` in the log there is expected, not a bug. Everything Prepare renders
is cache, so nothing is lost when it does not run.

### Cloud voices are bring-your-own-key

There is no backend and no account. Preferences → Cloud voices takes an HTTPS
endpoint, a model, a voice, and a request rate, plus **your** provider's API
key. The contract is OpenAI's speech endpoint —
`https://api.openai.com/v1/audio/speech`, a model such as `gpt-4o-mini-tts`, a
voice such as `alloy` — asked for raw 16-bit PCM at 24 kHz; a proxy in front of
another provider may answer with JSON (`{"audio": <base64 float32 PCM>,
"sample_rate": 24000, "word_timings": [...]}`) to add word timings, which
OpenAI does not give. The key goes to the Keychain and nowhere else; the non-secret
configuration (endpoint, model, voice, rate) is all that the settings store
keeps, and only the endpoint/model/voice/format fingerprint enters the render
key, so changing the rate limit does not invalidate cached audio. "Remove key"
deletes it from the device. Leave the section empty and the app never talks to
anything but the phone.

### Voices

On a phone the voice list (Preferences → Voice, and **Change voice** on a
document) lists the 28 Kokoro voices only — name, accent and gender per row,
American English then British — and nothing from the system; every row has a
preview button that reads one sample sentence in that voice (the book pauses
while it plays). The Simulator build links no Kokoro engine and keeps the
system voices there, with the same previews.

### Reader, speed picker, and sleep timer

Every way of starting playback from a document — Play on a Queue row, a tap
on the mini-player, and Play or a chapter in a book — opens the full-screen
Reader; there is no separate player screen. (The mini-player's own
play/pause button and the lock-screen controls still act in place.) The
paragraph being read is tinted lightly and
the spoken word more strongly (on a PDF, the utterance rather than the
paragraph); the page follows the word while audio plays, scrolling pauses
following until **Back to current** is tapped, and tapping a word seeks to it.
Floating buttons at the top: back, bookmark, and a menu
(chapters, bookmarks, appearance, change voice, sleep timer, details, render
whole document). At the bottom: a thin progress bar with times (its darker
segments are the rendered audio), sleep timer · back 15 · play · forward 30 ·
speed, then appearance · the voice chip · contents. Use the speed control to
choose 0.5x–4.0x in 0.1x steps; rates the device cannot sustain are
unavailable. The sleep timer offers 10, 20, 30, 45, or 60 minutes, plus
**End of chapter**, and pauses playback when it fires.

### Bookmarks

Save the current position with the Reader's bookmark button, or **Bookmark**
in its overflow menu. See them in the Book sheet's **Bookmarks** section,
shown once a document has any, or from **Bookmarks** in the Reader's overflow
menu — newest first. Tapping a bookmark plays from there; long-press one for
**Delete bookmark**, and in the Bookmarks list reached from the Reader's
overflow you can also swipe it away.
