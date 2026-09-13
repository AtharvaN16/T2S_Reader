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
    /// Render mode (the Book sheet): chapter index → the trailing mark it wears instead of the
    /// progress ring. Empty everywhere else, which is what makes this the same list it always was.
    var renderMarks: [Int: ChapterRenderMark] = [:]
    var onSelect: (ChapterEntry) -> Void
    var onSelectBookmark: ((BookmarkEntry) -> Void)? = nil
    var onEvict: ((ChapterEntry) -> Void)? = nil

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
                               renderMark: renderMarks[chapter.index],
                               onToggleBookmarks: {
                                   withAnimation(.spring(duration: 0.25)) {
                                       if isOpen { expanded.remove(chapter.index) } else { expanded.insert(chapter.index) }
                                   }
                               },
                               onEvict: { onEvict?(chapter) }) { onSelect(chapter) }
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
                // An open chapter's fill runs edge to edge; without air around it, two opened next
                // to each other read as one frame rather than two (owner, 2026-09-12).
                .padding(.vertical, isOpen ? Spacing.grid : 0)
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
                Text(entry.lead).typeRole(.meta).foregroundStyle(Tokens.ink).lineLimit(1)
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
        .accessibilityLabel("\(entry.lead), at \(entry.timeText)")
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
    /// In render mode, what this chapter has on the device or is doing about it — nil otherwise,
    /// and then the row is the row it has always been.
    var renderMark: ChapterRenderMark? = nil
    var onToggleBookmarks: () -> Void = {}
    var onEvict: () -> Void = {}
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
            // A fully rendered chapter has nothing left to render, so its row does not take a tap:
            // the trash beside it is its one action.
            .allowsHitTesting(renderMark?.isSelectable ?? true)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .accessibilityValue(renderMark?.accessibilityText
                ?? (isCurrent ? "\(Int((chapter.fraction * 100).rounded())) percent" : (isHeard ? "Heard" : "")))

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

            if let renderMark {
                // Render mode replaces the end of the row rather than crowding it: the ring says
                // how far you have listened, and this says what is on the device — two different
                // questions, and only one of them is being asked.
                ChapterRenderMarkView(mark: renderMark, onEvict: onEvict)
            } else if isCurrent {
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

/// The trailing mark on a chapter row in render mode — the whole language of that screen
/// (chapter-rendering design, "UI"): an empty circle, a filled check once picked, "Queued", a
/// waveform filling as it renders, and the `positive` tick with a size and a trash once it is on
/// the device.
enum ChapterRenderMark: Equatable {
    case unselected
    case selected
    case queued
    /// 0…1 of the chapter's utterances.
    case running(Double)
    /// Its size on disk, once the store can name one.
    case ready(String?)
    /// What went wrong, said in the row's accessibility value; the row stays selectable, so a tap
    /// is the retry.
    case failed(String)

    /// What the queue is doing with the chapter outranks what the store holds, because what the
    /// store holds is about to change. With no job, the store has the last word: a chapter rendered
    /// in an earlier session — or by the fill tier while you listened — is as ready as one this
    /// queue just finished.
    static func mark(status: ChapterAudioStatus?, job: ChapterRenderJob?, isSelected: Bool) -> ChapterRenderMark {
        switch job?.state {
        case .queued: return .queued
        case .running: return .running(job?.fraction ?? 0)
        case .failed(let message): return isSelected ? .selected : .failed(message)
        case .ready, .none: break
        }
        if status?.isFullyRendered == true { return .ready(status?.sizeText) }
        return isSelected ? .selected : .unselected
    }

    /// Whether tapping the row does anything. A ready chapter's row does not: there is nothing left
    /// to render in it.
    var isSelectable: Bool {
        if case .ready = self { return false }
        return true
    }

    var accessibilityText: String {
        switch self {
        case .unselected: return "Not rendered"
        case .selected: return "Selected"
        case .queued: return "Queued"
        case .running(let fraction): return "Rendering, \(Int((fraction * 100).rounded())) percent"
        case .ready(let size): return size.map { "On this device, \($0)" } ?? "On this device"
        case .failed(let message): return message
        }
    }
}

/// The mark drawn. Visual only but for the trash, which is its own button and plainly visible
/// rather than behind a long press — the lesson of the bookmarks work of the same day: a
/// destructive action hidden behind a gesture reads to the owner as absent.
struct ChapterRenderMarkView: View {
    var mark: ChapterRenderMark
    var onEvict: () -> Void

    var body: some View {
        switch mark {
        case .unselected:
            RadioMark(isOn: false)
        case .selected:
            RadioMark(isOn: true)
        case .queued:
            Text("Queued").typeRole(.meta).foregroundStyle(Tokens.ink2)
        case .running(let fraction):
            RenderWaveform(fraction: fraction)
        case .ready(let size):
            HStack(spacing: 6) {
                PositiveCheck()
                if let size { Text(size).typeRole(.meta).foregroundStyle(Tokens.ink2) }
                Button(action: onEvict) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Tokens.destructive)
                        .frame(width: 30, height: 30)                   // a target of its own, clear of the tick
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove this chapter's audio")
            }
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Tokens.destructive)
                .accessibilityLabel(message)
        }
    }
}

/// The SF `waveform` filling left to right as the chapter renders: a progress bar in the shape of
/// the thing being made. Both copies sit in the same box as the marks it stands between, so the
/// column does not shift when a row starts or finishes.
private struct RenderWaveform: View {
    var fraction: Double
    private static let box: CGFloat = 24

    var body: some View {
        let glyph = Image(systemName: "waveform").font(.system(size: 16, weight: .semibold))
        let filled = Self.box * min(1, max(0, fraction))
        return ZStack(alignment: .leading) {
            glyph.foregroundStyle(Tokens.ink3).frame(width: Self.box, height: Self.box)
            glyph.foregroundStyle(Tokens.accent).frame(width: Self.box, height: Self.box)
                .mask(alignment: .leading) { Rectangle().frame(width: filled) }
        }
        .frame(width: Self.box, height: Self.box)
        .animation(.linear(duration: 0.25), value: fraction)
        .accessibilityHidden(true)                                      // the row says the percentage
    }
}
