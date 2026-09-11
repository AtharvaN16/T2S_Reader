# Bookmark Notes and Markers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every bookmark a note of the reader's own, and show where bookmarks are — on the scrubber while it is pressed, and under the chapter rows behind one icon.

**Architecture:** One additive schema version (V4) adds `userNote` beside the existing `note` column, which keeps its name and its meaning (the passage text) because that meaning is already in the iCloud account. The domain type renames at the store boundary only. The Reader's bookmark toggle becomes a momentary save with a toast, which lets `toggleBookmark`, `isBookmarkedAtPlayhead` and `bookmarkedUtterances` be deleted; in their place `PlayerModel` holds the loaded document's bookmarks once, and the scrubber dots, the chapter stamps and the duplicate check all derive from that single list.

**Tech Stack:** Swift 6, SwiftData (versioned schema + `SchemaMigrationPlan`), CloudKit (`CKRecord` mapping in `T2SSync`), SwiftUI (app target), Swift Testing (`@Suite` / `@Test` / `#expect`).

**Spec:** `docs/superpowers/specs/2026-09-11-bookmark-notes-and-markers-design.md`

## Global Constraints

- **Never change the meaning of the stored `note` column or the CloudKit `"note"` key.** Both hold the passage text and always will (spec §3). `userNote` is added beside them.
- **Platforms:** iOS 18 / macOS 15 (`Package.swift`), `IPHONEOS_DEPLOYMENT_TARGET = 18.0`.
- **The persistence schema never shapes the domain model** (design spec §3.7.1). The store hands out `T2SCore` value types; the word `note` must not appear above `Sources/T2SStore/`.
- **Two test commands.** `swift test` runs the root package (everything under `Sources/`). The app target under `App/T2SReader/` is **not** in the package and has no tests — changes there are verified with `scripts/build-app.sh`.
- **No UI test harness may be introduced by this plan.**
- **Design system only.** Use `Pill`, `CircleGlyph`, `BarButton`, `Tokens`, `Spacing`, `typeRole(_:)` from `App/T2SReader/Design/`. Do not introduce new colours, type sizes, or lookalike components. The toast is the one new component and is built from existing tokens.
- **Commit after every task**, message in the house style (a sentence that says what changed and why, not a conventional-commits prefix).

## File Structure

**Created:**
- `Sources/T2SStore/LibrarySchemaV3.swift` — the frozen V3 schema, moved out of `Models.swift`.
- `App/T2SReader/Design/Toast.swift` — the transient message view and its view modifier.
- `App/T2SReader/Bookmarks/BookmarkNoteSheet.swift` — the note editor.
- `Sources/T2SApp/Bookmarks/BookmarkGrouping.swift` — pure functions grouping entries by chapter and mapping them to scrubber fractions (in the package, so it is testable).
- `Tests/T2SAppTests/BookmarkGroupingTests.swift`
- `Tests/T2SCoreTests/PositionRoundTripTests.swift`

**Modified:**
- `Sources/T2SStore/Models.swift` — becomes `LibrarySchemaV4`; `StoredBookmark` gains `userNote`.
- `Sources/T2SStore/LibrarySchema.swift` — typealiases and the new migration stage.
- `Sources/T2SStore/LibraryStore+Bookmarks.swift` — maps `note ↔ passageText`, carries `userNote`.
- `Sources/T2SStore/LibraryStore+Sync.swift` — `userNote` in and out of `SyncedBookmark`.
- `Sources/T2SCore/Model/Bookmark.swift` — `passageText` and `userNote`.
- `Sources/T2SCore/Sync/SyncRecords.swift` — `SyncedBookmark.userNote`.
- `Sources/T2SSync/CloudKit/CloudKitRecordMapping.swift` — the `"userNote"` key.
- `Sources/T2SApp/Player/PlayerModel.swift` — `bookmarks`, `saveBookmark()`; deletes the toggle trio.
- `Sources/T2SApp/Bookmarks/BookmarkEntry.swift` — `endSeconds`, `rangeText`, `userNote`.
- `Sources/T2SApp/Bookmarks/BookmarkListModel.swift` — headline fallback, note editing.
- `App/T2SReader/Reader/ReaderPage.swift` — momentary button, toast, note sheet.
- `App/T2SReader/Reader/ThinScrubber.swift` — the dots.
- `App/T2SReader/Bookmarks/BookmarkRow.swift` — layout B.
- `App/T2SReader/Bookmarks/BookmarksSheet.swift` — edit-note routing.
- `App/T2SReader/Player/ChapterList.swift` — the header toggle and the stamps.
- `App/T2SReader/Collection/BookSheet.swift` — passes bookmarks to `ChapterListView`.

**Task order rationale:** 1–3 are the data spine and each leaves the tree compiling. 4 is an investigation that could change 5. 5–6 are the model layer (all `swift test`). 7–11 are the app target (all `scripts/build-app.sh`).

---

### Task 1: Schema V4 — freeze V3, add the `userNote` column

**Files:**
- Create: `Sources/T2SStore/LibrarySchemaV3.swift`
- Modify: `Sources/T2SStore/Models.swift`, `Sources/T2SStore/LibrarySchema.swift`, `Sources/T2SStore/LibraryStore.swift:73`
- Test: `Tests/T2SStoreTests/LibraryStoreTests.swift:205`

**Interfaces:**
- Consumes: nothing.
- Produces: `LibrarySchemaV4.StoredBookmark` with `var userNote: String?`; the module aliases (`StoredDocument`, `StoredChapter`, `StoredBookmark`, `StoredPronunciation`, `StoredTombstone`) now point at V4.

- [ ] **Step 1: Update the migration-count assertion so it fails**

In `Tests/T2SStoreTests/LibraryStoreTests.swift`, change the existing assertion at line 205 from `== 2` to `== 3`:

```swift
        #expect(LibraryMigrationPlan.stages.count == 3)
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `swift test --filter LibraryStoreTests`
Expected: FAIL — the expectation sees 2 stages.

- [ ] **Step 3: Freeze V3 into its own file**

```bash
cp Sources/T2SStore/Models.swift Sources/T2SStore/LibrarySchemaV3.swift
```

Then in `Sources/T2SStore/LibrarySchemaV3.swift` replace the leading doc comment (the four lines beginning `/// The current schema (iCloud sync, 2026-09-11):`) with:

```swift
/// The iCloud-sync schema, frozen; see `LibrarySchemaV4` in Models.swift. Never edit these
/// classes — a change is a new version and a migration stage (spec §3.7.4).
```

Leave everything else in that file exactly as copied: the enum stays `LibrarySchemaV3`, `versionIdentifier` stays `Schema.Version(3, 0, 0)`.

- [ ] **Step 4: Turn Models.swift into V4**

In `Sources/T2SStore/Models.swift` make three edits.

Replace the header comment and enum declaration:

```swift
/// The current schema (bookmark notes, 2026-09-11): V3 plus `StoredBookmark.userNote`, the reader's
/// own words. Optional, so a V3 row reads back with it nil. `note` is untouched and still holds the
/// passage text — see the spec's §3 for why that name can never be reused.
/// Model classes live inside their schema version (see V2's note).
enum LibrarySchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
```

In `StoredBookmark`, add the property immediately after `var note: String?`:

```swift
        var note: String?
        /// The reader's own note, nil on a V3 row and on every bookmark nobody has written on.
        /// Distinct from `note`, which is the passage the app captured at save.
        var userNote: String?
```

And in that class's `init`, add the initialiser line immediately after `self.note = note`:

```swift
            self.note = note
            self.userNote = nil
```

- [ ] **Step 5: Point the aliases and the migration plan at V4**

Replace the whole body of `Sources/T2SStore/LibrarySchema.swift`:

```swift
import SwiftData

/// Every persisted thing carries a version (spec §3.7.4). The schema itself is versioned so a
/// change is a migration stage, not a rewrite: `LibrarySchemaV1` (Plan 3), `LibrarySchemaV2`
/// (Plan 16) and `LibrarySchemaV3` (iCloud sync) are frozen in their own files,
/// `LibrarySchemaV4` (bookmark notes) is the current one, and the rest of the module names the
/// current classes through these aliases.
typealias StoredDocument = LibrarySchemaV4.StoredDocument
typealias StoredChapter = LibrarySchemaV4.StoredChapter
typealias StoredBookmark = LibrarySchemaV4.StoredBookmark
typealias StoredPronunciation = LibrarySchemaV4.StoredPronunciation
typealias StoredTombstone = LibrarySchemaV4.StoredTombstone

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LibrarySchemaV1.self, LibrarySchemaV2.self, LibrarySchemaV3.self, LibrarySchemaV4.self]
    }
    /// V1 → V2 adds two optional columns; V2 → V3 adds optional and defaulted columns and one
    /// model; V3 → V4 adds one optional column. Core Data infers all three mappings.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self),
         .lightweight(fromVersion: LibrarySchemaV2.self, toVersion: LibrarySchemaV3.self),
         .lightweight(fromVersion: LibrarySchemaV3.self, toVersion: LibrarySchemaV4.self)]
    }
}
```

- [ ] **Step 5b: Point the container's registered schema at V4**

