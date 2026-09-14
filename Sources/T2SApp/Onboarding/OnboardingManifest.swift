import Foundation

/// The onboarding's script: the sample books, the voice each one's opening line is read in, and the
/// voices the voice row offers (design: `docs/superpowers/specs/2026-09-14-onboarding-design.md`).
/// Decoded from `onboarding-manifest.json` in the app bundle, which is also what
/// `scripts/render-onboarding-clips.sh` renders the clips from, so the app and the clips cannot
/// disagree about what is said.
public struct OnboardingManifest: Codable, Hashable, Sendable {
    public struct Book: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var author: String
        /// The Kokoro voice name (`af_heart`) its line rises in.
        public var voice: String
        /// The short opening line that rises with the card, as written; the clip's timing file
        /// carries the spoken form.
        public var line: String
        /// The hero's longer passage for the voice screen, rendered in every voice of the row. Nil
        /// on the other books, and the hero falls back to its `line`.
        public var passage: String?

        public init(id: String, title: String, author: String, voice: String, line: String, passage: String? = nil) {
            self.id = id
            self.title = title
            self.author = author
            self.voice = voice
            self.line = line
            self.passage = passage
        }
    }

    /// The `id` of the book that settles at the end and is imported when the flow finishes.
    public var hero: String
    /// The voice row, in order; the hero's line is rendered in every one of them.
    public var voices: [String]
    public var books: [Book]

    public static let resourceName = "onboarding-manifest"

    public init(hero: String, voices: [String], books: [Book]) {
        self.hero = hero
        self.voices = voices
        self.books = books
    }

    public static func load(from bundle: Bundle) throws -> OnboardingManifest {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(OnboardingManifest.self, from: Data(contentsOf: url))
    }

    public var heroBook: Book? { books.first { $0.id == hero } }

    /// The order the cards rise, each with its own voice: the manifest's order with the hero moved
    /// last, so the book that settles is the one whose line was heard most recently.
    public var risingOrder: [Book] {
        let others = books.filter { $0.id != hero }
        return heroBook.map { others + [$0] } ?? others
    }

    /// The bundle resource name (without extension) of a book's clip in a voice: the `.m4a` and the
    /// timing `.json` share it.
    public static func clipName(book: String, voice: String) -> String {
        "onboarding-\(book)-\(voice)"
    }

    /// The hero's passage in a voice, for the voice screen.
    public static func passageClipName(book: String, voice: String) -> String {
        "onboarding-\(book)-passage-\(voice)"
    }
}

/// What lies beside each clip: the text as spoken, the clip's length, and each word's time and
/// range in that text, for the tint that follows the voice on the voice screen.
public struct OnboardingClipTimings: Codable, Hashable, Sendable {
    public struct Word: Codable, Hashable, Sendable {
        public var start: TimeInterval
        public var end: TimeInterval
        /// UTF-16 offsets into `spoken`, `[lower, upper)`.
        public var range: [Int]

        public init(start: TimeInterval, end: TimeInterval, range: [Int]) {
            self.start = start
            self.end = end
            self.range = range
        }
    }

    public var book: String
    public var voice: String
    public var spoken: String
    public var duration: TimeInterval
    public var words: [Word]

    public init(book: String, voice: String, spoken: String, duration: TimeInterval, words: [Word]) {
        self.book = book
        self.voice = voice
        self.spoken = spoken
        self.duration = duration
        self.words = words
    }

    public static func load(named name: String, from bundle: Bundle) throws -> OnboardingClipTimings {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(OnboardingClipTimings.self, from: Data(contentsOf: url))
    }

    /// The index of the word being spoken at `time`, or the last word that has started; nil before
    /// the first word.
    public func wordIndex(at time: TimeInterval) -> Int? {
        var found: Int?
        for (i, word) in words.enumerated() where word.start <= time { found = i }
        return found
    }
}
