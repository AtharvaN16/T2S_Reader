import Foundation

enum Corpus {
    static let sentences: [String] = {
        guard let url = Bundle.main.url(forResource: "corpus", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }()
}
