import Foundation
import T2SCore

/// Where resume positions go (spec §5: local is the source of truth). Plan 3 provides SwiftData.
public protocol PlayheadStore: Sendable {
    func save(_ position: Position, for documentID: UUID) async
}
