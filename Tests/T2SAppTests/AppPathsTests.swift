import Foundation
import Testing
@testable import T2SApp

@Suite struct AppPathsTests {
    @Test func containerRootLivesUnderTheGivenBase() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("t2s-app-\(UUID().uuidString)")
        let root = try AppPaths.containerRoot(under: base)
        #expect(root.lastPathComponent == "t2s")
        #expect(root.deletingLastPathComponent().path == base.standardizedFileURL.path)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(try AppPaths.containerRoot(under: base) == root)             // idempotent
    }

    @Test func defaultsAreSensible() {
        #expect(AppPaths.defaultAudioCapacityBytes == 2 * 1024 * 1024 * 1024)
        #expect(AppPaths.audioCapacityKey == "audioCapacityBytes")
        #expect(AppPaths.prepareBudgetKey == "prepareBudgetSeconds")
    }
}
