import T2SCore

/// The app's models and formatters, kept free of UIKit and Readium so they run under `swift test`.
public enum T2SApp {
    /// The T2SCore schema this build of T2SApp was compiled against.
    public static let coreSchemaVersion = Versions.schema
}
