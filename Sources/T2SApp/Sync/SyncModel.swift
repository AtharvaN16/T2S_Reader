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

    /// Awaited after a cycle that pulled something, so the lists show what arrived instead of
    /// waiting for the next screen change. `AppEnvironment` refreshes `LibraryModel` here.
    public var onPulled: (@MainActor () async -> Void)?

    /// No two cycles closer together than this, however often this device writes (sync spec §7): a
    /// position is saved at every utterance boundary, so listening alone would otherwise mean a
    /// CloudKit round trip every couple of seconds for hours.
    static let minimumInterval: TimeInterval = 60
    /// The debounce the spec asks for: a cycle two seconds after the last local write.
    static let debounceInterval: TimeInterval = 2

    private let provider: (any SyncProvider)?
    private let engine: SyncEngine?
    private let syncStore: LibrarySyncStore
    private let library: Library
    private let tokens: UserDefaultsSyncTokenStore
    // `UserDefaults.standard` by name, at the point of use: `UserDefaults` is not `Sendable` to
    // Swift 6, so it is never stored as a parameter or captured value — every isolation domain
    // that needs it (this model, `UserDefaultsSyncTokenStore`) names `.standard` itself
    // (KokoroComposition.swift ~332).
    private var defaults: UserDefaults { .standard }
    private var debounce: Task<Void, Never>?
    private var observing: Task<Void, Never>?
    /// A trigger that arrived while a cycle was running: it runs once that cycle ends rather than
    /// being dropped, since whatever it was about was written after the cycle read the store.
    private var rerunRequested = false
    /// When the last cycle finished, for the floor above.
    private var lastSyncFinishedAt: Date?
    private let log = Logger(subsystem: "com.t2s.reader", category: "sync")

    public init(provider: (any SyncProvider)?, library: Library, deviceName: String) {
        self.provider = provider
        self.library = library
        // `tokens` is read here through a local binding, not `self.tokens`: an implicit `self.`
        // property read inside the `.map` closure below counts as capturing `self`, which the
        // initializer cannot do before every stored property — `engine` itself, on this very line —
        // has a value.
        let tokenStore = UserDefaultsSyncTokenStore()
        tokens = tokenStore
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        // The adapter is kept, not built inline: `setOnRemove` wires the player's hook into it, so a
        // pulled deletion cannot pull a playing book out from under the transport.
        let adapter = LibrarySyncStore(library: library, deviceName: deviceName)
        syncStore = adapter
        engine = provider.map { SyncEngine(provider: $0, store: adapter, tokens: tokenStore, deviceName: deviceName) }
        observing = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: LibraryStore.localChangeNotification) {
                self?.noteLocalChange()
            }
        }
    }

    isolated deinit {
        observing?.cancel()
        debounce?.cancel()
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
        if let provider {
            switch await provider.accountStatus() {
            case .available: availability = .available
            case .noAccount: availability = .noAccount
            case .restricted: availability = .restricted
            case .unavailable(let why): availability = .unavailable(why)
            }
        } else {
            availability = .noContainer
        }
        // Every branch above — including the no-container case — falls through to this check. Only a
        // state that will not fix itself turns the toggle off and persists it off: no container, no
        // account, a restricted account. `.unavailable` is CloudKit saying "not right now" — a
        // device that has just booted, an account temporarily out of reach — and a sync the reader
        // switched on has to survive it, or one moment of bad luck ends syncing for good.
        switch availability {
        case .available:
            break
        case .noContainer, .noAccount, .restricted:
            if isEnabled {
                isEnabled = false
                defaults.set(false, forKey: Self.enabledKey)
                statusText = unavailableReason ?? ""
            }
        case .unavailable(let reason):
            statusText = "iCloud isn't available right now (\(reason))"
        }
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

    /// Coalesced, never dropped (sync spec §7): a trigger that arrives while a cycle runs schedules
    /// one more, which runs the moment this one ends — the write behind it landed after this cycle
    /// had already read the store.
    public func syncIfEnabled() async {
        guard isEnabled, let engine else { return }
        if isSyncing { rerunRequested = true; return }
        isSyncing = true
        statusText = "Syncing…"
        repeat {
            rerunRequested = false
            let outcome = await engine.sync()
            lastSyncFinishedAt = Date()
            if let error = outcome.error {
                statusText = Self.message(for: error)
                if case .account = error { await refreshAvailability() }
            } else {
                statusText = "Synced just now"
            }
            // What arrived is in the store; the lists are still showing what was there before it.
            if outcome.pulled > 0 { await onPulled?() }
        } while rerunRequested
        isSyncing = false
    }

    /// The app's hook for a pulled deletion: awaited before the document is removed.
    public func setOnRemove(_ handler: @escaping @Sendable (UUID) async -> Void) async {
        await syncStore.setOnRemove(handler)
    }

    /// Two seconds after the last local write (sync spec §7) — but never sooner than a minute after
    /// the last cycle finished. The coordinator saves the position at every utterance boundary and
    /// each save is a local change: without the floor, listening to a book meant a CloudKit cycle
    /// every few seconds for as long as it played. A pause, a seek or a finish still syncs two
    /// seconds later, because the saves stop with them.
    func noteLocalChange() {
        guard isEnabled else { return }
        debounce?.cancel()
        let sinceLastCycle = lastSyncFinishedAt.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        let delay = max(Self.debounceInterval, Self.minimumInterval - sinceLastCycle)
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
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
