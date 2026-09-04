# Bookmarks list, app icon, and VoiceOver rows — design

**Date:** 2026-09-04 (written overnight, without the owner; every choice below that the owner
might have made differently is listed under "Decisions taken on the owner's behalf").
**Parent spec:** `2026-09-01-t2s-reader-design.md` (rev 9) — §2.2 "Should have: Bookmarks and
highlights", §2.4 visual direction, §2.4.5 screens.
**Motivation:** the owner's standing instruction is to improve the UI or the user experience when
nothing else is queued. A gap analysis of the parent spec against the app (2026-09-04) found
bookmarks half-built (the Player and Reader can *create* one; nothing can show, jump to, or
delete one), no app icon (HANDOFF known issue 10, blocking TestFlight), and VoiceOver reading the
Queue and Collection rows as a scatter of fragments.

## 1. Bookmarks

### 1.1 What exists
`Bookmark` (id, documentID, `Position`, note, createdAt) in `T2SCore`; `LibraryStore` can list,
add and delete them; `PlayerModel.addBookmark()` saves one at the playhead; the Player sheet's
bookmark button and the Reader overflow's "Bookmark" item call it. Nothing reads them back.

### 1.2 What this adds
A **bookmark list** for a document, reachable from three places, all showing the same rows:

- **Book sheet** (Collection → cover): a "Bookmarks" section under "Chapters", shown only when
  the document has at least one bookmark. Rows are inline, in the sheet's own style.
- **Player sheet** overflow menu: a "Bookmarks" item opening a **Bookmarks sheet** for the
  current document (`.medium`/`.large` detents like Details).
- **Reader page** overflow menu: the same "Bookmarks" item and sheet.

The existing add affordances stay exactly as they are.

### 1.3 A row
Three things a reader needs to recognise a bookmark: **where** (chapter title, meta style),
**what** (a snippet of the text at the bookmark, row-title style, two lines), **when in the
audio** (clock time at 1x, monospaced, right-aligned). Newest first. Tap → the document loads if
it is not current, the playhead seeks to the bookmark's position, playback starts; from the
Book sheet the sheet closes and the Reader opens, matching what a chapter tap does there.
Delete: swipe-to-delete in the sheet (the Queue's `List` + `swipeActions` pattern) and a native
context menu "Delete bookmark" everywhere. No confirmation (a bookmark is cheap to recreate).

Empty state (sheet only): "No bookmarks yet. Tap the bookmark button while listening to save
your place."

### 1.4 Resolving a bookmark for display and for the jump
`PositionResolver.resolve(position, in: timeline)` already turns a saved `Position` into a
`Playhead` and never fails (spec §6: falls back to the chapter start). The list model resolves
each bookmark against `Library.timelineForPlayback` to derive the chapter title, the snippet and
the time; the jump re-resolves against the coordinator's timeline after loading, so a re-derived
timeline can never be given a stale utterance index.

The snippet is the utterance's source text from the bookmark's character offset, at most 90
UTF-16 units, cut at the last word boundary before the limit, with an ellipsis when cut.

### 1.5 Not in scope
Notes on bookmarks (the model field exists; no UI), highlights, sync (Plan 7), bookmarks in the
Queue context menu (spec §2.4.5 fixes that menu's items), a bookmark count badge.

## 2. App icon

A single 1024×1024 icon in a new asset catalog, drawn by a committed, deterministic Swift script
so the design lives in code and can be tuned without a design tool:

- background: the accent, `#FF7A1A` (spec §2.4.2), flat — iOS masks the corners;
- three white rounded bars, left-aligned, widths 560 / 440 / 320 at 72 tall (a ragged text
  block), and a white play triangle to their lower right. Text becoming speech, in the app's
  one accent colour.

Both app targets get it through the shared xcodegen template (`ASSETCATALOG_COMPILER_APPICON_NAME`).
No dark/tinted variants (iOS 18 renders the same icon in both). The Share extension keeps none.

## 3. VoiceOver on the rows

The spec's visual direction says nothing about accessibility; this section applies the platform
norm that a row is one utterance, not five.

- **Queue row:** the meta line ("Article · 2 days ago · Chapter 1 of 3 · rendered") becomes one
  combined element; the rendered check gets the label "Fully rendered"; the title button gets the
  hint "Opens the reader". The pills and the More menu already carry labels.
- **Collection cell:** one element labelled "<title>, <n> percent read" with the hint "Opens the
  book"; the artwork is decorative and hidden from VoiceOver everywhere it appears.
- **Bookmark row:** one element, "<snippet>, <chapter>, at <time>", hint "Plays from this
  bookmark", with a custom "Delete bookmark" action.
- **Mini-player:** audited; any control without a label gets one.

## 4. Testing
- `BookmarkListModel` and the snippet rule are unit-tested in the root package with the existing
  fixtures (`AppFixtures`, `FakeReader`, `FakeEngine`), including jump and delete.
- The icon script's output is byte-identical across two runs; the built simulator app carries
  `Assets.car` and `CFBundleIconName`.
- The app builds for the simulator (`scripts/build-app.sh`) and the device (`build-device.sh`).
- VoiceOver labels are read in review; a VoiceOver pass on hardware is added to HANDOFF's manual
  matrix as pending.

## 5. Decisions taken on the owner's behalf
1. Bookmarks live in the Book sheet and behind the Player/Reader overflow, not in the Queue
   context menu — the spec enumerates that menu.
2. Newest first; snippet ≤ 90 UTF-16 units at a word boundary; no delete confirmation.
3. The icon is a generated placeholder with a stated geometry; the owner replaces the script or
   the PNG at will.
4. Accessibility changes are limited to the rows named above.
5. The branch is stacked on `plan-6-coreml-engine` (the Mac lacks the disk for a second app
   build tree); it merges after Plan 6.
