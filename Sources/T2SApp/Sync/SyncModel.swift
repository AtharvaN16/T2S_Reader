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
        // `tokens` built from `defaults` before `self.defaults` is set: constructing the actor
        // hands `defaults` to a different isolation domain, and Swift 6's sendability check wants
        // that to be the parameter's first use, not a second alias once `self` (main-actor) already
        // holds it.
        let tokenStore = UserDefaultsSyncTokenStore(defaults: defaults)
        self.defaults = defaults
        // `tokens` is read here through a local binding, not `self.tokens`: an implicit `self.`
        // property read inside the `.map` closure below counts as capturing `self`, which the
        // initializer cannot do before every stored property — `engine` itself, on this very line —
        // has a value.
        tokens = tokenStore
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        engine = provider.map { SyncEngine(provider: $0, store: LibrarySyncStore(library: library, deviceName: deviceName), tokens: tokenStore, deviceName: deviceName) }
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
