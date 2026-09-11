import Foundation
import Testing
@testable import T2SKokoro

@Suite struct KokoroPlanCacheTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "t2s-plancache-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A caches directory as iOS lays it out: the plan cache under the bundle identifier, beside
    /// Metal's caches and the timing log.
    private func caches(bundleID: String, planBytes: [Int]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "plancache-\(UUID().uuidString)")
        let plans = KokoroPlanCache.directory(cachesDirectory: root, bundleIdentifier: bundleID)
        let entry = plans.appending(path: "23G83/ABC/DEF.bundle/H12.bundle")
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
        for (index, bytes) in planBytes.enumerated() {
            try Data(repeating: 0, count: bytes).write(to: entry.appending(path: "plan\(index).bin"))
        }
        let metal = root.appending(path: bundleID).appending(path: "com.apple.metal")
        try FileManager.default.createDirectory(at: metal, withIntermediateDirectories: true)
        try Data("functions".utf8).write(to: metal.appending(path: "functions.list"))
        try Data("00:00 kokoro stage x loaded\n".utf8).write(to: root.appending(path: "kokoro-timing.log"))
        return root
    }

    @Test func theWipeRemovesThePlanCacheAloneAndReportsItsBytes() throws {
        let root = try caches(bundleID: "com.t2s.reader", planBytes: [1000, 24])
        let plans = KokoroPlanCache.directory(cachesDirectory: root, bundleIdentifier: "com.t2s.reader")
        #expect(KokoroPlanCache.size(of: plans) == 1024)
        #expect(KokoroPlanCache.wipe(plans) == 1024)
        #expect(!FileManager.default.fileExists(atPath: plans.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "com.t2s.reader/com.apple.metal/functions.list").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "kokoro-timing.log").path(percentEncoded: false)))
        #expect(KokoroPlanCache.wipe(plans) == 0)
    }

    /// The plans on a phone that warmed before this record existed belong to nobody on record:
    /// wiped on the first launch that asks. The same identity asking again keeps its own plans; a
    /// new install's identity wipes them.
    @Test func aCacheIsKeptForItsOwnIdentityAndWipedForAnyOther() throws {
        let defaults = freshDefaults()
        let root = try caches(bundleID: "com.t2s.reader", planBytes: [4096])
        let plans = KokoroPlanCache.directory(cachesDirectory: root, bundleIdentifier: "com.t2s.reader")
        #expect(KokoroPlanCache.prepare(for: "/install/a|26.6.1|/m|2e878c6a", cachesDirectory: root, bundleIdentifier: "com.t2s.reader", defaults: defaults) == 4096)
        #expect(!FileManager.default.fileExists(atPath: plans.path(percentEncoded: false)))

        try FileManager.default.createDirectory(at: plans.appending(path: "23G83/NEW"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 512).write(to: plans.appending(path: "23G83/NEW/plan.bin"))
        #expect(KokoroPlanCache.prepare(for: "/install/a|26.6.1|/m|2e878c6a", cachesDirectory: root, bundleIdentifier: "com.t2s.reader", defaults: defaults) == nil)
        #expect(KokoroPlanCache.size(of: plans) == 512)

        #expect(KokoroPlanCache.prepare(for: "/install/b|26.6.1|/m|2e878c6a", cachesDirectory: root, bundleIdentifier: "com.t2s.reader", defaults: defaults) == 512)
        #expect(!FileManager.default.fileExists(atPath: plans.path(percentEncoded: false)))
        #expect(defaults.string(forKey: KokoroPlanCache.identityKey) == "/install/b|26.6.1|/m|2e878c6a")
    }

    @Test func aPhoneWithNoPlanCacheYetRecordsTheIdentityAndRemovesNothing() {
        let defaults = freshDefaults()
        let root = FileManager.default.temporaryDirectory.appending(path: "plancache-empty-\(UUID().uuidString)")
        #expect(KokoroPlanCache.prepare(for: "/install/a|26.6.1|/m|2e878c6a", cachesDirectory: root, bundleIdentifier: "com.t2s.reader", defaults: defaults) == 0)
        #expect(defaults.string(forKey: KokoroPlanCache.identityKey) == "/install/a|26.6.1|/m|2e878c6a")
    }
}
