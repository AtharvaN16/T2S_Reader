// Sources/T2SApp/Sync/UserDefaultsSyncTokenStore.swift
import Foundation
import T2SCore

/// `UserDefaults` is documented thread-safe but its SDK's `Sendable` conformance is explicitly
/// marked unavailable (`@_nonSendable(_assumed)`), which makes passing one from `SyncModel`
/// (`@MainActor`) into this actor's `init` a Swift 6 "sending" error otherwise — the brief's
/// `SyncModel` needs the same instance on both sides of that boundary.
extension UserDefaults: @unchecked @retroactive Sendable {}

public actor UserDefaultsSyncTokenStore: SyncTokenStore {
    public static let key = "sync.token"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> SyncToken? { defaults.data(forKey: Self.key).map(SyncToken.init(data:)) }
    public func save(_ token: SyncToken?) { defaults.set(token?.data, forKey: Self.key) }
}
