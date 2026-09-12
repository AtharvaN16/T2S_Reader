// App/T2SReader/Bookmarks/BookmarkRow.swift
import SwiftUI
import T2SApp

/// One bookmark (2026-09-11 spec §6). The reader's own words are the headline when there are any
/// and the book's passage drops to a quote beneath them; with no note the passage keeps the
/// headline. The list then reads as a notebook rather than a second copy of the book.
///
/// Tapping the row opens the note in full; only the Listen pill plays (owner, 2026-09-12). The two
/// targets used to do the same thing, which left no way to read a long bookmark without starting
/// the audio.
struct BookmarkRow: View {
    var entry: BookmarkEntry
    var onJump: () -> Void
    var onEditNote: () -> Void
    var onDelete: () -> Void

    private var meta: String {
        entry.chapterTitle.isEmpty ? entry.rangeText : "\(entry.rangeText) · \(entry.chapterTitle)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meta).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
            Text(entry.headline).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                .lineLimit(4).multilineTextAlignment(.leading)
            if let quote = entry.quote {
                Text(quote).typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .lineLimit(3).multilineTextAlignment(.leading)
                    .padding(.leading, 11)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Tokens.ink3).frame(width: 2)
                    }
            }
            HStack(spacing: 8) {
                // Listen is Home's play pill exactly — the same filled grey, no outline of its own
                // (owner, 2026-09-12). The note is the outlined one, so the two read apart without
                // either shouting.
                Pill(label: "Listen", glyph: "play.fill", style: .soft, action: onJump)
                Pill(label: entry.hasNote ? "Edit note" : "Add a note", glyph: "square.and.pencil",
                     style: .soft, action: onEditNote)
                    .overlay(Capsule().strokeBorder(Tokens.ink3, lineWidth: 1).allowsHitTesting(false))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEditNote)
        .contextMenu {
            Button(action: onEditNote) {
                Label(entry.hasNote ? "Edit note" : "Add a note", systemImage: "square.and.pencil")
            }
            Button(role: .destructive, action: onDelete) { Label("Delete bookmark", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.headline), \(meta)")
        .accessibilityHint("Opens the note")
        .accessibilityAction(named: "Listen", onJump)
        .accessibilityAction(named: "Delete bookmark", onDelete)
    }
}
