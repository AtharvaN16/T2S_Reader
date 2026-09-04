# t2s_reader — Plan Series

**Spec:** `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (rev 8)

The spec covers several subsystems. Each gets its own plan that yields
working, tested software on its own. Order follows spec §9.

| # | Plan | Spec §9 steps | File | Status |
|---|---|---|---|---|
| 0 | Spikes: background compute, idle compute, runtime benchmark, word timings, memory, G2P coverage, license audit | 1–2 | `2026-09-02-plan-0-spikes.md` | in progress — §7.1 done; §7.3 MLX floor (A14+) found; Task 8 done: Core ML CPU-only passes on the A13 (RTF 0.18, 119 MB) and becomes the baseline runtime; §7.2/§7.7 and the MLX numbers on an A14+ phone still pending |
| 1 | Text pipeline (`T2SCore`): domain model, normalizer with span mapping, segmenter, timeline, codec, position resolution, highlight projection | 3–4 | `2026-09-02-plan-1-text-pipeline.md` | done |
| 2 | Render and playback: `SynthesisEngine`, `FakeEngine`, `RenderKey`, audio cache, `RenderPolicy` tiers, `RenderScheduler`, `AudioPlayer` (`T2SAudio`), `PlaybackCoordinator` | 5 | `2026-09-02-plan-2-render-playback.md` | done |
| 3 | Persistence and ingest: SwiftData store (`T2SStore`), Readium adapter for EPUB and PDF (`T2SReadium`), article-to-EPUB writer | 3 (Readium part), spec §5 | `2026-09-02-plan-3-persistence-ingest.md` | done |
| 4a | App shell, import, player: T2SApp models, design tokens, pager, Queue, Collection, mini-player, player sheet, Add sheet (link/file/text), system-voice fallback engine | 6, 8 | `2026-09-02-plan-4a-app-shell.md` | done (merged to `dev` 2026-09-02) |
| 4b | Reader page with decorations and auto-scroll, speed picker, sleep timer, Preferences, storage manager | 6, 8, 9 (part) | `2026-09-02-plan-4b-reader-controls.md` | done except Task 9: hardware read-along pass, EPUB/PDF fixture, and UI test |
| 5 | Kokoro engine, Share Extension and Readability import, Now Playing, pronunciation dictionary UI, BYO-key HTTP engine, `BGProcessingTask` wiring | 7, 9 | `2026-09-03-plan-5-engine-share-nowplaying.md` | implemented; Kokoro engine, probe, route, catalog and fallback landed on A14+ builds; runtime constants and word timings gated on the iPhone 17 Pro findings (§7.2–§7.5, §7.7); hardware matrix pending |
| 6 | Core ML Kokoro engine: vendored `KokoroPipeline`, `KokoroCoreMLEngine` with word timings, multi-engine routing (Core ML default, MLX beside it), Kokoro Heart as the default voice, device wiring and the first listen on the iPhone 11 Pro | 7, 9 | `2026-09-04-plan-6-coreml-kokoro-engine.md` | implemented 2026-09-04 (Tasks 1–6, each reviewed) on branch `plan-6-coreml-engine`; the first listen on the iPhone 11 Pro is pending, then merge |
| 7 | CloudKit sync behind `SyncProvider`, Live Activity, App Intents, Spotlight | 10–11 | — | after Plan 6 |

**Dependencies.** Plans 0 and 1 are independent; run them in parallel.
Plan 2 consumes Plan 1's types. The §7.2 spike result changes *when* the
scheduler may run, not its code, so Plan 2 need not wait for Plan 0.
Plan 5 is the first plan that needs a real engine and therefore the
runtime decision from Plan 0.

**Repository layout the plans converge on.**

```
Package.swift                 SPM package "T2S": T2SCore, T2SAudio, T2SStore, T2SLibrary
Packages/T2SReadium/          iOS-only package wrapping Readium (EPUB reading, Locator mapping)
Packages/T2SKokoro/           the Kokoro engines: Core ML, CPU-only and the default (Plan 6), and
                              MLX, A14+ (Plan 5 Task 5); tested with xcodebuild on macOS, cannot
                              link for the iOS simulator
Packages/KokoroPipeline/      vendored mattmireles/kokoro-coreml @ 66d8cf51, the low-level Core ML
                              pipeline (Plan 6 Task 1)
Packages/MLXUtilsLibrary/     vendored 0.0.6 without ZIPFoundation, so Kokoro and Readium resolve
                              together (Plan 5 Task 5)
Sources/<Target>/             library sources
Tests/<Target>Tests/          Swift Testing suites; T2SCore runs with `swift test` on macOS
App/                          the iOS app: project.yml → two targets, T2SReader (simulator + any
                              phone, no engine) and T2SReaderKokoro (device only, the app on a
                              phone), both from one template; T2SReader/ (SwiftUI views,
                              composition root), T2SReaderShare/ (Share Extension), Resources/Fonts
                              (Inter, OFL), Resources/Kokoro/ and Resources/KokoroCoreML/ (model
                              files, git-ignored)
spikes/                       throwaway harnesses (Plan 0); never imported by shipping code
scripts/check-licenses.sh     copyleft guard, run in CI from Plan 1 Task 1
scripts/fetch-kokoro-model.sh install the MLX Kokoro weights and voices into App/Resources/Kokoro
scripts/fetch-kokoro-coreml.sh --app  stage the Core ML model files into App/Resources/KokoroCoreML
scripts/test-kokoro.sh        Packages/T2SKokoro on macOS
scripts/build-device.sh       compile proof of T2SReaderKokoro for a device
spikes/findings/      spike findings, one file per spike
```
