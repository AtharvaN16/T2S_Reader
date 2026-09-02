import Foundation

/// The little XML the article writer needs: escaping, well-formedness through `XMLParser`, and
/// plain text for the "little text" check (spec §6).
enum XHTML {
    static let namespace = "http://www.w3.org/1999/xhtml"

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }

    /// Throws `ImportError.malformedBody` unless `fragment` parses as XML inside an XHTML wrapper.
    static func validateFragment(_ fragment: String) throws {
        _ = try plainText(ofFragment: fragment)
    }

    static func plainText(ofFragment fragment: String) throws -> String {
        try plainText(ofDocument: "<div xmlns=\"\(namespace)\">\(fragment)</div>")
    }

    /// Concatenated character data of a well-formed XML document; `ImportError.malformedBody` otherwise.
    static func plainText(ofDocument xml: String) throws -> String {
        let parser = XMLParser(data: Data(xml.utf8))
        let collector = TextCollector()
        parser.delegate = collector
        guard parser.parse() else {
            let reason = parser.parserError.map { "\($0.localizedDescription)" } ?? "unknown error"
            throw ImportError.malformedBody("line \(parser.lineNumber): \(reason)")
        }
        return collector.text
    }

    private final class TextCollector: NSObject, XMLParserDelegate {
        var text = ""
        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    }
}
