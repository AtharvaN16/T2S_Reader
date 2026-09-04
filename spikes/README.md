# Spikes

Throwaway harnesses for spec §7. Nothing under `spikes/` is imported by shipping code.

## SpikeHarness (iOS)

Generated Xcode project; `project.yml` is the source of truth.

```bash
brew install xcodegen                      # once
cd spikes/SpikeHarness
xcodegen generate
open SpikeHarness.xcodeproj                # set your team under Signing & Capabilities, then run on a device
```

The app does not run in the simulator: MLX needs a real GPU.

### Running a protocol from the command line (no taps)

Set the team once in Xcode (Signing & Capabilities on the SpikeHarness target) so the
`com.t2s.spike.harness` profile exists; `-allowProvisioningUpdates` cannot log in from a shell.
Then, with the phone on USB and **unlocked** (launches are refused while locked):

```bash
cd spikes/SpikeHarness
xcodebuild build -project SpikeHarness.xcodeproj -scheme SpikeHarness -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath .build/dd \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=<team id> ENABLE_DEBUG_DYLIB=NO
APP=.build/dd/Build/Products/Release-iphoneos/SpikeHarness.app
xcrun devicectl device install app --device <id> "$APP"
xcrun devicectl device process launch --device <id> --terminate-existing \
  -e '{"SPIKE_AUTORUN_SECONDS":"300","SPIKE_AUTORUN_RATE":"0"}' com.t2s.spike.harness
# … wait SECONDS + ~60 s …
xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  --domain-identifier com.t2s.spike.harness --source Documents --destination <dir>
python3 ../analyze.py <dir>/Documents/spike-*.csv
python3 ../timing_check.py <dir>/Documents/spike-*.csv <dir>/Documents
```

`SPIKE_AUTORUN_SECONDS` starts the bench on launch and stops it on time; `SPIKE_AUTORUN_RATE` is
`0` (flat out), `1`, or `3`. The idle timer is off while a bench runs. The first three sentences
are also written as `sentence-N.wav` next to the CSV for the §7.4 listening check.

Protocol runs per spec section, all on a device that passes §7.3 (A14 or newer — see the
runtime-benchmark findings):
- **§7.3/§7.5** — `SPIKE_AUTORUN_SECONDS=300`, rate `0`, screen on. Then `SPIKE_AUTORUN_SECONDS=1200`,
  rate `3`, for thermals.
- **§7.4** — the three WAVs from any run; open in Audacity with the `timing` rows from the CSV.
- **§7.2** — add `"SPIKE_BACKGROUND_AUDIO":"1"` to the launch environment, `SPIKE_AUTORUN_SECONDS=900`,
  then lock the screen for the 15 minutes. Repeat once with Low Power Mode on.
- **§7.7** — open the app, tap "Schedule prepare task", plug in overnight; from Xcode you can force it
  with `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.t2s.spike.prepare"]`.
  Look for `bg.begin` / `bg.expired` rows in the morning's CSV.

Gotchas seen on 2026-09-03:
- A Debug `xcodebuild build` produces Xcode's debug-dylib layout: package frameworks stay in
  DerivedData and the installed app aborts at launch with `Library not loaded:
  @rpath/KokoroSwift.framework`. Build Release with `ENABLE_DEBUG_DYLIB=NO` for `devicectl` installs.
- Even the Release build embeds the transitive package frameworks but not `KokoroSwift.framework`
  itself (`otool -L SpikeHarness.app/SpikeHarness` shows the `@rpath` reference; `Frameworks/`
  lacks it). Copy `Release-iphoneos/PackageFrameworks/KokoroSwift.framework` into
  `SpikeHarness.app/Frameworks/`, `codesign --force --sign <identity>` the framework, then re-sign
  the app with `--preserve-metadata=entitlements,flags` and `codesign --verify --deep --strict`.
- A free personal team may have only three of its apps on a device, and an app with an extension
  counts twice. `MIFreeProfileValidatedAppTracker … ApplicationVerificationFailed` means remove one.
- `xcodebuild -destination id=…` wants the UDID (`00008030-…`), `devicectl` the CoreDevice UUID.

