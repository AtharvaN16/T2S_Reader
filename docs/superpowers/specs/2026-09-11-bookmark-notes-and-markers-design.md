# Bookmarks — notes, and the markers that show where they are

_2026-09-11. Approved by the owner in conversation, section by section. Covers sub-projects A and B
of the bookmarks work; sub-project C (text selection, saved words, the dictionary) is a later spec —
its one settled decision is recorded in §11. The reference throughout is ElevenReader's bookmark
flow, read off Mobbin: the note offered in the save confirmation rather than behind a menu, the time
range rather than a single stamp, and Listen / Edit note as visible actions on the row. The dots on
the scrubber and the stamps under the chapter rows are ours; ElevenReader has neither._

## 1. What this adds, and what it does not

Bookmarks already exist and already sync. What they lack is anything the reader wrote, and any sign
of where they are other than a list.

Added:

- **A note of your own** on any bookmark, written from the save confirmation or from the list, and
  synced.
- **A toast** that says a bookmark was saved, and offers the note there and then.
- **Dots on the scrubber**, while it is pressed, for the bookmarks inside the chapter under the
  finger.
- **Stamps under the chapter rows**, behind one icon in the chapter list's header — in the Reader
  and, because the view is shared, in the Book sheet.
- **Time ranges** on every bookmark row, so the length of a passage is known before it is played.

