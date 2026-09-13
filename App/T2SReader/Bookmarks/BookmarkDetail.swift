// App/T2SReader/Bookmarks/BookmarkDetail.swift
import SwiftUI
import T2SApp
import T2SStore

/// One bookmark, opened (owner, 2026-09-12: "I want the bookmark to show in an expanded view. I
/// don't want to see the text field. I want the bookmark to be big and prominent and nothing else
/// on the screen").
///
/// So: the book's words, large, and almost nothing around them — where it is above them in small
/// type, the reader's note under them against a rule when they wrote one, and the two things you
/// would do next at the foot. A row's tap used to open `BookmarkNoteSheet`, which meant the only way
/// to *read* a long bookmark was to open the editor and look past a keyboard at it. Writing is now
/// something you choose from here rather than what opening one does.
///
/// **Long ones fit.** The words scroll and nothing truncates — this screen is the one place a
/// bookmark is shown whole. The row it came from still clips to four lines, which is a row's job.
/// The foot does not scroll with the text, and the text fades into it rather than meeting it at a
/// line (the same eased ramp every other edge in the app fades on, `TopFade.shape`, turned over).
struct BookmarkDetail: View {
    @Environment(\.dismiss) private var dismiss
    var entry: BookmarkEntry
    /// The book the bookmark belongs to, centered in the header, with the chapter under it
    /// (owner, 2026-09-13). The two are one address — book, then where in the book — so they read
    /// as one stacked label rather than a name up here and a chapter in the small print below.
    var bookTitle: String
    var onListen: () -> Void
    var onEditNote: () -> Void
    var onDelete: () -> Void

    @State private var confirmingDelete = false

    /// Solid under the buttons, easing to clear above them.
    private static let footSolid: CGFloat = 76
    private static let footFade: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.row) {
                    // The words first and the small print under them (owner, 2026-09-12: "move the
                    // time stamp and chapter below"). The passage is what this screen is for, and a
                    // line of grey type above it made the reader step over a label to reach it;
                    // under, it reads as the caption to what it describes. The two are one block,
                    // tighter than the gap to the note: the line belongs to those words, where the
                    // note answers them.
                    VStack(alignment: .leading, spacing: 14) {
                        BookmarkMeta(entry: entry, emphasized: true, showsChapter: false)
                        // The passage whole (`fullPassage`), not the row's 90-character snippet:
                        // this screen exists to show a long bookmark, and it was printing the same
                        // clipped words as the row it was opened from, ellipsis and all.
                        Text(entry.fullPassage)
                            .typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                            // `playerTitle` carries a four-line limit for the transport's book
                            // title (`TypeRole.lineLimit`), and a long bookmark was being cut at
                            // four lines here too, ellipsis and all, on the one screen that exists
                            // to show it whole. A limit set outside the role is the one that holds
                            // — a high number rather than `nil`, which the role reads as "nobody
                            // has set one" and fills in again.
                            .lineLimit(500)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // The reader's note under the passage it is about, against the rule the row
                    // gives it too. In full: the row shows two lines of it, this shows all of it.
                    if let note = entry.note {
                        Text(note)
                            .typeRole(.rowTitle).foregroundStyle(Tokens.ink2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 14)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Tokens.ink3).frame(width: 2)
                            }
                    }
                    // Room under the words for the fade and the buttons standing over them.
                    Color.clear.frame(height: Self.footSolid + Self.footFade)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.margin)
                .padding(.top, Spacing.row)
            }
            .scrollIndicators(.hidden)
            // The words pass under the header the way they pass under the foot — the same ramp at
            // both ends, so neither edge of this screen is a cut (owner, 2026-09-12).
            .overlay { EdgeFade(edge: .top) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.ground.ignoresSafeArea())
        .overlay(alignment: .bottom) { foot }
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

    /// Back on the left as everywhere else in the app, and Delete at the far right — the corner a
    /// destructive thing belongs in, and out of the way of the two buttons you actually came for.
    /// Red, and the only red on the screen (owner, 2026-09-12): it was an ink glyph like the back
    /// arrow, which said the two marks did comparable things. `CircleGlyph` takes the colour itself
    /// now — a `.foregroundStyle` outside it was set again inside and never showed.
    private var header: some View {
        HStack {
            Button { dismiss() } label: { CircleGlyph(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            Spacer()
            if !bookTitle.isEmpty {
                // The book's name, and under it in small grey type the chapter this bookmark
                // falls in — moved up out of the meta line below the passage (owner, 2026-09-13).
                // Quieter and a size down, so the stack still reads as one title with an address
                // under it rather than two headings fighting over the middle of the row.
                VStack(spacing: 5) {
                    Text(bookTitle)
                        .typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
                        .lineLimit(1)
                    if !entry.chapterTitle.isEmpty {
                        Text(entry.chapterTitle)
                            .typeRole(.meta).foregroundStyle(Tokens.ink2)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
            Button { confirmingDelete = true } label: {
                CircleGlyph(systemName: "trash", tint: Tokens.destructive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete bookmark")
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, Spacing.grid)
    }

    /// The two things you do with a bookmark, a half of the row each: neither is the lesser, and a
    /// pair of capsules hugging their words left an odd gap where Delete used to sit.
    private var foot: some View {
        HStack(spacing: 12) {
            Pill(label: "Listen", glyph: "play.fill", style: .soft, fillsWidth: true) {
                onListen()
                dismiss()
            }
            Pill(label: entry.hasNote ? "Edit note" : "Add a note", glyph: "square.and.pencil",
                 style: .soft, fillsWidth: true, action: onEditNote)
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.bottom, Spacing.grid)
        .frame(height: Self.footSolid, alignment: .top)
        .frame(maxWidth: .infinity)
        .background {
            // `TopFade`'s ramp, turned over: solid under the buttons, easing to clear above them,
            // so the words pass under it instead of stopping at a line.
            Tokens.ground
                .mask(
                    TopFade.shape(solidThrough: Self.footSolid, fade: Self.footFade)
                        .scaleEffect(y: -1)
                )
                .frame(height: Self.footSolid + Self.footFade)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
