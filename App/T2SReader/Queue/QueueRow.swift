// App/T2SReader/Queue/QueueRow.swift
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// One Queue row (spec §2.4.5). No card, no divider: the 28pt row gap is the rhythm.
struct QueueRow: View {
    @Environment(AppEnvironment.self) private var env
    var summary: DocumentSummary
    /// Play's target: the Reader, loading and playing a non-current document itself.
    var onOpen: () -> Void
    /// The book's target: the book sheet, scrolled to the resume chapter with a pulse on it
    /// (owner, 2026-09-11: two touch targets, the book and Play, each its own destination — the
    /// row used to open the Reader from either the cover's title or the pill).
    var onOpenBook: () -> Void
    var onDetails: () -> Void
    @State private var showSleepTimer = false
    @State private var showVoiceChange = false
    /// True only while the Play pill's own tap is resuming a paused, already-current document —
    /// the one branch that awaits playback before opening the reader, otherwise silently.
    @State private var isStarting = false
    /// The resume chapter's text and progress, loaded off the body so the list never decodes a chapter.
    @State private var glimpse: RowGlimpse?

    private var progress: DocumentProgress? { env.libraryModel.progress(for: summary.id) }
    /// Whether there's a saved position to pick back up — "Continue" over "Play" once there is.
    private var hasProgress: Bool { summary.document.resumePosition != nil }
    private var isCurrent: Bool { env.player.current?.id == summary.id }
    private var isPlayingHere: Bool { isCurrent && env.player.isPlaying }
    private var isArticle: Bool { summary.document.sourceType == .article }
    /// Books with chapters show the chapter's own progress and time; a file with none shows the file's.
    private var hasChapters: Bool { !isArticle && (progress?.chapterCount ?? summary.chapterCount) > 1 }

