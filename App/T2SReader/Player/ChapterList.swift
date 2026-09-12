// App/T2SReader/Player/ChapterList.swift
import SwiftUI
import T2SApp
import T2SCore

/// The chapter row's sheet (after Apple Podcasts' chapter list, owner's ask 2026-09-09): one
/// `ChapterRow` per chapter, the current chapter on a `surface` fill. Tap to jump.
struct ChapterList: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let player = env.player
        let current = player.chapterIndex
        ScrollView {
            ChapterListView(chapters: player.chapters, current: current, heading: .playerTitle,
                            bookmarks: player.bookmarksByChapter,
                            onSelect: { chapter in
                                Task { await player.seek(toChapter: chapter.index); dismiss() }
                            },
                            onSelectBookmark: { entry in
                                Task {
                                    guard let timeline = player.coordinator.timeline else { return }
                                    await player.seek(to: PositionResolver.resolve(entry.position, in: timeline))
                                    dismiss()
                                }
                            })
            .padding(.top, Spacing.section)
            .padding(.bottom, Spacing.section)
            .padding(.horizontal, Spacing.margin - 12)                     // the fill's own 12 pt makes up the margin
        }
        .background(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}

/// The "Chapters" heading and its rows, the same list in the Reader's sheet and the Book sheet
/// (owner's ask, 2026-09-09: one component). `heading` is the sheet's title role or a page's
/// section header; the rows' fill runs 12 pt past the text on each side, so a caller sets its
/// horizontal padding 12 pt short of the margin. `current` wears the ring, the chapters before it
/// the check.
///
/// One bookmark button in the header opens the stamps under every chapter that has any (2026-09-11
/// spec §7) — one control rather than a per-row badge, so each row stays a single tap target.
struct ChapterListView: View {
    var chapters: [ChapterEntry]
    var current: Int?
    var heading: TypeRole
    /// The row to flash once, drawing the eye to where a scroll just landed (the book sheet's
    /// open, owner 2026-09-11) — nil the rest of the time.
    var pulsing: Int? = nil
    /// Chapter index → its bookmarks. Empty hides the header button entirely.
    var bookmarks: [Int: [BookmarkEntry]] = [:]
    var onSelect: (ChapterEntry) -> Void
    var onSelectBookmark: ((BookmarkEntry) -> Void)? = nil

    @State private var showingStamps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Chapters").typeRole(heading).foregroundStyle(Tokens.ink)
                Spacer(minLength: 12)
                if !bookmarks.isEmpty {
                    Button {
                        withAnimation(.spring(duration: 0.25)) { showingStamps.toggle() }
                    } label: {
                        CircleGlyph(systemName: showingStamps ? "bookmark.fill" : "bookmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showingStamps ? "Hide bookmark times" : "Show bookmark times")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
            ForEach(chapters) { chapter in
                ChapterRow(chapter: chapter, isCurrent: chapter.index == current,
                           isHeard: current.map { chapter.index < $0 } ?? false,
                           isPulsing: chapter.index == pulsing) { onSelect(chapter) }
                if showingStamps, let stamps = bookmarks[chapter.index] {
                    ForEach(stamps) { stamp in
                        BookmarkStampRow(entry: stamp) { onSelectBookmark?(stamp) }
                    }
                }
            }
        }
    }
}

/// One bookmark under its chapter row: an accent dot, the time, and one line of what it says.
struct BookmarkStampRow: View {
    var entry: BookmarkEntry
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(Tokens.accent).frame(width: 7, height: 7)
                Text(entry.timeText).typeRole(.mono).foregroundStyle(Tokens.ink2)
                Text(entry.headline).typeRole(.meta).foregroundStyle(Tokens.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 24)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.headline), at \(entry.timeText)")
        .accessibilityHint("Plays from this bookmark")
    }
}

/// One chapter (owner's ask, 2026-09-09): its name over its length, and at the right end a ring
/// of how far through the current one we are, or a `positive` check for a chapter already heard.
/// The title sits a step under `rowTitle` and the time a step over `meta`, so the two read closer
/// in size.
struct ChapterRow: View {
    var chapter: ChapterEntry
    var isCurrent: Bool
    var isHeard: Bool
    /// One flash of `accent` over the row's own fill, then gone — `BookSheet` sets and clears it.
    var isPulsing: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ChapterLabel.text(for: chapter.title, ordinal: chapter.index + 1))
                        .typeRole(.settingsRow).foregroundStyle(Tokens.ink).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(DurationFormatter.remaining(chapter.durationSeconds, approximate: false))
                        .typeRole(.pill).foregroundStyle(Tokens.ink2)
                }
                Spacer(minLength: 12)
                if isCurrent {
                    CircularProgress(fraction: chapter.fraction, lineWidth: 2, size: 18)
                } else if isHeard {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Tokens.positive)
                        .accessibilityLabel("Heard")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isCurrent ? Tokens.surface : Tokens.surface.opacity(0),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Tokens.accent.opacity(isPulsing ? 0.3 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityValue(isCurrent ? "\(Int((chapter.fraction * 100).rounded())) percent" : (isHeard ? "Heard" : ""))
    }
}
