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

    /// A position saved on each device before either syncs is not a real conflict on the record's
    /// clock (only one of them is ever newer), but the offer mechanism must not eat the loser's edit:
    /// A's own newer save still has to reach B once the dust settles.
    @Test func aLocalPositionSavedDuringAConflictStillReachesTheOtherDevice() async throws {
        let d = Devices()
        await d.a.importLocal("k", title: "Book", at: t(1))
        _ = await d.engineA.sync(); _ = await d.engineB.sync()

        await d.b.savePosition("k", 0.4, at: t(10), device: "iPad")
        await d.a.savePosition("k", 0.6, at: t(20), device: "iPhone")

        _ = await d.engineB.sync()
        _ = await d.engineA.sync()
        #expect(await d.a.documents["k"]?.resume?.position.progression == 0.6)
        #expect(await d.a.dirtyRecords().isEmpty)

        _ = await d.engineB.sync()
        #expect(await d.b.pending["k"]?.position.progression == 0.6)
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

    /// A deletion beats anything older than it, but a newer local edit outlives an older deletion
    /// marker (sync spec §4) — the marker doesn't win just because it arrived first.
    @Test func aNewerLocalEditOutlivesAnOlderDeletionMarker() async throws {
        let d = Devices()
        await d.a.importLocal("k", title: "Book", at: t(1))
        _ = await d.engineA.sync(); _ = await d.engineB.sync()

        await d.b.deleteEverywhere("k", at: t(50))
        await d.a.savePosition("k", 0.5, at: t(60), device: "iPhone")

        for _ in 0..<2 {
            _ = await d.engineA.sync()
            _ = await d.engineB.sync()
        }
        #expect(await d.a.documents["k"] != nil)

        // B's deletion marker can never outlive A's edit; it must stop retrying, not haunt every
        // future cycle.
        #expect(await d.b.dirtyRecords().isEmpty)
        #expect(await d.b.tombstones.isEmpty)
        #expect(await d.a.documents["k"] != nil)
    }
}
