# t2s_reader — Plan Series

**Spec:** `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (rev 4)

The spec covers several subsystems. Each gets its own plan that yields
working, tested software on its own. Order follows spec §9.

| # | Plan | Spec §9 steps | File | Status |
|---|---|---|---|---|
| 0 | Spikes: background compute, idle compute, runtime benchmark, word timings, memory, G2P coverage, license audit | 1–2 | `2026-09-02-plan-0-spikes.md` | written |
| 1 | Text pipeline (`T2SCore`): domain model, normalizer with span mapping, segmenter, timeline, codec, position resolution, highlight projection | 3–4 | `2026-09-02-plan-1-text-pipeline.md` | written |
| 2 | Render and playback: `SynthesisEngine`, `FakeEngine`, `RenderKey`, audio cache, `RenderPolicy` tiers, `RenderScheduler`, `AudioPlayer` (`T2SAudio`), `PlaybackCoordinator` | 5 | `2026-09-02-plan-2-render-playback.md` | written |
| 3 | Persistence and ingest: SwiftData store (`T2SStore`), Readium adapter for EPUB and PDF (`T2SReadium`), article-to-EPUB writer | 3 (Readium part), spec §5 | `2026-09-02-plan-3-persistence-ingest.md` | written |
| 4 | App UI: design tokens, pager, Queue, Collection, Player sheet, Reader page with decorations and auto-scroll, speed, sleep timer, Preferences | 6, 8, part of 9 | — | after Plans 2 and 3 |
| 5 | Kokoro engine, Share Extension and Readability import, Now Playing, pronunciation dictionary UI, BYO-key HTTP engine, `BGProcessingTask` wiring | 7, 9 | — | after Plan 4 and Plan 0 |
| 6 | CloudKit sync behind `SyncProvider`, Live Activity, App Intents, Spotlight | 10–11 | — | after Plan 5 |

**Dependencies.** Plans 0 and 1 are independent; run them in parallel.
Plan 2 consumes Plan 1's types. The §7.2 spike result changes *when* the
scheduler may run, not its code, so Plan 2 need not wait for Plan 0.
Plan 5 is the first plan that needs a real engine and therefore the
runtime decision from Plan 0.

**Repository layout the plans converge on.**

```
Package.swift                 SPM package "T2S": T2SCore, T2SAudio, T2SStore, T2SLibrary
Packages/T2SReadium/          iOS-only package wrapping Readium (EPUB reading, Locator mapping)
Sources/<Target>/             library sources
Tests/<Target>Tests/          Swift Testing suites; T2SCore runs with `swift test` on macOS
App/                          Xcode project for the iOS app and extensions (Plan 4)
spikes/                       throwaway harnesses (Plan 0); never imported by shipping code
scripts/check-licenses.sh     copyleft guard, run in CI from Plan 1 Task 1
spikes/findings/      spike findings, one file per spike
```
