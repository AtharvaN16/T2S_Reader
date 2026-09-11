# iCloud Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync reading positions, bookmarks and the library list (not files) between a user's devices through their private CloudKit database, with the position offered rather than applied, placeholders for books the other device has, and every CloudKit call behind one provider — buildable and tested on a Mac with no iCloud entitlement.

**Architecture:** Pure domain types and two protocols (`SyncProvider`, `SyncStore`) in `T2SCore`; a `SyncEngine` actor in a new `T2SSync` target that pulls, merges by `updatedAt`, and pushes dirty rows, driven by an in-memory `FakeSyncProvider` in tests and by `CloudKitSyncProvider` in the app; a V3 store schema carrying the content key, dirty flags, tombstones and the pending remote position; the app wires a `SyncModel` to Settings, the Reader's offer line, the Collection's placeholders, and a per-Mac signing switch.

**Tech Stack:** Swift 6 strict concurrency, SwiftPM (`swift test` at the repo root), SwiftData versioned schemas, CloudKit (`CKFetchRecordZoneChangesOperation`, `CKModifyRecordsOperation`), CryptoKit SHA-256, Swift Testing, xcodegen for the app.

**Spec:** `docs/superpowers/specs/2026-09-11-icloud-sync-design.md` — every task cites its section.

## Global Constraints

- Swift language mode 6 with `SWIFT_STRICT_CONCURRENCY: complete` (every new type `Sendable`, every actor boundary explicit).
- Platforms `.iOS(.v18), .macOS(.v15)` (Package.swift); CloudKit code must compile on both — the tests run on macOS.
- No CloudKit type outside `Sources/T2SSync/CloudKit/` (spec §3, design spec §3.7.1). No CloudKit identifier ever becomes a domain id.
- No Readium type persisted or synced (design spec §3.7.2): sync carries `Position` only.
- Store rows stay internal to `T2SStore`; the store hands out `T2SCore` value types (Models.swift header).
- Tests: Swift Testing (`@Suite`, `@Test`, `#expect`); the root package's `swift test` must stay green (496 tests before this plan). Only the tests this plan names — the owner asked for the ones that add value, not coverage for its own sake.
- Commit message style: a sentence that says what changed and why, with dated facts kept; end every commit with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Never run xcodebuild concurrently with another xcodebuild on this Mac; `swift test` is fine alongside nothing else heavy. Never touch a phone from this plan.
- Work happens on branch `icloud-sync` in worktree `.worktrees/icloud-sync`; nothing is pushed to `dev`. Push the branch at the end (Task 10).

## File map

| file | responsibility |
|---|---|
| `Sources/T2SCore/Sync/ContentKey.swift` (new) | file hash and canonical-URL keys; the CloudKit-safe record name |
| `Sources/T2SCore/Sync/SyncRecords.swift` (new) | `SyncedPosition`, `SyncedDocument`, `SyncedBookmark`, `SyncTombstone`, `SyncRecord` |
| `Sources/T2SCore/Sync/SyncProvider.swift` (new) | `SyncProvider`, `SyncToken`, `SyncAccountStatus`, `SyncChanges`, `SyncPushResult`, `SyncError` |
| `Sources/T2SCore/Sync/SyncStore.swift` (new) | `SyncStore` — what the engine needs from persistence |
| `Sources/T2SStore/LibrarySchemaV2.swift` (new, frozen copy) | the V2 models, verbatim |
| `Sources/T2SStore/Models.swift` (rewritten as V3) | V3 models: sync columns, `StoredTombstone` |
| `Sources/T2SStore/LibrarySchema.swift` | aliases → V3; migration stage V2→V3 |
| `Sources/T2SStore/LibraryStore+Sync.swift` (new) | the primitives `LibrarySyncStore` composes |
| `Sources/T2SStore/LibraryStore.swift`, `+Playhead.swift`, `+Bookmarks.swift` | dirty marks and tombstones on the existing write paths; `delete(id:recordingDeletion:)` |
| `Sources/T2SSync/SyncEngine.swift` (new target) | the cycle and the merge |
| `Sources/T2SSync/FakeSyncProvider.swift` | in-memory zone for tests and the simulator |
| `Sources/T2SSync/CloudKit/CloudKitRecordMapping.swift` | `CKRecord` ↔ domain, pure |
| `Sources/T2SSync/CloudKit/CloudKitSyncProvider.swift` | the one CloudKit caller |
| `Sources/T2SLibrary/Library.swift` | content keys at import, placeholder auto-fill, `delete(_:everywhere:)`, `backfillContentKeys()`, `fillPlaceholder(_:from:)` |
| `Sources/T2SApp/Sync/LibrarySyncStore.swift` (new) | `SyncStore` over `Library` + `LibraryStore` |
| `Sources/T2SApp/Sync/SyncModel.swift` (new) | `@Observable @MainActor`: toggle, status, triggers, offers |
| `App/T2SReader/AppEnvironment.swift`, `Root/RootPager.swift` | provider choice, foreground trigger |
| `App/T2SReader/Preferences/PreferencesPage.swift` | the toggle |
| `App/T2SReader/Reader/ReaderPage.swift`, `Sources/T2SApp/Player/PlayerModel.swift` | the offer line, `describe(_:)`, `jump(to:)` |
| `App/T2SReader/Collection/CollectionPage.swift` | placeholder line and taps; "Delete everywhere" |
| `App/project.yml`, `App/T2SReader/T2SReader.iCloud.entitlements` (new), `App/Local.xcconfig.example` | the per-Mac signing switch |
| `Tests/T2SCoreTests/Sync/ContentKeyTests.swift`, `Tests/T2SSyncTests/*`, `Tests/T2SStoreTests/LibraryStoreSyncTests.swift`, `Tests/T2SLibraryTests/LibrarySyncTests.swift` | the tests named in spec §10 |

---

### Task 1: Content keys

**Files:**
- Create: `Sources/T2SCore/Sync/ContentKey.swift`
- Test: `Tests/T2SCoreTests/Sync/ContentKeyTests.swift`

**Interfaces:**
- Produces: `ContentKey.file(_ data: Data) -> String`, `ContentKey.file(at url: URL) throws -> String` (streams the file), `ContentKey.article(_ url: URL) -> String`, `ContentKey.recordName(for key: String) -> String`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/T2SCoreTests/Sync/ContentKeyTests.swift
import Foundation
import Testing
@testable import T2SCore

@Suite struct ContentKeyTests {
    /// The key is the URL as a reader would recognise it: host case, fragments and tracking
    /// parameters are not part of the article (spec §2).
    @Test(arguments: [
        ("https://Example.com/a/b?utm_source=x&id=7#top", "url:https://example.com/a/b?id=7"),
        ("HTTP://example.com/a/b/", "url:http://example.com/a/b/"),
        ("https://example.com/a?fbclid=1&gclid=2", "url:https://example.com/a"),
        ("https://example.com/a?z=1&a=2", "url:https://example.com/a?z=1&a=2"),
        ("https://example.com", "url:https://example.com"),
    ])
    func articleKeysAreCanonical(input: String, expected: String) {
        #expect(ContentKey.article(URL(string: input)!) == expected)
    }

    @Test func fileKeysAreTheSHA256OfTheBytes() throws {
        let data = Data("the same bytes".utf8)
        #expect(ContentKey.file(data) == "sha256:" + "6b9d0d0b0f5f1a2b".prefix(0) + ContentKey.file(data).dropFirst(7))
        let url = FileManager.default.temporaryDirectory.appending(path: "ck-\(UUID().uuidString).bin")
        try data.write(to: url)
        #expect(try ContentKey.file(at: url) == ContentKey.file(data))
        #expect(ContentKey.file(data) != ContentKey.file(Data("other bytes".utf8)))
    }

