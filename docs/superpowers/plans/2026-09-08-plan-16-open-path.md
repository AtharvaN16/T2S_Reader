# Plan 16 — Steady streaming and the open path

_2026-09-08 (night). Branch `plan-16-open-path` off `origin/dev` @ 246065b, worktree `.worktrees/plan-16-open-path`.
Written and executed by the controller directly (the owner asked for speed after Plan 15); one whole-branch
review before the merge. Other sessions edit this repository: `App/T2SReader/Root`, `Player`, `Collection`,
`Queue`, `Reader`, `Preferences` are not touched._

**Goal:** Close the one gap Plan 15 left (a streamed head that runs dry between pieces), take the audit's
remaining open-path items (#5), fold the normalizer's regex passes (#13), and stop the harmonic source doing
work the mask throws away (#12, the part that needs no model).

**Spec:** [the performance audit](../specs/2026-09-08-performance-audit.md) §3.6, §5.3, §5.4; the design spec
§3.5, §3.6, §5 (persisted progress).

## Tasks

| # | Task | Owns | Verification |
|---|---|---|---|
| 1 | **A streamed head that runs dry pauses.** `AudioPlaying.queuedSeconds`; `tick()` pauses on "catching up" when a stream is live and the player holds nothing; the next piece resumes. | `Sources/T2SAudio/AudioPlaying.swift`, `AudioPlayer.swift`, `PlaybackCoordinator.swift`, fakes, tests | `swift test` |
| 2 | **The normalizer folds its passes.** Abbreviations: one alternation + a lookup; numbers: skipped when the text holds no digit; dictionary: one alternation per case mode. Same output for every existing test. | `Sources/T2SCore/Normalize/Rules/*`, tests | `swift test --filter "Abbreviations\|Numbers\|Pronunciation\|TextNormalizer"` |
| 3 | **The harmonic source stops at the last voiced frame.** `sineGenFromF0Frames` computes the nine sine passes over the active prefix only (the mask zeroes the rest anyway; the noise stays full length), bit-identical; `buildHar` runs beside decoder-pre in the executor and `decoderPreHnsfOverlap` is finally set. | `Packages/KokoroPipeline` (vendored; README records the patch), its tests | `swift test` in the package |
| 4 | **Opening a book hashes nothing; progress rows need no decode.** The coordinator tracks chapters changed by `.rendered`; `PlayerModel.persistRenderedChapters` writes those, not a SipHash pass over the book. Schema V2 adds `resumeElapsedSeconds`/`resumeChapterIndex` to a document row, written with every position save; `LibraryModel.refresh` reads them instead of decoding the timeline. | `Sources/T2SCore/Model/PlayheadStore.swift`, `Sources/T2SAudio/PlaybackCoordinator.swift`, `Sources/T2SStore/*`, `Sources/T2SApp/Player/PlayerModel.swift`, `Library/LibraryModel.swift`, `Library/DocumentProgress.swift`, tests | `swift test` |
| 5 | **Docs.** HANDOFF, the audit's progress note, spec §3.5/§5 and rev 17. | `docs/` | review |

## Decisions taken without the owner
- Dryness is detected on the 10 Hz tick, so up to 100 ms of silence can pass before the pause; the alternative
  (a player callback) would need a second AVFoundation path. Cost: a tenth of a second of hole before the pause.
- Schema V2 is a lightweight migration (two optional columns); rows without the new fields fall back to the
  decode they do today, so an upgrade needs no rewrite. Cost: the first refresh after the upgrade decodes once
  more per book, then never again.
- The harmonic source's noise stays full-length so the output stays bit-identical to the reference; only the
  sine passes shrink. Cost: the noise's share of the stage is untouched.
