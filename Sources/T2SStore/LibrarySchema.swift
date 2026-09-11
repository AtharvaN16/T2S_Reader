import SwiftData

/// Every persisted thing carries a version (spec §3.7.4). The schema itself is versioned so a
/// change is a migration stage, not a rewrite: `LibrarySchemaV1` (Plan 3), `LibrarySchemaV2`
/// (Plan 16) and `LibrarySchemaV3` (iCloud sync) are frozen in their own files,
/// `LibrarySchemaV4` (bookmark notes) is the current one, and the rest of the module names the
/// current classes through these aliases.
typealias StoredDocument = LibrarySchemaV4.StoredDocument
typealias StoredChapter = LibrarySchemaV4.StoredChapter
typealias StoredBookmark = LibrarySchemaV4.StoredBookmark
typealias StoredPronunciation = LibrarySchemaV4.StoredPronunciation
typealias StoredTombstone = LibrarySchemaV4.StoredTombstone

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LibrarySchemaV1.self, LibrarySchemaV2.self, LibrarySchemaV3.self, LibrarySchemaV4.self]
    }
    /// V1 → V2 adds two optional columns; V2 → V3 adds optional and defaulted columns and one
    /// model; V3 → V4 adds one optional column. Core Data infers all three mappings.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self),
         .lightweight(fromVersion: LibrarySchemaV2.self, toVersion: LibrarySchemaV3.self),
         .lightweight(fromVersion: LibrarySchemaV3.self, toVersion: LibrarySchemaV4.self)]
    }
}