Not in this spec: export or share of bookmarks (ElevenReader's "Download"), a cross-book bookmarks
page, and everything in sub-project C. Each is an addition to what is built here, not a change to
it.

## 2. The two kinds of bookmark text

A bookmark carries two strings, and conflating them is the mistake this design exists to avoid.

- **The passage** — the utterance's source text, captured at save so the bookmark keeps its words
  after the document is re-derived and utterance indices move (owner's ask, 2026-09-09). Written by
  the app, never edited.
- **The note** — the reader's own words. Absent on most bookmarks. Edited freely.

Today only the first exists, and it is stored in a field called `note`
(`PlayerModel.addBookmark`, `Sources/T2SApp/Player/PlayerModel.swift`). That name is now wrong, and
§3 explains why it nevertheless stays.

The domain type gains the honest names:

```swift
public struct Bookmark {
    public var id: UUID
    public var documentID: UUID
    public var position: Position
    public var passageText: String?     // was `note`
    public var userNote: String?        // new
    public var createdAt: Date
}
```

## 3. Schema V4: additive, because the old meaning is already in the cloud

The tempting migration is to rename `note` to `passageText` and give the new field the good name.
It must not be done. `note` is a live CloudKit field
(`Sources/T2SSync/CloudKit/CloudKitRecordMapping.swift`), so its current meaning — the passage — is
already in the owner's iCloud account and will shortly be in Harsh's. A build that reinterpreted
`note` as the reader's writing would display, as the reader's words, text the app itself wrote on a
device still running the old build. Silent, cross-device, and not correctable afterwards.

So the stored column keeps both its name and its meaning, forever, and the new field is added beside
it:

- `LibrarySchemaV3` is frozen into `Sources/T2SStore/LibrarySchemaV3.swift`, the way V1 and V2
  already are. `Models.swift` becomes `LibrarySchemaV4`.
- `StoredBookmark` gains one property: `var userNote: String?`. Nothing else changes.
- The stage in `LibraryMigrationPlan` is lightweight — one added optional — exactly the shape of
  V2 → V3.

The ugly name is then sealed inside the store. `LibraryStore+Bookmarks.swift` already translates
rows into `T2SCore` value types (design spec §3.7.1: the persistence schema never shapes the domain
model), so it maps `row.note → passageText` and `row.userNote → userNote`, and nothing above the
store ever sees the word `note` again.

## 4. Sync: one new key, and no record rewritten

`SyncedBookmark` gains `userNote`. `CloudKitRecordMapping` keeps writing the passage to `"note"`
and adds a `"userNote"` key.

This is deliberately the boring option, and it buys two things. A build that never updates keeps
working, because it simply ignores a key it does not know. And no existing record has to be
rewritten, so there is no migration pass over the cloud and no window in which a half-migrated
account is wrong.

Editing a note is an ordinary local write: it sets `userNote`, bumps `updatedAt`, sets `isDirty`.
The existing push path and the existing last-write-wins resolution (sync spec §4) carry it with no
new machinery. A note edited on two devices between syncs resolves like everything else — the later
`updatedAt` wins, and the other is lost. For a field one person edits on their own devices this is
the right trade; per-field merging would cost more than it protects.

## 5. The save: a momentary button and a toast

The bookmark button in the Reader's tool row is today a toggle whose fill means *the sentence under
the playhead is bookmarked*. That is not what a reader reads it as. Paused, it fills and stays
filled, which looks stuck. Playing, it silently empties a few seconds later when the playhead
crosses into the next sentence, which looks like the bookmark was lost. Neither state says the one
thing that matters: it was saved.

The button becomes momentary. A tap always saves, the icon never fills, and a toast confirms it.

**The toast** is the one new component in this spec; nothing in the design system does transient
feedback. It is `Tokens.ink` filled with `Tokens.ground` text — the same pairing as
`Pill(.selected)` — so it reads as a message rather than a surface that can be touched. It carries
the chapter and the stamp, and one `Pill(.soft)` reading "Add a note". It floats above the Reader's
bottom block, clearing the chapter row, and never covers the scrubber or the transport. It lasts
about four seconds, dismisses on tap, and posts a VoiceOver announcement, so the confirmation is not
sighted-only.

**Removing** a bookmark moves entirely to the list, where swipe-to-delete and the context menu
already exist. A momentary button cannot also be an un-save without becoming a mode again.

**Saving twice on the same sentence** does not make two rows. The playhead's utterance is checked
against the loaded document's bookmarks in memory, and a match turns the toast into "Already
bookmarked" with Edit note. §9 explains why that check is now trustworthy.

**The note editor** is a sheet: the passage, the time range, a `TextEditor`, and `BarButton` for
Save — which exists for exactly this shape, "the one action of a step, as a full-width bar pinned to
a page's foot", and already rides above the keyboard. It is reached from the toast and from any
row's Edit note. Saving an empty note clears `userNote` rather than storing an empty string, so the
row falls back cleanly.

## 6. The bookmarks sheet: the reader's words first

`BookmarkRow` is rewritten. When a bookmark has a note, the note is the row's headline and the
book's passage drops to a quote beneath it; when it has none, the passage keeps the headline. The
list then reads as the reader's notebook rather than as a second copy of the book.

- A `.meta` line in `ink2`: the time range, then the chapter.
- The headline in `.rowTitle`, `ink`: `userNote` when non-empty, else `passageText`, else the
  timeline's text at the bookmark's offset. That last link is the fallback
  `BookmarkListModel` already has for bookmarks saved before passages were captured; the new link
  goes in front of it.
- When a note exists, the passage in `.meta`/`ink2` behind a 2 pt `ink3` left rule.
- `Pill("Listen", .selected)` and `Pill("Edit note", .soft)` — or `Pill("Add a note", .soft)` when
  there is no note.

The row remains tappable as well as carrying a Listen pill. Two targets for one action is usually a
fault; it is not one here, because both do the same thing and a mis-tap therefore costs nothing. The
rule this follows — and the reason the chapter list's design in §7 is what it is — is that a second
target inside a row is only acceptable when it is not a *different* action.

**Time ranges are derived, never stored.** `BookmarkEntry` gains `endSeconds`, computed from the
utterance's span through `TimeIndex` at display time, as `timeSeconds` already is. No column, no
record field, no migration — and it stays honest when a document is re-derived and durations shift.

## 7. The chapter list: one icon, stamps under the rows

`ChapterListView` gains a bookmark button beside its "Chapters" heading: a `CircleGlyph`, the 36 pt
`surface` circle the page headers' `+` and the Reader bar's circles already use. It appears only
when the document has bookmarks, and wears `bookmark.fill` while on.

Turning it on expands every chapter that has bookmarks — not one chapter at a time. The alternative
considered was a per-row count badge that opened its own row, and it was rejected for the reason
§6 names: it would have put a small target with its own behaviour inside a row that is already one
large button, which is the classic phone mis-tap. One control in the header leaves every row a
single tap target.

Each stamp is an accent dot, a `.mono` time, and one truncated line of the bookmark's text; tapping
it jumps there. The view stays free of models — it takes `bookmarksByChapter: [Int: [BookmarkEntry]]`
from its caller.

Because `ChapterListView` is shared, the **Book sheet gets the same button**, which is how bookmarks
become reachable from the Collection without a new screen. The Book sheet also keeps its existing
Bookmarks section. The two overlap, and that is accepted: the stamps answer *where in the book*, the
section answers *what I wrote*.

## 8. The scrubber: dots only while it is pressed

`ThinScrubber` takes `bookmarkFractions: [Double]` and draws a 10 pt `accent` dot per bookmark,
ringed 2.5 pt in `Tokens.ground` so it reads over both the played `ink` and the grey ticks ahead.

Two restrictions, both deliberate:

- **Only while pressed.** At rest the bar is 6 pt and carries the render frontier; dots on it would
  be noise on a bar that is already saying something.
- **Only the active chapter.** Pressed, that chapter widens to at least 45% of the bar and the rest
  shrink. Dots on a chapter rendered at 11% of the width would be a smear, so they are drawn only
  for bookmarks inside the active span, mapped through the same widened layout the scrub maths
  already computes.

The dots are a map, not a target. Making them tappable would put hit areas inside the 44 pt band the
drag gesture owns.

The cost is honest and should be stated: a dot sits on top of the render-frontier ticks underneath
it. The ring keeps the dot legible; it does not give the ticks back. This was the owner's choice
between four treatments, made with that trade in view.

`PlayerModel` derives the fractions behind a cache keyed on `coordinator.timelineRevision`, the
pattern `tickCache`, `derivedCache` and `chapterIndexCache` already use, so the 10 Hz tick never
recomputes them.

## 9. What is removed, and the bug that goes with it

`toggleBookmark`, `isBookmarkedAtPlayhead` and `bookmarkedUtterances` are deleted. In their place
`PlayerModel` holds the loaded document's `bookmarks: [Bookmark]`, refreshed on load and after any
add or delete; the scrubber's fractions, the chapter grouping and the duplicate check in §5 all
derive from that one list.

This removes a latent fault as a by-product. `addBookmark` records the raw
`playhead.utteranceIndex`, while `toggleBookmark` finds bookmarks by re-resolving a stored
`Position` — two different routes to the question *which utterance is this*. If they ever disagree,
the delete branch finds nothing, a second tap adds a duplicate instead of removing, and the button
never empties. After this change there is one route, and the duplicate check compares like with
like.

Whether the two routes actually do disagree is left as a question with a test attached rather than
an assumption (§10). It matters beyond bookmarks: the same resolver carries resume positions.

## 10. Tests — the ones that earn their place

Every one goes into a suite that already exists.

- `T2SStoreTests/BookmarkTests` — `userNote` round-trips; a row written without one reads back
  `nil` with `passageText` intact.
- `T2SStoreTests/LibraryStoreTests` — the V3 → V4 migration, beside the migration coverage already
  there.
- `T2SStoreTests/LibraryStoreSyncTests` — editing a note sets `isDirty` and bumps `updatedAt`.
- `T2SSyncTests/CloudKitRecordMappingTests` — `userNote` survives the record round-trip, **and a
  record carrying no `userNote` key decodes with `userNote` nil**. That second one is the
  old-device case and the whole reason §4 is shaped as it is.
- `T2SAppTests/BookmarkListModelTests` — the headline fallback chain of §6, and `endSeconds`
  against a known timeline.
- A new round-trip test on `PositionResolver`: `resolve(position(for: playhead)) == playhead` over a
  generated timeline. It either clears the resolver or finds a bug larger than this feature.

No UI tests. This codebase has none, and a bookmarks feature is not the occasion to introduce a
harness.

## 11. Rollback, risk, and what is already decided for C

**Rollback.** The cloud rolls back and the store does not, and the difference matters.

In the cloud everything is additive, so a device still on the old build keeps working throughout: it
reads the passage from `note` as it always did, ignores a `userNote` key it does not know, and
pushes records the new build reads without loss. Notes written on a new build sit in the account
unread until a forward build reads them again.

Locally there is no rollback. SwiftData migration is forward-only: once a store is at V4, a build
reverted to V3 cannot open it, because an added attribute changes the model's version hash and the
store is then newer than the model. `LibraryStore.onDisk` throws in that case rather than recreating
the store, so the data is refused rather than destroyed — the app fails to start, and nothing is
lost that a forward build cannot read again. A fault found after release is therefore fixed by
rolling *forward* to V5, never by shipping the previous build.

The real safety net is the other device. Because §4 added a key instead of changing one, a phone
left on the old build holds a complete, readable copy of the library and every bookmark throughout,
whatever happens to a migrated store.

**Risks.** The migration is the one irreversible step, and it is a single added optional. The toast
is new, and new transient UI is where accessibility is usually lost, hence the announcement in §5.
The scrubber dots obscure the render frontier, accepted knowingly in §8.

**Settled for sub-project C**, recorded here so it is not re-argued: Apple's own dictionary is shown
through `UIReferenceLibraryViewController`, gated on `dictionaryHasDefinition(forTerm:)`, and is
always available. No public API returns its definition text, so saving a definition requires the
app's own data: an optional offline dictionary of roughly 10–20 MB, downloaded from Settings and
removable there to reclaim the space. Apple Intelligence's on-device `FoundationModels` is not
pursued — it would give savable, in-context explanations, but it requires an iPhone 15 Pro or newer
and the owner's device is an 11 Pro. C also depends on text selection, which the Reader does not
have today: `ReaderTextView` sets `isSelectable = false`, and the selection menu in the owner's
reference screenshot exists on no branch.
