import Foundation

/// The little XML the article writer needs: escaping, well-formedness through `XMLParser`, and
/// plain text for the "little text" check (spec §6). Also the sanitization boundary: the fragment
/// is attacker-influenced content (Share Extension Readability output, or worse), and it lands in a
/// file Plan 4 renders in Readium's WKWebView, so scripts and event handlers are rejected outright
/// rather than merely checked for well-formedness.
enum XHTML {
    static let namespace = "http://www.w3.org/1999/xhtml"
    static let epubNamespace = "http://www.idpf.org/2007/ops"
    /// Elements that never belong in an article body.
    private static let rejectedElements: Set<String> = ["script", "iframe", "object", "embed", "form"]

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

    /// Throws `ImportError.malformedBody` unless `fragment` parses as XML inside an XHTML wrapper
    /// and contains no script, event handler, or `javascript:` reference.
    static func validateFragment(_ fragment: String) throws {
        _ = try plainText(ofFragment: fragment)
    }

    static func plainText(ofFragment fragment: String) throws -> String {
        try plainText(ofDocument: "<div xmlns=\"\(namespace)\" xmlns:epub=\"\(epubNamespace)\">\(fragment)</div>")
    }

    /// Concatenated character data of a well-formed XML document; `ImportError.malformedBody`
    /// otherwise (a rejected script or handler, or any other parse failure).
    static func plainText(ofDocument xml: String) throws -> String {
        let parser = XMLParser(data: Data(xml.utf8))
        let collector = TextCollector()
        parser.delegate = collector
        guard parser.parse() else {
            if let rejection = collector.rejection { throw ImportError.malformedBody(rejection) }
            let reason = parser.parserError.map { "\($0.localizedDescription)" } ?? "unknown error"
            throw ImportError.malformedBody("line \(parser.lineNumber): \(reason)")
        }
        return collector.text
    }

    private final class TextCollector: NSObject, XMLParserDelegate {
        var text = ""
        /// Set (and parsing aborted) the moment a disallowed element, handler attribute, or
        /// `javascript:` reference is seen; wins over whatever `XMLParser` reports afterward.
        var rejection: String?

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let local = localName(elementName).lowercased()
            if XHTML.rejectedElements.contains(local) {
                reject("disallowed element <\(local)> at line \(parser.lineNumber)", parser)
                return
            }
            for (name, value) in attributeDict {
                let attr = localName(name).lowercased()
                if attr.hasPrefix("on") {
                    reject("disallowed event handler attribute \"\(attr)\" at line \(parser.lineNumber)", parser)
                    return
                }
                if (attr == "href" || attr == "src"),
                   value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("javascript:") {
                    reject("disallowed javascript: reference at line \(parser.lineNumber)", parser)
                    return
                }
            }
        }

        private func localName(_ qualified: String) -> String {
            qualified.split(separator: ":", maxSplits: 1).last.map(String.init) ?? qualified
        }

        private func reject(_ message: String, _ parser: XMLParser) {
            rejection = message
            parser.abortParsing()
        }
    }
}
