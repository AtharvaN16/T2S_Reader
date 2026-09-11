// Tests/T2SCoreTests/Sync/ContentKeyTests.swift
import Foundation
import Testing
@testable import T2SCore

@Suite struct ContentKeyTests {
    /// The key is the URL as a reader would recognise it: host case, fragments and tracking
    /// parameters are not part of the article (spec §2).
    @Test(arguments: [
        ("https://Example.com/a/b?utm_source=x&id=7#top", "url:https://example.com/a/b?id=7"),
        ("HTTP://example.com/a/b/", "url:http://example.com/a/b/"),
        ("https://example.com/a?fbclid=1&gclid=2", "url:https://example.com/a"),
        ("https://example.com/a?z=1&a=2", "url:https://example.com/a?z=1&a=2"),
        ("https://example.com", "url:https://example.com"),
    ])
    func articleKeysAreCanonical(input: String, expected: String) {
        #expect(ContentKey.article(URL(string: input)!) == expected)
    }

    @Test func fileKeysAreTheSHA256OfTheBytes() throws {
        let data = Data("the same bytes".utf8)
        #expect(ContentKey.file(data).hasPrefix("sha256:") && ContentKey.file(data).count == 7 + 64)
        let url = FileManager.default.temporaryDirectory.appending(path: "ck-\(UUID().uuidString).bin")
        try data.write(to: url)
        #expect(try ContentKey.file(at: url) == ContentKey.file(data))
        #expect(ContentKey.file(data) != ContentKey.file(Data("other bytes".utf8)))
    }

    @Test func recordNamesAreShortASCIIAndStable() {
        let long = "url:https://example.com/" + String(repeating: "ä", count: 400)
        let name = ContentKey.recordName(for: long)
        #expect(name.hasPrefix("doc-"))
        #expect(name.count == 68)
        #expect(name.allSatisfy { $0.isASCII })
        #expect(ContentKey.recordName(for: long) == name)
    }
}
