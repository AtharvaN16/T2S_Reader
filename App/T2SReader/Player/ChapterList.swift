// App/T2SReader/Player/ChapterList.swift
import SwiftUI
import T2SApp
import T2SCore

/// The chapter row's sheet (after Apple Podcasts' chapter list, owner's ask 2026-09-09): one
/// `ChapterRow` per chapter, the current chapter on a `surface` fill. Tap to jump.
struct ChapterList: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    /// Which chapters the device holds in full. Read once when the sheet opens (owner, 2026-09-14:
    /// "make sure chapters that have been rendered are also visible in the chapter sheet in the
    /// reader"). It was left out on the argument that this list is about listening and has no
    /// business saying what is cached — but the reader deciding which chapter to jump to on a train
    /// is asking exactly that, and this is the list they are looking at when they ask it.
    @State private var onDevice: Set<Int> = []

    var body: some View {
        let player = env.player
        let current = player.chapterIndex
        ScrollView {
            ChapterListView(chapters: player.chapters, current: current, variant: .reader,
                            bookmarks: player.bookmarksByChapter,
                            onDevice: onDevice,
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
        // A short book has fewer rows than the detent is tall, and a scroll view with nothing to
        // scroll was still taking the drag and rubber-banding the whole list under the reader's
        // thumb (owner, 2026-09-14: "a lot of play … no bound vertical movement"). `basedOnSize`
        // gives the bounce back the moment there are rows enough to need it.
        .scrollBounceBehavior(.basedOnSize)
        .background(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
        // The coordinator's timeline, not a fresh read of the library: this book is loaded, so the
        // chapters on screen and the keys being checked are the same ones.
        .task(id: env.player.current?.id) {
            guard let timeline = env.player.coordinator.timeline else { onDevice = []; return }
            let status = await BookAudioStatus.read(timeline: timeline, audioStore: env.audioStore)
            onDevice = Set(status.chapters.filter(\.isFullyRendered).map(\.chapterIndex))
        }
    }
}

/// The "Chapters" heading and its rows, the same list in the Reader's sheet and the Book sheet
/// (owner's ask, 2026-09-09: one component). Which of the two it is standing in is `variant`, and
/// that is what sets the heading's type; the rows' fill runs 12 pt past the text on each side, so a
/// caller sets its horizontal padding 12 pt short of the margin. `current` wears the ring, the
/// chapters before it the check.
///
/// A chapter that holds bookmarks carries its own count pill, and tapping that opens just this
/// chapter's bookmarks under it (owner, 2026-09-12). That reverses the one header button of the
/// 2026-09-11 spec §7, whose worry was the row losing its single tap target: the pill is its own
/// button beside the row's, so the words and the space after them still jump to the chapter.
struct ChapterListView: View {
    /// Which sheet the list is standing in. The two are deliberately one component — a chapter
    /// should read the same wherever you meet it — but they are not the same *sheet*, and the owner
    /// asked for that difference to have a name so either side can be changed on purpose rather
    /// than by guessing which caller a tweak would reach (2026-09-14: "make reader's chp sheet a
    /// variant of the main sheet, so we can make targeted changes").
    ///
    /// Everything a surface decides for itself belongs here. Today that is the heading's type; what
    /// a caller *passes* — the render marks, the bookmarks, the way into render mode — stays a
    /// parameter, because those are about the book in hand, not about which sheet is open.
    enum Variant {
        /// The Book sheet: the chapter list as a section of the book's own page, and the one place
        /// render mode turns it into a selection list.
        case book
        /// The Reader's chapter sheet, at a detent over the text you are listening to. Its own
        /// title is the sheet's, so the heading is a page title rather than a section header.
        case reader

        var heading: TypeRole {
            switch self {
            case .book: return .groupTitle
            case .reader: return .playerTitle
            }
        }
    }

    var chapters: [ChapterEntry]
    var current: Int?
    var variant: Variant = .book
    /// The row to flash once, drawing the eye to where a scroll just landed (the book sheet's
    /// open, owner 2026-09-11) — nil the rest of the time.
    var pulsing: Int? = nil
    /// Chapter index → its bookmarks. A chapter with no key shows no pill.
    var bookmarks: [Int: [BookmarkEntry]] = [:]
    /// Render mode (the Book sheet): chapter index → the trailing mark it wears instead of the
    /// progress ring. Empty everywhere else, which is what makes this the same list it always was.
    var renderMarks: [Int: ChapterRenderMark] = [:]
    /// Which chapters the device holds in full, for the tag the row wears outside render mode
    /// (owner, 2026-09-13: "the chapters now have an on device tag to them"). Empty in the Reader's
    /// copy of this list, which is about listening and has no business saying what is cached.
    var onDevice: Set<Int> = []
    /// The way into render mode, as a glyph beside the heading (owner, 2026-09-13). Only the Book
    /// sheet passes one; without it the heading is the word it has always been.
    var headerAction: (() -> Void)? = nil
    /// The same slot once you are inside render mode: "Render all", which takes every chapter the
    /// device does not already hold (owner, 2026-09-14). The glyph's job is done by then — you are
    /// already in the mode — so the space goes to the one thing picking chapters one at a time
    /// cannot do quickly.
    var headerAllAction: (() -> Void)? = nil
    var onSelect: (ChapterEntry) -> Void
    var onSelectBookmark: ((BookmarkEntry) -> Void)? = nil
    var onEvict: ((ChapterEntry) -> Void)? = nil

    @State private var expanded: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text("Chapters").typeRole(variant.heading).foregroundStyle(Tokens.ink)
                if let headerAllAction {
                    Spacer(minLength: 8)
                    Pill(label: "Render all", glyph: "waveform", style: .soft, action: headerAllAction)
                        .accessibilityHint("Renders every chapter this device does not already have")
                } else if let headerAction {
                    Spacer(minLength: 8)
                    // 36 pt disc, 24 pt column: out by six, so its centre lands on the marks
                    // below rather than nine points inboard of them.
                    Button(action: headerAction) { CircleGlyph(systemName: "waveform") }
                        .padding(.trailing, -(36 - ChapterRow.markColumn) / 2)
                        .accessibilityLabel("Render chapters")
                        .accessibilityHint("Choose chapters to keep on this device")
                }
            }
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
                               isOnDevice: onDevice.contains(chapter.index),
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
        // The column takes the width it is offered and no more. Without this it measures itself
        // against its widest row, and one chapter title too long to break — book sections are full
        // of them — made the whole list wider than the sheet, which a vertical `ScrollView` answers
        // by letting the reader pan it sideways (owner, 2026-09-14: "it moves left and right").
        // Clamped, the title truncates inside its row, where the row already expects it to.
        .frame(maxWidth: .infinity, alignment: .leading)
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
    /// The width every trailing mark is centred in, so the column reads as a column. `RadioMark`'s
    /// own box — the heading's render glyph is pulled out by half the difference to meet it.
    static let markColumn: CGFloat = 24

    var chapter: ChapterEntry
    var isCurrent: Bool
    var isHeard: Bool
    /// How many bookmarks this chapter holds; 0 shows no pill.
    var bookmarkCount: Int = 0
    var isShowingBookmarks: Bool = false
    /// In render mode, what this chapter has on the device or is doing about it — nil otherwise,
    /// and then the row is the row it has always been.
    var renderMark: ChapterRenderMark? = nil
    /// Whether the device holds the whole chapter. Said in the line under the title rather than at
    /// the end of the row, where the listening ring and the heard-check already live: how far you
    /// have listened and what is cached are two questions, and the row can answer both only if they
    /// are not fighting for the same slot. A part-rendered chapter says nothing — a tag that is
    /// true of half a chapter is worse than no tag.
    var isOnDevice: Bool = false
    var onToggleBookmarks: () -> Void = {}
    var onEvict: () -> Void = {}
    var action: () -> Void

    var body: some View {
        let name = ChapterLabel.text(for: chapter.title, ordinal: chapter.index + 1)
        let length = DurationFormatter.remaining(chapter.durationSeconds, approximate: false)
        // The row is two lines, and everything that marks the chapter belongs to the *first* of
        // them (owner, 2026-09-14: "the row graphic elements need to be aligned with the title not
        // the entire row"). Centred on the row, a mark floats between the name and the length and
        // reads as belonging to neither — the more so on a chapter whose name wraps. On the title's
        // own line it is plainly a mark on the title, and the length sits under it with nothing in
        // its way. Bookmarks, the listening ring, the heard-check and every render mark, alike.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Button(action: action) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(name)
                            .typeRole(.settingsRow).foregroundStyle(Tokens.ink).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        // "This chapter is on the device", riding with the name (owner, 2026-09-14):
                        // a grey waveform, the app's glyph for rendered audio, where the eye already
                        // is. It replaced a green "On device" tag, which announced a fact about
                        // caching far louder than it deserves and put a second colour in a
                        // one-colour list.
                        if isOnDevice, renderMark == nil {
                            Image(systemName: "waveform")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Tokens.ink2)
                                .accessibilityHidden(true)          // the row's value says it in words
                        }
                        Spacer(minLength: 12)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // A fully rendered chapter has nothing left to render, so its row does not take a
                // tap: the trash beside it is its one action.
                .allowsHitTesting(renderMark?.isSelectable ?? true)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                .accessibilityLabel("\(name), \(length)")
                .accessibilityValue(renderMark?.accessibilityText
                    ?? [isCurrent ? "\(Int((chapter.fraction * 100).rounded())) percent" : (isHeard ? "Heard" : ""),
                        isOnDevice ? "On this device" : ""]
                        .filter { !$0.isEmpty }.joined(separator: ", "))

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
                        .frame(height: 28)                               // a target of its own, clear of the words
                        .background(isShowingBookmarks ? Tokens.ink : Tokens.ink3, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(bookmarkCount == 1 ? "1 bookmark" : "\(bookmarkCount) bookmarks")
                    .accessibilityHint(isShowingBookmarks ? "Hides them" : "Shows them")
                }

                // Every mark ends in the same column (owner, 2026-09-14). The ring and the
                // heard-check are 18 pt and the selection circle 24, so they sat three points apart
                // down a list, and the heading's 36 pt glyph nine points off all of them.
                //
                // The column is given to each *glyph*, not to the mark as a whole. Wrapping the
                // whole mark in a 24 pt frame is what broke the rows on 2026-09-14: `.ready` and
                // `.queued` carry text, and a `Text` offered 24 points wraps to a column of
                // letters — the size vanished and the row grew a 30 pt hole between the title and
                // its length. The marks that *are* a glyph take the frame; the marks that are a
                // sentence end in one.
                Group {
                    if let renderMark {
                    // The mark is a button of its own when it can be picked (owner, 2026-09-14: "the
                    // touch target is weird"). It sits outside the row's button — the row's stops at
                    // its `Spacer` — so a tap landing squarely on the circle used to do nothing at
                    // all, and the only way to pick a chapter was to hit its name. Padded out and
                    // back, so a 24 pt circle takes a 44 pt tap without moving anything.
                        if renderMark.isSelectable {
                            Button(action: action) {
                                ChapterRenderMarkView(mark: renderMark, onEvict: onEvict)
                                    .padding(10)
                                    .contentShape(Rectangle())
                                    .padding(-10)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHidden(true)                   // the row carries the state and the action
                        } else {
                            ChapterRenderMarkView(mark: renderMark, onEvict: onEvict)
                        }
                    } else if isCurrent {
                        CircularProgress(fraction: chapter.fraction, lineWidth: 2, size: 18)
                            .frame(width: ChapterRow.markColumn)
                    } else if isHeard {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Tokens.positive)
                            .frame(width: ChapterRow.markColumn)
                            .accessibilityLabel("Heard")
                    }
                }
            }
            // The length, on its own line and clear to the margin. Still the row's tap, so the gap
            // under the title is not a dead strip.
            Button(action: action) {
                HStack(spacing: 0) {
                    Text(length).typeRole(.pill).foregroundStyle(Tokens.ink2)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(renderMark?.isSelectable ?? true)
            .accessibilityHidden(true)                                   // the line above speaks for the row
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
            // No tick (owner, 2026-09-14). The size and the trash are already the whole of "this
            // one is here"; a green check in front of them was a third thing saying the same fact,
            // and it pushed the pair off the column every other row's mark stands in.
            HStack(spacing: 10) {
                if let size { Text(size).typeRole(.meta).foregroundStyle(Tokens.ink2) }
                Button(action: onEvict) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.destructive)
                        // `RadioMark`'s box exactly, so the trash lands in the same column as the
                        // rings above and below it — then padded out and back for a target twice
                        // the glyph's size without moving anything (owner: "align the delete with
                        // the checkmarks").
                        .frame(width: 24, height: 24)
                        .padding(10)
                        .contentShape(Rectangle())
                        .padding(-10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove this chapter's audio")
            }
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Tokens.destructive)
                .frame(width: ChapterRow.markColumn)
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