`Sources/T2SStore/LibraryStore.swift:73` names the version explicitly. Left at V3, the
`ModelContainer` registers V3's model classes while every typealias in the module resolves to V4's,
so `userNote` is not in the registered schema at all:

```swift
    static let schema = Schema(versionedSchema: LibrarySchemaV4.self)
```

- [ ] **Step 6: Run the store tests**

Run: `swift test --filter T2SStoreTests`
Expected: PASS. If the compiler reports `LibrarySchemaV3` declared twice, `Models.swift` still says `LibrarySchemaV3` — finish Step 4.

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SStore/LibrarySchemaV3.swift Sources/T2SStore/Models.swift Sources/T2SStore/LibrarySchema.swift Sources/T2SStore/LibraryStore.swift Tests/T2SStoreTests/LibraryStoreTests.swift
git commit -m "Schema V4 adds the reader's own note beside the passage, and freezes V3"
```

---

### Task 2: `passageText` and `userNote` on the domain type

**Files:**
- Modify: `Sources/T2SCore/Model/Bookmark.swift`, `Sources/T2SStore/LibraryStore+Bookmarks.swift`, `Sources/T2SStore/LibraryStore+Sync.swift:102-120`, `Sources/T2SApp/Player/PlayerModel.swift:311-325`, `Sources/T2SApp/Bookmarks/BookmarkListModel.swift:90`
- Test: `Tests/T2SStoreTests/BookmarkTests.swift`

**Interfaces:**
- Consumes: `LibrarySchemaV4.StoredBookmark.userNote` (Task 1).
- Produces: `Bookmark(id:documentID:position:passageText:userNote:createdAt:)`, with `passageText: String?` and `userNote: String?`. `Bookmark.note` no longer exists — every call site must move.

- [ ] **Step 1: Write the failing test**

Add to `Tests/T2SStoreTests/BookmarkTests.swift`, inside the `@Suite`:

```swift
    @Test func userNoteRoundTripsBesideThePassage() async throws {
        let store = try LibraryStore.inMemory()
        let doc = Document(title: "D", sourceType: .epub)
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        let saved = Bookmark(documentID: doc.id, position: Position(resourceHref: "ch1.xhtml", progression: 0.1),
                             passageText: "The passage the app captured.", createdAt: fixedDate)
        try await store.add(saved)
        #expect(try await store.bookmarks(for: doc.id) == [saved])

        var annotated = saved
        annotated.userNote = "my own words"
        try await store.add(annotated)
        let read = try #require(try await store.bookmarks(for: doc.id).first)
        #expect(read.userNote == "my own words")
        #expect(read.passageText == "The passage the app captured.")

        annotated.userNote = nil
        try await store.add(annotated)
        #expect(try await store.bookmarks(for: doc.id).first?.userNote == nil)
    }
```

`fixedDate` is already defined in this test target (`Tests/T2SStoreTests/LibraryStoreTests.swift`).

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter BookmarkTests`
Expected: FAIL to compile — `Bookmark` has no `passageText` or `userNote`.

- [ ] **Step 3: Rewrite the domain type**

Replace the whole of `Sources/T2SCore/Model/Bookmark.swift`:

```swift
import Foundation

/// A user-placed anchor into a document (spec §2.2). Persisted as a `Position`, never as a
/// runtime index (spec §3.2).
///
/// Two strings, and they must never be conflated. `passageText` is the utterance's source, written
/// by the app at save so the bookmark keeps its words when the document is re-derived and utterance
/// indices move. `userNote` is the reader's own writing, and is absent on most bookmarks.
public struct Bookmark: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var documentID: UUID
    public var position: Position
    /// Written by the app, never edited. Stored in the column still called `note` (2026-09-11 spec
    /// §3: that column's meaning is already in iCloud and can never be reused).
    public var passageText: String?
    /// Written by the reader, edited freely, nil when they have written nothing.
    public var userNote: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), documentID: UUID, position: Position, passageText: String? = nil,
                userNote: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.documentID = documentID
        self.position = position
        self.passageText = passageText
        self.userNote = userNote
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Map it in the store**

In `Sources/T2SStore/LibraryStore+Bookmarks.swift`, change the read in `bookmarks(for:)`:

```swift
        return try modelContext.fetch(descriptor).map { row in
            Bookmark(id: row.id, documentID: row.documentID, position: row.position,
                     passageText: row.note, userNote: row.userNote, createdAt: row.createdAt)
        }
```

In `add(_:)`, replace `row.note = bookmark.note` in the update branch with both fields:

```swift
            row.note = bookmark.passageText
            row.userNote = bookmark.userNote
```

and in the insert branch replace the two construction lines with:

```swift
            let row = StoredBookmark(id: bookmark.id, documentID: bookmark.documentID, position: bookmark.position,
                                     note: bookmark.passageText, createdAt: bookmark.createdAt)
            row.userNote = bookmark.userNote
            row.updatedAt = Date()
            row.isDirty = true
            modelContext.insert(row)
```

- [ ] **Step 5: Move the two remaining call sites**

In `Sources/T2SApp/Player/PlayerModel.swift`, inside `addBookmark()`, change the construction to name the field it means:

```swift
            try await library.store.add(Bookmark(documentID: current.id, position: position, passageText: block))
```

In `Sources/T2SApp/Bookmarks/BookmarkListModel.swift`, in `entry(for:timeline:index:)`, change the snippet line:

```swift
        let snippet = bookmark.passageText.map { BookmarkSnippet.make(from: $0, offset: 0) }
            ?? BookmarkSnippet.make(from: utterance.source, offset: offset)
```

- [ ] **Step 6: Run the whole package**

Run: `swift test`
Expected: PASS. Any remaining compile error naming `.note` on a `Bookmark` is a call site this step missed — move it to `passageText`; `Sources/T2SStore/LibraryStore+Sync.swift:226` is handled in Task 3 and may still read `r.note` on the **row**, which is correct and must not change.

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SCore/Model/Bookmark.swift Sources/T2SStore/LibraryStore+Bookmarks.swift Sources/T2SApp/Player/PlayerModel.swift Sources/T2SApp/Bookmarks/BookmarkListModel.swift Tests/T2SStoreTests/BookmarkTests.swift
git commit -m "A bookmark's two strings get their own names: the app's passage and the reader's note"
```

---

### Task 3: Carry `userNote` through sync

**Files:**
- Modify: `Sources/T2SCore/Sync/SyncRecords.swift:38-52`, `Sources/T2SStore/LibraryStore+Sync.swift:102-120,225-227`, `Sources/T2SSync/CloudKit/CloudKitRecordMapping.swift:28-56`
- Test: `Tests/T2SSyncTests/CloudKitRecordMappingTests.swift`, `Tests/T2SStoreTests/LibraryStoreSyncTests.swift`

