// App/T2SReader/Bookmarks/BookmarkRow.swift
import SwiftUI
import T2SApp

/// One bookmark (2026-09-11 spec §6). The reader's own words are the headline when there are any
/// and the book's passage drops to a quote beneath them; with no note the passage keeps the
/// headline. The list then reads as a notebook rather than a second copy of the book.
///
/// The row is tappable *and* carries a Listen pill. Two targets for one action is usually a fault;
/// it is not one here, because both do the same thing and a mis-tap therefore costs nothing.
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
                Pill(label: "Listen", glyph: "play.fill", style: .selected, action: onJump)
                Pill(label: entry.hasNote ? "Edit note" : "Add a note", glyph: "square.and.pencil",
                     style: .soft, action: onEditNote)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onJump)
        .contextMenu {
            Button(action: onEditNote) {
                Label(entry.hasNote ? "Edit note" : "Add a note", systemImage: "square.and.pencil")
            }
            Button(role: .destructive, action: onDelete) { Label("Delete bookmark", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.headline), \(meta)")
        .accessibilityHint("Plays from this bookmark")
        .accessibilityAction(named: entry.hasNote ? "Edit note" : "Add a note", onEditNote)
        .accessibilityAction(named: "Delete bookmark", onDelete)
    }
}
