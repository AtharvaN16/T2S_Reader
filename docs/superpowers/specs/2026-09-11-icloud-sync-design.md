# iCloud sync — positions, bookmarks and the library list

_2026-09-11. Approved by the owner in conversation; built on branch `icloud-sync` (worktree
`.worktrees/icloud-sync`). The owner's Apple ID is a free personal team, which cannot carry the iCloud
entitlement; Harsh's is paid. Everything here is built and tested on the owner's Mac against a fake
provider and the CloudKit framework's own types; the entitlement, the container and the two-device run
are Harsh's (§9). Design spec §3.7.1 (a `SyncProvider` protocol, CloudKit as one implementation, no
CloudKit identifier ever a domain id) is a requirement of this design, not a preference._

## 1. What syncs, and what does not

Between devices signed into the same iCloud account, through the account's **private** CloudKit
database (each user's quota, never the developer's — design spec §1):

- **The library list**: each document's title, author, source type, source URL, added date and
  finished flag — but **not its file**. A book known from another device appears as a placeholder
  (§5).
- **The reading position** of each document, with when and on which device it was saved. A remote
  position is *offered*, never applied (§4).
- **Bookmarks**: position, note, created and updated times; deletions travel as markers.
- **Deletions of documents**, when the reader chose "everywhere" (§4).

Not in v1: rendered audio (cache, never truth), chapters and timelines (derived on each device),
per-document voice overrides, the pronunciation dictionary, cloud-voice keys (Keychain, never leaves
the device), sharing between people, silent push. Each is a later record or field on the same
records.

## 2. Identity: the content key

Two phones importing the same book create two local `UUID`s (design spec §3.7.1 keeps them client
generated). Sync meets on a **content key**, computed at import and stored on the document:

| source | key | note |
|---|---|---|
| EPUB, PDF | `sha256:<hex of the file bytes>` | hashed while the import copies the file into the container |
| article | `url:<canonical URL>` | scheme and host lowercased, fragment dropped, `utm_*`/`fbclid`/`gclid` query items dropped, trailing slash kept as given |

`ContentKey` lives in `T2SCore` (`Sources/T2SCore/Sync/ContentKey.swift`), pure. The document row
gains `contentKey: String?`; rows that predate this (V2 stores) are backfilled when sync is first
turned on: the file under `Documents/<uuid>/source.*` is hashed, an article's `sourceURL`
canonicalised; a row with neither stays unsynced and is logged once.

