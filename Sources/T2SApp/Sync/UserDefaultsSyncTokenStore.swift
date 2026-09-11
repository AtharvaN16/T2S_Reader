// Sources/T2SApp/Sync/UserDefaultsSyncTokenStore.swift
import Foundation
import T2SCore

public actor UserDefaultsSyncTokenStore: SyncTokenStore {
    public static let key = "sync.token"
    // `UserDefaults.standard` by name, at the point of use: `UserDefaults` is not `Sendable` to
    // Swift 6, so it is never stored as a parameter or a captured value crossing into this actor —
    // each isolation domain that needs it names `.standard` itself (KokoroComposition.swift ~332).
    private var defaults: UserDefaults { .standard }
    public init() {}
    public func load() -> SyncToken? { defaults.data(forKey: Self.key).map(SyncToken.init(data:)) }
    public func save(_ token: SyncToken?) { defaults.set(token?.data, forKey: Self.key) }
}