**Interfaces:**
- Consumes: `Bookmark.userNote` (Task 2).
- Produces: `SyncedBookmark(id:contentKey:position:note:userNote:createdAt:updatedAt:deletedAt:)` — `note` keeps its position and meaning (the passage), `userNote` is appended after it. CloudKit key `"userNote"`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/T2SSyncTests/CloudKitRecordMappingTests.swift`, inside the `@Suite`:

```swift
    @Test func userNoteSurvivesTheRecordRoundTrip() throws {
        let zone = CKRecordZone.ID(zoneName: "t2s", ownerName: CKCurrentUserDefaultName)
        let bookmark = SyncedBookmark(id: UUID(), contentKey: "key", position: Position(resourceHref: "ch1.xhtml", progression: 0.5),
                                      note: "the passage", userNote: "my own words",
                                      createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
        let record = CloudKitRecordMapping.record(for: bookmark, zone: zone, updating: nil)
        guard case .bookmark(let back)? = CloudKitRecordMapping.syncRecord(from: record) else {
            Issue.record("not a bookmark record"); return
        }
        #expect(back == bookmark)
    }

    /// The old-device case, and the reason the spec adds a key instead of changing one: a record
    /// written by a build that has never heard of `userNote` must decode with it nil, and must keep
    /// its passage.
    @Test func aRecordWithoutTheUserNoteKeyDecodesWithNoNote() throws {
        let zone = CKRecordZone.ID(zoneName: "t2s", ownerName: CKCurrentUserDefaultName)
        let id = UUID()
        let record = CKRecord(recordType: "Bookmark", recordID: CKRecord.ID(recordName: "bm-" + id.uuidString, zoneID: zone))
        record["bookmarkID"] = id.uuidString as NSString
        record["contentKey"] = "key" as NSString
        record["position"] = #"{"resourceHref":"ch1.xhtml","progression":0.5}"# as NSString
        record["note"] = "the passage" as NSString
        record["createdAt"] = Date(timeIntervalSince1970: 1) as NSDate
        record["updatedAt"] = Date(timeIntervalSince1970: 2) as NSDate
        guard case .bookmark(let back)? = CloudKitRecordMapping.syncRecord(from: record) else {
            Issue.record("not a bookmark record"); return
        }
        #expect(back.userNote == nil)
        #expect(back.note == "the passage")
    }
```

Add to `Tests/T2SStoreTests/LibraryStoreSyncTests.swift`, inside the `@Suite`:

```swift
    @Test func editingANoteMarksTheBookmarkDirtyAndPushesIt() async throws {
        let store = try LibraryStore.inMemory()
        let doc = makeDocument()
        try await store.insert(doc, timeline: makeTimeline([[makeUtterance("One.")]]))
        try await store.setContentKey(doc.id, "key")
        var bookmark = Bookmark(documentID: doc.id, position: Position(resourceHref: "ch1.xhtml", progression: 0.2),
                                passageText: "the passage", createdAt: fixedDate)
        try await store.add(bookmark)
        try await store.markClean(try await store.dirtyRecords(deviceName: "Mac"))

        bookmark.userNote = "written later"
        try await store.add(bookmark)

        let records = try await store.dirtyRecords(deviceName: "Mac")
        let notes = records.compactMap { record -> String?? in
            if case .bookmark(let b) = record, b.id == bookmark.id { return b.userNote }
            return nil
        }
        #expect(notes == ["written later"])
    }
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter "CloudKitRecordMappingTests|LibraryStoreSyncTests"`
Expected: FAIL to compile — `SyncedBookmark` has no `userNote`.

- [ ] **Step 3: Add the field to the record type**

In `Sources/T2SCore/Sync/SyncRecords.swift`, replace the `SyncedBookmark` declaration:

```swift
public struct SyncedBookmark: Sendable, Codable, Hashable {
    public var id: UUID
    public var contentKey: String
    public var position: Position
    /// The passage the app captured. Named `note` because that is this record's CloudKit key and
    /// has been since iCloud sync shipped; it must never be reused for the reader's writing.
    public var note: String?
    /// The reader's own note. Absent from records written by a build older than 2026-09-11.
    public var userNote: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public init(id: UUID, contentKey: String, position: Position, note: String? = nil, userNote: String? = nil,
                createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id; self.contentKey = contentKey; self.position = position; self.note = note
        self.userNote = userNote; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}
```

- [ ] **Step 4: Carry it through the store's sync columns**

In `Sources/T2SStore/LibraryStore+Sync.swift`, in `synced(_:contentKey:)` (line ~225):

```swift
    static func synced(_ r: StoredBookmark, contentKey: String) -> SyncedBookmark {
        SyncedBookmark(id: r.id, contentKey: contentKey, position: r.position, note: r.note, userNote: r.userNote,
                       createdAt: r.createdAt, updatedAt: r.updatedAt ?? r.createdAt)
    }
```

In `writeSynced(_ bookmark:)`, add the field to both branches — the update branch:

```swift
            row.note = bookmark.note; row.userNote = bookmark.userNote; row.updatedAt = bookmark.updatedAt
```

and the insert branch, immediately after the `StoredBookmark(...)` construction:

```swift
            let row = StoredBookmark(id: bookmark.id, documentID: document.id, position: bookmark.position, note: bookmark.note, createdAt: bookmark.createdAt)
            row.userNote = bookmark.userNote
            row.updatedAt = bookmark.updatedAt
            modelContext.insert(row)
```

- [ ] **Step 5: Add the CloudKit key**

In `Sources/T2SSync/CloudKit/CloudKitRecordMapping.swift`, in `record(for b: SyncedBookmark, ...)` add one line after the `note` line:

```swift
        record["note"] = b.note.map { $0 as NSString }
        record["userNote"] = b.userNote.map { $0 as NSString }
```

and in `syncRecord(from:)`'s `bookmarkType` branch, add the field to the construction:

```swift
            return .bookmark(SyncedBookmark(id: id, contentKey: key, position: position, note: r["note"] as? String,
                                            userNote: r["userNote"] as? String,
                                            createdAt: createdAt, updatedAt: updatedAt, deletedAt: r["deletedAt"] as? Date))
```

Do **not** add `userNote` to the `guard let` — a missing key must decode as nil, not drop the record. That is what the second test in Step 1 pins.

- [ ] **Step 6: Run the suites, then the whole package**

Run: `swift test --filter "CloudKitRecordMappingTests|LibraryStoreSyncTests"`
Expected: PASS.

Run: `swift test`
Expected: PASS. The tombstone construction in `dirtyRecords` (line ~44) builds a `SyncedBookmark` positionally and still compiles because `userNote` is defaulted — leave it alone.

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SCore/Sync/SyncRecords.swift Sources/T2SStore/LibraryStore+Sync.swift Sources/T2SSync/CloudKit/CloudKitRecordMapping.swift Tests/T2SSyncTests/CloudKitRecordMappingTests.swift Tests/T2SStoreTests/LibraryStoreSyncTests.swift
git commit -m "Notes sync as a new key, so a device on the old build reads every record it always did"
```

---

### Task 4: Does the position round-trip hold?

This task is an investigation with a test attached, not a change. The spec (§9) will not assume the answer. It matters past bookmarks: the same resolver carries resume positions.

**Files:**
- Create: `Tests/T2SCoreTests/PositionRoundTripTests.swift`

**Interfaces:**
- Consumes: `PositionResolver.position(for:in:)` and `PositionResolver.resolve(_:in:)` (`Sources/T2SCore/Timeline/PositionResolver.swift:40,76`).
- Produces: nothing consumed by later tasks. A failure here is reported, not silently worked around.

- [ ] **Step 1: Write the test**

```swift
import Foundation
import Testing
@testable import T2SCore

/// `PositionResolver` is the only route between a runtime `Playhead` (an utterance index) and a
/// persisted `Position` (an href plus offsets), and bookmarks, resume positions and the sync offer
/// all cross it. If the two directions disagree the app silently lands somewhere other than where
/// it saved.
@Suite struct PositionRoundTripTests {
    /// Utterances laid out the way `Segmenter` lays them out: each one's `charOffset` is its own
    /// UTF-16 offset within its resource (`Segmenter.swift:43`), so no two in a resource share a
    /// start. The fixture helper defaults `charOffset` to 0 for every utterance, which no real
    /// document does — a timeline built that way cannot round-trip and would test nothing.
    private func realisticTimeline() -> Timeline {
        func chapter(_ texts: [String], href: String) -> [Utterance] {
            var offset = 0
            return texts.map { text in
                let utterance = makeUtterance(text, href: href, charOffset: offset)
                offset += text.utf16.count + 1                  // the whitespace the segmenter trims
                return utterance
            }
        }
        return makeTimeline([
            chapter(["First sentence.", "Second one is longer than the first."], href: "ch1.xhtml"),
            chapter(["Chapter two opens here.", "And closes here."], href: "ch2.xhtml"),
            chapter(["A third chapter with one line."], href: "ch3.xhtml"),
        ])
    }

    @Test func everyUtteranceSurvivesPositionThenResolve() throws {
        let timeline = realisticTimeline()
        for index in 0..<timeline.utteranceCount {
            let playhead = Playhead(utteranceIndex: index)
            let position = PositionResolver.position(for: playhead, in: timeline)
            let back = PositionResolver.resolve(position, in: timeline)
            #expect(back.utteranceIndex == index, "utterance \(index) round-tripped to \(back.utteranceIndex)")
        }
    }

    /// The round-trip's documented limit. Two utterances claiming the same `charOffset` in one
    /// resource are indistinguishable by `Position` alone, and `resolve` returns the earlier —
    /// the fallback of spec §1.4, "never fails". The segmenter never produces this, so it is
    /// pinned here as a decision on record rather than left to be rediscovered as a bug.
    @Test func utterancesSharingACharOffsetCollapseToTheFirst() throws {
        let timeline = makeTimeline([[makeUtterance("First."), makeUtterance("Second.")]])
        let position = PositionResolver.position(for: Playhead(utteranceIndex: 1), in: timeline)
        #expect(PositionResolver.resolve(position, in: timeline).utteranceIndex == 0)
    }

    /// The `offset` half of the round trip. Every assertion above leaves `Playhead.offset` at its
    /// default of 0, where `time(atSourceOffset: 0)` and `sourceOffset(atTime: 0)` both return 0
    /// whatever the seconds-to-character maths does — so a bug in the conversion that lands a
    /// resume on the wrong word would pass unnoticed.
    ///
    /// The round trip is deliberately **not** asserted as the identity on `offset`. A `Position`
    /// stores a character, so a time is quantised to a character boundary on the way out and comes
    /// back as that character's time. The invariant that matters is idempotence: a saved position
    /// re-resolves to the same character and re-saves to the same `Position`, which is what makes a
    /// resume re-highlight the word it was saved on (`PositionResolver.swift:20-22`).
    @Test func offsetsWithinAnUtteranceSurviveTheRoundTripAsCharacters() throws {
        let timeline = realisticTimeline()
        let index = 1                                  // "Second one is longer than the first."
        let seconds = timeline[utterance: index].duration.seconds
        for fraction in [0.25, 0.5, 0.75] {
            let playhead = Playhead(utteranceIndex: index, offset: seconds * fraction)
            let position = PositionResolver.position(for: playhead, in: timeline)
            let back = PositionResolver.resolve(position, in: timeline)
            #expect(back.utteranceIndex == index, "offset at \(fraction) left the utterance")
            #expect(PositionResolver.position(for: back, in: timeline) == position,
                    "offset at \(fraction) did not re-save to the same position")
        }
    }

    /// Proof the offset is not simply discarded: three different times inside one utterance must
    /// store three different characters. Without this, the idempotence above would hold just as
    /// well for a `position(for:)` that threw the offset away entirely.
    @Test func differentOffsetsInOneUtteranceStoreDifferentCharacters() throws {
        let timeline = realisticTimeline()
        let index = 1
        let seconds = timeline[utterance: index].duration.seconds
        let stored = [0.0, 0.5, 0.9].map { fraction in
            PositionResolver.position(for: Playhead(utteranceIndex: index, offset: seconds * fraction),
                                      in: timeline).charOffset
        }
        #expect(Set(stored).count == stored.count,
                "the playhead's offset is not reaching the stored position: \(stored)")
    }
}
```

- [ ] **Step 2: Run it**

Run: `swift test --filter PositionRoundTripTests`

- [ ] **Step 3: Act on the result**

**If it passes:** the resolver is clear, and the old button fault was purely the playhead-derived toggle described in the spec's §5. Nothing to fix. Go to Step 4.

**If it fails:** stop. Do not continue to Task 5, and do not adjust the test to make it pass. Report which utterance index round-tripped wrong, what it came back as, and the `Position` that was produced. With realistic offsets in the fixture a failure here is a genuine bug in `PositionResolver` — which carries resume positions and the sync offer, not only bookmarks — and it needs its own fix and its own review before this feature is built on top of it.

- [ ] **Step 4: Commit**

```bash
git add Tests/T2SCoreTests/PositionRoundTripTests.swift
git commit -m "Pin the position round-trip: a playhead that is saved and read back is the same playhead"
```

---

### Task 5: `PlayerModel` holds the bookmarks; the toggle goes

**Files:**
- Modify: `Sources/T2SApp/Player/PlayerModel.swift:95-98,238,305-350`
- Test: `Tests/T2SAppTests/PlayerModelTests.swift`

**Interfaces:**
- Consumes: `Bookmark.passageText` (Task 2).
- Produces:
  - `public private(set) var bookmarks: [Bookmark]` on `PlayerModel` — the loaded document's, oldest first.
  - `public func saveBookmark() async -> BookmarkSaveResult`
  - `public enum BookmarkSaveResult: Sendable, Equatable { case saved(Bookmark), alreadyBookmarked(Bookmark), failed }`
  - `public func refreshBookmarks() async` (kept, now filling `bookmarks`)
  - **Removed:** `toggleBookmark()`, `isBookmarkedAtPlayhead`, `bookmarkedUtterances`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/T2SAppTests/PlayerModelTests.swift`, inside the `@Suite`:

```swift
    @Test func savingTwiceOnTheSameSentenceDoesNotMakeTwoBookmarks() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)

        guard case .saved(let first) = await player.saveBookmark() else {
            Issue.record("first save did not save"); return
        }
        #expect(player.bookmarks.count == 1)
        #expect(first.passageText == "First sentence.")

        guard case .alreadyBookmarked(let same) = await player.saveBookmark() else {
            Issue.record("second save on the same sentence should report it was already bookmarked"); return
        }
        #expect(same.id == first.id)
        #expect(player.bookmarks.count == 1)
        #expect(try await f.store.bookmarks(for: id).count == 1)
    }

    @Test func movingOnAndSavingAgainMakesASecondBookmark() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        _ = await player.saveBookmark()
        await player.seek(toChapter: 1)
        guard case .saved = await player.saveBookmark() else {
            Issue.record("a different sentence should save"); return
        }
        #expect(player.bookmarks.count == 2)
    }