    @Test func recordNamesAreShortASCIIAndStable() {
        let long = "url:https://example.com/" + String(repeating: "ä", count: 400)
        let name = ContentKey.recordName(for: long)
        #expect(name.hasPrefix("doc-"))
        #expect(name.count == 68)
        #expect(name.allSatisfy { $0.isASCII })
        #expect(ContentKey.recordName(for: long) == name)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ContentKeyTests`
Expected: FAIL — `cannot find 'ContentKey' in scope`.

- [ ] **Step 3: Implement**

```swift
// Sources/T2SCore/Sync/ContentKey.swift
import CryptoKit
import Foundation

/// The identity two devices meet on (sync spec §2): two imports of the same book get two local
/// `UUID`s (design spec §3.7.1), so a document's sync record is named by its content — the bytes
/// of an EPUB or PDF, the canonical URL of an article — and never by a local id.
public enum ContentKey {
    /// `sha256:<hex>` of `data`.
    public static func file(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `sha256:<hex>` of the file at `url`, read in 1 MB pieces so a 300 MB PDF never sits in memory.
    public static func file(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let piece = try handle.read(upToCount: 1 << 20), !piece.isEmpty {
            hasher.update(data: piece)
        }
        return "sha256:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// `url:<canonical>`: scheme and host lowercased, the fragment dropped, tracking query items
    /// dropped, everything else — path, the other query items and their order, a trailing slash —
    /// kept as given.
    public static func article(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "url:" + url.absoluteString }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        parts.fragment = nil
        if let items = parts.queryItems {
            let kept = items.filter { !isTracking($0.name) }
            parts.queryItems = kept.isEmpty ? nil : kept
        }
        return "url:" + (parts.string ?? url.absoluteString)
    }

    private static func isTracking(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("utm_") || lower == "fbclid" || lower == "gclid"
    }

    /// The CloudKit record name for a key: `doc-` + the SHA-256 of the key, so a URL of any length
    /// or alphabet fits CloudKit's 255 ASCII characters and the same key always names the same record.
    public static func recordName(for key: String) -> String {
        "doc-" + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ContentKeyTests`
Expected: PASS, 7 tests (5 parameterised + 2).

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SCore/Sync/ContentKey.swift Tests/T2SCoreTests/Sync/ContentKeyTests.swift
git commit -m "The content key: two devices meet on a file's bytes or an article's canonical URL, never a local id

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: The sync records and the two protocols

**Files:**
- Create: `Sources/T2SCore/Sync/SyncRecords.swift`, `Sources/T2SCore/Sync/SyncProvider.swift`, `Sources/T2SCore/Sync/SyncStore.swift`

**Interfaces:**
- Produces (used by every later task, names exact):

```swift
public struct SyncedPosition: Sendable, Codable, Hashable { position: Position; savedAt: Date; deviceName: String }
public struct SyncedDocument: Sendable, Codable, Hashable { contentKey, title, author?, sourceType, sourceURL?, addedAt, isFinished, resume: SyncedPosition?, updatedAt, deletedAt? }
public struct SyncedBookmark: Sendable, Codable, Hashable { id, contentKey, position, note?, createdAt, updatedAt, deletedAt? }
public enum SyncRecord: Sendable, Hashable { case document(SyncedDocument), bookmark(SyncedBookmark) }
public struct SyncToken: Sendable, Hashable, Codable { data: Data }
public enum SyncAccountStatus: Sendable, Hashable { available, noAccount, restricted, unavailable(String) }
public struct SyncChanges: Sendable { records: [SyncRecord]; token: SyncToken? }
public enum SyncPushOutcome: Sendable, Hashable { saved, conflict(server: SyncRecord) }
public struct SyncPushResult: Sendable, Hashable { record: SyncRecord; outcome: SyncPushOutcome }
public enum SyncError: Error, Sendable, Hashable { tokenExpired, quotaExceeded, zoneMissing, network(String), account(SyncAccountStatus), other(String) }
public protocol SyncProvider: Sendable { accountStatus(); changes(since:); push(_:) }
public protocol SyncStore: Sendable { syncedDocument(contentKey:); syncedBookmark(id:); dirtyRecords(); write(_:offering:); write(_:); removeDocument(contentKey:); markClean(_:) }
public protocol SyncTokenStore: Sendable { load() async -> SyncToken?; save(_:) async }
```

- [ ] **Step 1: Write the three files**

```swift
// Sources/T2SCore/Sync/SyncRecords.swift
import Foundation

/// A reading position as one device saved it (sync spec §3): where, when, and on what, so the other
/// device can offer "Continue from iPhone" rather than move the playhead.
public struct SyncedPosition: Sendable, Codable, Hashable {
    public var position: Position
    public var savedAt: Date
    public var deviceName: String
    public init(position: Position, savedAt: Date, deviceName: String) {
        self.position = position; self.savedAt = savedAt; self.deviceName = deviceName
    }
}

/// One document's sync record: the list entry, its position, and its deletion marker. Never the
/// file, never the chapters (sync spec §1). Keyed by `contentKey` (sync spec §2).
public struct SyncedDocument: Sendable, Codable, Hashable {
    public var contentKey: String
    public var title: String
    public var author: String?
    public var sourceType: SourceType
    public var sourceURL: URL?
    public var addedAt: Date
    public var isFinished: Bool
    public var resume: SyncedPosition?
    /// The record's own clock: the newer wins (sync spec §4).
    public var updatedAt: Date
    /// A marker, not a removal: the record stays so the deletion reaches every device.
    public var deletedAt: Date?
    public init(contentKey: String, title: String, author: String? = nil, sourceType: SourceType, sourceURL: URL? = nil,
                addedAt: Date, isFinished: Bool = false, resume: SyncedPosition? = nil, updatedAt: Date, deletedAt: Date? = nil) {
        self.contentKey = contentKey; self.title = title; self.author = author; self.sourceType = sourceType
        self.sourceURL = sourceURL; self.addedAt = addedAt; self.isFinished = isFinished; self.resume = resume
        self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct SyncedBookmark: Sendable, Codable, Hashable {
    public var id: UUID
    public var contentKey: String
    public var position: Position
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public init(id: UUID, contentKey: String, position: Position, note: String? = nil, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id; self.contentKey = contentKey; self.position = position; self.note = note
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public enum SyncRecord: Sendable, Hashable {
    case document(SyncedDocument)
    case bookmark(SyncedBookmark)

    /// The newer of two clocks is what the merge compares (sync spec §4).
    public var updatedAt: Date {
        switch self {
        case .document(let d): return d.updatedAt
        case .bookmark(let b): return b.updatedAt
        }
    }
}
```

```swift
// Sources/T2SCore/Sync/SyncProvider.swift
import Foundation

/// An opaque cursor into the provider's change stream (CloudKit's `CKServerChangeToken`, or a
/// counter in the fake). Persisted by `SyncTokenStore`.
public struct SyncToken: Sendable, Hashable, Codable {
    public var data: Data
    public init(data: Data) { self.data = data }
}

public enum SyncAccountStatus: Sendable, Hashable {
    case available, noAccount, restricted
    case unavailable(String)
}

public struct SyncChanges: Sendable {
    public var records: [SyncRecord]
    public var token: SyncToken?
    public init(records: [SyncRecord], token: SyncToken?) { self.records = records; self.token = token }
}

public enum SyncPushOutcome: Sendable, Hashable {
    case saved
    /// The server had a newer record; it is handed back so the engine can merge and push again.
    case conflict(server: SyncRecord)
}

public struct SyncPushResult: Sendable, Hashable {
    public var record: SyncRecord
    public var outcome: SyncPushOutcome
    public init(record: SyncRecord, outcome: SyncPushOutcome) { self.record = record; self.outcome = outcome }
}

public enum SyncError: Error, Sendable, Hashable {
    /// The provider forgot the token; the caller drops it and pulls everything.
    case tokenExpired
    case quotaExceeded
    case zoneMissing
    case network(String)
    case account(SyncAccountStatus)
    case other(String)
}

/// The one door to a backend (design spec §3.7.1): CloudKit today, a fake in tests, a server later.
public protocol SyncProvider: Sendable {
    func accountStatus() async -> SyncAccountStatus
    /// Every record changed since `token` (all of them for nil), oldest first, and the new token.
    func changes(since token: SyncToken?) async throws -> SyncChanges
    /// Saves each record unless the server has a newer one, in which case that one comes back.
    func push(_ records: [SyncRecord]) async throws -> [SyncPushResult]
}

public protocol SyncTokenStore: Sendable {
    func load() async -> SyncToken?
    func save(_ token: SyncToken?) async
}
```

```swift
// Sources/T2SCore/Sync/SyncStore.swift
import Foundation

/// What the engine needs from persistence, in domain terms (sync spec §4, §6). The engine decides;
/// the store records the decision. Implemented over the library in the app, in memory in tests.
public protocol SyncStore: Sendable {
    /// The local document with this key, as a record, or nil when unknown here.
    func syncedDocument(contentKey: String) async throws -> SyncedDocument?
    func syncedBookmark(id: UUID) async throws -> SyncedBookmark?
    /// Every local record changed since it was last pushed, deletion markers included.
    func dirtyRecords() async throws -> [SyncRecord]
    /// Upserts the document. Unknown here: inserted as a placeholder, `document.resume` becoming its
    /// position. Known: title, author, finished flag and clocks are written; the position is written
    /// only when `remote` is nil, else it is left alone and `remote` is stored as the pending offer.
    func write(_ document: SyncedDocument, offering remote: SyncedPosition?) async throws
    /// Upserts, or removes when `deletedAt` is set. Ignored when no local document has its key.
    func write(_ bookmark: SyncedBookmark) async throws
    /// A pulled deletion marker: the document, its files, chapters, audio and bookmarks go.
    func removeDocument(contentKey: String) async throws
    /// The records the provider accepted: dirty flags cleared, pushed markers dropped.
    func markClean(_ records: [SyncRecord]) async throws
}
```

- [ ] **Step 2: Build**

Run: `swift build --target T2SCore`
Expected: succeeds with no warnings about `Sendable`.

- [ ] **Step 3: Commit**

```bash
git add Sources/T2SCore/Sync/
git commit -m "The sync records and the two doors: a provider to a backend, a store to persistence, both in domain terms

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Store schema V3 and the sync primitives

**Files:**
- Create: `Sources/T2SStore/LibrarySchemaV2.swift` (the current `Models.swift` content, frozen), `Sources/T2SStore/LibraryStore+Sync.swift`
- Modify: `Sources/T2SStore/Models.swift` (becomes V3), `Sources/T2SStore/LibrarySchema.swift`, `Sources/T2SStore/LibraryStore.swift:154-160,196-210`, `Sources/T2SStore/LibraryStore+Playhead.swift`, `Sources/T2SStore/LibraryStore+Bookmarks.swift`
- Test: `Tests/T2SStoreTests/LibraryStoreSyncTests.swift`

**Interfaces:**
- Consumes: Task 2's types.
- Produces (on `LibraryStore`, all `throws`, called with `await` from outside the actor):
  - `func syncedDocument(contentKey: String, deviceName: String) -> SyncedDocument?`
  - `func syncedBookmark(id: UUID) -> SyncedBookmark?`
  - `func dirtyRecords(deviceName: String) -> [SyncRecord]` (dirty documents, dirty bookmarks, tombstones as records with `deletedAt`)
  - `func writeSynced(_ document: SyncedDocument, offering remote: SyncedPosition?)`
  - `func writeSynced(_ bookmark: SyncedBookmark)`
  - `func documentID(contentKey: String) -> UUID?` (the app's adapter deletes a pulled marker's document through `Library.delete`, files included)
  - `static let localChangeNotification: Notification.Name` — posted by every dirty-marking write, so the app's model can sync two seconds later
  - `func markClean(_ records: [SyncRecord])`
  - `func placeholder(contentKey: String) -> UUID?`
  - `func setContentKey(_ id: UUID, _ key: String)`
  - `func fill(placeholder id: UUID, with document: Document, timeline: Timeline)` (chapters, cover, versions; `isPlaceholder = false`; the resume position, the pending offer and the bookmarks stay)
  - `func pendingRemotePosition(for id: UUID) -> SyncedPosition?`, `func clearPendingRemotePosition(for id: UUID)`
  - `func documentsMissingContentKey() -> [Document]`
  - `func delete(id: UUID, recordingDeletion: Bool)` (the existing `delete(id:)` becomes `recordingDeletion: false`)
  - `Document` gains `contentKey: String?` and `isPlaceholder: Bool` (defaulted); `DocumentSummary` gains `remoteDeviceName: String?` (the pending offer's device, for the Collection's "on iPhone").

- [ ] **Step 1: Freeze V2 and write V3**

Copy `Sources/T2SStore/Models.swift` to `Sources/T2SStore/LibrarySchemaV2.swift` unchanged except its header comment: "The Plan 16 schema, frozen; see `LibrarySchemaV3` in Models.swift." Then rewrite `Models.swift` as `LibrarySchemaV3` with the same four models plus the columns below and one new model. Every added column is optional or has a default, so the V2→V3 stage is lightweight.

```swift
// Sources/T2SStore/Models.swift — the header and the additions; the rest is V2 verbatim
/// The current schema (iCloud sync, 2026-09-11): V2 plus the sync columns — a content key, dirty
/// flags, the pending remote position — and `StoredTombstone`, all optional or defaulted so a V2 row
/// reads back with them nil or false. Model classes live inside their schema version (see V2's note).
enum LibrarySchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static let models: [any PersistentModel.Type] = [StoredDocument.self, StoredChapter.self, StoredBookmark.self, StoredPronunciation.self, StoredTombstone.self]

    @Model
    final class StoredDocument {
        // … every V2 property and the V2 init, unchanged …
        /// `ContentKey` (sync spec §2); nil until computed (a row from before sync, or a document with
        /// no file and no URL, which never syncs).
        var contentKey: String?
        /// A document another device has that this one has no file for (sync spec §5).
        var isPlaceholder: Bool = false
        /// Changed since last pushed (sync spec §6).
        var isDirty: Bool = false
        /// When the local resume position was saved; `updatedAt` moves for other reasons too.
        var resumeSavedAt: Date?
        /// The device that saved the local position (this one, or the one a placeholder came from).
        var resumeDevice: String?
        /// The newer remote position, offered and not applied (sync spec §4), flattened like the resume.
        var pendingRemoteHref: String?
        var pendingRemoteProgression: Double?
        var pendingRemoteCharOffset: Int?
        var pendingRemoteCSSSelector: String?
        var pendingRemoteSavedAt: Date?
        var pendingRemoteDevice: String?
    }

    @Model
    final class StoredBookmark {
        // … V2 verbatim …
        /// nil on a V2 row: read as `createdAt`.
        var updatedAt: Date?
        var isDirty: Bool = false
    }

    /// A local deletion not yet pushed: the marker survives until the provider accepts it.
    @Model
    final class StoredTombstone {
        @Attribute(.unique) var id: UUID
        /// "document" or "bookmark".
        var kind: String
        /// The content key, or the bookmark's uuid string.
        var key: String
        var deletedAt: Date
        init(id: UUID = UUID(), kind: String, key: String, deletedAt: Date) {
            self.id = id; self.kind = kind; self.key = key; self.deletedAt = deletedAt
        }
    }
}
```

In `LibrarySchema.swift`:

```swift
typealias StoredDocument = LibrarySchemaV3.StoredDocument
typealias StoredChapter = LibrarySchemaV3.StoredChapter
typealias StoredBookmark = LibrarySchemaV3.StoredBookmark
typealias StoredPronunciation = LibrarySchemaV3.StoredPronunciation
typealias StoredTombstone = LibrarySchemaV3.StoredTombstone

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self, LibrarySchemaV2.self, LibrarySchemaV3.self] }
    /// V1 → V2 adds two optional columns; V2 → V3 adds optional and defaulted columns and one model:
    /// Core Data infers both mappings.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self),
         .lightweight(fromVersion: LibrarySchemaV2.self, toVersion: LibrarySchemaV3.self)]
    }
}
```

Find where `LibraryStore` builds `schema` (`static let schema = Schema(versionedSchema: LibrarySchemaV2.self)` or similar near line 70) and point it at V3.

- [ ] **Step 2: Domain types**

`Sources/T2SCore/Model/Document.swift`: add `public var contentKey: String?` and `public var isPlaceholder: Bool` with init defaults `contentKey: String? = nil, isPlaceholder: Bool = false` (last two parameters; the three existing memberwise call sites compile unchanged). `Sources/T2SStore/LibraryStore.swift` `DocumentSummary`: add `public var remoteDeviceName: String?` with init default nil. In `static func domain(_ r:)` pass `contentKey: r.contentKey, isPlaceholder: r.isPlaceholder`; in `static func summary(_ r:)` pass `remoteDeviceName: r.isPlaceholder ? r.resumeDevice : r.pendingRemoteDevice`.

- [ ] **Step 3: Write the failing tests**

```swift
// Tests/T2SStoreTests/LibraryStoreSyncTests.swift
import Foundation
import SwiftData
import Testing
import T2SCore
@testable import T2SStore

@Suite struct LibraryStoreSyncTests {
    private func store() throws -> LibraryStore { try LibraryStore.inMemory() }
    /// `makeTimeline` and `makeUtterance` are the helpers at the top of `LibraryStoreTests.swift`;
    /// copy them into this file unchanged (they are file-private there).
    private func timeline() -> Timeline { makeTimeline([[makeUtterance("Hello.")]]) }
    private func document(_ key: String) -> Document {
        Document(title: "A Book", sourceType: .epub, addedAt: Date(timeIntervalSince1970: 1000), contentKey: key)
    }

    /// A position save, a bookmark, a finish flag: each leaves its row dirty, and the dirty records
    /// carry this device's name and the save time. Marking clean clears them.
    @Test func writesLeaveRowsDirtyUntilMarkedClean() async throws {
        let s = try store()
        let doc = document("sha256:aaa")
        try await s.insert(doc, timeline: timeline())
        try await s.markClean(try await s.dirtyRecords(deviceName: "iPhone"))    // the import itself is dirty
        #expect(try await s.dirtyRecords(deviceName: "iPhone").isEmpty)

        try await s.savePosition(Position(resourceHref: "c1.xhtml", progression: 0.5), for: doc.id)
        let bookmark = Bookmark(documentID: doc.id, position: Position(resourceHref: "c1.xhtml", progression: 0.2), note: "here")
        try await s.add(bookmark)
        let dirty = try await s.dirtyRecords(deviceName: "iPhone")
        #expect(dirty.count == 2)
        guard case .document(let d) = dirty[0], case .bookmark(let b) = dirty[1] else { Issue.record("wrong kinds \(dirty)"); return }
        #expect(d.contentKey == "sha256:aaa")
        #expect(d.resume?.deviceName == "iPhone")
        #expect(d.resume?.position.progression == 0.5)
        #expect(b.id == bookmark.id && b.contentKey == "sha256:aaa" && b.note == "here")

        try await s.markClean(dirty)
        #expect(try await s.dirtyRecords(deviceName: "iPhone").isEmpty)
        try await s.deleteBookmark(id: bookmark.id)
        let afterDelete = try await s.dirtyRecords(deviceName: "iPhone")
        #expect(afterDelete.count == 1)
        guard case .bookmark(let gone) = afterDelete[0] else { Issue.record("expected a bookmark marker"); return }
        #expect(gone.id == bookmark.id && gone.deletedAt != nil)
    }

