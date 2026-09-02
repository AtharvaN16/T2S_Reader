// Tests/T2SLibraryTests/LibraryPathsTests.swift
import Foundation
import Testing
import T2SCore
@testable import T2SLibrary

@Suite struct LibraryPathsTests {
    let paths = LibraryPaths(root: URL(fileURLWithPath: "/tmp/t2s-root/"))
    let id = UUID(uuidString: "0C1A9E2E-6D2B-4A8C-9F0D-1B2C3D4E5F60")!

    @Test func layoutIsFixed() {
        #expect(paths.databaseURL.path == "/tmp/t2s-root/Library.store")
        #expect(paths.audioDirectory.path == "/tmp/t2s-root/Audio")
        #expect(paths.documentDirectory(id).path == "/tmp/t2s-root/Documents/\(id.uuidString)")
        #expect(paths.sourceURL(id, type: .epub).lastPathComponent == "source.epub")
        #expect(paths.sourceURL(id, type: .article).lastPathComponent == "source.epub")
        #expect(paths.sourceURL(id, type: .pdf).lastPathComponent == "source.pdf")
        #expect(paths.originalHTMLURL(id).lastPathComponent == "original.html")
        #expect(paths.coverURL(id).lastPathComponent == "cover.jpg")
    }

    @Test func relativePathsRoundTrip() {
        let cover = paths.coverURL(id)
        let rel = paths.relativePath(of: cover)
        #expect(rel == "Documents/\(id.uuidString)/cover.jpg")
        #expect(paths.url(forRelativePath: rel!).path == cover.path)
        #expect(paths.relativePath(of: URL(fileURLWithPath: "/elsewhere/cover.jpg")) == nil)
        #expect(paths.relativePath(of: URL(fileURLWithPath: "/tmp/t2s-root")) == nil)
    }
}
