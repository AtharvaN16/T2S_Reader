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
/// A chapter that holds bookmarks carries its own count pill, and tapping that opens just this
/// chapter's bookmarks under it (owner, 2026-09-12). That reverses the one header button of the
/// 2026-09-11 spec §7, whose worry was the row losing its single tap target: the pill is its own
/// button beside the row's, so the words and the space after them still jump to the chapter.
struct ChapterListView: View {
    var chapters: [ChapterEntry]
    var current: Int?
    var heading: TypeRole
    /// The row to flash once, drawing the eye to where a scroll just landed (the book sheet's
    /// open, owner 2026-09-11) — nil the rest of the time.
    var pulsing: Int? = nil
    /// Chapter index → its bookmarks. A chapter with no key shows no pill.
    var bookmarks: [Int: [BookmarkEntry]] = [:]
    var onSelect: (ChapterEntry) -> Void
    var onSelectBookmark: ((BookmarkEntry) -> Void)? = nil

    @State private var expanded: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chapters").typeRole(heading).foregroundStyle(Tokens.ink)
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            ForEach(chapters) { chapter in
                let stamps = bookmarks[chapter.index] ?? []
                let isOpen = expanded.contains(chapter.index)
                let isCurrent = chapter.index == current
                // The open chapter and its bookmarks share one fill, so the bookmarks read as
                // belonging to the chapter above them rather than floating under it (owner,
                // 2026-09-12).
                VStack(alignment: .leading, spacing: 6) {
                    ChapterRow(chapter: chapter, isCurrent: isCurrent,
                               isHeard: current.map { chapter.index < $0 } ?? false,
                               bookmarkCount: stamps.count, isShowingBookmarks: isOpen,
                               onToggleBookmarks: {
                                   withAnimation(.spring(duration: 0.25)) {
                                       if isOpen { expanded.remove(chapter.index) } else { expanded.insert(chapter.index) }
                                   }
                               }) { onSelect(chapter) }
                    if isOpen {
                        ForEach(stamps) { stamp in
                            BookmarkStampRow(entry: stamp) { onSelectBookmark?(stamp) }
                        }
                    }
                }
                .padding(.bottom, isOpen ? 6 : 0)                       // the last bookmark keeps off the fill's edge
                .background(isCurrent || isOpen ? Tokens.surface : Tokens.surface.opacity(0),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Tokens.accent.opacity(chapter.index == pulsing ? 0.3 : 0))
                )
            }
        }
    }
}

/// One bookmark inside its chapter's fill, in the order you read it: the accent dot, what it says,
/// and the time it says it at, out at the end (owner, 2026-09-12). Its own row to tap — deeper than
/// the chapter row above it, since a list of them is tapped at speed.
struct BookmarkStampRow: View {
    var entry: BookmarkEntry
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(Tokens.accent).frame(width: 7, height: 7)
                Text(entry.headline).typeRole(.meta).foregroundStyle(Tokens.ink).lineLimit(1)
                Spacer(minLength: 8)
                // Inter, not the `.mono` role the stamp wore when the time led the row: out at the
                // end it is read, not scanned down a column (owner, 2026-09-12).
                Text(entry.timeText)
                    .font(.custom("Inter-Medium", size: 13, relativeTo: .footnote))
                    .foregroundStyle(Tokens.ink2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 13)
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
    /// How many bookmarks this chapter holds; 0 shows no pill.
    var bookmarkCount: Int = 0
    var isShowingBookmarks: Bool = false
    var onToggleBookmarks: () -> Void = {}
    var action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // The row's own button stops short of the pill, so the two never share a tap.
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .accessibilityValue(isCurrent ? "\(Int((chapter.fraction * 100).rounded())) percent" : (isHeard ? "Heard" : ""))

            if bookmarkCount > 0 {
                Button(action: onToggleBookmarks) {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark.fill").font(.system(size: 11, weight: .semibold))
                        Text("\(bookmarkCount)").font(.custom("Inter-Medium", size: 13, relativeTo: .footnote))
                    }
                    // Grey, not the dots' accent (owner, 2026-09-12): it counts bookmarks, it is
                    // not one. Open, it takes the app's selected chip — ink under `ground`.
                    .foregroundStyle(isShowingBookmarks ? Tokens.ground : Tokens.ink)
                    .padding(.horizontal, 9)
                    .frame(height: 28)                                   // a target of its own, clear of the words
                    .background(isShowingBookmarks ? Tokens.ink : Tokens.ink3, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bookmarkCount == 1 ? "1 bookmark" : "\(bookmarkCount) bookmarks")
                .accessibilityHint(isShowingBookmarks ? "Hides them" : "Shows them")
            }

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
    }
}