    /// A pulled document with no local match is a placeholder that carries the position; the same
    /// key pulled again with an offer leaves the local position alone and stores the offer.
    @Test func aPulledDocumentIsAPlaceholderAndAnOfferNeverMovesThePosition() async throws {
        let s = try store()
        let remote = SyncedDocument(contentKey: "url:https://x.y/a", title: "Article", sourceType: .article,
                                    sourceURL: URL(string: "https://x.y/a"), addedAt: Date(timeIntervalSince1970: 5),
                                    resume: SyncedPosition(position: Position(resourceHref: "c1.xhtml", progression: 0.3),
                                                           savedAt: Date(timeIntervalSince1970: 50), deviceName: "iPad"),
                                    updatedAt: Date(timeIntervalSince1970: 50))
        try await s.writeSynced(remote, offering: nil)
        let id = try #require(try await s.placeholder(contentKey: "url:https://x.y/a"))
        let stored = try #require(try await s.document(id: id))
        #expect(stored.isPlaceholder && stored.resumePosition?.progression == 0.3)
        #expect(try await s.summary(id: id)?.remoteDeviceName == "iPad")

        let offer = SyncedPosition(position: Position(resourceHref: "c1.xhtml", progression: 0.8),
                                   savedAt: Date(timeIntervalSince1970: 90), deviceName: "iPad")
        try await s.writeSynced(remote, offering: offer)
        #expect(try await s.document(id: id)?.resumePosition?.progression == 0.3)
        #expect(try await s.pendingRemotePosition(for: id) == offer)
        try await s.clearPendingRemotePosition(for: id)
        #expect(try await s.pendingRemotePosition(for: id) == nil)
    }

    /// Filling a placeholder with the real book keeps its position and bookmarks and ends the
    /// placeholder state; deleting everywhere leaves a marker behind.
    @Test func fillingAPlaceholderKeepsWhatSyncBroughtAndDeleteEverywhereLeavesAMarker() async throws {
        let s = try store()
        let remote = SyncedDocument(contentKey: "sha256:bbb", title: "Book", sourceType: .epub, addedAt: Date(timeIntervalSince1970: 5),
                                    resume: SyncedPosition(position: Position(resourceHref: "c1.xhtml", progression: 0.4),
                                                           savedAt: Date(timeIntervalSince1970: 50), deviceName: "iPad"),
                                    updatedAt: Date(timeIntervalSince1970: 50))
        try await s.writeSynced(remote, offering: nil)
        let id = try #require(try await s.placeholder(contentKey: "sha256:bbb"))
        try await s.writeSynced(SyncedBookmark(id: UUID(), contentKey: "sha256:bbb", position: Position(resourceHref: "c1.xhtml", progression: 0.1),
                                               createdAt: Date(timeIntervalSince1970: 20), updatedAt: Date(timeIntervalSince1970: 20)))
        try await s.fill(placeholder: id, with: Document(id: id, title: "Book, really", sourceType: .epub, contentKey: "sha256:bbb"), timeline: timeline())
        let filled = try #require(try await s.document(id: id))
        #expect(!filled.isPlaceholder && filled.title == "Book, really" && filled.resumePosition?.progression == 0.4)
        #expect(try await s.bookmarks(for: id).count == 1)
        #expect(try await s.placeholder(contentKey: "sha256:bbb") == nil)

        try await s.delete(id: id, recordingDeletion: true)
        let dirty = try await s.dirtyRecords(deviceName: "iPhone")
        #expect(dirty.count == 1)
        guard case .document(let marker) = dirty[0] else { Issue.record("expected a document marker"); return }
        #expect(marker.contentKey == "sha256:bbb" && marker.deletedAt != nil)
        #expect(try await s.documentID(contentKey: "sha256:bbb") == nil)
    }

    /// The riskiest line of the change: a store written by the app as it ships today (schema V2)
    /// opens under V3 with the new columns nil or false and nothing lost.
    @Test func aV2StoreOpensUnderV3() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "v2-\(UUID().uuidString)").appending(path: "Library.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let id = UUID()
        do {
            let v2 = try ModelContainer(for: Schema(versionedSchema: LibrarySchemaV2.self), configurations: ModelConfiguration(url: url))
            let context = ModelContext(v2)
            context.insert(LibrarySchemaV2.StoredDocument(id: id, title: "Old", author: nil, sourceType: "epub", sourceURL: nil, coverImagePath: nil,
                                                          addedAt: Date(timeIntervalSince1970: 1), voiceID: nil, schemaVersion: 1, segmenterVersion: 2, normalizerVersion: 4))
            try context.save()
        }
        let s = try LibraryStore.onDisk(at: url)
        let document = try #require(try await s.document(id: id))
        #expect(document.title == "Old" && document.contentKey == nil && !document.isPlaceholder)
        #expect(try await s.dirtyRecords(deviceName: "iPhone").isEmpty)
        #expect(try await s.documentsMissingContentKey().map(\.id) == [id])
    }
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `swift test --filter LibraryStoreSyncTests`
Expected: FAIL — `value of type 'LibraryStore' has no member 'dirtyRecords'`.

- [ ] **Step 5: Implement the primitives**

```swift
// Sources/T2SStore/LibraryStore+Sync.swift
import Foundation
import SwiftData
import T2SCore

/// The sync columns, in domain terms (sync spec §6). The engine decides, these record the decision;
/// `LibrarySyncStore` in T2SApp composes them with the library's file handling.
extension LibraryStore {
    static let documentTombstone = "document", bookmarkTombstone = "bookmark"

    public func syncedDocument(contentKey: String, deviceName: String) throws -> SyncedDocument? {
        try rowWithContentKey(contentKey).map { Self.synced($0, deviceName: deviceName) }
    }

    public func syncedBookmark(id: UUID) throws -> SyncedBookmark? {
        guard let row = try bookmarkRow(id), let key = try row(row.documentID)?.contentKey else { return nil }
        return Self.synced(row, contentKey: key)
    }

    /// Dirty documents, dirty bookmarks, then the markers — documents first so a receiver can
    /// insert a placeholder before its bookmarks arrive.
    public func dirtyRecords(deviceName: String) throws -> [SyncRecord] {
        var records: [SyncRecord] = []
        let documents = try modelContext.fetch(FetchDescriptor<StoredDocument>(predicate: #Predicate { $0.isDirty }))
        for row in documents where row.contentKey != nil { records.append(.document(Self.synced(row, deviceName: deviceName))) }
        let bookmarks = try modelContext.fetch(FetchDescriptor<StoredBookmark>(predicate: #Predicate { $0.isDirty }))
        for row in bookmarks {
            if let key = try self.row(row.documentID)?.contentKey { records.append(.bookmark(Self.synced(row, contentKey: key))) }
        }
        for stone in try modelContext.fetch(FetchDescriptor<StoredTombstone>()) {
            if stone.kind == Self.documentTombstone {
                records.append(.document(SyncedDocument(contentKey: stone.key, title: "", sourceType: .epub, addedAt: stone.deletedAt,
                                                        updatedAt: stone.deletedAt, deletedAt: stone.deletedAt)))
            } else if let id = UUID(uuidString: stone.key) {
                records.append(.bookmark(SyncedBookmark(id: id, contentKey: "", position: Position(resourceHref: "", progression: 0),
                                                        createdAt: stone.deletedAt, updatedAt: stone.deletedAt, deletedAt: stone.deletedAt)))
            }
        }
        return records
    }

    public func writeSynced(_ document: SyncedDocument, offering remote: SyncedPosition?) throws {
        if let row = try rowWithContentKey(document.contentKey) {
            row.title = document.title
            row.author = document.author
            row.isFinished = document.isFinished
            row.updatedAt = document.updatedAt
            // A placeholder has no reading of its own: a newer position is taken, not offered.
            if let remote, row.isPlaceholder {
                Self.setResume(row, remote.position)
                row.resumeSavedAt = remote.savedAt
                row.resumeDevice = remote.deviceName
            } else if let remote {
                row.pendingRemoteHref = remote.position.resourceHref
                row.pendingRemoteProgression = remote.position.progression
                row.pendingRemoteCharOffset = remote.position.charOffset
                row.pendingRemoteCSSSelector = remote.position.cssSelector
                row.pendingRemoteSavedAt = remote.savedAt
                row.pendingRemoteDevice = remote.deviceName
            } else if let resume = document.resume, resume.savedAt != row.resumeSavedAt {
                Self.setResume(row, resume.position)
                row.resumeSavedAt = resume.savedAt
                row.resumeDevice = resume.deviceName
            }
            row.isDirty = false
        } else {
            let row = StoredDocument(id: UUID(), title: document.title, author: document.author, sourceType: document.sourceType.rawValue,
                                     sourceURL: document.sourceURL?.absoluteString, coverImagePath: nil, addedAt: document.addedAt, voiceID: nil,
                                     schemaVersion: Versions.schema, segmenterVersion: 0, normalizerVersion: 0)
            row.contentKey = document.contentKey
            row.isPlaceholder = true
            row.isFinished = document.isFinished
            row.updatedAt = document.updatedAt
            if let resume = document.resume {
                Self.setResume(row, resume.position)
                row.resumeSavedAt = resume.savedAt
                row.resumeDevice = resume.deviceName
            }
            modelContext.insert(row)
        }
        try commit()
    }

    public func writeSynced(_ bookmark: SyncedBookmark) throws {
        guard let document = try rowWithContentKey(bookmark.contentKey) else { return }
        if bookmark.deletedAt != nil {
            if let row = try bookmarkRow(bookmark.id) { modelContext.delete(row) }
        } else if let row = try bookmarkRow(bookmark.id) {
            row.href = bookmark.position.resourceHref; row.progression = bookmark.position.progression
            row.charOffset = bookmark.position.charOffset; row.cssSelector = bookmark.position.cssSelector
            row.note = bookmark.note; row.updatedAt = bookmark.updatedAt; row.isDirty = false
        } else {
            let row = StoredBookmark(id: bookmark.id, documentID: document.id, position: bookmark.position, note: bookmark.note, createdAt: bookmark.createdAt)
            row.updatedAt = bookmark.updatedAt
            modelContext.insert(row)
        }
        try commit()
    }

    /// The local document with this key, for the adapter that removes a pulled deletion's document
    /// through the library (files and audio included). nil when nothing has the key.
    public func documentID(contentKey: String) throws -> UUID? { try rowWithContentKey(contentKey)?.id }

    public func markClean(_ records: [SyncRecord]) throws {
        for record in records {
            switch record {
            case .document(let d) where d.deletedAt != nil: try removeTombstone(kind: Self.documentTombstone, key: d.contentKey)
            case .document(let d): try rowWithContentKey(d.contentKey)?.isDirty = false
            case .bookmark(let b) where b.deletedAt != nil: try removeTombstone(kind: Self.bookmarkTombstone, key: b.id.uuidString)
            case .bookmark(let b): try bookmarkRow(b.id)?.isDirty = false
            }
        }
        try commit()
    }

    public func placeholder(contentKey: String) throws -> UUID? {
        guard let row = try rowWithContentKey(contentKey), row.isPlaceholder else { return nil }
        return row.id
    }

    public func setContentKey(_ id: UUID, _ key: String) throws {
        let row = try existing(id)
        row.contentKey = key
        row.isDirty = true
        try commit()
    }

    /// The real document lands in the placeholder's row: chapters, cover and versions from the
    /// import, everything sync brought — position, pending offer, bookmarks — kept (sync spec §5).
    public func fill(placeholder id: UUID, with document: Document, timeline: Timeline) throws {
        let row = try existing(id)
        row.title = document.title
        row.author = document.author
        row.coverImagePath = document.coverImagePath
        row.sourceType = document.sourceType.rawValue
        row.isPlaceholder = false
        row.updatedAt = Date()
        row.isDirty = true
        try replaceChapters(of: row, with: timeline)
        if row.queueOrder == nil { row.queueOrder = (try queueRows().last?.queueOrder ?? -1) + 1 }
        try commit()
    }

    public func pendingRemotePosition(for id: UUID) throws -> SyncedPosition? {
        let row = try existing(id)
        guard let href = row.pendingRemoteHref, let savedAt = row.pendingRemoteSavedAt else { return nil }
        return SyncedPosition(position: Position(resourceHref: href, progression: row.pendingRemoteProgression ?? 0,
                                                 charOffset: row.pendingRemoteCharOffset, cssSelector: row.pendingRemoteCSSSelector),
                              savedAt: savedAt, deviceName: row.pendingRemoteDevice ?? "another device")
    }

    public func clearPendingRemotePosition(for id: UUID) throws {
        let row = try existing(id)
        row.pendingRemoteHref = nil; row.pendingRemoteProgression = nil; row.pendingRemoteCharOffset = nil
        row.pendingRemoteCSSSelector = nil; row.pendingRemoteSavedAt = nil; row.pendingRemoteDevice = nil
        try commit()
    }

    public func documentsMissingContentKey() throws -> [Document] {
        try modelContext.fetch(FetchDescriptor<StoredDocument>(predicate: #Predicate { $0.contentKey == nil })).map(Self.domain)
    }

    // MARK: helpers

    /// Posted after every write a reader made that sync should carry (`noteLocalChange()`); the
    /// app's `SyncModel` syncs two seconds after the last one (sync spec §7).
    public nonisolated static let localChangeNotification = Notification.Name("LibraryStore.localChange")
    func noteLocalChange() { NotificationCenter.default.post(name: Self.localChangeNotification, object: nil) }

    func rowWithContentKey(_ key: String) throws -> StoredDocument? {
        var descriptor = FetchDescriptor<StoredDocument>(predicate: #Predicate { $0.contentKey == key })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func addTombstone(kind: String, key: String) {
        modelContext.insert(StoredTombstone(kind: kind, key: key, deletedAt: Date()))
    }

    private func removeTombstone(kind: String, key: String) throws {
        for stone in try modelContext.fetch(FetchDescriptor<StoredTombstone>(predicate: #Predicate { $0.kind == kind && $0.key == key })) {
            modelContext.delete(stone)
        }
    }

    static func synced(_ r: StoredDocument, deviceName: String) -> SyncedDocument {
        let resume = r.resumeHref.map { href in
            SyncedPosition(position: Position(resourceHref: href, progression: r.resumeProgression ?? 0, charOffset: r.resumeCharOffset, cssSelector: r.resumeCSSSelector),
                           savedAt: r.resumeSavedAt ?? r.updatedAt, deviceName: r.resumeDevice ?? deviceName)
        }
        return SyncedDocument(contentKey: r.contentKey ?? "", title: r.title, author: r.author, sourceType: SourceType(rawValue: r.sourceType) ?? .epub,
                              sourceURL: r.sourceURL.flatMap(URL.init(string:)), addedAt: r.addedAt, isFinished: r.isFinished,
                              resume: resume, updatedAt: r.updatedAt)
    }

    static func synced(_ r: StoredBookmark, contentKey: String) -> SyncedBookmark {
        SyncedBookmark(id: r.id, contentKey: contentKey, position: r.position, note: r.note, createdAt: r.createdAt, updatedAt: r.updatedAt ?? r.createdAt)
    }
}
```

