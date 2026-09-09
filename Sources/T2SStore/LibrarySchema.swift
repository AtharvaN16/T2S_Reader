import SwiftData

/// Every persisted thing carries a version (spec §3.7.4). The schema itself is versioned so a
/// change is a migration stage, not a rewrite: `LibrarySchemaV1` (Plan 3) is frozen in its own
/// file, `LibrarySchemaV2` (Plan 16) is the current one, and the rest of the module names the
/// current classes through these aliases.
typealias StoredDocument = LibrarySchemaV2.StoredDocument
typealias StoredChapter = LibrarySchemaV2.StoredChapter
typealias StoredBookmark = LibrarySchemaV2.StoredBookmark
typealias StoredPronunciation = LibrarySchemaV2.StoredPronunciation

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self, LibrarySchemaV2.self] }
    /// V1 → V2 adds two optional columns: Core Data infers the mapping.
    static var stages: [MigrationStage] { [.lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self)] }
}