```

`makePlayer` and `AppFixtures` are the helpers the existing tests in this suite already use; if `makePlayer` is private to another suite, copy the four-line body from `Tests/T2SAppTests/BookmarkListModelTests.swift`.

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter PlayerModelTests`
Expected: FAIL to compile — no `saveBookmark`, no `bookmarks`.

- [ ] **Step 3: Replace the bookmark region of PlayerModel**

Delete the `bookmarkedUtterances` property (line ~98, with its doc comment) and put in its place:

```swift
    /// The loaded document's bookmarks, oldest first — read once per load and after every change.
    /// One list feeds three surfaces: the scrubber's dots, the chapter list's stamps, and the
    /// duplicate check in `saveBookmark`. Keeping one resolved list is what makes that check
    /// trustworthy: before 2026-09-11 the save recorded a raw utterance index while the un-save
    /// re-resolved a stored `Position`, and the two could disagree.
    public private(set) var bookmarks: [Bookmark] = []
```

Delete `isBookmarkedAtPlayhead` and `toggleBookmark()` entirely, and replace `addBookmark()` with:

```swift
    /// What a save did, for the Reader's toast.
    public enum BookmarkSaveResult: Sendable, Equatable {
        case saved(Bookmark)
        /// The sentence under the playhead already carried this bookmark; nothing was written.
        case alreadyBookmarked(Bookmark)
        case failed
    }

    /// Saves a bookmark at the playhead, with the block of text it lands on — the utterance's
    /// source, so the bookmark keeps its words after the document is re-derived (owner's ask,
    /// 2026-09-09). Saving twice on one sentence does not make two rows: the check runs against
    /// `bookmarks`, resolved the same way the list itself is.
    public func saveBookmark() async -> BookmarkSaveResult {
        guard let current, let timeline = coordinator.timeline, timeline.utteranceCount > 0 else { return .failed }
        let utterance = coordinator.playhead.utteranceIndex
        if let existing = bookmarks.first(where: {
            PositionResolver.resolve($0.position, in: timeline).utteranceIndex == utterance
        }) {
            return .alreadyBookmarked(existing)
        }
        let position = PositionResolver.position(for: coordinator.playhead, in: timeline)
        let block = timeline[utterance: utterance].source
        let bookmark = Bookmark(documentID: current.id, position: position, passageText: block)
        do {
            try await library.store.add(bookmark)
            await refreshBookmarks()
            return .saved(bookmark)
        } catch {
            localError = "\(error)"
            return .failed
        }
    }
```

Replace `refreshBookmarks()`:

```swift
    /// Re-reads the loaded document's bookmarks. Cheap: a document has a handful.
    public func refreshBookmarks() async {
        guard let current else { bookmarks = []; return }
        bookmarks = (try? await library.store.bookmarks(for: current.id)) ?? []
    }
```

- [ ] **Step 4: Run the app-package tests**

Run: `swift test --filter T2SAppTests`
Expected: PASS, except that `BookmarkListModelTests` will fail to compile where it calls `player.addBookmark()`. Change each of those calls to discard the new result — `_ = await player.saveBookmark()` where the return is unused, and replace `#expect(await player.addBookmark())` with:

```swift
        #expect(await player.saveBookmark() != .failed)
```

- [ ] **Step 5: Run the whole package**

