// Sources/T2SSync/InMemorySyncTokenStore.swift
import T2SCore

public actor InMemorySyncTokenStore: SyncTokenStore {
    private var token: SyncToken?
    public init() {}
    public func load() -> SyncToken? { token }
    public func save(_ token: SyncToken?) { self.token = token }
}
