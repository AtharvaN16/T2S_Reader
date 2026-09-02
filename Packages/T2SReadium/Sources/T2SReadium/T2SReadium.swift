import ReadiumShared
import T2SCore

/// Readium adapter: opens EPUBs into `ChapterInput`s and converts `Position` ↔ `Locator` at the
/// boundary (spec §3.7.2). Nothing from ReadiumShared leaves this module.
public enum T2SReadium {
    /// The T2SCore schema this build of T2SReadium was compiled against.
    public static let coreSchemaVersion = Versions.schema
}
