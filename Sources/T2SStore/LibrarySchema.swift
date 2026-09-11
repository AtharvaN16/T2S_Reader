import SwiftData

/// Every persisted thing carries a version (spec §3.7.4). The schema itself is versioned so a
/// change is a migration stage, not a rewrite: `LibrarySchemaV1` (Plan 3) and `LibrarySchemaV2`
/// (Plan 16) are frozen in their own files, `LibrarySchemaV3` (iCloud sync) is the current one, and
/// the rest of the module names the current classes through these aliases.
typealias StoredDocument = LibrarySchemaV3.StoredDocument
typealias StoredChapter = LibrarySchemaV3.StoredChapter
typealias StoredBookmark = LibrarySchemaV3.StoredBookmark
typealias StoredPronunciation = LibrarySchemaV3.StoredPronunciation
typealias StoredTombstone = LibrarySchemaV3.StoredTombstone

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self, LibrarySchemaV2.self, LibrarySchemaV3.self] }
    /// V1 → V2 adds two optional columns; V2 → V3 adds optional and defaulted columns and one model:
    /// Core Data infers both mappings.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self),
         .lightweight(fromVersion: LibrarySchemaV2.self, toVersion: LibrarySchemaV3.self)]
    }
}