`bookmarkRow(_:)` in `LibraryStore+Bookmarks.swift` and `queueRows()` in `LibraryStore.swift` are `private`; make both internal (drop the keyword), since the extension file uses them.

- [ ] **Step 6: Dirty marks and markers on the existing write paths**

- `LibraryStore+Playhead.swift`, in `touchPlayed(_:)` after `row.updatedAt = now`: `row.resumeSavedAt = now; row.resumeDevice = nil; row.isDirty = true` (nil device = "this device"; `synced(_:deviceName:)` fills it in), and `noteLocalChange()` after the commit.
- `LibraryStore+Bookmarks.swift`: in `add(_:)`, both branches set `row.updatedAt = Date()` and `row.isDirty = true` (for the insert branch, on the new row after construction). In `deleteBookmark(id:)`, before `modelContext.delete(row)`: `addTombstone(kind: Self.bookmarkTombstone, key: id.uuidString)`. Both call `noteLocalChange()` after their commit.
- `LibraryStore.swift`: `insert(_:timeline:queued:)` sets `row.contentKey = document.contentKey` and `row.isDirty = true` before the commit; `update(_:)`, `setFinished`, `finish` set `row.isDirty = true` where they set `updatedAt`; each of these four calls `noteLocalChange()` after its commit. Replace `delete(id:)` with:

```swift
    /// `recordingDeletion`: the reader chose "everywhere" (sync spec §4) — a marker stays behind
    /// for the next push. The plain delete leaves the record, so the book returns as a placeholder.
    public func delete(id: UUID, recordingDeletion: Bool = false) throws {
        let row = try existing(id)
        if recordingDeletion, let key = row.contentKey { addTombstone(kind: Self.documentTombstone, key: key) }
        try deleteBookmarks(for: id)
        modelContext.delete(row)
        try commit()
        if recordingDeletion { noteLocalChange() }
    }
```

- [ ] **Step 7: Run the tests**

Run: `swift test --filter LibraryStoreSyncTests` then `swift test`
Expected: the three new tests PASS; the full suite stays green (the schema change must not break `LibraryStoreTests`; if a test constructs `Document` positionally, the new trailing defaults keep it compiling).

- [ ] **Step 8: Commit**

