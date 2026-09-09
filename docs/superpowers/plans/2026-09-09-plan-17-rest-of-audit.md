# Plan 17 — The rest of the audit

_2026-09-09. Branch `plan-17-rest-of-audit` off `origin/dev` @ 7dc7498, worktree `.worktrees/plan-17-rest-of-audit`.
Written and executed by the controller directly; one whole-branch review before the merge. Other sessions
edit this repository: `App/T2SReader/Root`, `Player`, `Collection`, `Queue`, `Reader`, `Preferences` are not
touched; `App/T2SReader/System` is, minimally._

**Goal:** Take what remains of [the performance audit](../specs/2026-09-08-performance-audit.md) that this
Mac can build: re-derivation without the reader (#6), the app-side timer churn (#7), the launch sweep and
concurrent stage loads (#10), and the 3 s and 10 s buckets (#9). Record what is not taken and why.

## Tasks

| # | Task | Owns | Verification |
|---|---|---|---|
| 1 | **Re-derivation never touches the reader again.** Import retains the reader's chapters (`ChapterInput`, LZFSE JSON in the document directory); `reprocess` reads them, falling back to the reader once for a document imported before this build; the old audio's removal moves to a background task that decodes the old blobs after the replacement, so the load path pays for neither; Bookmarks and Prepare read `currentTimeline` and never re-derive. | `Sources/T2SCore/Segment/SourceBlock.swift`, `Sources/T2SLibrary/*`, `Sources/T2SStore/LibraryStore.swift`, `Sources/T2SApp/Bookmarks/BookmarkListModel.swift`, `Sources/T2SApp/Playback/PrepareRunner.swift`, tests | `swift test` |
| 2 | **The timer work coalesces.** `highlight` is written only when the word changes; `PlayerModel` caches `isTotalApproximate`, the chapter entries' time axis and `chapterIndex` against `timelineRevision`; `ChapterEntry.entries` is one pass; the ticker idles at 1 Hz as its comment says; `NowPlayingController.clear()` writes the centre once, not four times a second. | `Sources/T2SAudio/PlaybackCoordinator.swift`, `Sources/T2SApp/Player/PlayerModel.swift`, `App/T2SReader/System/PlaybackTicker.swift`, `App/T2SReader/System/NowPlayingController.swift`, tests | `swift test`; the App files by reading (no simulator build fits the disk) |
| 3 | **Launch.** The old-codec sweep runs on the store's actor at first use, not in `init` on the main thread; the eight (now fourteen) Core ML stages load concurrently under a shared task. | `Sources/T2SCore/Render/FileAudioStore.swift`, `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLModels.swift`, `KokoroCoreMLEngine.swift`, tests | `swift test`; `xcodebuild build` of T2SKokoro |
| 4 | **The 3 s and 10 s buckets.** `scripts/fetch-kokoro-coreml.sh` pins their files (LFS oids at the pinned revision; every weight file is byte-identical to a bucket the manifest covers and is cross-checked); `KokoroCoreMLResources.buckets = [3, 7, 10, 15]`; the resources test. | `scripts/fetch-kokoro-coreml.sh`, `Packages/T2SKokoro/Sources/T2SKokoro/CoreML/KokoroCoreMLResources.swift`, its tests | the script against the main checkout's staging; `xcodebuild test` of the non-model T2SKokoro suites |
| 5 | **Docs.** HANDOFF, the audit's progress note and its "not taken" list, spec rev 18. | `docs/` | review |

## Decisions taken without the owner
- Per-chapter *lazy* re-derivation (audit §5.1 b) is not taken: the coordinator's timeline is indexed
  across the whole document, so a half-re-derived book would shift every later index under it. With the
  reader out of the path, the GC off it and the normalizer folded, a full re-derivation is the segmenter
  alone. Cost: a big book still re-derives whole, in one to three seconds, on its first open after a bump.
- The stale audio is still removed — in the background, after the replacement — rather than left to age
  out: the Storage screen reports the cache, and a listener who just updated should not see it grow.
- Both new buckets are staged. Every `weight.bin` is byte-identical across buckets, so the download is
  small, but the bundle duplicates them: about +250 MB on the phone. The owner can drop the 10 s bucket
  by removing it from `KokoroCoreMLResources.buckets` and the script.
- Not taken, with the reason in the audit's progress note: the OOV phoneme cache (MisakiSwift's fallback
  is private to `EnglishG2P`; it needs an upstream hook), the G2P/generator overlap and the AAC encode off
  the render path (the audit asks for the §8 measurement first), the MLX items (#14: nothing runs at
  launch; the weights are not staged; the BART port is its own project), `RootPager`'s second
  `update()` per tick (another session's file).
