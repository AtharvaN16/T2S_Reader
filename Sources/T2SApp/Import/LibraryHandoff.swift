import Foundation

/// A durable library identifier passed from the Share Extension to its host. It deliberately
/// contains no file path, shared-provider URL, or secret.
public enum LibraryHandoff: Sendable {
    public static func url(for id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = "t2s"
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        return components.url!
    }

    public static func documentID(from url: URL) -> UUID? {
        guard url.scheme == "t2s", url.host == "import",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, items.count == 1,
              items[0].name == "id", let value = items[0].value else {
            return nil
        }
        return UUID(uuidString: value)
    }
}