```bash
git add Sources/T2SStore Sources/T2SCore/Model/Document.swift Tests/T2SStoreTests/LibraryStoreSyncTests.swift
git commit -m "Store schema V3: the content key, dirty flags, deletion markers and the pending remote position, with the primitives sync writes through

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: The engine, the fake provider, and the five scenarios

**Files:**
- Modify: `Package.swift` (new target `T2SSync` depending on `T2SCore`, product `T2SSync`, test target `T2SSyncTests`; `T2SApp` gains the dependency `"T2SSync"`)
- Create: `Sources/T2SSync/SyncEngine.swift`, `Sources/T2SSync/FakeSyncProvider.swift`, `Sources/T2SSync/InMemorySyncTokenStore.swift`
- Test: `Tests/T2SSyncTests/Support/InMemorySyncStore.swift`, `Tests/T2SSyncTests/SyncEngineTests.swift`

**Interfaces:**
- Consumes: Task 2's protocols and records.
- Produces: `public actor SyncEngine { init(provider:store:tokens:deviceName:); func sync() async -> SyncOutcome }`, `public struct SyncOutcome: Sendable, Hashable { pulled: Int; pushed: Int; error: SyncError? }`, `public actor FakeSyncProvider: SyncProvider { var status; var expireNextToken; func reset() }`, `public actor InMemorySyncTokenStore: SyncTokenStore`.

- [ ] **Step 1: Package.swift**

Add after the `T2SLibrary` target line:

```swift
        .target(name: "T2SSync", dependencies: ["T2SCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
```

Add `"T2SSync"` to `T2SApp`'s dependencies, `.library(name: "T2SSync", targets: ["T2SSync"])` to products, and a test target:

```swift
        .testTarget(
            name: "T2SSyncTests",
            dependencies: ["T2SSync", "T2SCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
```

- [ ] **Step 2: The in-memory store for the tests**

```swift
// Tests/T2SSyncTests/Support/InMemorySyncStore.swift
import Foundation
import T2SCore

/// One device's persistence, in memory: the same contract `LibrarySyncStore` keeps over the
/// library, plus the local edits the scenarios need.
actor InMemorySyncStore: SyncStore {
    var documents: [String: SyncedDocument] = [:]
    var pending: [String: SyncedPosition] = [:]
    var placeholders: Set<String> = []
    var bookmarks: [UUID: SyncedBookmark] = [:]
    var dirty: Set<String> = []
    var tombstones: [SyncRecord] = []
    var removed: [String] = []

    // MARK: SyncStore
    func syncedDocument(contentKey: String) -> SyncedDocument? { documents[contentKey] }
    func syncedBookmark(id: UUID) -> SyncedBookmark? { bookmarks[id] }
    func dirtyRecords() -> [SyncRecord] {
        documents.values.filter { dirty.contains("doc:\($0.contentKey)") }.sorted { $0.contentKey < $1.contentKey }.map(SyncRecord.document)
            + bookmarks.values.filter { dirty.contains("bm:\($0.id)") }.sorted { $0.updatedAt < $1.updatedAt }.map(SyncRecord.bookmark)
            + tombstones
    }
    func write(_ document: SyncedDocument, offering remote: SyncedPosition?) {
        if var local = documents[document.contentKey] {
            local.title = document.title; local.author = document.author; local.isFinished = document.isFinished; local.updatedAt = document.updatedAt
            if let remote, !placeholders.contains(document.contentKey) { pending[document.contentKey] = remote }
            else { local.resume = remote ?? document.resume }
            documents[document.contentKey] = local
            dirty.remove("doc:\(document.contentKey)")
        } else {
            documents[document.contentKey] = document
            placeholders.insert(document.contentKey)
        }
    }
    func write(_ bookmark: SyncedBookmark) {
        guard documents[bookmark.contentKey] != nil else { return }
        if bookmark.deletedAt != nil { bookmarks[bookmark.id] = nil } else { bookmarks[bookmark.id] = bookmark }
        dirty.remove("bm:\(bookmark.id)")
    }
    func removeDocument(contentKey: String) {
        documents[contentKey] = nil; pending[contentKey] = nil; placeholders.remove(contentKey)
        bookmarks = bookmarks.filter { $0.value.contentKey != contentKey }
        removed.append(contentKey)
    }
    func markClean(_ records: [SyncRecord]) {
        for record in records {
            switch record {
            case .document(let d): dirty.remove("doc:\(d.contentKey)"); tombstones.removeAll { $0 == record }
            case .bookmark(let b): dirty.remove("bm:\(b.id)"); tombstones.removeAll { $0 == record }
            }
        }
    }

    // MARK: what a reader does on this device
    func importLocal(_ key: String, title: String, at time: Date) {
        documents[key] = SyncedDocument(contentKey: key, title: title, sourceType: .epub, addedAt: time, updatedAt: time)
        dirty.insert("doc:\(key)")
    }
    func fillPlaceholder(_ key: String) { placeholders.remove(key) }
    func savePosition(_ key: String, _ progression: Double, at time: Date, device: String) {
        documents[key]?.resume = SyncedPosition(position: Position(resourceHref: "c1", progression: progression), savedAt: time, deviceName: device)
        documents[key]?.updatedAt = time
        dirty.insert("doc:\(key)")
    }
    func acceptOffer(_ key: String, at time: Date, device: String) {
        guard let offer = pending[key] else { return }
        documents[key]?.resume = SyncedPosition(position: offer.position, savedAt: time, deviceName: device)
        documents[key]?.updatedAt = time
        pending[key] = nil
        dirty.insert("doc:\(key)")
    }
    func addBookmark(_ id: UUID, _ key: String, note: String?, at time: Date) {
        bookmarks[id] = SyncedBookmark(id: id, contentKey: key, position: Position(resourceHref: "c1", progression: 0.2), note: note, createdAt: time, updatedAt: time)
        dirty.insert("bm:\(id)")
    }
    func editBookmark(_ id: UUID, note: String, at time: Date) {
        bookmarks[id]?.note = note; bookmarks[id]?.updatedAt = time
        dirty.insert("bm:\(id)")
    }
    func deleteBookmark(_ id: UUID, at time: Date) {
        guard let b = bookmarks.removeValue(forKey: id) else { return }
        tombstones.append(.bookmark(SyncedBookmark(id: id, contentKey: b.contentKey, position: b.position, createdAt: b.createdAt, updatedAt: time, deletedAt: time)))
    }
    func deleteEverywhere(_ key: String, at time: Date) {
        documents[key] = nil
        tombstones.append(.document(SyncedDocument(contentKey: key, title: "", sourceType: .epub, addedAt: time, updatedAt: time, deletedAt: time)))
    }
}
```

- [ ] **Step 3: Write the failing scenario tests**

```swift
// Tests/T2SSyncTests/SyncEngineTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SSync

@Suite struct SyncEngineTests {
    /// Two devices over one backend.
    struct Devices {
        let provider = FakeSyncProvider()
        let a = InMemorySyncStore(), b = InMemorySyncStore()
        let engineA: SyncEngine, engineB: SyncEngine
        init() {
            engineA = SyncEngine(provider: provider, store: a, tokens: InMemorySyncTokenStore(), deviceName: "iPhone")
            engineB = SyncEngine(provider: provider, store: b, tokens: InMemorySyncTokenStore(), deviceName: "iPad")
        }
    }
    func t(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    /// Sync spec §4: a newer position is offered, never applied; accepting it is a new save, and the
    /// other device — already at that place — gets nothing back.
    @Test func aNewerPositionIsOfferedThenAcceptedWithoutBouncing() async throws {
        let d = Devices()
        await d.a.importLocal("k", title: "Book", at: t(1))
        _ = await d.engineA.sync()
        _ = await d.engineB.sync()
        #expect(await d.b.placeholders.contains("k"))
        await d.b.fillPlaceholder("k")

        await d.b.savePosition("k", 0.4, at: t(10), device: "iPad")
        _ = await d.engineB.sync(); _ = await d.engineA.sync()
        #expect(await d.a.documents["k"]?.resume?.position.progression == 0.4)      // A had no place: taken as is
        #expect(await d.a.pending["k"] == nil)

        await d.a.savePosition("k", 0.6, at: t(20), device: "iPhone")
        _ = await d.engineA.sync(); _ = await d.engineB.sync()
        #expect(await d.b.documents["k"]?.resume?.position.progression == 0.4)      // unmoved
        #expect(await d.b.pending["k"]?.position.progression == 0.6)
        #expect(await d.b.pending["k"]?.deviceName == "iPhone")

        await d.b.acceptOffer("k", at: t(30), device: "iPad")
        _ = await d.engineB.sync(); _ = await d.engineA.sync()
        #expect(await d.b.documents["k"]?.resume?.position.progression == 0.6)
        #expect(await d.a.pending["k"] == nil)                                        // same place: no offer back
    }

    /// A deletion newer than an edit wins on both devices, including over the edit still waiting to push.
    @Test func aNewerDeletionBeatsAnOlderEditOnBothDevices() async throws {
        let d = Devices()
        let id = UUID()
        await d.a.importLocal("k", title: "Book", at: t(1))
        await d.a.addBookmark(id, "k", note: "a", at: t(10))
        _ = await d.engineA.sync(); _ = await d.engineB.sync()
        #expect(await d.b.bookmarks[id]?.note == "a")

        await d.a.editBookmark(id, note: "b", at: t(20))
        await d.b.deleteBookmark(id, at: t(30))
        _ = await d.engineB.sync()
        let outcome = await d.engineA.sync()
        #expect(outcome.error == nil)
        #expect(await d.a.bookmarks[id] == nil)
        #expect(await d.b.bookmarks[id] == nil)
        #expect(await d.a.dirtyRecords().isEmpty)
    }

    /// Sync spec §5: the other device's book is a placeholder carrying its position; the import that
    /// fills it finds the position waiting.
    @Test func anotherDevicesBookIsAPlaceholderWithItsPosition() async throws {
        let d = Devices()
        await d.a.importLocal("k", title: "Book", at: t(1))
        await d.a.savePosition("k", 0.3, at: t(10), device: "iPhone")
        _ = await d.engineA.sync(); _ = await d.engineB.sync()
        #expect(await d.b.placeholders.contains("k"))
        #expect(await d.b.documents["k"]?.title == "Book")
        #expect(await d.b.documents["k"]?.resume?.position.progression == 0.3)
        await d.b.fillPlaceholder("k")
        #expect(await d.b.documents["k"]?.resume?.position.progression == 0.3)
    }

    /// Delete everywhere: the marker reaches the other device and the book goes.
    @Test func deleteEverywhereRemovesTheBookOnTheOtherDevice() async throws {
        let d = Devices()
        await d.a.importLocal("k", title: "Book", at: t(1))
        _ = await d.engineA.sync(); _ = await d.engineB.sync()
        await d.a.deleteEverywhere("k", at: t(50))
        _ = await d.engineA.sync(); _ = await d.engineB.sync()
        #expect(await d.b.documents["k"] == nil)
        #expect(await d.b.removed == ["k"])
        #expect(await d.a.dirtyRecords().isEmpty)
    }

    /// An expired token is a full pull, and a full pull changes nothing that was already right.
    @Test func anExpiredTokenIsAFullPullThatChangesNothing() async throws {
        let d = Devices()
        await d.a.importLocal("k", title: "Book", at: t(1))
        await d.a.addBookmark(UUID(), "k", note: "x", at: t(5))
        _ = await d.engineA.sync(); _ = await d.engineB.sync()
        let before = (await d.b.documents, await d.b.bookmarks, await d.b.pending)
        await d.provider.setExpireNextToken(true)
        let outcome = await d.engineB.sync()
        #expect(outcome.error == nil)
        #expect(await d.b.documents == before.0)
        #expect(await d.b.bookmarks == before.1)
        #expect(await d.b.pending == before.2)
    }
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `swift test --filter SyncEngineTests`
Expected: FAIL to compile — `cannot find 'SyncEngine' in scope`.

- [ ] **Step 5: The token store, the fake, the engine**

```swift
// Sources/T2SSync/InMemorySyncTokenStore.swift
import T2SCore

public actor InMemorySyncTokenStore: SyncTokenStore {
    private var token: SyncToken?
    public init() {}
    public func load() -> SyncToken? { token }
    public func save(_ token: SyncToken?) { self.token = token }
}
```

```swift
// Sources/T2SSync/FakeSyncProvider.swift
import Foundation
import T2SCore

/// A backend in memory: every accepted push gets a sequence number, `changes(since:)` returns the
/// latest version of every record numbered after the token, and a push older than what it holds is
/// a conflict — CloudKit's behaviour, without CloudKit. Used by the tests and, under `-t2s.sync
/// fake`, by a simulator run of the UI (sync spec §3, §8).
public actor FakeSyncProvider: SyncProvider {
    private var sequence = 0
    private var latest: [String: (sequence: Int, record: SyncRecord)] = [:]
    public var status: SyncAccountStatus = .available
    private var expireNextToken = false

    public init() {}

    public func setStatus(_ status: SyncAccountStatus) { self.status = status }
    public func setExpireNextToken(_ expire: Bool) { expireNextToken = expire }
    public func reset() { sequence = 0; latest = [:]; expireNextToken = false }

    public func accountStatus() -> SyncAccountStatus { status }

    public func changes(since token: SyncToken?) throws -> SyncChanges {
        let from = token.flatMap { Int(String(decoding: $0.data, as: UTF8.self)) } ?? 0
        if expireNextToken, token != nil { expireNextToken = false; throw SyncError.tokenExpired }
        let records = latest.values.filter { $0.sequence > from }.sorted { $0.sequence < $1.sequence }.map(\.record)
        return SyncChanges(records: records, token: SyncToken(data: Data(String(sequence).utf8)))
    }

    public func push(_ records: [SyncRecord]) throws -> [SyncPushResult] {
        records.map { record in
            let key = Self.key(of: record)
            if let held = latest[key], held.record.updatedAt > record.updatedAt {
                return SyncPushResult(record: record, outcome: .conflict(server: held.record))
            }
            sequence += 1
            latest[key] = (sequence, record)
            return SyncPushResult(record: record, outcome: .saved)
        }
    }

    static func key(of record: SyncRecord) -> String {
        switch record {
        case .document(let d): return "doc:" + d.contentKey
        case .bookmark(let b): return "bm:" + b.id.uuidString
        }
    }
}
```

```swift
// Sources/T2SSync/SyncEngine.swift
import Foundation
import os
import T2SCore

public struct SyncOutcome: Sendable, Hashable {
    public var pulled: Int
    public var pushed: Int
    public var error: SyncError?
    public init(pulled: Int = 0, pushed: Int = 0, error: SyncError? = nil) { self.pulled = pulled; self.pushed = pushed; self.error = error }
}

/// The cycle and the merge (sync spec §4, §7): pull since the token and apply, then push what is
/// dirty. One rule for records — the newer `updatedAt` wins, a deletion marker beats anything older
/// — and one exception: a newer remote position is stored as an offer, never applied. An actor, so
/// two triggers run one after the other; a cycle that finds nothing changed costs one fetch.
public actor SyncEngine {
    private let provider: any SyncProvider
    private let store: any SyncStore
    private let tokens: any SyncTokenStore
    private let deviceName: String
    private let log = Logger(subsystem: "com.t2s.reader", category: "sync")

    public init(provider: any SyncProvider, store: any SyncStore, tokens: any SyncTokenStore, deviceName: String) {
        self.provider = provider; self.store = store; self.tokens = tokens; self.deviceName = deviceName
    }

    public func sync() async -> SyncOutcome {
        do {
            let changes = try await pull()
            let pushed = try await push(try await store.dirtyRecords())
            log.notice("sync: pulled \(changes.records.count, privacy: .public), pushed \(pushed, privacy: .public)")
            return SyncOutcome(pulled: changes.records.count, pushed: pushed)
        } catch let error as SyncError {
            log.error("sync failed: \(String(describing: error), privacy: .public)")
            return SyncOutcome(error: error)
        } catch {
            log.error("sync failed: \(error.localizedDescription, privacy: .public)")
            return SyncOutcome(error: .other(error.localizedDescription))
        }
    }

    private func pull() async throws -> SyncChanges {
        var token = await tokens.load()
        let changes: SyncChanges
        do {
            changes = try await provider.changes(since: token)
        } catch SyncError.tokenExpired {
            token = nil
            changes = try await provider.changes(since: nil)
        }
        try await apply(changes.records)
        await tokens.save(changes.token)
        return changes
    }

    /// Documents before bookmarks, so a bookmark never arrives before the placeholder it belongs to.
    private func apply(_ records: [SyncRecord]) async throws {
        for case .document(let d) in records { try await apply(d) }
        for case .bookmark(let b) in records { try await apply(b) }
    }

    private func apply(_ remote: SyncedDocument) async throws {
        if remote.deletedAt != nil {
            try await store.removeDocument(contentKey: remote.contentKey)
            return
        }
        guard let local = try await store.syncedDocument(contentKey: remote.contentKey) else {
            try await store.write(remote, offering: nil)
            return
        }
        var merged = remote.updatedAt > local.updatedAt ? remote : local
        merged.resume = local.resume
        var offer: SyncedPosition?
        if let theirs = remote.resume {
            if let mine = local.resume {
                if theirs.savedAt > mine.savedAt, theirs.position != mine.position { offer = theirs }
            } else {
                merged.resume = theirs
            }
        }
        try await store.write(merged, offering: offer)
    }

    private func apply(_ remote: SyncedBookmark) async throws {
        if let local = try await store.syncedBookmark(id: remote.id), local.updatedAt >= remote.updatedAt { return }
        try await store.write(remote)
    }

    /// Pushes, and on a conflict merges the server's copy in and pushes once more; a second conflict
    /// leaves the row dirty for the next cycle.
    private func push(_ records: [SyncRecord]) async throws -> Int {
        guard !records.isEmpty else { return 0 }
        var accepted: [SyncRecord] = []
        var retry: [SyncRecord] = []
        for result in try await provider.push(records) {
            switch result.outcome {
            case .saved: accepted.append(result.record)
            case .conflict(let server):
                try await apply([server])
                if result.record.updatedAt > server.updatedAt { retry.append(result.record) } else { accepted.append(result.record) }
            }
        }
        if !retry.isEmpty {
            for result in try await provider.push(retry) where result.outcome == .saved { accepted.append(result.record) }
        }
        try await store.markClean(accepted)
        return accepted.count
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter SyncEngineTests`
Expected: PASS, 5 tests. If scenario 2 fails on the last expectation, the conflict path is not marking the losing local edit clean: check `push` appends `result.record` to `accepted` when the server wins.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/T2SSync Tests/T2SSyncTests
git commit -m "The sync engine: pull since the token, merge by the newer clock, offer a position rather than apply it, push what is dirty — five scenarios over a fake backend

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: The CloudKit provider

**Files:**
- Create: `Sources/T2SSync/CloudKit/CloudKitRecordMapping.swift`, `Sources/T2SSync/CloudKit/CloudKitSyncProvider.swift`
- Test: `Tests/T2SSyncTests/CloudKitRecordMappingTests.swift`

**Interfaces:**
- Consumes: Task 2's records and errors.
- Produces: `enum CloudKitRecordMapping { static let zoneName = "t2s"; static func record(for: SyncedDocument, zone: CKRecordZone.ID, updating: CKRecord?) -> CKRecord; static func record(for: SyncedBookmark, zone:updating:) -> CKRecord; static func syncRecord(from: CKRecord) -> SyncRecord? }`, `public actor CloudKitSyncProvider: SyncProvider { init(containerIdentifier: String) }`.

- [ ] **Step 1: Write the failing round-trip tests**

```swift
// Tests/T2SSyncTests/CloudKitRecordMappingTests.swift
import CloudKit
import Foundation
import Testing
import T2SCore
@testable import T2SSync

@Suite struct CloudKitRecordMappingTests {
    let zone = CKRecordZone.ID(zoneName: CloudKitRecordMapping.zoneName, ownerName: CKCurrentUserDefaultName)

    /// Design spec §3.7.1: the record is a mapping of the domain type, and the mapping is lossless.
    @Test func aDocumentSurvivesTheRoundTrip() {
        let document = SyncedDocument(contentKey: "url:https://x.y/a", title: "T", author: "A", sourceType: .article,
                                      sourceURL: URL(string: "https://x.y/a"), addedAt: Date(timeIntervalSince1970: 1), isFinished: true,
                                      resume: SyncedPosition(position: Position(resourceHref: "c.xhtml", progression: 0.5, charOffset: 12, cssSelector: "p:nth-child(3)"),
                                                             savedAt: Date(timeIntervalSince1970: 2), deviceName: "iPhone"),
                                      updatedAt: Date(timeIntervalSince1970: 3), deletedAt: Date(timeIntervalSince1970: 4))
        let record = CloudKitRecordMapping.record(for: document, zone: zone, updating: nil)
        #expect(record.recordType == "Document")
        #expect(record.recordID.recordName == ContentKey.recordName(for: document.contentKey))
        #expect(CloudKitRecordMapping.syncRecord(from: record) == .document(document))
    }

    @Test func aBookmarkSurvivesTheRoundTrip() {
        let bookmark = SyncedBookmark(id: UUID(), contentKey: "sha256:abc", position: Position(resourceHref: "c.xhtml", progression: 0.25),
                                      note: "here", createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
        let record = CloudKitRecordMapping.record(for: bookmark, zone: zone, updating: nil)
        #expect(record.recordID.recordName == "bm-" + bookmark.id.uuidString)
        #expect(CloudKitRecordMapping.syncRecord(from: record) == .bookmark(bookmark))
        let updated = CloudKitRecordMapping.record(for: bookmark, zone: zone, updating: record)
        #expect(updated === record)                                             // the server's copy is edited, its change tag kept
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter CloudKitRecordMappingTests`
Expected: FAIL to compile — `cannot find 'CloudKitRecordMapping'`.

- [ ] **Step 3: The mapping**

```swift
// Sources/T2SSync/CloudKit/CloudKitRecordMapping.swift
import CloudKit
import Foundation
import T2SCore

/// `CKRecord` ↔ the sync records, and nothing else: CloudKit's schema is this file's business alone
/// (design spec §3.7.1). Positions travel as JSON strings so the record has no shape of its own.
enum CloudKitRecordMapping {
    static let zoneName = "t2s"
    static let documentType = "Document"
    static let bookmarkType = "Bookmark"

    static func record(for d: SyncedDocument, zone: CKRecordZone.ID, updating existing: CKRecord?) -> CKRecord {
        let record = existing ?? CKRecord(recordType: documentType, recordID: CKRecord.ID(recordName: ContentKey.recordName(for: d.contentKey), zoneID: zone))
        record["contentKey"] = d.contentKey as NSString
        record["title"] = d.title as NSString
        record["author"] = d.author.map { $0 as NSString }
        record["sourceType"] = d.sourceType.rawValue as NSString
        record["sourceURL"] = d.sourceURL?.absoluteString.map { $0 as NSString }
        record["addedAt"] = d.addedAt as NSDate
        record["isFinished"] = (d.isFinished ? 1 : 0) as NSNumber
        record["resume"] = d.resume.flatMap { json($0) }.map { $0 as NSString }
        record["updatedAt"] = d.updatedAt as NSDate
        record["deletedAt"] = d.deletedAt.map { $0 as NSDate }
        return record
    }

    static func record(for b: SyncedBookmark, zone: CKRecordZone.ID, updating existing: CKRecord?) -> CKRecord {
        let record = existing ?? CKRecord(recordType: bookmarkType, recordID: CKRecord.ID(recordName: "bm-" + b.id.uuidString, zoneID: zone))
        record["bookmarkID"] = b.id.uuidString as NSString
        record["contentKey"] = b.contentKey as NSString
        record["position"] = json(b.position).map { $0 as NSString }
        record["note"] = b.note.map { $0 as NSString }
        record["createdAt"] = b.createdAt as NSDate
        record["updatedAt"] = b.updatedAt as NSDate
        record["deletedAt"] = b.deletedAt.map { $0 as NSDate }
        return record
    }

    static func syncRecord(from r: CKRecord) -> SyncRecord? {
        switch r.recordType {
        case documentType:
            guard let key = r["contentKey"] as? String, let title = r["title"] as? String, let type = (r["sourceType"] as? String).flatMap(SourceType.init(rawValue:)),
                  let addedAt = r["addedAt"] as? Date, let updatedAt = r["updatedAt"] as? Date else { return nil }
            return .document(SyncedDocument(contentKey: key, title: title, author: r["author"] as? String, sourceType: type,
                                            sourceURL: (r["sourceURL"] as? String).flatMap(URL.init(string:)), addedAt: addedAt,
                                            isFinished: (r["isFinished"] as? Int ?? 0) != 0,
                                            resume: (r["resume"] as? String).flatMap { decode(SyncedPosition.self, $0) },
                                            updatedAt: updatedAt, deletedAt: r["deletedAt"] as? Date))
        case bookmarkType:
            guard let id = (r["bookmarkID"] as? String).flatMap(UUID.init(uuidString:)), let key = r["contentKey"] as? String,
                  let position = (r["position"] as? String).flatMap({ decode(Position.self, $0) }),
                  let createdAt = r["createdAt"] as? Date, let updatedAt = r["updatedAt"] as? Date else { return nil }
            return .bookmark(SyncedBookmark(id: id, contentKey: key, position: position, note: r["note"] as? String,
                                            createdAt: createdAt, updatedAt: updatedAt, deletedAt: r["deletedAt"] as? Date))
        default: return nil
        }
    }

    private static func json<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) }
    }
    private static func decode<T: Decodable>(_ type: T.Type, _ string: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(string.utf8))
    }
}
```

`Date` round-trips through `NSDate` exactly (a `TimeInterval` double); the tests use whole seconds so `==` holds.

- [ ] **Step 4: The provider**

```swift
// Sources/T2SSync/CloudKit/CloudKitSyncProvider.swift
import CloudKit
import Foundation
import T2SCore

/// The one CloudKit caller (sync spec §3): a custom zone in the private database, zone changes
/// behind the token, saves that refuse to overwrite a newer server record so the engine can merge.
/// Records fetched or saved are kept by name so a later save carries the server's change tag.
public actor CloudKitSyncProvider: SyncProvider {
    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: CloudKitRecordMapping.zoneName, ownerName: CKCurrentUserDefaultName)
    private var zoneReady = false
    private var known: [String: CKRecord] = [:]

    public init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
    }

    public func accountStatus() async -> SyncAccountStatus {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .couldNotDetermine: return .unavailable("could not determine")
            case .temporarilyUnavailable: return .unavailable("temporarily unavailable")
            @unknown default: return .unavailable("unknown")
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    public func changes(since token: SyncToken?) async throws -> SyncChanges {
        try await ensureZone()
        var serverToken = try token.map { try Self.unarchive($0) }
        var records: [SyncRecord] = []
        var more = true
        do {
            while more {
                let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: serverToken)
                for (_, result) in page.modificationResultsByID {
                    if case .success(let modification) = result {
                        known[modification.record.recordID.recordName] = modification.record
                        if let mapped = CloudKitRecordMapping.syncRecord(from: modification.record) { records.append(mapped) }
                    }
                }
                serverToken = page.changeToken
                more = page.moreComing
            }
        } catch {
            throw Self.mapped(error)
        }
        return SyncChanges(records: records, token: try serverToken.map(Self.archive))
    }

    public func push(_ records: [SyncRecord]) async throws -> [SyncPushResult] {
        try await ensureZone()
        let ckRecords = records.map { record -> (SyncRecord, CKRecord) in
            switch record {
            case .document(let d): return (record, CloudKitRecordMapping.record(for: d, zone: zoneID, updating: known[ContentKey.recordName(for: d.contentKey)]))
            case .bookmark(let b): return (record, CloudKitRecordMapping.record(for: b, zone: zoneID, updating: known["bm-" + b.id.uuidString]))
            }
        }
        let results: (saveResults: [CKRecord.ID: Result<CKRecord, Error>], deleteResults: [CKRecord.ID: Result<Void, Error>])
        do {
            results = try await database.modifyRecords(saving: ckRecords.map(\.1), deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
        } catch {
            throw Self.mapped(error)
        }
        return try ckRecords.map { record, ck in
            switch results.saveResults[ck.recordID] {
            case .success(let saved)?:
                known[saved.recordID.recordName] = saved
                return SyncPushResult(record: record, outcome: .saved)
            case .failure(let error)?:
                if let ckError = error as? CKError, ckError.code == .serverRecordChanged, let server = ckError.serverRecord,
                   let mapped = CloudKitRecordMapping.syncRecord(from: server) {
                    known[server.recordID.recordName] = server
                    return SyncPushResult(record: record, outcome: .conflict(server: mapped))
                }
                throw Self.mapped(error)
            case nil:
                throw SyncError.other("no result for \(ck.recordID.recordName)")
            }
        }
    }

    private func ensureZone() async throws {
        guard !zoneReady else { return }
        do {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
            zoneReady = true
        } catch {
            throw Self.mapped(error)
        }
    }

    static func mapped(_ error: Error) -> SyncError {
        guard let ck = error as? CKError else { return .other(error.localizedDescription) }
        switch ck.code {
        case .changeTokenExpired: return .tokenExpired
        case .quotaExceeded: return .quotaExceeded
        case .zoneNotFound, .userDeletedZone: return .zoneMissing
        case .notAuthenticated: return .account(.noAccount)
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy: return .network(ck.localizedDescription)
        default: return .other("\(ck.code.rawValue): \(ck.localizedDescription)")
        }
    }

    static func archive(_ token: CKServerChangeToken) throws -> SyncToken {
        SyncToken(data: try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true))
    }
    static func unarchive(_ token: SyncToken) throws -> CKServerChangeToken {
        guard let value = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: token.data) else { throw SyncError.tokenExpired }
        return value
    }
}
```

The `zoneMissing` case is the one the engine does not handle: `SyncModel` (Task 7) resets `zoneReady` by creating a new provider and syncing again, once. Saving an existing zone succeeds, so `ensureZone` is idempotent.

- [ ] **Step 5: Run the tests and the full suite**

Run: `swift test --filter CloudKitRecordMappingTests` then `swift test`
Expected: 2 PASS; everything green. If the `updated === record` expectation fails, `record(for:zone:updating:)` created a new record instead of editing `existing`.

- [ ] **Step 6: Commit**

```bash
git add Sources/T2SSync/CloudKit Tests/T2SSyncTests/CloudKitRecordMappingTests.swift
git commit -m "The CloudKit provider: a private zone, zone changes behind the token, saves that yield to a newer server record — and the one file that knows a CKRecord

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: The library — keys at import, placeholders filled, deletion everywhere, the backfill

**Files:**
- Modify: `Sources/T2SLibrary/Library.swift` (`importFile`, `importArticle`, `ingest`, `delete`), `Sources/T2SLibrary/ImportError.swift`
- Test: `Tests/T2SLibraryTests/LibrarySyncTests.swift`

**Interfaces:**
- Consumes: `ContentKey` (Task 1), `LibraryStore.placeholder(contentKey:)`, `fill(placeholder:with:timeline:)`, `setContentKey`, `documentsMissingContentKey()`, `delete(id:recordingDeletion:)` (Task 3).
- Produces: `Library.delete(_ id: UUID, everywhere: Bool = false)`, `Library.backfillContentKeys() async throws -> Int`, `Library.fillPlaceholder(_ id: UUID, from url: URL, sourceType: SourceType) async throws -> ImportResult`, `ImportError.differentFile`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/T2SLibraryTests/LibrarySyncTests.swift
import Foundation
import Testing
import T2SCore
import T2SStore
@testable import T2SLibrary

@Suite struct LibrarySyncTests {
    /// A library over an in-memory store and a temporary root, reading through `FakeDocumentReader`
    /// (the test target's stub; it claims every source type and yields two fixed chapters) — the
    /// same harness `LibraryTests.makeHarness` builds.
    private func makeLibrary() throws -> Library {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-sync-\(UUID().uuidString)")
        return Library(paths: LibraryPaths(root: root), store: try LibraryStore.inMemory(),
                       audioStore: InMemoryAudioStore(codec: RawPCMCodec(), capacityBytes: 10_000_000),
                       readers: [FakeDocumentReader()], segmenterPackLength: 0)
    }

    /// Sync spec §5: an article the other device has is a placeholder; importing it here — by its
    /// URL — fills that row rather than adding a second document, and the position waits on it.
    @Test func importingAnArticleFillsItsPlaceholder() async throws {
        let library = try makeLibrary()
        let url = URL(string: "https://Example.com/story?utm_source=mail")!
        let key = ContentKey.article(url)
        try await library.store.writeSynced(
            SyncedDocument(contentKey: key, title: "Story", sourceType: .article, sourceURL: url, addedAt: Date(timeIntervalSince1970: 1),
                           resume: SyncedPosition(position: Position(resourceHref: "chapter1.xhtml", progression: 0.5),
                                                  savedAt: Date(timeIntervalSince1970: 2), deviceName: "iPad"),
                           updatedAt: Date(timeIntervalSince1970: 2)),
            offering: nil)
        let placeholder = try #require(try await library.store.placeholder(contentKey: key))

        let article = ArticleContent(title: "Story", sourceURL: url, bodyXHTML: "<p>Once upon a time. The end.</p>")
        let result = try await library.importArticle(article, originalHTML: "<html>…</html>")

        #expect(result.document.id == placeholder)
        #expect(result.document.contentKey == key)
        #expect(try await library.store.placeholder(contentKey: key) == nil)
        #expect(try await library.store.documents().count == 1)
        #expect(try await library.store.document(id: placeholder)?.resumePosition?.progression == 0.5)
    }

    /// A file that is not the placeholder's is refused before anything is imported.
    @Test func fillingAPlaceholderWithTheWrongFileIsRefused() async throws {
        let library = try makeLibrary()
        try await library.store.writeSynced(SyncedDocument(contentKey: "sha256:not-these-bytes", title: "Book", sourceType: .epub,
                                                           addedAt: Date(), updatedAt: Date()), offering: nil)
        let placeholder = try #require(try await library.store.placeholder(contentKey: "sha256:not-these-bytes"))
        let file = FileManager.default.temporaryDirectory.appending(path: "wrong-\(UUID().uuidString).epub")
        try Data("zip".utf8).write(to: file)
        await #expect(throws: ImportError.differentFile) {
            try await library.fillPlaceholder(placeholder, from: file, sourceType: .epub)
        }
        #expect(try await library.store.documents().count == 1)
    }
}
```

`FakeDocumentReader` lives in the test target already (`LibraryTests.importsAnEPUBThroughTheReader` uses it); if it is `private` to its file, drop the keyword.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LibrarySyncTests`
Expected: FAIL — `result.document.id == placeholder` false (a second document was created), and `fillPlaceholder` missing.

- [ ] **Step 3: Implement**

`ImportError.swift`: add `/// The file offered for a placeholder is not the file the other device has (sync spec §5).` `case differentFile`. If `ImportError` has a `message`/`errorDescription` switch, add "That's a different file."

`Library.swift`:

```swift
    public func importFile(at url: URL, sourceType: SourceType) async throws -> ImportResult {
        let reader = try reader(for: sourceType)
        // The content key first (sync spec §2): the same bytes on another device are the same book,
        // and a placeholder for them is filled rather than doubled (sync spec §5).
        let key = try ContentKey.file(at: url)
        let placeholder = try await store.placeholder(contentKey: key)
        let id = placeholder ?? UUID()
        let directory = paths.documentDirectory(id)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: paths.sourceURL(id, type: sourceType))
            return try await ingest(id: id, sourceType: sourceType, sourceURL: nil, contentKey: key, fillingPlaceholder: placeholder != nil, reader: reader)
        } catch {
            if placeholder == nil { try? FileManager.default.removeItem(at: directory) } else { try? FileManager.default.removeItem(at: paths.sourceURL(id, type: sourceType)) }
            throw error
        }
    }

    public func importArticle(_ article: ArticleContent, originalHTML: String) async throws -> ImportResult {
        let reader = try reader(for: .article)
        // An article's key is its URL; pasted text has none and stays on this device.
        let key = article.sourceURL.map(ContentKey.article)
        let placeholder = try await key.flatMap { try await store.placeholder(contentKey: $0) }
        let id = placeholder ?? UUID()
        let directory = paths.documentDirectory(id)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(originalHTML.utf8).write(to: paths.originalHTMLURL(id), options: .atomic)
            try ArticleEPUBWriter.write(article, to: paths.sourceURL(id, type: .article), identifier: id)
            return try await ingest(id: id, sourceType: .article, sourceURL: article.sourceURL, contentKey: key, fillingPlaceholder: placeholder != nil, reader: reader)
        } catch {
            if placeholder == nil { try? FileManager.default.removeItem(at: directory) }
            throw error
        }
    }

    private func ingest(id: UUID, sourceType: SourceType, sourceURL: URL?, contentKey: String?, fillingPlaceholder: Bool, reader: any DocumentReader) async throws -> ImportResult {
        // … unchanged up to `let document = …`, which gains `contentKey: contentKey` …
        if fillingPlaceholder {
            try await store.fill(placeholder: id, with: document, timeline: timeline)
        } else {
            try await store.insert(document, timeline: timeline, queued: true)
        }
        return ImportResult(document: document, utteranceCount: timeline.utteranceCount, skippedResources: read.skippedResources)
    }

    /// `everywhere`: the reader chose so with sync on (sync spec §4); a marker stays for the push.
    public func delete(_ id: UUID, everywhere: Bool = false) async throws {
        if let stored = try? await store.timeline(for: id) { await removeAudio(of: stored.timeline) }
        try await store.delete(id: id, recordingDeletion: everywhere)
        try? FileManager.default.removeItem(at: paths.documentDirectory(id))
    }

    /// Keys for the rows that predate sync (sync spec §2): the file hashed, the URL canonicalised;
    /// a row with neither is left alone. Returns how many were keyed.
    public func backfillContentKeys() async throws -> Int {
        var keyed = 0
        for document in try await store.documentsMissingContentKey() where !document.isPlaceholder {
            let key: String?
            switch document.sourceType {
            case .epub, .pdf:
                let source = paths.sourceURL(document.id, type: document.sourceType)
                key = FileManager.default.fileExists(atPath: source.path) ? try ContentKey.file(at: source) : nil
            case .article:
                key = document.sourceURL.map(ContentKey.article)
            }
            if let key { try await store.setContentKey(document.id, key); keyed += 1 }
        }
        return keyed
    }

    /// The Files picker's answer for an EPUB or PDF placeholder: accepted only when its bytes are the
    /// other device's (sync spec §5), then imported through the ordinary path, which fills the row.
    public func fillPlaceholder(_ id: UUID, from url: URL, sourceType: SourceType) async throws -> ImportResult {
        guard let expected = try await store.document(id: id)?.contentKey else { throw ImportError.unreadable("no placeholder") }
        guard try ContentKey.file(at: url) == expected else { throw ImportError.differentFile }
        return try await importFile(at: url, sourceType: sourceType)
    }
```

- [ ] **Step 4: Run the tests and the suite**

Run: `swift test --filter LibrarySyncTests` then `swift test`
Expected: 2 PASS; everything green.

- [ ] **Step 5: Commit**

```bash
git add Sources/T2SLibrary Tests/T2SLibraryTests/LibrarySyncTests.swift
git commit -m "The library keys every import, fills a placeholder instead of doubling it, refuses the wrong file, and can delete everywhere

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: The app's sync model and its wiring

**Files:**
- Create: `Sources/T2SApp/Sync/LibrarySyncStore.swift`, `Sources/T2SApp/Sync/UserDefaultsSyncTokenStore.swift`, `Sources/T2SApp/Sync/SyncModel.swift`
- Modify: `Sources/T2SApp/Player/PlayerModel.swift` (two methods), `App/T2SReader/AppEnvironment.swift` (a property, `live()`, `deleteDocument`), `App/T2SReader/Root/RootPager.swift:213-221`, `Sources/T2SApp/Library/LibraryModel.swift` (`delete(_:everywhere:)`, `fillPlaceholder`)

**Interfaces:**
- Consumes: `SyncEngine`, `FakeSyncProvider`, `CloudKitSyncProvider` (Tasks 4–5); `Library.delete(_:everywhere:)`, `backfillContentKeys()`, `fillPlaceholder(_:from:sourceType:)` (Task 6); `LibraryStore.pendingRemotePosition(for:)`, `clearPendingRemotePosition(for:)`, `documentID(contentKey:)`, `LibraryStore.localChangeNotification` (Task 3).
- Produces: `SyncModel` (`@Observable @MainActor`): `availability`, `isEnabled`, `canEnable`, `statusText`, `unavailableReason`, `setEnabled(_:) async`, `syncIfEnabled() async`, `offer(for:) async -> SyncedPosition?`, `dismissOffer(for:) async`; `PlayerModel.describe(_ position: Position) -> String?`, `PlayerModel.jump(to position: Position) async`; `AppEnvironment.syncModel`, `AppEnvironment.deleteDocument(_:everywhere:)`; `LibraryModel.delete(_:everywhere:)`, `LibraryModel.fillPlaceholder(_:from:sourceType:) async -> String?` (an error message, or nil).

- [ ] **Step 1: The store adapter and the token store**

```swift
// Sources/T2SApp/Sync/LibrarySyncStore.swift
import Foundation
import T2SCore
import T2SLibrary
import T2SStore

/// `SyncStore` over the library (sync spec §6): the store's primitives, plus the library for what
/// touches files — a pulled deletion removes the document the way a reader's delete does.
public actor LibrarySyncStore: SyncStore {
    private let library: Library
    private let deviceName: String
    public init(library: Library, deviceName: String) { self.library = library; self.deviceName = deviceName }

    public func syncedDocument(contentKey: String) async throws -> SyncedDocument? {
        try await library.store.syncedDocument(contentKey: contentKey, deviceName: deviceName)
    }
    public func syncedBookmark(id: UUID) async throws -> SyncedBookmark? { try await library.store.syncedBookmark(id: id) }
    public func dirtyRecords() async throws -> [SyncRecord] { try await library.store.dirtyRecords(deviceName: deviceName) }
    public func write(_ document: SyncedDocument, offering remote: SyncedPosition?) async throws {
        try await library.store.writeSynced(document, offering: remote)
    }
    public func write(_ bookmark: SyncedBookmark) async throws { try await library.store.writeSynced(bookmark) }
    public func removeDocument(contentKey: String) async throws {
        guard let id = try await library.store.documentID(contentKey: contentKey) else { return }
        try await library.delete(id, everywhere: false)             // it came from the other device: no marker of our own
    }
    public func markClean(_ records: [SyncRecord]) async throws { try await library.store.markClean(records) }
}
```

```swift
// Sources/T2SApp/Sync/UserDefaultsSyncTokenStore.swift
import Foundation
import T2SCore

public actor UserDefaultsSyncTokenStore: SyncTokenStore {
    public static let key = "sync.token"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> SyncToken? { defaults.data(forKey: Self.key).map(SyncToken.init(data:)) }
    public func save(_ token: SyncToken?) { defaults.set(token?.data, forKey: Self.key) }
}
```

- [ ] **Step 2: The model**

```swift
// Sources/T2SApp/Sync/SyncModel.swift
import Foundation
import Observation
import os
import T2SCore
import T2SLibrary
import T2SStore
import T2SSync

/// The toggle, its reasons, the triggers, and the offers (sync spec §7, §8). Nil provider: the build
/// has no container; the row stays off with the reason underneath.
@Observable @MainActor
public final class SyncModel {
    public enum Availability: Sendable, Hashable { case noContainer, noAccount, restricted, unavailable(String), available }
    public static let enabledKey = "sync.enabled"

    public private(set) var availability: Availability = .noContainer
    public private(set) var isEnabled: Bool
    public private(set) var statusText = ""
    public private(set) var isSyncing = false

    private let provider: (any SyncProvider)?
    private let engine: SyncEngine?
    private let library: Library
    private let tokens: UserDefaultsSyncTokenStore
    private let defaults: UserDefaults
    private var debounce: Task<Void, Never>?
    private var observing: Task<Void, Never>?
    private let log = Logger(subsystem: "com.t2s.reader", category: "sync")

    public init(provider: (any SyncProvider)?, library: Library, deviceName: String, defaults: UserDefaults = .standard) {
        self.provider = provider
        self.library = library
        self.defaults = defaults
        tokens = UserDefaultsSyncTokenStore(defaults: defaults)
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        engine = provider.map { SyncEngine(provider: $0, store: LibrarySyncStore(library: library, deviceName: deviceName), tokens: tokens, deviceName: deviceName) }
        observing = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: LibraryStore.localChangeNotification) {
                await self?.noteLocalChange()
            }
        }
    }

    public var canEnable: Bool { availability == .available }

    /// The row's subtitle when the toggle cannot be turned on (sync spec §8).
    public var unavailableReason: String? {
        switch availability {
        case .available: return nil
        case .noContainer: return "Needs an iCloud-enabled build"
        case .noAccount: return "Sign in to iCloud in Settings"
        case .restricted, .unavailable: return "iCloud is not available"
        }
    }

    public func refreshAvailability() async {
        guard let provider else { availability = .noContainer; return }
        switch await provider.accountStatus() {
        case .available: availability = .available
        case .noAccount: availability = .noAccount
        case .restricted: availability = .restricted
        case .unavailable(let why): availability = .unavailable(why)
        }
        if isEnabled, !canEnable { isEnabled = false; defaults.set(false, forKey: Self.enabledKey); statusText = unavailableReason ?? "" }
    }

    /// On: keys for the rows that predate sync, then a first full pull and push. Off: nothing runs
    /// and the token is forgotten, so a later "on" pulls everything again.
    public func setEnabled(_ on: Bool) async {
        guard on != isEnabled else { return }
        if on { guard canEnable else { return } }
        isEnabled = on
        defaults.set(on, forKey: Self.enabledKey)
        if on {
            let keyed = (try? await library.backfillContentKeys()) ?? 0
            log.notice("sync on: \(keyed, privacy: .public) documents keyed")
            await syncIfEnabled()
        } else {
            await tokens.save(nil)
            statusText = ""
        }
    }

    public func syncIfEnabled() async {
        guard isEnabled, let engine, !isSyncing else { return }
        isSyncing = true
        statusText = "Syncing…"
        let outcome = await engine.sync()
        isSyncing = false
        if let error = outcome.error {
            statusText = Self.message(for: error)
            if case .account = error { await refreshAvailability() }
        } else {
            statusText = "Synced just now"
        }
    }

    /// Two seconds after the last local write (sync spec §7).
    func noteLocalChange() {
        guard isEnabled else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.syncIfEnabled()
        }
    }

    // MARK: the offer (sync spec §4)
    public func offer(for documentID: UUID) async -> SyncedPosition? {
        try? await library.store.pendingRemotePosition(for: documentID)
    }
    public func dismissOffer(for documentID: UUID) async {
        try? await library.store.clearPendingRemotePosition(for: documentID)
    }

    static func message(for error: SyncError) -> String {
        switch error {
        case .quotaExceeded: return "iCloud is full"
        case .network: return "Couldn't reach iCloud; will try again"
        case .account: return "Sign in to iCloud in Settings"
        case .tokenExpired, .zoneMissing, .other: return "Sync didn't finish; will try again"
        }
    }
}
```

- [ ] **Step 3: The player's two methods**

In `Sources/T2SApp/Player/PlayerModel.swift`, next to `seek(to playhead:)`:

```swift
    /// "Chapter 7, 12:40" for a remote position, against the loaded timeline — what the offer line
    /// says (sync spec §4). nil when nothing is loaded.
    public func describe(_ position: Position) -> String? {
        guard let timeline = coordinator.timeline else { return nil }
        let playhead = PositionResolver.resolve(position, in: timeline)
        let chapter = timeline.chapterIndex(forUtterance: playhead.utteranceIndex)
        let range = timeline.utteranceRange(ofChapter: chapter)
        var seconds = playhead.offset
        for index in range.lowerBound ..< playhead.utteranceIndex { seconds += timeline[utterance: index].duration.seconds }
        return "\(timeline.chapters[chapter].title), \(DurationFormatter.clock(seconds))"
    }

    /// The offer accepted: a seek, which the coordinator saves as this device's newest position.
    public func jump(to position: Position) async {
        guard let timeline = coordinator.timeline else { return }
        await coordinator.seek(to: PositionResolver.resolve(position, in: timeline))
    }