### Core ML arm (Plan 0 Task 8, §7.3 addendum)

A second engine beside the MLX one, for the question the A13 raised: kokoro-ios/MLX traps in Metal's
steel GEMM kernels on Apple GPU family 6, so can *any* Kokoro runtime drive the owner's iPhone 11 Pro?
The runtime is `mattmireles/kokoro-coreml`'s low-level `KokoroPipeline` package (Apache-2.0, iOS 16+,
no dependencies): Kokoro token IDs in, PCM plus per-input-token duration frames out, four fp16 Core ML
stages plus Swift/Accelerate DSP. `CoreMLBench.swift` does the front half itself (MisakiSwift 1.0.6 →
Kokoro's 178-symbol vocab → token IDs), so both arms phonemize identically.

```bash
scripts/fetch-kokoro-coreml.sh          # ~350 MB of models + the pinned source clone; idempotent
cd spikes/SpikeHarness && xcodegen generate
```

The script must run **before** `xcodegen generate`: it stages `Resources/CoreML/` (whose `.mlpackage`
directories Xcode compiles to `.mlmodelc` at the bundle root) and clones the package into
`.deps/kokoro-coreml` — the repo root has no `Package.swift`, the package is its `swift/` subdirectory,
and SwiftPM cannot consume a subdirectory by URL. Both directories are git-ignored.

Launch environment:

| Variable | Values | Meaning |
|---|---|---|
| `SPIKE_ENGINE` | `mlx` (default), `coreml`, `mlxcpu` | which runtime the run measures |
| `SPIKE_COREML_POLICY` | `default`, `cpuOnly` (case-insensitive) | per-stage Core ML compute units, `coreml` only |
| `SPIKE_COREML_BUCKETS` | `7,15` (default), or a subset | which decoder/f0ntrain buckets are vended to `selectBucket` |
| `SPIKE_COREML_DURATION_TOKENS` | `128,256` (default), or a subset | which duration models are offered to `selectDurationChoice` |

An unrecognised policy logs a `policy.unknown` row and falls back to `default`; an unparseable
bucket or token list logs `config.unknown`. Neither is silent, because a run mislabelled in the CSV
is worse than a run that fails.

`default` is the upstream SDK's shipped iPhone policy (`KokoroComputePolicy.gistDefault`): duration on
the CPU — the padded duration graph can spend *minutes* in MPSGraph specialization otherwise —
f0ntrain and generator on CPU+GPU, decoder-pre on CPU+ANE. `cpuOnly` puts every stage on the CPU.
`mlxcpu` is the control: the MLX arm with `MLX.Device` forced to `.cpu`, behind a 120-second
per-sentence watchdog that logs `sentence.timeout` and stops the bench.

The A13 run (phone unlocked, on USB):

```bash
xcrun devicectl device process launch --device <id> --terminate-existing \
  -e '{"SPIKE_ENGINE":"coreml","SPIKE_COREML_POLICY":"default","SPIKE_AUTORUN_SECONDS":"300","SPIKE_AUTORUN_RATE":"0"}' \
  com.t2s.spike.harness
```

Extra CSV columns on the Core ML arm's `sentence` rows: `engine`, `policy`, `bucket`, `tokens`,
`frames`, `g2p`, `pipeline` (the pipeline's own token-IDs-in-to-PCM-out boundary, which is what the
upstream iPhone 12 Pro / A17 Pro numbers measure), `rtfPipeline`, and `st_*` per stage
(`duration, align, matrix, f0ntrain, pad, decoderPre, hnsf, generator, trim`). `synth`/`rtf` stay
G2P-inclusive so they compare with the MLX arm directly. `timing` rows are per Misaki **word**, folded
from `tokenDurationFrames`; one `frames.check` row per WAV sentence records
`frames × samplesPerDurationFrame` against the real sample count.

Read that `frames.check` row for what it is: the executor trims to
`round(frames × 2 / f0FrameRate × sampleRate)` and `samplesPerDurationFrame` is the same formula, so
the two columns agree by construction whenever the utterance fits its bucket — which is the one
thing the row does prove (`trimLen = min(waveform.count, targetLen)`, so a mismatch means the
bucket clamped the speech). The 25 ms-vs-12.5 ms question is settled off-device instead: an energy
envelope over the WAV (12.5 ms would leave the second half of the file silent; it is not) plus
`python3 spikes/timing_check.py <csv> <dir>` on the per-word rows, plus listening.

**Bucket staging is a measurement variable, not a packaging detail.** The pipeline pads every
utterance out to the geometry of the smallest staged bucket that can hold it, and `decoderPre` +
the generator are ~80% of a warm call, so staging only the 15-second bucket makes a 6.5-second
sentence pay 15 seconds of decoder work — it inflates RTF as much as it inflates footprint. The
fetch script therefore stages the 7- and 15-second buckets and the `t128`/`t256` duration models,
and the harness vends all of them so the upstream `selectBucket` /
`KokoroPipeline.selectDurationChoice` do the picking. Each `sentence` row records the `bucket` and
`durationModel` that were actually used. Narrow the set with `SPIKE_COREML_BUCKETS=15` to reproduce
a single-geometry run. Sentences longer than 15 s of audio or 256 tokens are out of range (the
corpus is well inside both).

### Model files (not committed)

Two files go in `spikes/SpikeHarness/Resources/` and are gitignored:

| File | Source | Size | SHA-256 |
|---|---|---|---|
| `kokoro-v1_0.safetensors` | `https://media.githubusercontent.com/media/mlalma/KokoroTestApp/main/Resources/kokoro-v1_0.safetensors` | 327,115,152 bytes | `4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8` |
| `voices.npz` | `https://raw.githubusercontent.com/mlalma/KokoroTestApp/main/Resources/voices.npz` | 14,629,684 bytes | `56dbfa2f2970af2e395397020393d368c5f441d09b3de4e9b77f6222e790f10f` (28 voice styles) |

```bash
cd spikes/SpikeHarness/Resources
curl -sSL -o kokoro-v1_0.safetensors https://media.githubusercontent.com/media/mlalma/KokoroTestApp/main/Resources/kokoro-v1_0.safetensors
curl -sSL -o voices.npz https://raw.githubusercontent.com/mlalma/KokoroTestApp/main/Resources/voices.npz
shasum -a 256 kokoro-v1_0.safetensors     # must match the table
```

The app needs the same two files under `App/Resources/Kokoro`; since Plan 5 Task 5,
`scripts/fetch-kokoro-model.sh` installs both there (reusing these copies when they are already
present) and verifies both checksums.

Weights are Kokoro-82M (Apache 2.0) as packaged by KokoroTestApp (Apache 2.0).

### Dependencies

| Package | Pin | License |
|---|---|---|
| kokoro-ios (`KokoroSwift`) | 1.0.11 (`4d6d1d8ff8cd`) | MIT |
| MLXUtilsLibrary | 0.0.6 | Apache-2.0 (vendored as `Packages/MLXUtilsLibrary` from Plan 5 Task 5) |
| mlx-swift (transitive) | 0.30.2 | MIT |
| MisakiSwift (transitive) | 1.0.6 | Apache 2.0 — the spec calls it MIT; correct that in the §7.1 audit |

### Reading the log

Each run writes `spike-<epoch>.csv` to the app's Documents folder (Files → On My iPhone → Spike Harness).
Columns: `ts,event,k,v`. Events: `app.launch`, `model.loaded`, `bench.start`, `sentence`, `timing`, `bench.stop`.
Analyse with `python3 spikes/analyze.py spike-*.csv` (added in Plan 0 Task 4). It splits the file
by run — one CSV can hold several `bench.start`s, and mixing engines or policies produces a median
of nothing — discards the first two calls of each run (`--warm-skip N` to change it; Core ML's
first prediction builds the compute plan), and reports warm median and p90 RTF, the footprint slope
in MB per sentence over each half of the run, the elapsed seconds to each thermal state measured
from `bench.start`, the battery delta and the median stage split. `--per-minute` adds the old
per-minute median view.
