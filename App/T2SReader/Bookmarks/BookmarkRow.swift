// App/T2SReader/Bookmarks/BookmarkRow.swift
import SwiftUI
import T2SApp

/// One bookmark (spec §2.2): chapter as meta, the text at the bookmark as the title, the time in
/// monospaced on the right. Used inline in the Book sheet and inside `BookmarksSheet`.
struct BookmarkRow: View {
    var entry: BookmarkEntry
    var onJump: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(action: onJump) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.chapterTitle).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
                    Text(entry.snippet).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text(entry.timeText).typeRole(.mono).foregroundStyle(Tokens.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) { Label("Delete bookmark", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.snippet), \(entry.chapterTitle), at \(entry.timeText)")
        .accessibilityHint("Plays from this bookmark")
        .accessibilityAction(named: "Delete bookmark", onDelete)
    }
}
