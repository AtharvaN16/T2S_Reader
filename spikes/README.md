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
| MLXUtilsLibrary | 0.0.6 | see repo |
| mlx-swift (transitive) | 0.30.2 | MIT |
| MisakiSwift (transitive) | 1.0.6 | Apache 2.0 — the spec calls it MIT; correct that in the §7.1 audit |

### Reading the log

Each run writes `spike-<epoch>.csv` to the app's Documents folder (Files → On My iPhone → Spike Harness).
Columns: `ts,event,k,v`. Events: `app.launch`, `model.loaded`, `bench.start`, `sentence`, `timing`, `bench.stop`.
Analyse with `python3 spikes/analyze.py spike-*.csv` (added in Plan 0 Task 4).
