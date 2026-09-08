# Plan 12 — One playback UI: the Reader

_2026-09-08. Branch `plan-12-one-playback-ui` off `dev` @ b951d86 (after the second session's Plan 11, voice quality 2), in the main checkout. From the owner's
report after Plan 10: "If I play a document from the queue page, there is no way to see the text … There
should not be 2 separate UIs for playback. Keep only one, with the text read-along." Approved design in
conversation ("ok"). Ledger: `.superpowers/sdd/2026-09-08-plan-12-one-playback-ui/progress.md` (git-ignored)._

## Why

Plan 10 made the Reader page the text read-along, but the Queue's Play pill and the mini-player still opened
the Player sheet (audio chrome from Plan 4a), so playback started without any text in sight; only a row title
or a chapter in the book sheet reached the Reader. The Reader already has everything the sheet had (scrubber
with the render frontier, transport, sleep timer, speed, chapters, bookmarks, voice, details), so the sheet is
retired and every way of starting playback opens the Reader.

## Tasks

| # | Task | Owns | Verification |
|---|---|---|---|
| 1 | **Every playback entry opens the Reader; the Player sheet goes.** Queue row Play → the Reader (Pause on the playing row pauses in place); mini-player tap → the Reader on the shown item; book-sheet Play → the Reader; `PlayerSheet`, `TickScrubber` and `ControlPill` deleted; comments that named them updated. | `App/T2SReader/Root/{RootPager,MiniPlayer}.swift`, `App/T2SReader/Queue/QueueRow.swift`, `App/T2SReader/Collection/BookSheet.swift`, `App/T2SReader/Reader/ThinScrubber.swift` (comment), deletions under `App/T2SReader/Player/` | `swift test` (regression); `scripts/build-app.sh` |
| 2 | **Docs.** Main spec rev 13 (§2.3 one playback UI; §2.4.4 mini-player tap; §2.4.5 Queue Play, book sheet Play, the Player sheet paragraph retired, the Reader's entry points; changelog); HANDOFF (a Plan 12 section, the retired "Player sheet styling" deferral, the App layout line, the phone checklist); roadmap row. | `docs/` | review |

Sequential; one review per task; a short whole-branch look before `dev` fast-forwards.

## Decisions taken without the owner (each in the ledger, with its cost if wrong)

- **Play in the Queue navigates to the Reader** rather than playing in place — the owner's own expectation
  when they tapped it. Pause on the playing row stays in place. Cost if wrong: two lines in `QueueRow`.
- **The Reader loads and plays a non-current document itself** (`ReaderPage.open()` already does), so the
  entry points only open it; a current-but-paused document is resumed before opening. Cost: none.
- **The shared sheets stay under `App/T2SReader/Player/`** (chapter list, sleep timer, speed picker, voice
  change) — moving them is churn with no behaviour. Cost: a folder name that reads oddly.

## Deferred

- The Reader shows no artwork or source/age line; the Details sheet has them. Add to the page only if missed.
- `PlayerModel` may keep a property or two that only the sheet read; a later tidy.
