import Foundation
import Testing
@testable import T2SApp

/// The app icon in its ten liveries (2026-09-19): the wizard reading by the light of his book, as
/// drawn in the Figma file, chosen on Settings → Appearance. iOS keeps the choice, not the app —
/// `UIApplication.alternateIconName` is the one true answer — so the catalog here is only the
/// list: which icons there are, what they are called, and which asset each one is.
@Suite struct AppIconTests {
    @Test func theDefaultComesFirstAndIsThePrimaryIcon() {
        #expect(AppIcon.allCases.first == .standard)
        #expect(AppIcon.standard.alternateIconName == nil)
        #expect(AppIcon.standard.title == "Default")
        #expect(AppIcon.allCases.count == 10)
    }

    @Test func everyOtherIconIsAnAlternateWithAssetsOfItsOwn() {
        for icon in AppIcon.allCases where icon != .standard {
            #expect(icon.alternateIconName?.hasPrefix("AppIcon-") == true, "\(icon)")
        }
        let all = AppIcon.allCases
        #expect(Set(all.map(\.title)).count == all.count)
        #expect(Set(all.map(\.previewAssetName)).count == all.count)
        #expect(Set(all.compactMap(\.alternateIconName)).count == all.count - 1)
    }

    /// What iOS reports comes back as a choice; a name it no longer knows is the default rather
    /// than a crash or a blank grid.
    @Test func theSystemsAnswerMapsBackToAChoice() {
        #expect(AppIcon(alternateIconName: nil) == .standard)
        #expect(AppIcon(alternateIconName: "AppIcon-Candy") == .candy)
        #expect(AppIcon(alternateIconName: "AppIcon-Gone") == .standard)
    }

    /// The build names the alternates in `App/project.yml` and the catalog names them here. If the
    /// two drift, a tap on the grid asks iOS for an icon the build never gave it, and it refuses.
    @Test func theBuildSettingListsExactlyTheAlternates() throws {
        let text = try String(contentsOf: Self.repo.appendingPathComponent("App/project.yml"), encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first { $0.contains("ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES") })
        let value = line.split(separator: ":", maxSplits: 1)[1].replacingOccurrences(of: "\"", with: "")
        let listed = Set(value.split(separator: " ").map(String.init))
        #expect(listed == Set(AppIcon.allCases.compactMap(\.alternateIconName)))
    }

    /// Every icon has its two assets in the catalog: the icon set the build compiles, and the
    /// preview the grid draws — the compiled icon cannot be loaded by name at run time.
    @Test func everyIconHasItsAssetsInTheCatalog() {
        let catalog = Self.repo.appendingPathComponent("App/T2SReader/Assets.xcassets")
        for icon in AppIcon.allCases {
            let set = catalog.appendingPathComponent("\(icon.alternateIconName ?? "AppIcon").appiconset/Contents.json")
            let preview = catalog.appendingPathComponent("AppIconPreviews/\(icon.previewAssetName).imageset/Contents.json")
            #expect(FileManager.default.fileExists(atPath: set.path), "missing \(set.path)")
            #expect(FileManager.default.fileExists(atPath: preview.path), "missing \(preview.path)")
        }
    }

    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
