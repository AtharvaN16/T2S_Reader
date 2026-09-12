// App/T2SReader/Bookmarks/BookmarkDetail.swift
import SwiftUI
import T2SApp
import T2SStore

/// One bookmark, opened (owner, 2026-09-12: "I want the bookmark to show in an expanded view. I
/// don't want to see the text field. I want the bookmark to be big and prominent and nothing else
/// on the screen").
///
/// So: the words, large, and almost nothing around them — where it is above them in small type, the
/// book's passage beneath when the reader wrote a note of their own, and the three things you can do
/// with it at the foot. A row's tap used to open `BookmarkNoteSheet`, which meant the only way to
/// *read* a long bookmark was to open the editor and look past a keyboard at it. Writing is now
/// something you choose from here rather than what opening one does.
///
/// **Long ones fit.** The words scroll and nothing truncates — this screen is the one place a
/// bookmark is shown whole. The row it came from still clips to four lines, which is a row's job;
/// this is where the rest of a note lives, and a note has no length limit anywhere in the app. The
/// foot does not scroll with the text, so Delete is reachable without reading to the end.
struct BookmarkDetail: View {
    @Environment(\.dismiss) private var dismiss
    var entry: BookmarkEntry
    var onListen: () -> Void
    var onEditNote: () -> Void
    var onDelete: () -> Void

    @State private var confirmingDelete = false

    private var meta: String {
        entry.chapterTitle.isEmpty ? entry.rangeText : "\(entry.rangeText) · \(entry.chapterTitle)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.row) {
                    Text(meta)
                        .typeRole(.mono).foregroundStyle(Tokens.ink2)
                    // The reader's words when they wrote any, else the book's — `headline` is that
                    // rule, and it lives on the entry so every surface tells the same story.
                    Text(entry.headline)
                        .typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    // Only when it is not already the headline, and in full: the row shows three
                    // lines of the trimmed snippet, this shows the whole block that was saved.
                    if entry.quote != nil {
                        Text(entry.fullPassage)
                            .typeRole(.rowTitle).foregroundStyle(Tokens.ink2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 14)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Tokens.ink3).frame(width: 2)
                            }
                    }
                    Color.clear.frame(height: Spacing.section)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.margin)
                .padding(.top, Spacing.row)
            }
            .scrollIndicators(.hidden)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.ground.ignoresSafeArea())
        .confirmationDialog("Delete this bookmark?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete bookmark", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The note goes with it. This cannot be undone.")
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: { CircleGlyph(systemName: "chevron.down") }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, Spacing.grid)
    }

    /// Pinned under the words rather than following them: on a long note the actions would
    /// otherwise be a scroll away, and Delete is the one the owner could not find at all.
    private var actions: some View {
        HStack(spacing: 8) {
            Pill(label: "Listen", glyph: "play.fill", style: .soft) {
                onListen()
                dismiss()
            }
            Pill(label: entry.hasNote ? "Edit note" : "Add a note", glyph: "square.and.pencil",
                 style: .soft, action: onEditNote)
            Spacer(minLength: 8)
            Pill(label: "Delete", glyph: "trash", style: .destructiveSoft) { confirmingDelete = true }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, Spacing.grid)
        .padding(.bottom, Spacing.grid)
        .background(alignment: .top) {
            // A hairline over the foot, so a note scrolling under the actions stops at a line
            // rather than fading into them.
            Rectangle().fill(Tokens.ink3).frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}
