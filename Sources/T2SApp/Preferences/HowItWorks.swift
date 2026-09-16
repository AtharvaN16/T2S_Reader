// Sources/T2SApp/Preferences/HowItWorks.swift
import Foundation

/// What Settings → About → "How the app works" says, as data rather than as a view.
///
/// It is here, beside the preferences, for the same reason `WarmUpReading` is a value: every
/// claim on that sheet is checkable, and some of them are promises. "Nothing leaves the device"
/// and "about a 620 MB download" are the kind of sentence that goes quietly untrue two refactors
/// later, and a `body` cannot be asked whether it still holds. A `[Point]` can.
///
/// The everyday build has no on-device voice — it reads with the system's — so the sheet is built
/// from `hasOnDeviceVoice` rather than written once and hedged. A reader whose phone will never
/// fetch a model should not be told the size of one.
public enum HowItWorks {

    /// One point of the sheet: an SF Symbol, a line, and a paragraph under it.
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

    /// The sentence above the list — the whole sheet in one breath, for the reader who opens it,
    /// reads the top and closes it again.
    public static func lead(hasOnDeviceVoice: Bool) -> String {
        hasOnDeviceVoice
            ? "Your books are read aloud by a voice that runs entirely on your iPhone. Nothing you read or listen to leaves the device."
            : "Your books are read aloud by your iPhone's own system voice. Nothing you read or listen to leaves the device."
    }

    public static func points(hasOnDeviceVoice: Bool) -> [Point] {
        var points: [Point] = [
            Point(
                id: "on-device",
                symbol: "iphone",
                title: "Made on this iPhone",
                body: hasOnDeviceVoice
                    ? "The speech is synthesized here, from the book's own words, a sentence at a time. No text and no audio is sent to a server — there is no account and nothing to sign in to."
                    : "This build reads with the iPhone's system voice, which also speaks here. No text and no audio is sent to a server — there is no account and nothing to sign in to."
            )
        ]
        if hasOnDeviceVoice {
            points.append(Point(
                id: "one-download",
                symbol: "arrow.down.circle",
                title: "The voice arrives once",
                body: "The voice is about a 620 MB download over Wi-Fi, fetched once on the first launch. After that it needs no network at all: a plane, a tunnel, a week without signal, all the same. Until it lands, books play in the system voice."
            ))
        }
        points.append(contentsOf: [
            Point(
                id: "made-ahead",
                symbol: "waveform",
                title: "Audio is made ahead",
                body: "Playing a chapter renders it a little ahead of where you are listening, so the voice and the highlighted words stay together. Prepare on charge can make whole chapters overnight, before you open the book at all."
            ),
            Point(
                id: "kept",
                symbol: "internaldrive",
                title: "Kept, not remade",
                body: "Rendered audio is saved on this iPhone, so going back to a chapter plays at once and costs nothing to hear again. Storage shows what it is taking and clears whatever you no longer want."
            ),
            Point(
                id: "warmth",
                symbol: "thermometer.medium",
                title: "The phone may warm up",
                body: "Because the work happens here, the CPU and Neural Engine run hard while audio is being made, and a long stretch of rendering can produce noticeable warmth. This is normal. Rendering stops on its own when the phone gets hot and picks up once it has cooled."
            ),
            Point(
                id: "synthetic",
                symbol: "sparkles",
                title: "A voice, not a narrator",
                body: "The reading is synthesized rather than performed. Names, foreign words and unusual punctuation can come out wrong, and nothing is acted. Treat it as a good reading voice, not as an audiobook recording."
            ),
            Point(
                id: "icloud",
                symbol: "icloud",
                title: "Only your place travels",
                body: "With iCloud sync on, where you are in a book and the bookmarks you have made follow you between your own devices. The books themselves, and every second of audio, stay on the phone that made them."
            )
        ])
        return points
    }
}