    var body: some View {
        // 20 pt between the book and its text: the cover's shadow needs air, and the reference cell
        // (Apple Books' Continue) breathes there too.
        HStack(alignment: .top, spacing: 20) {
            // On its shelf slot so the chapter line, title and Play pill start at one x on every
            // row, whatever width the cover is; the grid stands its books the same way. Its own
            // button, not part of the text's: the cover is the same fixed 120 pt tall regardless of
            // how little text a row has, and folding Play in under a Button spanning that height
            // pushed it down to the cover's foot, leaving a gap under a short excerpt.
            Button(action: onOpenBook) {
                if isArticle {
                    // A web page or pasted text is not a book: a sheet of paper, on the same slot.
                    SheetCover(title: summary.document.title, sourceURL: summary.document.sourceURL, height: BookCover.rowHeight)
                        .shelved
                } else {
                    BookCover(relativePath: summary.document.coverImagePath, paths: env.paths, height: BookCover.rowHeight,
                              title: summary.document.title, author: summary.document.displayAuthor,
                              isPDF: summary.document.sourceType == .pdf)
                        .shelved
                }
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)                                          // decorative beside the text button's own label

            // 18 between the words and the pill: the gap that says the reading stopped and a
            // tap target started. Inside the words, 0 — each pair sets its own, so the three
            // lines group instead of standing an identical 8 apart (owner, 2026-09-11).
            VStack(alignment: .leading, spacing: 18) {
                Button(action: onOpenBook) {
                    VStack(alignment: .leading, spacing: 0) {
                        // "Chapter 7 · ◔ 41%  ✓": the chapter, how far through it, and ready-offline.
                        HStack(spacing: 6) {
                            if let chapterText { Text(chapterText) }
                            if let fraction {
                                if chapterText != nil {
                                    // A size up from the text it divides, or it reads as punctuation inside one fact.
                                    Text("·")
                                        .font(.custom("Inter-SemiBold", size: 15, relativeTo: .footnote))
                                        .accessibilityHidden(true)
                                }
                                CircularProgress(fraction: fraction, lineWidth: 2, size: 12)
                                Text("\(Int((fraction * 100).rounded()))%")
                            }
                            if summary.isFullyRendered { PositiveCheck() }
                        }
                        // No `typeRole(.meta)` here: it sets the font through the environment, and
                        // an override applied after it sits *further* from the Text, so the role
                        // wins and the override is dropped in silence. That is why this line and
                        // the excerpt had both been rendering as plain meta — identical, which is
                        // exactly the complaint (owner, 2026-09-11). Meta's tracking is 0, so the
                        // role has nothing else to give here.
                        .font(.custom("Inter-SemiBold", size: 12, relativeTo: .footnote))  // smaller and denser than the excerpt, not the same size a shade heavier
                        .foregroundStyle(Tokens.ink2)
                        .padding(.bottom, 4)                                              // it labels the title under it, so it sits with it

                        Text(summary.document.title)
                            .typeRole(.rowTitle)                                   // the Settings rows' face, by the owner's eye
                            .foregroundStyle(Tokens.ink)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let excerpt = glimpse?.excerpt, !excerpt.isEmpty {
                            Text(excerpt)
                                // The real face, not `.italic()`: that asks for a trait the system
                                // fonts carry, and a `Font.custom` face without one is left upright.
                                // And no `typeRole(.meta)` above it — see the chapter line: the role
                                // would win and this face would never be reached (owner, 2026-09-11).
                                .font(.custom("Inter-Italic", size: 13, relativeTo: .footnote))
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .foregroundStyle(Tokens.ink2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)      // wraps to its 2 lines instead of hugging 1
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 7)                                  // its own top, so a row without one keeps the 18 below
                        }
                    }
                }
                .buttonStyle(.plain)
                // One element, not the header line and the excerpt read out on top of it: the
                // visible detail collapses to the words that matter for a listener choosing where
                // to jump in.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([chapterText, summary.document.title].compactMap { $0 }.joined(separator: ", "))
                .accessibilityHint("Opens the book")

                HStack(spacing: 14) {                                          // fixed gap, not a Spacer: ⋯ sits near Play instead of riding the row's far edge
                    Pill(label: isPlayingHere ? "Pause" : (isStarting ? "Starting…" : (hasProgress ? "Continue" : "Play")),
                         detail: isStarting ? nil : timeDetail,
                         glyph: isPlayingHere ? "pause.fill" : (isStarting ? nil : "play.fill"),
                         style: .soft) {
                        Task {
                            if isPlayingHere { await env.player.togglePlay(); return }   // Pause stays in place
                            if isCurrent {
                                isStarting = true
                                await env.player.togglePlay()                            // resume, then read along
                                isStarting = false
                            }
                            onOpen()                                                       // the Reader loads and plays a non-current document itself
                        }
                    }
                    .disabled(isStarting)
                    .accessibilityHint(isPlayingHere ? "Pauses" : "Plays and opens the reader")
                    Menu {
                        contextItems
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Tokens.ink)
                            .frame(width: 36, height: 36)
                            .background(Tokens.surface, in: Circle())
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .contextMenu { contextItems }
        .sheet(isPresented: $showSleepTimer) { SleepTimerSheet() }
        .sheet(isPresented: $showVoiceChange) { VoiceChangeSheet(summary: summary) }
        .task(id: glimpseKey) { glimpse = await env.libraryModel.glimpse(for: summary) }
    }

    @ViewBuilder private var contextItems: some View {
        Button { Task { await env.libraryModel.markFinished(summary.id, !summary.isFinished) } } label: {
            Label(summary.isFinished ? "Mark as unfinished" : "Mark as finished", systemImage: "checkmark.circle")
        }
        Button(action: onDetails) { Label("Details", systemImage: "info.circle") }
        Button { showSleepTimer = true } label: { Label("Sleep timer", systemImage: "moon.zzz") }
        Button { showVoiceChange = true } label: { Label("Change voice", systemImage: "person.wave.2") }
        Button {
            Task {
                if !isCurrent { await env.player.load(summary, play: false) }
                env.player.renderCurrentChapter()
            }
        } label: { Label(hasChapters ? "Render chapter" : "Render whole document", systemImage: "waveform") }
    }

    /// What the book calls the section being listened to — "Introduction", "Chp 7: A Precarious
    /// Position" — as the chapter list and the Reader print it (`ChapterLabel`), never a number
    /// counted off the table of contents. Counting called a book's first entry "Chapter 1" when it
    /// was the title page or the contents, so the minute left in the front matter read as the
    /// minute left in chapter 1 (owner, 2026-09-11). Books only, once the glimpse has read the
    /// chapter; nothing at all when the book left the section unnamed or named it after itself,
    /// since a made-up number and the title repeated are both worse than one line fewer.
    private var chapterText: String? {
        guard let progress, !isArticle, progress.chapterCount > 1, let c = progress.chapterIndex,
              let title = glimpse?.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              title.localizedCaseInsensitiveCompare(summary.document.title) != .orderedSame
        else { return nil }
        return ChapterLabel.text(for: title, ordinal: c + 1)
    }

    /// How far through the chapter (books) or the file (everything else). Nil until a chaptered
    /// book's glimpse has loaded, rather than flashing the whole book's number first.
    private var fraction: Double? {
        hasChapters ? glimpse?.chapterFraction : (progress?.fraction ?? 0)
    }

    /// Time left in the chapter (books) or the file, on the Play pill: "2h 28m", never "~" and no
    /// "left" — the pill is the sentence. Nil until a chaptered book's glimpse has loaded.
    private var timeDetail: String? {
        let seconds: TimeInterval?
        if hasChapters { seconds = glimpse?.chapterRemainingSeconds }
        else { seconds = progress?.remainingSeconds ?? summary.totalSeconds }
        return seconds.map { DurationFormatter.remaining($0, approximate: false) }
    }

    /// What `LibraryModel.glimpse(for:)` reads: the task reloads only when the resume point or the
    /// chapters behind it could have moved, not on every row refresh.
    private struct GlimpseKey: Hashable {
        var id: UUID
        var resumePosition: Position?
        var resumeChapterIndex: Int?
        var isStale: Bool
        var chapterIndex: Int?
    }

    private var glimpseKey: GlimpseKey {
        GlimpseKey(id: summary.id, resumePosition: summary.document.resumePosition, resumeChapterIndex: summary.resumeChapterIndex,
                   isStale: summary.isStale, chapterIndex: progress?.chapterIndex)
    }
}
