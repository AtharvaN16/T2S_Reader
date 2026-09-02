import Foundation
import T2SCore
@testable import T2SAudio

actor MemoryPlayheadStore: PlayheadStore {
    private(set) var saved: [(UUID, Position)] = []
    func save(_ position: Position, for documentID: UUID) { saved.append((documentID, position)) }
    var last: Position? { saved.last?.1 }
}