Run: `swift test`
Expected: PASS. Any remaining reference to `isBookmarkedAtPlayhead` or `bookmarkedUtterances` is in the app target and is fixed in Task 7 — `swift test` will not see it.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SApp/Player/PlayerModel.swift Tests/T2SAppTests/PlayerModelTests.swift Tests/T2SAppTests/BookmarkListModelTests.swift
git commit -m "One resolved list of bookmarks replaces the playhead-derived toggle, and its two disagreeing routes"
```

---

### Task 6: Time ranges, the headline fallback, and editing a note

**Files:**
- Modify: `Sources/T2SApp/Bookmarks/BookmarkEntry.swift`, `Sources/T2SApp/Bookmarks/BookmarkListModel.swift`, `App/T2SReader/Bookmarks/BookmarkRow.swift:17,31`
- Test: `Tests/T2SAppTests/BookmarkListModelTests.swift`

**Interfaces:**
- Consumes: `Bookmark.passageText`, `Bookmark.userNote` (Task 2); `PlayerModel.bookmarks`, `refreshBookmarks()` (Task 5).
- Produces:
  - `BookmarkEntry` gains `let endSeconds: TimeInterval`, `let userNote: String?`, `let passage: String`, and computed `var headline: String`, `var quote: String?`, `var rangeText: String`. `snippet` is **removed** — `passage` replaces it.
  - `BookmarkListModel.setNote(_ note: String?, on entry: BookmarkEntry) async`

- [ ] **Step 1: Write the failing test**

Add to `Tests/T2SAppTests/BookmarkListModelTests.swift`:

```swift
    @Test func theReadersNoteBecomesTheHeadlineAndThePassageBecomesTheQuote() async throws {
        let f = try AppFixtures()
        let id = try await f.importFake()
        let summary = try #require(try await f.store.summary(id: id))
        let (player, _) = try await makePlayer(f)
        await player.load(summary, play: false)
        #expect(await player.saveBookmark() != .failed)

        let model = BookmarkListModel(library: f.library, player: player)
        await model.load(summary)
        let before = try #require(model.entries.first)
        #expect(before.headline == "First sentence.")
        #expect(before.quote == nil)
        #expect(before.endSeconds > before.timeSeconds)
        #expect(before.rangeText == "\(DurationFormatter.clock(before.timeSeconds)) – \(DurationFormatter.clock(before.endSeconds))")

        await model.setNote("my own words", on: before)
        let after = try #require(model.entries.first)
        #expect(after.headline == "my own words")
        #expect(after.quote == "First sentence.")

        await model.setNote("   ", on: after)
        #expect(model.entries.first?.headline == "First sentence.")
        #expect(model.entries.first?.quote == nil)
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter BookmarkListModelTests`
Expected: FAIL to compile — no `headline`, `quote`, `endSeconds`, `rangeText`, `setNote`.

- [ ] **Step 3: Rewrite `BookmarkEntry`**

Replace the `BookmarkEntry` struct in `Sources/T2SApp/Bookmarks/BookmarkEntry.swift` (leave `BookmarkSnippet` below it untouched):

```swift
/// One saved bookmark, resolved for display (spec §2.2 "Bookmarks"): where it is, what it says, and
/// the span of audio it covers. `position` is kept so the jump can resolve it against the timeline
/// the coordinator actually holds.
///
/// The row leads with the reader's own words when there are any, and with the book's otherwise
/// (2026-09-11 spec §6) — `headline` and `quote` are that rule, in one place, so every surface
/// showing a bookmark shows it the same way.
public struct BookmarkEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let position: Position
    public let chapterTitle: String
    /// The book's words at the bookmark, trimmed for a row.
    public let passage: String
    /// The reader's own note, nil or blank when they have written none.
    public let userNote: String?
    /// Seconds at 1x from the document start.
    public let timeSeconds: TimeInterval
    /// Where the bookmarked utterance ends, so a row can show a span rather than an instant.
    public let endSeconds: TimeInterval
    public let createdAt: Date

    public init(id: UUID, position: Position, chapterTitle: String, passage: String, userNote: String?,
                timeSeconds: TimeInterval, endSeconds: TimeInterval, createdAt: Date) {
        self.id = id
        self.position = position
        self.chapterTitle = chapterTitle
        self.passage = passage
        self.userNote = userNote
        self.timeSeconds = timeSeconds
        self.endSeconds = endSeconds
        self.createdAt = createdAt
    }

    /// A note of only whitespace is no note.
    private var writtenNote: String? {
        guard let userNote, !userNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return userNote
    }

    public var hasNote: Bool { writtenNote != nil }
    /// The reader's words when they wrote any, else the book's.
    public var headline: String { writtenNote ?? passage }
    /// The book's words, but only when they are not already the headline.
    public var quote: String? { writtenNote == nil ? nil : passage }

    public var timeText: String { DurationFormatter.clock(timeSeconds) }
    public var rangeText: String { "\(DurationFormatter.clock(timeSeconds)) – \(DurationFormatter.clock(endSeconds))" }
}
```

- [ ] **Step 4: Fill the new fields and add the editor**

In `Sources/T2SApp/Bookmarks/BookmarkListModel.swift`, replace `entry(for:timeline:index:)`'s body after the guard:

```swift
    private static func entry(for bookmark: Bookmark, timeline: Timeline, index: TimeIndex) -> BookmarkEntry {
        guard timeline.utteranceCount > 0 else {
            return BookmarkEntry(id: bookmark.id, position: bookmark.position, chapterTitle: "", passage: "",
                                 userNote: bookmark.userNote, timeSeconds: 0, endSeconds: 0, createdAt: bookmark.createdAt)
        }
        let playhead = PositionResolver.resolve(bookmark.position, in: timeline)
        let utterance = timeline[utterance: playhead.utteranceIndex]
        let chapter = timeline.chapterIndex(forUtterance: playhead.utteranceIndex).map { timeline.chapters[$0].title } ?? ""
        let raw = (bookmark.position.charOffset ?? 0) - (utterance.position.charOffset ?? 0)
        // A fallback resolution (PositionResolver.resolve, spec §1.4 "never fails") can return an
        // utterance that does not contain the bookmark's offset; show it from its start rather
        // than let a negative or out-of-range offset produce an empty passage.
        let offset = (0..<utterance.source.utf16.count).contains(raw) ? raw : 0
        // A bookmark saved with its block of text (`PlayerModel.saveBookmark`) shows that block from
        // its start; an older one, the timeline's text from the bookmark's own word.
        let passage = bookmark.passageText.map { BookmarkSnippet.make(from: $0, offset: 0) }
            ?? BookmarkSnippet.make(from: utterance.source, offset: offset)
        let start = index.time(at: playhead)
        return BookmarkEntry(id: bookmark.id,
                             position: bookmark.position,
                             chapterTitle: chapter,
                             passage: passage,
                             userNote: bookmark.userNote,
                             timeSeconds: start,
                             endSeconds: start + utterance.duration.seconds,
                             createdAt: bookmark.createdAt)
    }
```

Add the editor method beside `delete(_:)`:

```swift
    /// Writes the reader's note, or clears it when the text is blank. Reloads so the row's headline
    /// and quote follow the rule in `BookmarkEntry`, and refreshes the player's copy so the Reader's
    /// surfaces agree with this list.
    public func setNote(_ note: String?, on entry: BookmarkEntry) async {
        do {
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let all = try await library.store.bookmarks(for: currentDocumentID ?? UUID())
            guard var bookmark = all.first(where: { $0.id == entry.id }) else { return }
            bookmark.userNote = (trimmed?.isEmpty ?? true) ? nil : trimmed
            try await library.store.add(bookmark)
            await player.refreshBookmarks()
            if let summary = loadedSummary { await load(summary) }
        } catch {
            self.error = "\(error)"
        }
    }
```

That method needs the document it is showing. Add two stored properties to the class and set them in `load(_:)`:

```swift
    /// The summary this list was last loaded with, so an edit can reload without the caller
    /// passing it again.
    private var loadedSummary: DocumentSummary?
    private var currentDocumentID: UUID? { loadedSummary?.id }
