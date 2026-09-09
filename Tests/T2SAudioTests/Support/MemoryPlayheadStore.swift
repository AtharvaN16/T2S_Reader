import Foundation
import T2SCore
@testable import T2SAudio

actor MemoryPlayheadStore: PlayheadStore {
    private(set) var saved: [(UUID, SavedPlayhead)] = []
    func save(_ playhead: SavedPlayhead, for documentID: UUID) { saved.append((documentID, playhead)) }
    var last: Position? { saved.last?.1.position }
    var lastSaved: SavedPlayhead? { saved.last?.1 }
}
