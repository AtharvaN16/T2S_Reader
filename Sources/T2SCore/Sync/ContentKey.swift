// Sources/T2SCore/Sync/ContentKey.swift
import CryptoKit
import Foundation

/// The identity two devices meet on (sync spec §2): two imports of the same book get two local
/// `UUID`s (design spec §3.7.1), so a document's sync record is named by its content — the bytes
/// of an EPUB or PDF, the canonical URL of an article — and never by a local id.
public enum ContentKey {
    /// `sha256:<hex>` of `data`.
    public static func file(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `sha256:<hex>` of the file at `url`, read in 1 MB pieces so a 300 MB PDF never sits in memory.
    public static func file(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let piece = try handle.read(upToCount: 1 << 20), !piece.isEmpty {
            hasher.update(data: piece)
        }
        return "sha256:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// `url:<canonical>`: scheme and host lowercased, the fragment dropped, tracking query items
    /// dropped, everything else — path, the other query items and their order, a trailing slash —
    /// kept as given.
    public static func article(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "url:" + url.absoluteString }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        parts.fragment = nil
        if let items = parts.queryItems {
            let kept = items.filter { !isTracking($0.name) }
            parts.queryItems = kept.isEmpty ? nil : kept
        }
        return "url:" + (parts.string ?? url.absoluteString)
    }

    private static func isTracking(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("utm_") || lower == "fbclid" || lower == "gclid"
    }

    /// The CloudKit record name for a key: `doc-` + the SHA-256 of the key, so a URL of any length
    /// or alphabet fits CloudKit's 255 ASCII characters and the same key always names the same record.
    public static func recordName(for key: String) -> String {
        "doc-" + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
