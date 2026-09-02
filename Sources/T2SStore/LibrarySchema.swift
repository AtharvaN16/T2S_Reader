import SwiftData

/// Every persisted thing carries a version (spec §3.7.4). The schema itself is versioned here so a
/// future change is a migration stage, not a rewrite. V1 is the Plan 3 schema.
enum LibrarySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static let models: [any PersistentModel.Type] = [StoredDocument.self, StoredChapter.self, StoredBookmark.self, StoredPronunciation.self]
}

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [LibrarySchemaV1.self]
    static let stages: [MigrationStage] = []
}
