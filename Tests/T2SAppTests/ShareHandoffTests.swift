import Foundation
import Testing
@testable import T2SApp

@Suite struct ShareHandoffTests {
    @Test func appGroupRootAndHandoffURLAreStable() throws {
        #expect(AppPaths.appGroupIdentifier == "group.com.t2s.reader")
        let root = try AppPaths.containerRoot(under: URL(filePath: "/tmp/t2s-group"))
        #expect(LibraryHandoff.url(for: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!).absoluteString
                == "t2s://import?id=00000000-0000-0000-0000-000000000001")
        #expect(LibraryHandoff.documentID(from: URL(string: "t2s://import?id=bad")!) == nil)
        #expect(root.lastPathComponent == "t2s")
    }
}
