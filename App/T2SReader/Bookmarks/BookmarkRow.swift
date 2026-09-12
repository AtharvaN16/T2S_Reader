// App/T2SReader/Bookmarks/BookmarkRow.swift
import SwiftUI
import T2SApp

/// One bookmark. The book's words lead and the reader's note stands under them against a rule
/// (`BookmarkEntry.lead` / `.note`, where the arrangement and the reason for it live).
///
/// Tapping the row opens the bookmark (`BookmarkDetail`); only the Listen pill plays (owner,
/// 2026-09-12). The two targets used to do the same thing, which left no way to read a long
/// bookmark without starting the audio — and then the tap opened the *editor*, so reading a long
/// one meant looking at it past a keyboard. Opening and writing are two different asks now.
struct BookmarkRow: View {
    var entry: BookmarkEntry
    /// Opens the bookmark in full.
    var onOpen: () -> Void
    var onJump: () -> Void
    var onEditNote: () -> Void
    var onDelete: () -> Void

    private var meta: String {
        entry.chapterTitle.isEmpty ? entry.rangeText : "\(entry.rangeText) · \(entry.chapterTitle)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meta).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
            Text(entry.lead).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                .lineLimit(4).multilineTextAlignment(.leading)
            if let note = entry.note {
                Text(note).typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .lineLimit(3).multilineTextAlignment(.leading)
                    .padding(.leading, 11)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Tokens.ink3).frame(width: 2)
                    }
            }
            HStack(spacing: 8) {
                // Both are Home's filled grey pill; `surface` carries them on its own now that
                // dark's grey is lifted, so neither wears an outline (owner, 2026-09-12).
                Pill(label: "Listen", glyph: "play.fill", style: .soft, action: onJump)
                Pill(label: entry.hasNote ? "Edit note" : "Add a note", glyph: "square.and.pencil",
                     style: .soft, action: onEditNote)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button(action: onOpen) { Label("Open bookmark", systemImage: "arrow.up.left.and.arrow.down.right") }
            Button(action: onEditNote) {
                Label(entry.hasNote ? "Edit note" : "Add a note", systemImage: "square.and.pencil")
            }
            Button(role: .destructive, action: onDelete) { Label("Delete bookmark", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.lead), \(meta)")
        .accessibilityHint("Opens the bookmark")
        .accessibilityAction(named: "Listen", onJump)
        .accessibilityAction(named: "Delete bookmark", onDelete)
    }
}
