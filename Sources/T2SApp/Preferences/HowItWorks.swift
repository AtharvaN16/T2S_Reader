// Sources/T2SApp/Preferences/HowItWorks.swift
import Foundation

/// What Settings → About → "How it works" says, as data rather than as a view.
///
/// It is here, beside the preferences, because these sentences are checkable and one of them is a
/// promise. "Nothing you read or listen to leaves the phone" is the kind of line that goes quietly
/// untrue two refactors later, and a `body` cannot be asked whether it still holds. A `[Point]`
/// can — and `HowItWorksTests` also holds the writing to its length, which is the part that went
/// wrong first (owner, 2026-09-16: "too many options and this is very bad UX writing").
///
/// **Four points, short titles, two sentences each.** The first draft had six points of four-line
/// paragraphs, a download size, an iCloud clause, and titles like "Kept, not remade" — a page of
/// prose in a place nobody reads prose. What survived is what a reader cannot find out any other
/// way. The 620 MB download is on the Storage page, beside the model it describes; what iCloud
/// syncs is on the sync row's own subtitle. Neither needs saying twice.
public enum HowItWorks {

    /// One point: an SF Symbol, a two- or three-word title, and a line or two under it.
    public struct Point: Sendable, Identifiable, Hashable {
        public let id: String
        public let symbol: String
        public let title: String
        public let body: String

        public init(id: String, symbol: String, title: String, body: String) {
            self.id = id
            self.symbol = symbol
            self.title = title
            self.body = body
        }
    }

    /// The one line above the list.
    public static let lead = "Your books are read aloud by a voice that runs on your iPhone."

    public static let points: [Point] = [
        Point(id: "on-device", symbol: "iphone", title: "On device",
              body: "Speech is made on your iPhone, never on a server. Nothing you read or listen to leaves the phone, and none of it needs a network."),
        Point(id: "warmth", symbol: "thermometer.medium", title: "May warm up",
              body: "Making audio works the phone hard, so long chapters can feel warm. Rendering pauses if it gets hot, then picks up once it cools."),
        Point(id: "kept", symbol: "internaldrive", title: "Saved once made",
              body: "Audio is kept on this iPhone, so playing a chapter again is instant. Clear it whenever you like in Storage."),
        Point(id: "synthetic", symbol: "sparkles", title: "Not a narrator",
              body: "Names and unusual words can come out wrong. It is a reading voice, not an audiobook recording.")
    ]
}
