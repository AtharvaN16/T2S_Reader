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

@Suite struct AppGroupIdentifierTests {
    @Test func theOwnersGroupIsTheDefaultWhenTheBundleSaysNothing() {
        #expect(AppPaths.appGroupIdentifier(infoDictionary: [:]) == "group.com.t2s.reader")
        #expect(AppPaths.defaultAppGroupIdentifier == "group.com.t2s.reader")
    }

    @Test func aBlankOrUnexpandedValueFallsBackToTheDefault() {
        #expect(AppPaths.appGroupIdentifier(infoDictionary: ["T2SAppGroupIdentifier": ""]) == "group.com.t2s.reader")
        #expect(AppPaths.appGroupIdentifier(infoDictionary: ["T2SAppGroupIdentifier": "  "]) == "group.com.t2s.reader")
        #expect(AppPaths.appGroupIdentifier(infoDictionary: ["T2SAppGroupIdentifier": "$(T2S_APP_GROUP)"]) == "group.com.t2s.reader")
    }

    @Test func aRealValueWins() {
        #expect(AppPaths.appGroupIdentifier(infoDictionary: ["T2SAppGroupIdentifier": "group.com.antarlabs.t2sreader"])
                == "group.com.antarlabs.t2sreader")
    }
}