The CloudKit record name is derived from the key (`doc-` + sha256 of the key string, so URLs of any
length and character set fit CloudKit's 255-ASCII limit); the key itself is a field. A bookmark's
record name is `bm-<uuid>`.

## 3. Records and the domain types

Domain types, `T2SCore`, `Codable`, `Sendable`, no CloudKit:

```swift
public struct SyncedDocument: Sendable, Codable, Hashable {
    public var contentKey: String
    public var title: String
    public var author: String?
    public var sourceType: SourceType
    public var sourceURL: URL?
    public var addedAt: Date
    public var isFinished: Bool
    public var resume: SyncedPosition?        // position + savedAt + deviceName
    public var updatedAt: Date                // the record's own clock, for the merge
    public var deletedAt: Date?               // a marker; the record stays
}
public struct SyncedBookmark: Sendable, Codable, Hashable {
    public var id: UUID
    public var contentKey: String
    public var position: Position
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
}
public enum SyncRecord: Sendable, Hashable { case document(SyncedDocument), bookmark(SyncedBookmark) }
```

The provider:

```swift
public protocol SyncProvider: Sendable {
    func accountStatus() async -> SyncAccountStatus          // available, noAccount, restricted, unavailable(reason)
    func changes(since token: SyncToken?) async throws -> SyncChanges   // records + deletions + new token; `tokenExpired` when the zone forgot it
    func push(_ records: [SyncRecord]) async throws -> [SyncPushResult] // per record: saved | conflict(server: SyncRecord)
}
```

`CloudKitSyncProvider` (`Sources/T2SSync/CloudKit/…`) is the one file that imports CloudKit: one
custom zone `t2s` in the private database; `CKFetchRecordZoneChangesOperation` with the zone's
`CKServerChangeToken` behind `SyncToken`; `CKModifyRecordsOperation` with `.ifServerRecordUnchanged`,
a `serverRecordChanged` error mapped to `.conflict(server:)`. Record types `Document` and `Bookmark`
with the fields above (`position` and `resume` as JSON strings — CloudKit's schema must not shape the
domain, design spec §3.7.1). The mapping is two pure functions per type, `CKRecord ↔ domain`.

`FakeSyncProvider` (in `T2SSync`, not the tests, so the app can run against it under a launch
argument): an in-memory zone with a monotonically increasing token; `changes(since:)` returns what
was pushed after the token; a flag makes the next call throw `tokenExpired`; conflicts are simulated
by pushing a newer record from "the other device" first.

## 4. The merge

`SyncEngine` (`Sources/T2SSync/SyncEngine.swift`, an actor) owns the cycle and the rules. It talks
to the store through a small protocol, `SyncStore`, that `LibraryStore` implements (§6): read and
write synced fields, mark dirty, list dirty.

**One rule for records:** the newer `updatedAt` wins, field by field is not attempted; a `deletedAt`
beats any record older than it. Timestamps are device clocks; a skewed clock can make one device's
edits lose for as long as the skew — accepted for v1 and not surfaced anywhere in the UI.

**Positions are offered, not applied.** When the pulled document's `resume.savedAt` is newer than
the local position's save time *and* the position differs, the engine stores it on the row as
`pendingRemotePosition` (position, saved-at, device name) and leaves the local position alone. The
Reader shows one line above its controls — "Continue from iPhone · Chapter 7, 12:40" (the chapter
and time come from `PositionResolver.resolve(_:in:)` against the local timeline) — with **Jump**;
Jump seeks there and clears the pending position; dismissing (the ✕, or playing on for ten seconds)
clears it and keeps the local place. The next local position save is the newest record, so the
*other* device gets the same offer in turn. Nothing ever moves the playhead unasked.

**Bookmarks** union by id: an unknown id is inserted, a known one takes the newer `updatedAt`, a
marker newer than the local edit deletes it locally. Local deletions write the marker; the row is
removed locally at once.

**Documents:** title and author take the newer `updatedAt` (they rarely change); `isFinished` the
newer. A pulled document with no local row of that content key becomes a placeholder (§5). A pulled
marker removes the local document — files, chapters, audio, bookmarks — through the existing
`Library.delete`; that is what "delete everywhere" means, and it is only written when the reader
chose it: with sync on, the delete confirmation offers **Remove from this device** (no marker; the
record stays, so the book will come back as a placeholder — said in the sheet) and **Remove
everywhere**.

**Local edits mark the row dirty**; the engine pushes dirty rows and clears the flag on `.saved`. A
`.conflict(server:)` is merged by the same rule and pushed once more; a second conflict leaves the
row dirty for the next cycle.

## 5. Placeholders: the list without the file

A pulled document with no local match inserts a row with the synced fields, no chapters, and
`isPlaceholder = true`. In the Collection it shows with an "on iPhone" line (the device name from
its position record, else "on another device"); play is disabled. Tapping:

- an **article**: the app fetches the URL through the existing article import
  (`Library.importArticle`) *into that row* — the importer takes an optional placeholder id and fills
  it rather than creating a new document, so the content key, position and bookmarks stay attached;
- an **EPUB or PDF**: the Files picker; the picked file is hashed first and accepted only when the
  hash equals the placeholder's key ("That's a different file" otherwise), then imported into the row
  the same way.

Any ordinary import whose content key matches a placeholder fills it, silently — the hash is
computed on every import anyway. Bookmarks and the pending position of a placeholder are stored
against its row and become live the moment the file lands, since a `Position` is anchored in the
source, not in a runtime index (design spec §3.2).

## 6. Storage

`LibrarySchemaV3` (lightweight migration from V2; `LibraryMigrationPlan.stages` gains one entry):

- `StoredDocument`: `contentKey: String?`, `isPlaceholder: Bool = false`, `syncUpdatedAt: Date?`
  (the record's `updatedAt` as last pulled or pushed), `isDirty: Bool = false`,
  `pendingRemoteHref/Progression/CharOffset/CSSSelector`, `pendingRemoteSavedAt: Date?`,
  `pendingRemoteDevice: String?`, `resumeSavedAt: Date?` (when the local position was saved — the
  row's `updatedAt` moves for other reasons).
- `StoredBookmark`: `updatedAt: Date`, `isDirty: Bool = false`, `syncedAt: Date?`.
- A new `StoredTombstone` (kind, key, deletedAt) so local deletions survive until pushed.
- `SyncState` in `UserDefaults`: the token (`Data`), `enabled`, `deviceName`.

`LibraryStore` implements `SyncStore`; every existing write path that changes a synced field
(`savePosition`, `add(bookmark)`, `deleteBookmark`, finish, delete) sets `isDirty` (or writes a
tombstone) — one line each, no new write paths.

## 7. The cycle and its triggers

`SyncEngine.sync()` — serialised, coalesced (a call while one runs schedules one more):

1. `changes(since: token)` → apply (§4) → save the new token. `tokenExpired` → token nil → the
   same call again, a full pull; the merge rule makes a full pull idempotent.
2. push every dirty row and tombstone → clear flags on `.saved`, re-merge on `.conflict`.

Triggers: the app entering the foreground; two seconds after any dirty mark (debounced); the toggle
turning on (a backfill of content keys first, then a full pull and push). Off: nothing runs; the
token is forgotten so that a later "on" pulls everything.

Errors: network → logged, next trigger; `quotaExceeded` → a line under the toggle ("iCloud is full")
until a cycle succeeds; account gone (`noAccount`, `restricted`) → the toggle turns itself off with the
reason; zone missing → created once. Logging: `os_log`, subsystem `com.t2s.reader`, category `sync`,
one line per cycle with counts, one per error. Never the timing log — that is the engine's.

## 8. The app: Settings, the Reader, the Collection, signing

**Settings.** The row keeps its place and name, "Sync positions and bookmarks". Enabled only when
the build carries a container (Info.plist `T2SICloudContainer` non-empty) **and** `accountStatus ==
.available`; otherwise off and disabled with the reason as its subtitle: "Needs an iCloud-enabled
build" / "Sign in to iCloud in Settings" / "iCloud is not available". On: the first cycle runs at
once; a small "Syncing…" then "Synced just now" subtitle, and the last error if any.

**The Reader**: the one-line offer (§4). **The Collection**: the placeholder line and the tap
actions (§5); the delete sheet's two choices when sync is on (§4).

**Signing, per Mac** (the pattern `Local.xcconfig` already carries for the bundle id, the app group
and the team): `T2S_ICLOUD_CONTAINER` (empty by default; Harsh's `iCloud.com.antarlabs.t2sreader`),
passed to the Info.plist as `T2SICloudContainer`; and `T2S_ENTITLEMENTS`, a project-level setting the
target xcconfig overrides, that `CODE_SIGN_ENTITLEMENTS` reads — `T2SReader/T2SReader.entitlements`
(app groups only, committed, what xcodegen generated until now) or
`T2SReader/T2SReader.iCloud.entitlements` (the same plus `com.apple.developer.icloud-services:
[CloudKit]` and `com.apple.developer.icloud-container-identifiers: [$(T2S_ICLOUD_CONTAINER)]`). The
owner's build never mentions iCloud and keeps signing on the free team; the composition creates
`CloudKitSyncProvider` only when the plist key is non-empty, else the toggle's disabled state.
`-t2s.sync fake` as a launch argument substitutes `FakeSyncProvider` for a simulator run of the UI.

## 9. Harsh's part, in order

1. `App/Local.xcconfig`: `T2S_ICLOUD_CONTAINER = iCloud.<his bundle id>` and `T2S_ENTITLEMENTS =
   T2SReader/T2SReader.iCloud.entitlements`; `xcodegen generate`; in Xcode's Signing & Capabilities
   the iCloud → CloudKit capability with that container under his team (Xcode registers it).
2. Run once on a device signed into iCloud: the first save creates the zone and the two record
   types in CloudKit's **development** environment. Check the fields in CloudKit Dashboard; add the
   `updatedAt` and `deletedAt` queryable indexes if the fetch needs them (it should not — zone
   changes need none).
3. Two devices (a phone and a simulator signed into the same account will do): import a book on one;
   the placeholder on the other; fill it by import; read on one, the offer on the other; a bookmark
   each way; delete everywhere; airplane mode on one for a few edits, then back.
4. Before any TestFlight: **Deploy Schema to Production** in the Dashboard, or production users see
   an empty zone and every push fails.

## 10. Tests — the ones that earn their place

- `SyncEngineTests` (`Tests/T2SSyncTests`), each a scenario on two engines over one
  `FakeSyncProvider` and two in-memory `SyncStore`s: (1) A saves a position → B has it pending, its
  playhead unmoved; B accepts → moved, and A gets no offer back; (2) A edits a bookmark's note, B
  deletes it later → gone on both; (3) A's document appears on B as a placeholder; B imports the
  matching hash → filled, A's position offered; (4) delete everywhere → B removes; (5) the token
  expires → a full pull leaves the state identical.
- `CloudKitRecordMappingTests`: one round trip per record type through real `CKRecord`s (no
  account needed on macOS).
- `ContentKeyTests`: a five-row table for URL canonicalisation; the file hash of a fixture.
- `LibraryStoreMigrationTests`: V2 rows open under V3 with the new fields defaulted.
- No UI tests. The offer, the placeholder line and the delete sheet are checked by the simulator
  build with `-t2s.sync fake` and by Harsh's run.

## 11. Rollback and risk

The toggle is off by default and the provider is nil without a container: shipping this with an
empty `T2S_ICLOUD_CONTAINER` is exactly today's app plus a V3 store migration (additive, lightweight).
Risks: a bad merge duplicating bookmarks (the id union prevents it), a placeholder filled with the
wrong file (the hash check prevents it), a clock far off skewing which edit wins (accepted, v1).