```

and as the first line of `load(_ summary:)`:

```swift
    public func load(_ summary: DocumentSummary) async {
        loadedSummary = summary
        error = nil
```

- [ ] **Step 5: Keep the two `snippet` readers compiling**

Removing `snippet` breaks six assertions and the App target. In
`Tests/T2SAppTests/BookmarkListModelTests.swift`, change `entry.snippet` / `.snippet` to `.passage`
at lines 36, 39, 63, 64, 153 and 154 — the expected values do not change.

In `App/T2SReader/Bookmarks/BookmarkRow.swift`, change the two reads so the App target still builds
(Task 10 rewrites this file properly; this is the minimum to keep Task 8's build green):

```swift
                    Text(entry.passage).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
```

```swift
        .accessibilityLabel("\(entry.passage), \(entry.chapterTitle), at \(entry.timeText)")
```

- [ ] **Step 6: Run the tests**

Run: `swift test`
Expected: PASS. `BookmarkSnippetTests` is untouched — it tests `BookmarkSnippet`, not `BookmarkEntry`.

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SApp/Bookmarks/BookmarkEntry.swift Sources/T2SApp/Bookmarks/BookmarkListModel.swift Tests/T2SAppTests/BookmarkListModelTests.swift App/T2SReader/Bookmarks/BookmarkRow.swift
git commit -m "A bookmark row leads with the reader's words, and says how long the passage runs"
```

---

### Task 7: Grouping bookmarks for the scrubber and the chapter list

**Files:**
- Create: `Sources/T2SApp/Bookmarks/BookmarkGrouping.swift`, `Tests/T2SAppTests/BookmarkGroupingTests.swift`
- Modify: `Sources/T2SApp/Player/PlayerModel.swift`

**Interfaces:**
- Consumes: `PlayerModel.bookmarks` (Task 5), `BookmarkEntry` (Task 6).
- Produces:
  - `public enum BookmarkGrouping { static func fractions(_:timeline:index:) -> [Double]; static func byChapter(_:timeline:index:) -> [Int: [BookmarkEntry]] }`
  - `PlayerModel.bookmarkFractions: [Double]` and `PlayerModel.bookmarksByChapter: [Int: [BookmarkEntry]]`, both cached on `coordinator.timelineRevision`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
import T2SCore
@testable import T2SApp

@Suite struct BookmarkGroupingTests {
    /// Three chapters of one second each; a bookmark on the first utterance of chapters 1 and 3.
    private func fixture() -> (Timeline, TimeIndex, [Bookmark]) {
        let timeline = makeTimeline([
            [makeUtterance("One.")],
            [makeUtterance("Two.", href: "ch2.xhtml")],
            [makeUtterance("Three.", href: "ch3.xhtml")],
        ])
        let index = TimeIndex(timeline)
        let doc = UUID()
        let bookmarks = [0, 2].map { i in
            Bookmark(documentID: doc,
                     position: PositionResolver.position(for: Playhead(utteranceIndex: i), in: timeline),
                     passageText: nil, createdAt: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        return (timeline, index, bookmarks)
    }

    @Test func fractionsSitWhereTheBookmarksAreAlongTheWholeDuration() {
        let (timeline, index, bookmarks) = fixture()
        let fractions = BookmarkGrouping.fractions(bookmarks, timeline: timeline, index: index)
        #expect(fractions.count == 2)
        #expect(abs(fractions[0] - 0.0) < 0.0001)
        #expect(abs(fractions[1] - (2.0 / 3.0)) < 0.0001)
    }

    @Test func entriesGroupUnderTheChapterTheyFallIn() {
        let (timeline, index, bookmarks) = fixture()
        let grouped = BookmarkGrouping.byChapter(bookmarks, timeline: timeline, index: index)
        #expect(Set(grouped.keys) == [0, 2])
        #expect(grouped[0]?.count == 1)
        #expect(grouped[2]?.count == 1)
        #expect(grouped[1] == nil)
    }

    @Test func anEmptyTimelineYieldsNothingRatherThanCrashing() {
        let timeline = makeTimeline([])
        let index = TimeIndex(timeline)
        #expect(BookmarkGrouping.fractions([], timeline: timeline, index: index).isEmpty)
        #expect(BookmarkGrouping.byChapter([], timeline: timeline, index: index).isEmpty)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter BookmarkGroupingTests`
Expected: FAIL to compile — no `BookmarkGrouping`.

- [ ] **Step 3: Write the grouping**

```swift
import Foundation
import T2SCore

/// Where a document's bookmarks fall, in the two shapes the Reader draws them: as fractions along
/// the whole duration (the scrubber's dots) and grouped under their chapter (the chapter list's
/// stamps). Pure functions over a timeline, so both surfaces agree and both can be tested without
/// a player.
public enum BookmarkGrouping {
    /// 0…1 along the total duration, in the order given. An empty or zero-length timeline yields
    /// nothing rather than dividing by zero.
    public static func fractions(_ bookmarks: [Bookmark], timeline: Timeline, index: TimeIndex) -> [Double] {
        let total = index.totalDuration
        guard timeline.utteranceCount > 0, total > 0 else { return [] }
        return bookmarks.map { bookmark in
            let playhead = PositionResolver.resolve(bookmark.position, in: timeline)
            return min(1, max(0, index.time(at: playhead) / total))
        }
    }

    /// Chapter index → its bookmarks, oldest first. A chapter with none has no key at all, so a
    /// caller can ask `grouped[i] != nil` for "does this chapter have any".
    public static func byChapter(_ bookmarks: [Bookmark], timeline: Timeline, index: TimeIndex) -> [Int: [BookmarkEntry]] {
        guard timeline.utteranceCount > 0 else { return [:] }
        var grouped: [Int: [BookmarkEntry]] = [:]
        for bookmark in bookmarks {
            let playhead = PositionResolver.resolve(bookmark.position, in: timeline)
            guard let chapter = timeline.chapterIndex(forUtterance: playhead.utteranceIndex) else { continue }
            grouped[chapter, default: []].append(BookmarkListModel.displayEntry(for: bookmark, timeline: timeline, index: index))
        }
        return grouped
    }
}
```

This calls a shared entry builder. In `Sources/T2SApp/Bookmarks/BookmarkListModel.swift`, change the existing `private static func entry(...)` to be reachable by renaming it and widening its access:

```swift
    /// Public, not internal: the Reader's toast resolves the bookmark it just saved through this,
    /// and the App target cannot see T2SApp's internal symbols.
    public static func displayEntry(for bookmark: Bookmark, timeline: Timeline, index: TimeIndex) -> BookmarkEntry {
```

and update its one caller inside `load(_:)` from `Self.entry(for:...)` to `Self.displayEntry(for:...)`.

- [ ] **Step 4: Run the test**

Run: `swift test --filter BookmarkGroupingTests`
Expected: PASS.

- [ ] **Step 5: Expose both on `PlayerModel`, cached**

In `Sources/T2SApp/Player/PlayerModel.swift`, add beside the other caches (near line 92):

```swift
    @ObservationIgnored private var bookmarkCache: (revision: Int, count: Int, fractions: [Double], byChapter: [Int: [BookmarkEntry]])?
```

and add the two properties near `scrubber`:

```swift
    /// The loaded document's bookmarks as fractions along the whole duration — the scrubber's dots.
    public var bookmarkFractions: [Double] { bookmarkDerived.fractions }
    /// The same bookmarks grouped under their chapter — the chapter list's stamps.
    public var bookmarksByChapter: [Int: [BookmarkEntry]] { bookmarkDerived.byChapter }

    /// Both shapes in one pass, cached on the timeline revision *and* the bookmark count so an add
    /// or a delete invalidates it too. Read from view bodies that run at 10 Hz while playing, so it
    /// must not re-resolve the whole list every tick.
    private var bookmarkDerived: (fractions: [Double], byChapter: [Int: [BookmarkEntry]]) {
        let revision = coordinator.timelineRevision
        if let cache = bookmarkCache, cache.revision == revision, cache.count == bookmarks.count {
            return (cache.fractions, cache.byChapter)
        }
        guard let timeline = coordinator.timeline else { return ([], [:]) }
        let index = coordinator.timeIndex
        let derived = (BookmarkGrouping.fractions(bookmarks, timeline: timeline, index: index),
                       BookmarkGrouping.byChapter(bookmarks, timeline: timeline, index: index))
        bookmarkCache = (revision, bookmarks.count, derived.0, derived.1)
        return derived
    }
```

- [ ] **Step 6: Run the whole package**

Run: `swift test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SApp/Bookmarks/BookmarkGrouping.swift Sources/T2SApp/Bookmarks/BookmarkListModel.swift Sources/T2SApp/Player/PlayerModel.swift Tests/T2SAppTests/BookmarkGroupingTests.swift
git commit -m "One pass turns the bookmark list into the scrubber's dots and the chapter list's stamps"
```

---

### Task 8: The toast

Everything from here is in the app target, which has no tests. Each task is verified with `scripts/build-app.sh` and read against the spec.

**Files:**
- Create: `App/T2SReader/Design/Toast.swift`
- Modify: `App/T2SReader/Reader/ReaderPage.swift`

**Interfaces:**
- Consumes: `PlayerModel.saveBookmark()`, `BookmarkSaveResult` (Task 5); `BookmarkEntry.rangeText` (Task 6).
- Produces: `struct Toast: View` and `ReaderPage`'s `@State private var toast: ToastContent?`.

- [ ] **Step 1: Write the component**

`App/T2SReader/Design/Toast.swift`:

```swift
// App/T2SReader/Design/Toast.swift
import SwiftUI
import T2SApp

/// What a toast says: a line, an optional quieter second line, and at most one action.
struct ToastContent: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var detail: String?
    var actionLabel: String?

    static func == (a: ToastContent, b: ToastContent) -> Bool { a.id == b.id }
}

/// A transient message over the page (2026-09-11 spec §5). `ink` with `ground` lettering — the same
/// pairing as `Pill(.selected)` — so it reads as a message rather than a surface that can be
/// scrolled or swiped. The one action sits inside it as a `soft` pill, which on `ink` is the
/// `surface` capsule the rest of the app uses.
///
/// It is not a sheet and never takes focus: the transport underneath stays live while it shows.
struct Toast: View {
    var content: ToastContent
    var onAction: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title).typeRole(.pill).foregroundStyle(Tokens.ground)
                if let detail = content.detail {
                    Text(detail).typeRole(.meta).foregroundStyle(Tokens.ground.opacity(0.65)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let label = content.actionLabel {
                Pill(label: label, glyph: "square.and.pencil", style: .soft, action: onAction)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, content.actionLabel == nil ? 16 : 8)
        .padding(.vertical, 10)
        .background(Tokens.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel([content.title, content.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isStaticText)
    }
}
```

- [ ] **Step 2: Fix the Reader's button and show the toast**

In `App/T2SReader/Reader/ReaderPage.swift`, add the state beside the other `@State`s (near line 29):

```swift
    /// The save confirmation, and the bookmark it is about so "Add a note" knows what to open.
    @State private var toast: ToastContent?
    @State private var toastBookmark: Bookmark?
    @State private var noteTarget: BookmarkEntry?
    @State private var toastTask: Task<Void, Never>?
```

Replace the whole `toolRow` bookmark branch. The current first line `let bookmarked = env.player.isBookmarkedAtPlayhead` must go — that property no longer exists:

```swift
    private var toolRow: some View {
        ZStack {
            HStack {
                icon("textformat.size", "Appearance") { showAppearance = true }
                Spacer()
                // Momentary, never filled (2026-09-11 spec §5): the old toggle's fill meant "the
                // sentence under the playhead is bookmarked", which paused looked stuck and playing
                // looked like the bookmark had been lost. Removing is done from the list.
                icon("bookmark", "Bookmark") { Task { await saveBookmark() } }
                    .accessibilityHint("Saves this place and its sentence")
            }
```

Leave the rest of `toolRow` (the voice chip) exactly as it is.

Add the action and the dismissal beside the other private methods:

```swift
    /// Saves, says so, and offers the note there and then.
    private func saveBookmark() async {
        let result = await env.player.saveBookmark()
        let chapter = env.player.chapterIndex.flatMap { i in env.player.chapters.first { $0.index == i }?.title } ?? ""
        let stamp = DurationFormatter.clock(env.player.elapsed)
        let detail = chapter.isEmpty ? stamp : "\(chapter) · \(stamp)"
        switch result {
        case .saved(let bookmark):
            toastBookmark = bookmark
            show(ToastContent(title: "Bookmark saved", detail: detail, actionLabel: "Add a note"))
        case .alreadyBookmarked(let bookmark):
            toastBookmark = bookmark
            show(ToastContent(title: "Already bookmarked", detail: detail, actionLabel: "Edit note"))
        case .failed:
            toastBookmark = nil
            show(ToastContent(title: "Could not save a bookmark", detail: nil, actionLabel: nil))
        }
    }

    /// Four seconds, restarted by a second save so two taps do not leave a stale message.
    private func show(_ content: ToastContent) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { toast = content }
        UIAccessibility.post(notification: .announcement, argument: content.title)
        toastTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { toast = nil }
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = nil }
    }
```

- [ ] **Step 3: Place it above the bottom block**

The bottom block is the `VStack` that ends with `toolRow` and carries `.padding(.horizontal, Spacing.margin)` and the `.background(alignment: .bottom)` ground mask (around line 252). Add one modifier to that `VStack`, after `.padding(.bottom, Spacing.grid)` and before `.background(alignment: .bottom)`:

```swift
        .overlay(alignment: .top) {
            if let toast {
                Toast(content: toast,
                      onAction: { openNoteEditor(); dismissToast() },
                      onDismiss: dismissToast)
                    .padding(.horizontal, Spacing.margin)
                    // The toast's bottom sits on the block's top edge, 10 pt clear, so it floats
                    // over the text and never covers the chapter row, the scrubber or the transport.
                    .alignmentGuide(.top) { d in d[.bottom] + 10 }
            }
        }
```

`openNoteEditor()` is written in Task 9. For this task, add a stub that compiles and does nothing yet:

```swift
    private func openNoteEditor() { }
```

- [ ] **Step 4: Build the app**

Run: `scripts/build-app.sh`
Expected: BUILD SUCCEEDED. If the compiler still reports `isBookmarkedAtPlayhead` or `toggleBookmark`, a reference survives in `toolRow` — Step 2 replaces the whole `HStack`, including the `let bookmarked` line above it.

- [ ] **Step 5: Commit**

```bash
git add App/T2SReader/Design/Toast.swift App/T2SReader/Reader/ReaderPage.swift
git commit -m "The bookmark button says it saved, and offers the note in the same breath"
```

---

### Task 9: The note editor

**Files:**
- Create: `App/T2SReader/Bookmarks/BookmarkNoteSheet.swift`
- Modify: `App/T2SReader/Reader/ReaderPage.swift`

**Interfaces:**
- Consumes: `BookmarkListModel.setNote(_:on:)` (Task 6), `BookmarkEntry` (Task 6), `Toast` (Task 8).
- Produces: `struct BookmarkNoteSheet: View` taking `summary: DocumentSummary`, `entry: BookmarkEntry`, `onSaved: () -> Void`.

- [ ] **Step 1: Write the sheet**

```swift
// App/T2SReader/Bookmarks/BookmarkNoteSheet.swift
import SwiftUI
import T2SApp
import T2SStore

/// Writing a note on a bookmark (2026-09-11 spec §5). The passage and its span first, so it is
/// clear what is being annotated, then the field, then `BarButton` — which exists for exactly this
/// shape, "the one action of a step, as a full-width bar pinned to a page's foot", and already
/// rides above the keyboard.
///
/// Saving blank clears the note rather than storing an empty string, so the row falls back to the
/// passage (`BookmarkEntry.headline`).
struct BookmarkNoteSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var summary: DocumentSummary
    var entry: BookmarkEntry
    var onSaved: () -> Void

    @State private var text: String = ""
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry.hasNote ? "Edit note" : "Add a note")
                .typeRole(.playerTitle).foregroundStyle(Tokens.ink)
            Text(entry.passage)
                .typeRole(.meta).foregroundStyle(Tokens.ink2)
                .lineLimit(4).multilineTextAlignment(.leading)
            Text(entry.rangeText)
                .typeRole(.mono).foregroundStyle(Tokens.ink2)
            TextEditor(text: $text)
                .typeRole(.rowTitle)
                .foregroundStyle(Tokens.ink)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 120)
                .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($focused)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write a note so you can find this again")
                            .typeRole(.rowTitle).foregroundStyle(Tokens.ink3)
                            .padding(.horizontal, 15).padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, Spacing.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom) {
            BarButton(label: "Save note", busyLabel: isSaving ? "Saving…" : nil, isEnabled: !isSaving) {
                Task {
                    isSaving = true
                    let model = BookmarkListModel(library: env.library, player: env.player)
                    await model.load(summary)
                    await model.setNote(text, on: entry)
                    isSaving = false
                    onSaved()
                    dismiss()
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.grid)
        }
        .presentationBackground(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
        .task {
            text = entry.userNote ?? ""
            focused = true
        }
    }
}
```

- [ ] **Step 2: Open it from the toast**

In `App/T2SReader/Reader/ReaderPage.swift`, replace the `openNoteEditor()` stub from Task 8:

```swift
    /// The toast's action: resolve the bookmark just saved into a display entry, then edit it.
    private func openNoteEditor() {
        guard let bookmark = toastBookmark, let timeline = env.player.coordinator.timeline else { return }
        noteTarget = BookmarkListModel.displayEntry(for: bookmark, timeline: timeline,
                                                    index: env.player.coordinator.timeIndex)
    }
```

and add the sheet beside the other `.sheet` modifiers at the end of `body`:

```swift
        .sheet(item: $noteTarget) { entry in
            if let current = env.player.current {
                BookmarkNoteSheet(summary: current, entry: entry,
                                  onSaved: { Task { await env.player.refreshBookmarks() } })
            }
        }
```

`BookmarkEntry` is already `Identifiable`, so `.sheet(item:)` works with no extra conformance.

- [ ] **Step 3: Build the app**

Run: `scripts/build-app.sh`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add App/T2SReader/Bookmarks/BookmarkNoteSheet.swift App/T2SReader/Reader/ReaderPage.swift
git commit -m "A note can be written the moment a bookmark is saved, or any time after"
```

---

### Task 10: The bookmarks sheet, the reader's words first

**Files:**
- Modify: `App/T2SReader/Bookmarks/BookmarkRow.swift`, `App/T2SReader/Bookmarks/BookmarksSheet.swift`, `App/T2SReader/Collection/BookSheet.swift:84-91`

**Interfaces:**
- Consumes: `BookmarkEntry.headline`, `.quote`, `.rangeText`, `.hasNote` (Task 6); `BookmarkNoteSheet` (Task 9).
- Produces: `BookmarkRow(entry:onJump:onEditNote:onDelete:)` — one extra closure over today's.

- [ ] **Step 1: Rewrite the row**

Replace the whole of `App/T2SReader/Bookmarks/BookmarkRow.swift`:

```swift
// App/T2SReader/Bookmarks/BookmarkRow.swift
import SwiftUI
import T2SApp

/// One bookmark (2026-09-11 spec §6). The reader's own words are the headline when there are any
/// and the book's passage drops to a quote beneath them; with no note the passage keeps the
/// headline. The list then reads as a notebook rather than a second copy of the book.
///
/// The row is tappable *and* carries a Listen pill. Two targets for one action is usually a fault;
/// it is not one here, because both do the same thing and a mis-tap therefore costs nothing.
struct BookmarkRow: View {
    var entry: BookmarkEntry
    var onJump: () -> Void
    var onEditNote: () -> Void
    var onDelete: () -> Void

    private var meta: String {
        entry.chapterTitle.isEmpty ? entry.rangeText : "\(entry.rangeText) · \(entry.chapterTitle)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meta).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
            Text(entry.headline).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                .lineLimit(4).multilineTextAlignment(.leading)
            if let quote = entry.quote {
                Text(quote).typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .lineLimit(3).multilineTextAlignment(.leading)
                    .padding(.leading, 11)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Tokens.ink3).frame(width: 2)
                    }
            }
            HStack(spacing: 8) {
                Pill(label: "Listen", glyph: "play.fill", style: .selected, action: onJump)
                Pill(label: entry.hasNote ? "Edit note" : "Add a note", glyph: "square.and.pencil",
                     style: .soft, action: onEditNote)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onJump)
        .contextMenu {
            Button(action: onEditNote) {
                Label(entry.hasNote ? "Edit note" : "Add a note", systemImage: "square.and.pencil")
            }
            Button(role: .destructive, action: onDelete) { Label("Delete bookmark", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.headline), \(meta)")
        .accessibilityHint("Plays from this bookmark")
        .accessibilityAction(named: entry.hasNote ? "Edit note" : "Add a note", onEditNote)
        .accessibilityAction(named: "Delete bookmark", onDelete)
    }
}
```

- [ ] **Step 2: Route editing from the sheet**

In `App/T2SReader/Bookmarks/BookmarksSheet.swift`, add state and pass the closure. Add beside `@State private var model`:

```swift
    @State private var editing: BookmarkEntry?
```

Change the `BookmarkRow(...)` call inside the `ForEach` to:

```swift
                            BookmarkRow(entry: entry,
                                        onJump: { Task { await model.jump(to: entry, in: summary); dismiss() } },
                                        onEditNote: { editing = entry },
                                        onDelete: { Task { await model.delete(entry) } })
```

and add the sheet to the outer `VStack`, beside `.presentationDetents`:

```swift
        .sheet(item: $editing) { entry in
            BookmarkNoteSheet(summary: summary, entry: entry,
                              onSaved: { Task { await model?.load(summary) } })
        }
```

Also update the empty-state copy on line 20, which still describes the old toggle:

```swift
                    Text("No bookmarks yet. Tap the bookmark button while listening to save your place — you can add a note to any of them.")
```

- [ ] **Step 3: Update the Book sheet's call**

In `App/T2SReader/Collection/BookSheet.swift`, add `@State private var editingBookmark: BookmarkEntry?` beside the other state, change the `BookmarkRow(...)` call to pass the new closure:

```swift
                                BookmarkRow(entry: entry, onJump: {
                                    Task {
                                        await bookmarks.jump(to: entry, in: live)
                                        dismiss()
                                        readerRoute.open(live)
                                    }
                                }, onEditNote: { editingBookmark = entry },
                                   onDelete: { Task { await bookmarks.delete(entry) } })
```

and add the sheet beside the view's other modifiers:

```swift
            .sheet(item: $editingBookmark) { entry in
                BookmarkNoteSheet(summary: live, entry: entry,
                                  onSaved: { Task { await bookmarks?.load(live) } })
            }
```

- [ ] **Step 4: Build the app**

Run: `scripts/build-app.sh`
Expected: BUILD SUCCEEDED. If `live` is not in scope where the sheet modifier was added, attach the modifier inside the same branch that already binds `live`.

- [ ] **Step 5: Commit**

```bash
git add App/T2SReader/Bookmarks/BookmarkRow.swift App/T2SReader/Bookmarks/BookmarksSheet.swift App/T2SReader/Collection/BookSheet.swift
git commit -m "The bookmarks list leads with what the reader wrote, and says how long each passage runs"
```

---

### Task 11: Stamps under the chapter rows, dots on the scrubber

**Files:**
- Modify: `App/T2SReader/Player/ChapterList.swift`, `App/T2SReader/Collection/BookSheet.swift`, `App/T2SReader/Reader/ThinScrubber.swift`, `App/T2SReader/Reader/ReaderPage.swift`

**Interfaces:**
- Consumes: `PlayerModel.bookmarksByChapter`, `PlayerModel.bookmarkFractions` (Task 7).
- Produces: `ChapterListView(chapters:current:heading:pulsing:bookmarks:onSelect:onSelectBookmark:)`; `ThinScrubber(model:segments:bookmarkFractions:onSeek:)`.

- [ ] **Step 1: Add the header toggle and the stamps**

In `App/T2SReader/Player/ChapterList.swift`, replace `ChapterListView`'s declaration and body:

```swift
/// The "Chapters" heading and its rows, the same list in the Reader's sheet and the Book sheet
/// (owner's ask, 2026-09-09: one component). `heading` is the sheet's title role or a page's
/// section header; the rows' fill runs 12 pt past the text on each side, so a caller sets its
/// horizontal padding 12 pt short of the margin. `current` wears the ring, the chapters before it
/// the check.
///
/// One bookmark button in the header opens the stamps under every chapter that has any (2026-09-11
/// spec §7) — one control rather than a per-row badge, so each row stays a single tap target.
struct ChapterListView: View {
    var chapters: [ChapterEntry]
    var current: Int?
    var heading: TypeRole
    /// The row to flash once, drawing the eye to where a scroll just landed (the book sheet's
    /// open, owner 2026-09-11) — nil the rest of the time.
    var pulsing: Int? = nil
    /// Chapter index → its bookmarks. Empty hides the header button entirely.
    var bookmarks: [Int: [BookmarkEntry]] = [:]
    var onSelect: (ChapterEntry) -> Void
    var onSelectBookmark: ((BookmarkEntry) -> Void)? = nil

    @State private var showingStamps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Chapters").typeRole(heading).foregroundStyle(Tokens.ink)
                Spacer(minLength: 12)
                if !bookmarks.isEmpty {
                    Button {
                        withAnimation(.spring(duration: 0.25)) { showingStamps.toggle() }
                    } label: {
                        CircleGlyph(systemName: showingStamps ? "bookmark.fill" : "bookmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showingStamps ? "Hide bookmark times" : "Show bookmark times")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
            ForEach(chapters) { chapter in
                ChapterRow(chapter: chapter, isCurrent: chapter.index == current,
                           isHeard: current.map { chapter.index < $0 } ?? false,
                           isPulsing: chapter.index == pulsing) { onSelect(chapter) }
                if showingStamps, let stamps = bookmarks[chapter.index] {
                    ForEach(stamps) { stamp in
                        BookmarkStampRow(entry: stamp) { onSelectBookmark?(stamp) }
                    }
                }
            }
        }
    }
}

/// One bookmark under its chapter row: an accent dot, the time, and one line of what it says.
struct BookmarkStampRow: View {
    var entry: BookmarkEntry
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(Tokens.accent).frame(width: 7, height: 7)
                Text(entry.timeText).typeRole(.mono).foregroundStyle(Tokens.ink2)
                Text(entry.headline).typeRole(.meta).foregroundStyle(Tokens.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 24)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.headline), at \(entry.timeText)")
        .accessibilityHint("Plays from this bookmark")
    }
}
```

- [ ] **Step 2: Feed it from both callers**

In the same file, `ChapterList`'s body — pass the bookmarks and the jump:

```swift
            ChapterListView(chapters: player.chapters, current: current, heading: .playerTitle,
                            bookmarks: player.bookmarksByChapter,
                            onSelect: { chapter in
                                Task { await player.seek(toChapter: chapter.index); dismiss() }
                            },
                            onSelectBookmark: { entry in
                                Task {
                                    guard let timeline = player.coordinator.timeline else { return }
                                    await player.seek(to: PositionResolver.resolve(entry.position, in: timeline))
                                    dismiss()
                                }
                            })
```

Add `import T2SCore` at the top of `ChapterList.swift` for `PositionResolver`.

In `App/T2SReader/Collection/BookSheet.swift`, add `bookmarks:` to its `ChapterListView` call, using the entries it already loads:

```swift
                    ChapterListView(chapters: chapters, current: resumeIndex, heading: .sectionHeader,
                                    pulsing: pulsingChapter,
                                    bookmarks: isCurrent ? env.player.bookmarksByChapter : [:]) { chapter in
```

The Book sheet shows a document that may not be the loaded one, and `bookmarksByChapter` only describes the loaded one — hence the `isCurrent` guard. Its own Bookmarks section below already covers the other case.

- [ ] **Step 3: Draw the dots**

In `App/T2SReader/Reader/ThinScrubber.swift`, add the input after `segments`:

```swift
    /// Bookmarks as fractions of the whole, in any order. Drawn only while the bar is pressed, and
    /// only for the chapter under the finger (2026-09-11 spec §8): at rest the bar is 6 pt and
    /// already carries the render frontier, and a dulled 11 pt-wide chapter would show a smear.
    var bookmarkFractions: [Double] = []
```

In `segment(_:width:height:rounded:fraction:)`, add the dots to the `ZStack`, after the played `Rectangle()` and before the closing brace of the `ZStack`:

```swift
            if rounded {
                ForEach(Array(dots(in: span).enumerated()), id: \.offset) { _, local in
                    Circle()
                        .fill(Tokens.accent)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Tokens.ground, lineWidth: 2.5))
                        .offset(x: width * local - 5)
                }
            }
```

`rounded` is true exactly for the pressed chapter, so it is already the "expanded, within-chapter" condition. Add the helper beside `ticks(in:)`:

```swift
    /// The bookmarks inside this chapter, as 0…1 along the chapter itself.
    private func dots(in span: Range<Double>) -> [Double] {
        let length = max(span.upperBound - span.lowerBound, .leastNonzeroMagnitude)
        return bookmarkFractions
            .filter { $0 >= span.lowerBound && $0 <= span.upperBound }
            .map { min(1, max(0, ($0 - span.lowerBound) / length)) }
    }
```

- [ ] **Step 4: Pass the fractions in**

In `App/T2SReader/Reader/ReaderPage.swift`, find the `ThinScrubber(` call in the bottom block and add the argument:

The call is at `App/T2SReader/Reader/ReaderPage.swift:214`. Add one argument and change nothing else:

```swift
                ThinScrubber(model: player.scrubber, segments: chapterSegments,
                             bookmarkFractions: player.bookmarkFractions) { fraction in
                    Task { await player.seek(fraction: fraction) }
                }
```

- [ ] **Step 5: Build the app**

Run: `scripts/build-app.sh`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run the whole package once more**

Run: `swift test`
Expected: PASS — nothing in this task touches `Sources/`, so this is a regression check on the five tasks that did.

- [ ] **Step 7: Commit**

```bash
git add App/T2SReader/Player/ChapterList.swift App/T2SReader/Collection/BookSheet.swift App/T2SReader/Reader/ThinScrubber.swift App/T2SReader/Reader/ReaderPage.swift
git commit -m "Bookmarks become visible where you navigate: dots on the pressed scrubber, stamps under the chapter rows"
```

---

## Verification before calling this done

- [ ] `swift test` — the whole root package, green.
- [ ] `scripts/build-app.sh` — BUILD SUCCEEDED.
- [ ] On the simulator, by hand: save a bookmark and confirm the toast appears and fades; tap Add a note and confirm the note saves; reopen the Bookmarks sheet and confirm the note is the headline with the passage quoted beneath; press and hold the scrubber inside a chapter with a bookmark and confirm the dot; open the chapter list and confirm the bookmark button reveals the stamps.
- [ ] Confirm the bookmark icon **never** fills, paused or playing. That was the reported fault.
- [ ] Update `docs/HANDOFF.md` with the new test counts and a line on what shipped.
