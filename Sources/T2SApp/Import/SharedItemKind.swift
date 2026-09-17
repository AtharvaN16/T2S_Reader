import Foundation
import T2SCore
import UniformTypeIdentifiers

/// What a shared attachment actually is, decided from every type it registers and the name it
/// suggests — rather than from the order the Share Extension happens to ask in.
///
/// The order matters because a sender may offer the same book twice over. AirDropping an EPUB from
/// the Mac hands the phone a provider that carries the file *and* its name as plain text; asking
/// "is there text?" early enough imports the name and nothing else, and the library gets a book
/// that is only a title (owner, 2026-09-16 — which is why the owner had been routing every book
/// through Apple Books instead). Bytes always win over a name.
public enum SharedItemKind: Hashable, Sendable {
    /// A book we can read, and the type identifier to load a file representation for.
    case book(SourceType, typeIdentifier: String)
    /// A URL — which may still be a `file://` one the sender described as a link.
    case link
    case text
    case unknown

    public static func of(typeIdentifiers: [String], suggestedName: String?) -> SharedItemKind {
        // A provider that names the kind it holds is believed first.
        for identifier in typeIdentifiers {
            guard let type = UTType(identifier) else { continue }
            if type.conforms(to: .epub) { return .book(.epub, typeIdentifier: identifier) }
            if type.conforms(to: .pdf) { return .book(.pdf, typeIdentifier: identifier) }
        }
        // Then the file's own name, for a sender that describes an EPUB as bytes and nothing more:
        // load it under whichever type carries those bytes, never under the text or the URL beside
        // them.
        if let name = suggestedName, let source = sourceType(forName: name),
           let identifier = typeIdentifiers.first(where: { carriesFile($0) }) {
            return .book(source, typeIdentifier: identifier)
        }
        if typeIdentifiers.contains(where: { UTType($0)?.conforms(to: .url) == true }) { return .link }
        if typeIdentifiers.contains(where: { UTType($0)?.conforms(to: .text) == true }) { return .text }
        return .unknown
    }

    /// True when shared text is only a file's name. Importing that as an article is the bug above
    /// wearing a different hat: better to say the file itself did not come through.
    public static func isJustAFileName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200,
              !trimmed.contains(where: \.isNewline) else { return false }
        return sourceType(forName: trimmed) != nil
    }

    static func sourceType(forName name: String) -> SourceType? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch URL(fileURLWithPath: trimmed).pathExtension.lowercased() {
        case "epub": return .epub
        case "pdf": return .pdf
        default: return nil
        }
    }

    /// A type whose items are the file's own bytes: everything that is data without being the text
    /// or the address *about* a file. `public.plain-text` and `public.file-url` both conform to
    /// `public.data`, and loading either as a file gives a name, not a book.
    private static func carriesFile(_ identifier: String) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: .data) && !type.conforms(to: .text) && !type.conforms(to: .url)
    }
}
