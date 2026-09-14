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
    /// A chapter of this book has just finished. See `flashComplete`.
    @State private var justFinished = false
    @State private var completeTask: Task<Void, Never>?
    /// The toast's own four seconds: the row and the message are one announcement, so they go
    /// together rather than one outstaying the other.
    private static let completeSeconds: TimeInterval = 4

    /// The widest the chapter's name is allowed to run before it fades out (owner, 2026-09-14).
    /// A ceiling, not a demand: it is the one flexible thing on its line, so on a narrow phone — or
    /// beside a long "· ◔ 100% ✓" — it simply takes what is left and fades sooner. 140 leaves the
    /// ring and its number sitting right after the name on a 393pt phone's 221pt text column,
    /// instead of a title long enough to reach the far edge carrying them there with it.
    private static let chapterWidth: CGFloat = 140

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
                        // One fact on one line, so it is spaced and aligned as one: no `maxWidth:
                        // .infinity` under the chapter pushing the rest out to the row's far edge
                        // (owner, 2026-09-14 — "there should not be so much space between the
                        // chapter, the dot and the percentage"), and the baseline, not the top, to
                        // line up on. Top-aligning had hung a 12pt ring from the same y as the
                        // text's line box, which starts above the letters: the ring read high and
                        // every word under it read low, the 15pt dot lowest of all since its box is
                        // the tallest. Baselines are what the eye actually reads a line off.
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            // A render of this book takes the line while it runs (owner,
                            // 2026-09-14). Starting one from this row's `⋯` used to show nothing at
                            // all — the queue is app-wide and its only face was inside the Book
                            // sheet — so the one row that sent the work is the one row that should
                            // say it is happening. The chapter and the listening ring come back the
                            // moment the queue is done with this book.
                            if lineState == .complete {
                                // Green, and for exactly as long as the toast that says the same
                                // thing (owner, 2026-09-14). The row and the message arrive
                                // together and leave together, and what the row goes back to is
                                // where the reader actually is in the book.
                                Text("Render complete")
                                    .foregroundStyle(Tokens.positive)
                                    .transition(.blurReplace)
                            } else if let job = renderJob {
                                // Two words and a number, and nothing else (owner, 2026-09-14): the
                                // dot divides a chapter from its progress, and the ring draws a
                                // proportion the percentage has already given. Neither has anything
                                // to divide or add here.
                                // `accent`, not `glow`: the Book sheet's render bar is the accent
                                // already, and one activity wearing two colours in two places is
                                // two activities as far as the eye is concerned (owner, 2026-09-14).
                                ShimmerText(text: "Rendering \(Int((job.fraction * 100).rounded()))%",
                                            tint: Tokens.accent)
                                    .transition(.blurReplace)
                            } else if let chapterText {
                                FadingLine(text: chapterText, maxWidth: Self.chapterWidth)
                                    .transition(.blurReplace)
                            }
                            if lineState == .normal, let fraction {
                                if chapterText != nil {
                                    // A size up from the text it divides, or it reads as punctuation inside one fact.
                                    Text("·")
                                        .font(.custom("Inter-SemiBold", size: 15, relativeTo: .footnote))
                                        .accessibilityHidden(true)
                                }
                                // The ring and its number are one reading, so they sit closer to
                                // each other than either sits to the dot.
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    CircularProgress(fraction: fraction, lineWidth: 2, size: 12)
                                        // A shape has no baseline of its own, so it would hang by
                                        // its bottom edge. This drops it 1.8 below the line instead,
                                        // which centres the ring on the digits' cap height — the
                                        // optical middle of "41%", not the middle of its line box.
                                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1.8 }
                                    Text("\(Int((fraction * 100).rounded()))%")
                                }
                                .transition(.blurReplace)
                            }
                            if lineState == .normal, summary.isFullyRendered {
                                PositiveCheck().transition(.blurReplace)
                            }
                        }
                        // The line is one fact replacing another, so it dissolves rather than
                        // being edited in place — and the row's width settles with it (owner,
                        // 2026-09-14). Here, wrapping the `HStack`'s geometry as well as its
                        // contents, because the two lines are different widths and the reflow is
                        // half of what makes the swap read as smooth.
                        .animation(.snappy(duration: 0.32), value: lineState)
                        // No `typeRole(.meta)` here: it sets the font through the environment, and
                        // an override applied after it sits *further* from the Text, so the role
                        // wins and the override is dropped in silence. That is why this line and
                        // the excerpt had both been rendering as plain meta — identical, which is
                        // exactly the complaint (owner, 2026-09-11). Meta's tracking is 0, so the
                        // role has nothing else to give here.
                        .font(.custom("Inter-SemiBold", size: 12, relativeTo: .footnote))  // smaller and denser than the excerpt, not the same size a shade heavier
                        .foregroundStyle(Tokens.ink2)
                        .padding(.bottom, 4)                                              // it labels the title under it, so it sits with it

                        // Two lines, as `rowTitle` has always allowed — but a third one dissolves
                        // at the end of the second rather than stopping at an ellipsis, the way the
                        // chapter above it does (owner, 2026-09-14).
                        FadingParagraph(text: summary.document.title, lines: 2)
                            .typeRole(.rowTitle)                                   // the Settings rows' face, by the owner's eye
                            .foregroundStyle(Tokens.ink)
                            .multilineTextAlignment(.leading)

                        if let excerpt = glimpse?.excerpt, !excerpt.isEmpty {
                            FadingParagraph(text: excerpt, lines: 2)
                                // The real face, not `.italic()`: that asks for a trait the system
                                // fonts carry, and a `Font.custom` face without one is left upright.
                                // And no `typeRole(.meta)` above it — see the chapter line: the role
                                // would win and this face would never be reached (owner, 2026-09-11).
                                .font(.custom("Inter-Italic", size: 13, relativeTo: .footnote))
                                .foregroundStyle(Tokens.ink2)
                                .multilineTextAlignment(.leading)
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
        // The queue publishes each chapter as it leaves, ready or failed. A failure has its own
        // toast and nothing to celebrate on the row, so only `.ready` lights this.
        .onChange(of: env.chapterRenderer.finishCount) { _, _ in
            guard let job = env.chapterRenderer.lastFinished,
                  job.documentID == summary.id, job.state == .ready else { return }
            flashComplete()
        }
        .onDisappear { completeTask?.cancel() }
    }

    @ViewBuilder private var contextItems: some View {
        Button { Task { await env.libraryModel.markFinished(summary.id, !summary.isFinished) } } label: {
            Label(summary.isFinished ? "Mark as unfinished" : "Mark as finished", systemImage: "checkmark.circle")
        }
        Button(action: onDetails) { Label("Details", systemImage: "info.circle") }
        Button { showSleepTimer = true } label: { Label("Sleep timer", systemImage: "moon.zzz") }
        Button { showVoiceChange = true } label: { Label("Change voice", systemImage: "person.wave.2") }
        // The book's resume chapter — chapter 1 if it has never been played — without loading it.
        // The `load` this used to do made pressing "Render chapter" on a book you were not
        // listening to silently make it your current book (chapter-rendering design, "Entry points").
        if let job = renderJob {
            Button(role: .destructive) {
                env.chapterRenderer.cancel(job.id)
            } label: { Label("Stop rendering", systemImage: "xmark") }
        } else {
            Button {
                Task { await env.chapterRenderer.enqueueResumeChapter(of: summary.id) }
            } label: { Label(hasChapters ? "Render chapter" : "Render whole document", systemImage: "waveform") }
        }
    }

    /// What the row's first line is saying. Three states rather than a pair of booleans, so the one
    /// animation below has one value to watch and the three cannot contradict each other.
    private enum LineState: Equatable { case normal, rendering, complete }

    private var lineState: LineState {
        if justFinished { return .complete }
        return renderJob != nil ? .rendering : .normal
    }

    /// A chapter of *this* book has just become playable. Held for as long as the toast that says so
    /// — they are one announcement in two places — and then the line goes back to the book. In a
    /// batch, "back" is the next chapter's blue, which is the truth: one is done and another is on.
    private func flashComplete() {
        completeTask?.cancel()
        justFinished = true
        completeTask = Task {
            try? await Task.sleep(for: .seconds(Self.completeSeconds))
            guard !Task.isCancelled else { return }
            justFinished = false
        }
    }

    /// This book's outstanding render, if the app's one queue has one. The chapter being made wins
    /// over one still waiting: it is the one with a number worth showing.
    private var renderJob: ChapterRenderJob? {
        let mine = env.chapterRenderer.queue.filter { $0.documentID == summary.id }
        return mine.first { $0.state == .running } ?? mine.first { $0.state == .queued }
    }

    /// What the book calls the section being listened to — "Introduction", "Chapter 7" — never a
    /// number counted off the table of contents. Counting called a book's first entry "Chapter 1"
    /// when it was the title page or the contents, so the minute left in the front matter read as
    /// the minute left in chapter 1 (owner, 2026-09-11). Books only, once the glimpse has read the
    /// chapter; nothing at all when the book left the section unnamed or named it after itself,
    /// since a made-up number and the title repeated are both worse than one line fewer.
    ///
    /// A numbered chapter shows the bare number here, not the name after it — this row is a place
    /// to find your spot, not to read the chapter list again (owner, 2026-09-11).
    private var chapterText: String? {
        guard let progress, !isArticle, progress.chapterCount > 1, let c = progress.chapterIndex,
              let title = glimpse?.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              title.localizedCaseInsensitiveCompare(summary.document.title) != .orderedSame
        else { return nil }
        if let number = ChapterLabel.number(for: title) { return "Chapter \(number)" }
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
