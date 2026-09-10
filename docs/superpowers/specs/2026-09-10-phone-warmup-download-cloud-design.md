# Phone warm-up, the model download, the crash, and the cloud route — design

_2026-09-10. Written from the iPhone 17 Pro's own crash reports (pulled with `devicectl`) and the code on
`dev` @ d849036. One branch, `phone-warmup-download-cloud`._

## 1. What the phone said

Two reports under `T2SReaderKokoro` in the 17 Pro's system crash logs:

- **15:14, `cpu_resource_fatal`** (ten minutes after the 15:04 build): "48 seconds cpu time over 48
  seconds (100% cpu average), exceeding limit of 80% cpu over 60 seconds. Action taken: Process
  killed." 13 of 14 samples *Non-Frontmost App*, on battery. Symbolicated with the iOS 26.6.1
  device-support symbols, the heaviest stack is `MLModel.load` → `MLE5Engine` →
  `MLE5ProgramLibraryOnDeviceAOTCompilationImpl createProgramLibraryHandleWithRespecialization` →
  `E5RT::E5CompilerImpl::Compile` → `MILCompilerForBnns` → `bnns::GraphCompile`. That is the warm-up
  building Core ML compute plans, after the phone locked or the app was switched away. iOS kills any
  app that is not frontmost and holds 80% of a core for a minute; the app stays alive in the
  background because `AudioPlayer` starts its `AVAudioEngine` at launch, so a locked phone does not
  suspend it. On the 11 Pro this never fired because the owner sat through the first warm-up.
- **03:33, `EXC_BREAKPOINT`** in `closure #1 in static PrepareTask.register()` on the queue
  `com.apple.BGTaskScheduler (com.t2s.reader.prepare)`, 0.4 s after a launch: the launch handler is
  formed inside the `@MainActor` enum, `BGTaskScheduler`'s parameter is not `@Sendable`, so Swift 6
  infers main-actor isolation and traps when the scheduler calls it on its own queue. Every overnight
  Prepare launch dies this way, on any phone.

## 2. Decisions

1. **Heavy Core ML work happens in the foreground only.** A `ForegroundGate` (T2SCore) says whether
   the scene is active; the app sets it from `scenePhase`, and a process launched for a background
   task never opens it. The stage loader waits on it before starting each stage; the model installer
   waits on it before each compile; the warm-up itself starts on the first active scene.
2. **A silent app can suspend.** `AudioPlayer` starts its engine on `play()` and pauses it on
   `pause()`/`reset()`; nothing keeps the process alive in the background but real playback.
3. **Background renders are paced.** `CPUBudget` (T2SCore) measures the process's CPU time and, while
   the app is not frontmost, holds the next render until the trailing 60 s window is under 36 s of
   CPU (60%) — the fatal line is 48 s. Play-ahead at 1–2x never touches it; Prepare in the
   background slows down instead of dying; the log says when it engages.
4. **Prepare never compiles in the background.** A background Prepare pass runs only when a foreground
   warm-up has finished on this install (`KokoroWarmUpRecord`); the launch prime waits for the
   warm-up to settle rather than running after five minutes regardless.
5. **The launch handler is `@Sendable`.**
6. **The model is not in the app.** `KokoroCoreMLInstall` (T2SKokoro) downloads the 72 files of the
   pinned Hugging Face revision (the same pins and SHA-256s as `scripts/fetch-kokoro-coreml.sh`) into
   `Application Support/KokoroCoreML/<revision>/`, over Wi-Fi only, resumable file by file; compiles
   each `.mlpackage` with `MLModel.compileModel` (foreground only) into a compiled layout the
   resources locator reads as precompiled; deletes the sources. `App/project.yml` no longer bundles
   `Resources/KokoroCoreML`; the bundle path stays as a fallback. The install is ~60 MB instead of
   676 MB, and the models sit at a path that survives reinstalls — if Core ML's plan cache keys on the
   path, reinstalls stop paying the first-launch compile.
7. **Readiness after the first bucket.** The engine reports ready once the two duration models and the
   3 s bucket's three stages are loaded; the 7, 10 and 15 s buckets follow under the same gate. The
   executor sees only loaded buckets; a piece rendered before its bucket arrives is split by the
   existing overflow rule. Progress stays "stages loaded of 14".
8. **Measurement, not guesses, for the 17 Pro.** Every stage load and every utterance logs its
   timings (`com.t2s.reader`, category `kokoro.timing`); a user default `kokoro.computeUnits`
   (`cpu`, `cpuAndNeuralEngine`, `cpuAndGPU`, `all`) picks the compute units at launch for the
   experiment the audit §3.7 asks for; a macOS probe renders one passage under each and prints the
   stage split. The shipped default stays CPU (Harsh, 2026-09-10): on this Mac CPU+GPU is 8% slower
   at steady state, 30 s slower to load and 26 s slower on its first render, and the Neural Engine
   policies spend minutes per generator stage failing to compile (`ANECCompile() FAILED`). A GPU
   default for Apple GPU family 7 and up is a ten-line change once the phone shows it winning.
9. **The cloud route speaks OpenAI's real contract.** Request `{model, input, voice, response_format:
   "pcm"}`; the response is raw 16-bit little-endian mono PCM at 24 kHz (`audio/pcm`) or — from a
   proxy — the JSON `{audio, sample_rate, word_timings}` contract the code already had.
10. **Per-Mac identity.** Bundle id, app group and team come from `Local.xcconfig` (defaults in
    `project.yml`; `AppPaths` reads the group from Info.plist), so a second developer's team never
    has to edit tracked files.

## 3. Not done here

The phone run itself (install, listen, read the timing log) and the MLX measurement: the protocol is
in `docs/HANDOFF.md`. Whether Core ML's plan cache survives a reinstall is answered by the first
launch's `kokoro.timing` lines after this change.
