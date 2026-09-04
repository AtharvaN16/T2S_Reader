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
Packages/T2SReadium/   iOS-only package wrapping the Readium toolkit (EPUB reading, Locator
                       mapping). Readium does not build for macOS, so it is tested on the iOS
                       simulator with scripts/test-readium.sh.
Packages/T2SKokoro/    the Kokoro engine (kokoro-ios on MLX): the model-file contract, the
                       KokoroEngine actor, the device probe, the runtime decision. MLX needs a
                       compiled Metal library, so the package is tested with xcodebuild on
                       macOS (scripts/test-kokoro.sh) and stays out of the root package, which
                       must keep working under plain `swift test`.
Packages/MLXUtilsLibrary/
                       vendored mlalma/MLXUtilsLibrary 0.0.6 with its ZIPFoundation dependency
                       replaced by our own npz reader. Readium's ZIPFoundation fork and the
                       upstream one share the SwiftPM identity `zipfoundation` with disjoint
                       version ranges, so Kokoro and Readium could not resolve together; the
                       local copy takes zip off the Kokoro path entirely. docs/HANDOFF.md
                       carries the accepted cost and the exit plan.
App/                   the iOS app: project.yml → T2SReader.xcodeproj (generated, ignored) with
                       two app targets from one template, T2SReader (simulator + any phone) and
                       T2SReaderKokoro (A14+ device only); T2SReader/ (SwiftUI views, composition
                       root), T2SReaderShare/ (the Share Extension), Resources/Fonts (Inter, OFL),
                       Resources/Readability/ (Readability.js), Resources/Kokoro/ (the Kokoro
                       weights and voice styles — ~342 MB, git-ignored, installed by
                       scripts/fetch-kokoro-model.sh)
scripts/               build and CI helpers (check-licenses.sh, test-readium.sh, test-kokoro.sh,
                       build-app.sh, build-device.sh, fetch-kokoro-model.sh, fetch-fonts.sh,
                       fetch-readability.sh)
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
model files under `spikes/SpikeHarness/Resources/` and `App/Resources/Kokoro/`
(see `spikes/README.md` and `scripts/fetch-kokoro-model.sh`), and
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

## Working on it

```bash
scripts/fetch-kokoro-model.sh  # once: install the Kokoro weights + voices into App/Resources/Kokoro
swift test                     # the root package, on macOS
scripts/test-readium.sh        # Packages/T2SReadium on an iPhone simulator
scripts/test-kokoro.sh         # Packages/T2SKokoro with xcodebuild on macOS (MLX needs Metal)
scripts/check-licenses.sh      # fails on any copyleft dependency, in every package
cd spikes/SpikeHarness && xcodegen generate && open SpikeHarness.xcodeproj
scripts/build-app.sh           # regenerate App/T2SReader.xcodeproj and build for the simulator
scripts/build-device.sh        # compile proof of the Kokoro target for a device (Release, unsigned)
open App/T2SReader.xcodeproj   # after scripts/build-app.sh has generated it
scripts/fetch-readability.sh   # re-vendor Readability.js (committed under App/Resources/Readability)
```

Run `scripts/fetch-kokoro-model.sh` once before anything Kokoro-related: it
installs `kokoro-v1_0.safetensors` (327,115,152 bytes) and `voices.npz`
(14,629,684 bytes) into `App/Resources/Kokoro`, verifying both SHA-256s, and
reuses the spike harness's copies if they are already on the machine. The two
files are git-ignored; without them the model-backed package tests skip and a
device build bundles no voices. The first `scripts/test-kokoro.sh` or
`scripts/build-device.sh` compiles mlx-swift (10–20 minutes, ~2 GB of
DerivedData); later runs are incremental.

**Running the app.** Open the generated `App/T2SReader.xcodeproj` and pick a
scheme:

- **`T2SReader`** — the everyday scheme. Runs on the iPhone simulator and on
  any phone, and does not link Kokoro. mlx-swift cannot link against the iOS
  simulator SDK (the SDK's Metal framework does not export `_MTLIOErrorDomain`
  or `_MTLTensorDomain`), and Xcode resolves packages per project rather than
  per target, so the only way to keep "open the project and run on a simulator"
  working was a second target. A document whose stored voice is a Kokoro voice
  plays through the system default here, and the log says so
  (`voice route fallback: kokoro → default`).
- **`T2SReaderKokoro`** — device only (`SUPPORTED_PLATFORMS: iphoneos`), links
  `Packages/T2SKokoro` and compiles with `KOKORO_ENGINE`. It needs an A14 or
  newer phone (iPhone 12+): MLX's fused GEMM kernels need `simdgroup_matrix`,
  which Metal provides from Apple GPU family 7 upward, and the app probes for
  that at launch. Both targets come from one `targetTemplates` entry in
  `App/project.yml`, so they cannot drift apart.

Import a document with the `+` button on the Queue page.

**Kokoro is not the default voice yet.** Preferences → Voice lists a "Kokoro
(beta)" section with a footer saying whether the route is usable on this
device, but the default voice stays the system voice until the iPhone 17 Pro
measurements land (spec §7.2–§7.5, §7.7) and `KokoroRuntimeDecision.current`
can be filled from them — the engine refuses to run on guessed constants. For
development on an A14+ phone you can switch the gate on by hand in a `DEBUG`
build, which yields an explicitly labelled decision (`isDebugOverride`, and a
"development override" note in the Preferences footer) rather than a measured
one. Set either the `T2S_KOKORO_DEBUG_OVERRIDE` environment variable to `1` (Xcode
→ Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables, on
the `T2SReaderKokoro` scheme) or the `kokoro.debugOverride` user default to
true. The override is compiled out of Release builds, and it does nothing on
the simulator, which reports the route unavailable before any GPU probe.

### Sharing into the app

`App/T2SReaderShare` is a Share Extension: from Safari, Files, or any share
sheet, "T2S Reader" accepts a link, plain text, an EPUB, or a PDF, copies it
into a `ShareInbox` inside the app group, and opens the host app on a hand-off
URL to finish the import. Both targets are members of the app group
`group.com.t2s.reader` and the library lives in that group's container, so **the app will not open its library
without the `application-groups` entitlement**. `scripts/build-app.sh` signs
ad hoc for exactly this reason (unsigned only under `CI`); an unsigned build
shows "The library could not be opened."

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
key. The key goes to the Keychain and nowhere else; the non-secret
configuration (endpoint, model, voice, rate) is all that the settings store
keeps, and only the endpoint/model/voice/format fingerprint enters the render
key, so changing the rate limit does not invalidate cached audio. "Remove key"
deletes it from the device. Leave the section empty and the app never talks to
anything but the phone.

### Reader, speed picker, and sleep timer

Tap a Queue title, a chapter in a book, or **Read along →** in the player to
open the full-screen Reader. It follows the active word while audio plays;
scrolling pauses following until **Back to current** is tapped, and tapping a
sentence seeks to it. Use the speed control to choose 0.5x–4.0x in 0.1x
steps; rates the device cannot sustain are unavailable. The sleep timer offers
10, 20, 30, 45, or 60 minutes, plus **End of chapter**, and pauses playback
when it fires.