```

(`Timeline.chapterIndex(forUtterance:)` and `utteranceRange(ofChapter:)` exist at `Sources/T2SCore/Model/Timeline.swift:36-50`; `timeline[utterance:]` is the subscript `LibraryTests` uses.)

- [ ] **Step 4: The library model**

In `Sources/T2SApp/Library/LibraryModel.swift`, replace `delete(_:)` and add the fill:

```swift
    public func delete(_ id: UUID, everywhere: Bool = false) async { await perform { try await self.library.delete(id, everywhere: everywhere) } }

    /// The Files picker's answer for a placeholder (sync spec §5): nil on success, else what to tell
    /// the reader.
    public func fillPlaceholder(_ id: UUID, from url: URL, sourceType: SourceType) async -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            _ = try await library.fillPlaceholder(id, from: url, sourceType: sourceType)
            await refresh()
            return nil
        } catch ImportError.differentFile {
            return "That's a different file."
        } catch {
            return error.localizedDescription
        }
    }
```

- [ ] **Step 5: The environment and the scene**

`App/T2SReader/AppEnvironment.swift`: a stored `let syncModel: SyncModel`, an init parameter `syncModel: SyncModel` assigned in `init`, and in `live()` before the `return`:

```swift
        // The provider (sync spec §8): CloudKit when the build carries a container, the fake under
        // `-t2s.sync fake` for a simulator run, else none — the toggle stays off with its reason.
        let container = ((Bundle.main.infoDictionary?["T2SICloudContainer"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let provider: (any SyncProvider)? = UserDefaults.standard.string(forKey: "t2s.sync") == "fake" ? FakeSyncProvider()
            : (container.isEmpty || container.hasPrefix("$(")) ? nil : CloudKitSyncProvider(containerIdentifier: container)
        let syncModel = SyncModel(provider: provider, library: shared.library, deviceName: UIDevice.current.name)
```

and `syncModel: syncModel` in the `AppEnvironment(...)` call. `deleteDocument` gains `everywhere: Bool = false` and passes it to `libraryModel.delete(id, everywhere: everywhere)`. Add `import T2SSync` at the top.

`App/T2SReader/Root/RootPager.swift`, inside the `.onChange(of: scenePhase, initial: true)` handler after `env.coordinator.isForeground = …`:

```swift
            if phase == .active { Task { await env.syncModel.refreshAvailability(); await env.syncModel.syncIfEnabled() } }
```

- [ ] **Step 6: Build the package, then the everyday app**

Run: `swift build` (the root package; `T2SApp` must compile with the new files), then `scripts/build-app.sh` from the repo root of this worktree (simulator; one xcodebuild at a time on this Mac).
Expected: both succeed. `UIDevice` is UIKit: `AppEnvironment.swift` is in the app target, which already imports UIKit through SwiftUI — if not, add `import UIKit`.

- [ ] **Step 7: Commit**

```bash
git add Sources/T2SApp/Sync Sources/T2SApp/Player/PlayerModel.swift Sources/T2SApp/Library/LibraryModel.swift App/T2SReader/AppEnvironment.swift App/T2SReader/Root/RootPager.swift
git commit -m "The sync model: the toggle and its reasons, a cycle on foreground and two seconds after a write, the offer the Reader can show

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Settings, the Reader's offer, the Collection's placeholders

**Files:**
- Modify: `App/T2SReader/Preferences/PreferencesPage.swift:95-101`, `App/T2SReader/Reader/ReaderPage.swift:190-212`, `App/T2SReader/Collection/CollectionPage.swift` (the `confirmationDialog` at 134-144, the row at 322-340, a `.fileImporter`)

**Interfaces:**
- Consumes: `SyncModel`, `PlayerModel.describe(_:)`, `jump(to:)`, `AppEnvironment.deleteDocument(_:everywhere:)`, `LibraryModel.fillPlaceholder(_:from:sourceType:)`, `DocumentSummary.document.isPlaceholder`, `DocumentSummary.remoteDeviceName`, `ImportModel.fetch(link:)` and `confirmPreview()`.

- [ ] **Step 1: Settings**

Replace the disabled toggle in `PreferencesPage.swift`:

```swift
                    section("iCloud sync") {
                        row("Sync positions and bookmarks", subtitle: env.syncModel.unavailableReason ?? env.syncModel.statusText) {
                            Toggle("", isOn: Binding(get: { env.syncModel.isEnabled },
                                                     set: { on in Task { await env.syncModel.setEnabled(on) } }))
                                .labelsHidden()
                                .disabled(!env.syncModel.canEnable && !env.syncModel.isEnabled)
                        }
                    }
```

and `.task { await env.syncModel.refreshAvailability() }` on the page's outer view.

- [ ] **Step 2: The Reader's offer line**

In `ReaderPage.swift`, after the `if let error = player.renderError { … }` block inside the same `VStack`:

```swift
                if let offer = syncOffer, let where_ = player.describe(offer.position), let id = player.current?.id {
                    HStack(spacing: 8) {
                        Text("Continue from \(offer.deviceName) · \(where_)").typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Jump") { Task { await player.jump(to: offer.position); await env.syncModel.dismissOffer(for: id); syncOffer = nil } }
                            .typeRole(.pill)
                        Button { Task { await env.syncModel.dismissOffer(for: id); syncOffer = nil } } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Tokens.ink3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
```

with `@State private var syncOffer: SyncedPosition?` on the page and, on the page's outer view, `.task(id: player.current?.id) { syncOffer = await player.current.map { await env.syncModel.offer(for: $0.id) } ?? nil }` (import `T2SCore` if the file lacks it). Playing on for ten seconds also dismisses it: `.onChange(of: player.elapsed) { old, new in if syncOffer != nil, new - offerShownAt > 10 { … dismiss … } }` with `@State private var offerShownAt: TimeInterval = 0` set when the offer appears — keep it to these two states.

- [ ] **Step 3: The Collection**

In `CollectionRow` (line ~322), under the author line:

```swift
                        if summary.document.isPlaceholder {
                            Text("On \(summary.remoteDeviceName ?? "another device") · tap to add here").typeRole(.meta).foregroundStyle(Tokens.ink3)
                        }
```

In the page, where a row's `onOpen` runs (the closure passed to `CollectionRow`, near line 330): if `summary.document.isPlaceholder`, do not open the sheet; instead:

```swift
    private func addHere(_ summary: DocumentSummary) {
        if summary.document.sourceType == .article, let url = summary.document.sourceURL {
            Task { await env.importModel.fetch(link: url); await env.importModel.confirmPreview(); await env.libraryModel.refresh() }
        } else {
            pendingFill = summary
        }
    }
```

with `@State private var pendingFill: DocumentSummary?`, `@State private var fillMessage: String?`, and on the page:

```swift
        .fileImporter(isPresented: Binding(get: { pendingFill != nil }, set: { if !$0 { pendingFill = nil } }),
                      allowedContentTypes: [.epub, .pdf]) { result in
            guard let summary = pendingFill, case .success(let url) = result else { return }
            Task { fillMessage = await env.libraryModel.fillPlaceholder(summary.id, from: url, sourceType: summary.document.sourceType) }
        }
        .alert("Couldn't add this book", isPresented: Binding(get: { fillMessage != nil }, set: { if !$0 { fillMessage = nil } })) {
            Button("OK") { fillMessage = nil }
        } message: { Text(fillMessage ?? "") }
```

The delete dialog (line 134-144) gains the second choice when sync is on, and its message says what each does:

```swift
        ) { book in
            Button("Delete from this device", role: .destructive) { Task { await env.deleteDocument(book.id) } }
            if env.syncModel.isEnabled {
                Button("Delete everywhere", role: .destructive) { Task { await env.deleteDocument(book.id, everywhere: true) } }
            }
        } message: { _ in
            Text(env.syncModel.isEnabled ? AppEnvironment.deleteMessageWithSync : AppEnvironment.deleteMessage)
        }
```

with, in `AppEnvironment`: `static let deleteMessageWithSync = "This device: removes it, its audio and its progress here; it stays on your other devices. Everywhere: removes it from every device signed into your iCloud."` Do the same in `Queue/DetailsSheet.swift:47-50`, the other delete.

- [ ] **Step 4: Build**

Run: `scripts/build-app.sh` (simulator). Optionally run the simulator with `-t2s.sync fake` and `SIMCTL_CHILD_T2S_SILENT=1` (never sound on the Mac) to see the toggle enable and "Synced just now".
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add App/T2SReader/Preferences/PreferencesPage.swift App/T2SReader/Reader/ReaderPage.swift App/T2SReader/Collection/CollectionPage.swift App/T2SReader/Queue/DetailsSheet.swift App/T2SReader/AppEnvironment.swift
git commit -m "Settings turns sync on when the build and the account allow it; the Reader offers the other device's place; the Collection shows what the other device has and adds it here

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: The per-Mac signing switch

**Files:**
- Modify: `App/project.yml` (the `T2SReaderApp` template: its `entitlements:` block at ~79-82, its `info: properties:` at ~83-86, `settings.base` at ~112), `App/Local.xcconfig.example`
- Create: `App/T2SReader/T2SReader.iCloud.entitlements`
- Keep: `App/T2SReader/T2SReader.entitlements` (tracked; app groups only)

- [ ] **Step 1: project.yml**

In the `T2SReaderApp` template remove the `entitlements:` block (the tracked file stays as it is) and add to the template's `settings.base`:

```yaml
        # Which entitlements file signs the app (sync spec §8): the plain one, app groups only, by
        # default; `Local.xcconfig` on a paid team points at `T2SReader.iCloud.entitlements`, which
        # adds CloudKit with `T2S_ICLOUD_CONTAINER`. The owner's free team cannot carry iCloud, so
        # the default build never mentions it.
        T2S_ENTITLEMENTS: T2SReader/T2SReader.entitlements
        T2S_ICLOUD_CONTAINER: ""
        CODE_SIGN_ENTITLEMENTS: $(T2S_ENTITLEMENTS)
```

and to the template's `info: properties:`:

```yaml
        T2SICloudContainer: $(T2S_ICLOUD_CONTAINER)
```

- [ ] **Step 2: The iCloud entitlements file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>$(T2S_APP_GROUP)</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>$(T2S_ICLOUD_CONTAINER)</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 3: Local.xcconfig.example**

Append:

```
//
// iCloud sync needs a paid team (sync spec §8, §9). On such a Mac, the container under that team
// and the entitlements file that asks for it; the owner's Mac leaves both alone and the toggle
// says "Needs an iCloud-enabled build".
// T2S_ICLOUD_CONTAINER = iCloud.com.antarlabs.t2sreader
// T2S_ENTITLEMENTS = T2SReader/T2SReader.iCloud.entitlements
```

- [ ] **Step 4: Verify both builds still sign and the plist carries the key**

Run, from the worktree's `App/`: `xcodegen generate --quiet`, then `xcodebuild -showBuildSettings -scheme Phone 2>/dev/null | grep -E 'CODE_SIGN_ENTITLEMENTS|T2S_ICLOUD'` — expect `CODE_SIGN_ENTITLEMENTS = T2SReader/T2SReader.entitlements` and an empty container. Then `scripts/build-app.sh` and, when no other xcodebuild is running, the signed device build the HANDOFF documents (`xcodebuild build -scheme Phone -destination "generic/platform=iOS" -configuration Release -derivedDataPath ../.build/DerivedData-App CODE_SIGN_STYLE=Automatic ENABLE_DEBUG_DYLIB=NO -allowProvisioningUpdates`) — it must sign on the owner's free team exactly as before. Then `/usr/libexec/PlistBuddy -c 'Print :T2SICloudContainer' ../.build/DerivedData-App/Build/Products/Release-iphoneos/T2SReaderKokoro.app/Info.plist` prints an empty line.
Expected: both BUILD SUCCEEDED; no iCloud key in the signed app's entitlements (`codesign -d --entitlements - <app>` shows only the app group).

- [ ] **Step 5: Commit**

```bash
git add App/project.yml App/T2SReader/T2SReader.iCloud.entitlements App/Local.xcconfig.example
git commit -m "The iCloud entitlement is a per-Mac switch: the paid team's xcconfig names the container and the entitlements file, the free team's build never mentions iCloud

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: HANDOFF and the branch

**Files:**
- Modify: `docs/HANDOFF.md` (the top "for Harsh" section: a new numbered item and its steps)

- [ ] **Step 1: The hand-off text**

Under "### What's next, in this order", add before item 1:

```markdown
0. **iCloud sync, branch `icloud-sync`** (spec `docs/superpowers/specs/2026-09-11-icloud-sync-design.md`,
   plan `docs/superpowers/plans/2026-09-11-icloud-sync.md`): positions, bookmarks and the library
   list (not files) through the private CloudKit database; the position is offered ("Continue from
   iPhone · Chapter 7, 12:40"), never applied; a book the other device has is a placeholder filled
   by import or by its URL; "Delete everywhere" writes a marker. Built and tested here against a
   fake provider and real `CKRecord`s (`swift test`: the engine's five scenarios, the mapping, the
   store's primitives, the library's keys); the owner's free team cannot carry the entitlement, so
   the rest is yours, in this order: (1) `App/Local.xcconfig`: `T2S_ICLOUD_CONTAINER =
   iCloud.<your bundle id>` and `T2S_ENTITLEMENTS = T2SReader/T2SReader.iCloud.entitlements`,
   `xcodegen generate`, and in Signing & Capabilities the iCloud → CloudKit capability with that
   container under your team; (2) one run on a device signed into iCloud — the first save creates
   the zone `t2s` and the record types `Document` and `Bookmark` in the development environment;
   (3) two devices (a phone and a simulator on the same account will do): import on one, the
   placeholder on the other and fill it, read on one and take the offer on the other, a bookmark
   each way, delete everywhere, airplane mode through a few edits and back; (4) before any
   TestFlight, **Deploy Schema to Production** in CloudKit Dashboard. Merge to `dev` when (3) holds.
```

- [ ] **Step 2: Full suite, commit, push the branch**

Run: `swift test` — expected green, about 510 tests. Then:

```bash
git add docs/HANDOFF.md
git commit -m "HANDOFF: iCloud sync on branch icloud-sync — what is built, what Harsh's account finishes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin icloud-sync
```

The branch is pushed; `dev` is untouched until Harsh's two-device run holds.
