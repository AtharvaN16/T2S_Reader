import Foundation

/// Where resume positions go (spec §5: local is the source of truth). `T2SStore.LibraryStore` conforms.
public protocol PlayheadStore: Sendable {
    func save(_ position: Position, for documentID: UUID) async
}
