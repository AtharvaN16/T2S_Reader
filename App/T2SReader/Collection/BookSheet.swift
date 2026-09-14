// App/T2SReader/Collection/BookSheet.swift
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// Spec §2.4.5 book sheet, after the owner's 2026-09-09 cut: the book alone at the top, lit from
/// behind in its own colour and tilting with the phone, the title and author centred under it,
/// one Play pill in the Home row's form, then the chapters. Chapters come from the timeline
/// (re-derived if stale) and their progress from the persisted position through `DocumentProgress`.
/// Nothing about a queue: playing is what puts a book on Home. The bookmarks were listed under the
/// chapters until 2026-09-12 and are behind the `⋯` now, as a page — a sheet that grew with every
/// note written in the book was a sheet about two things.
///
/// Behind the same `⋯` is render mode (chapter-rendering design, "UI"), which turns the chapter
/// list into a selection list rather than opening a screen of its own: the summary line of what
/// this book has on the device, a state mark on every row, and one bar at the foot. It is the one
/// place in the app that says what is cached and the one place that can take it back.
struct BookSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerRoute) private var readerRoute
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var summary: DocumentSummary
    /// Only Home's book tap asks for the scroll-and-pulse (owner, 2026-09-11) — Collection's tile
    /// and row open on the chapter list as it's always shown, at the top.
    var pulseOnOpen: Bool = false
    /// The Collection's "Render chapter" opens straight into render mode rather than dropping the
    /// reader on the chapter list to find the `⋯` again (chapter-rendering design, "Entry points").
    var startInRenderMode: Bool = false

    @State private var chapters: [ChapterEntry] = []
    @State private var bookmarks: BookmarkListModel?
    /// True only while the Play pill's own tap is resuming a paused, already-current document —
    /// the one branch that awaits playback before dismissing, otherwise silently.
    @State private var isStarting = false
    /// The phone's lean for the hero. The sheet owns it: the gyro runs only while the sheet shows.
    @State private var motion = MotionTilt()
    /// The resume chapter's one flash, right after the sheet scrolls to it (owner, 2026-09-11:
    /// opening the sheet from Home should land the eye on where the book picks up).
    @State private var pulsingChapter: Int?
    @State private var showBookmarks = false
    /// The chapter list turned into a selection list. The queue itself is app-wide and outlives
    /// this sheet; only the picking is local.
    @State private var isRendering = false
    @State private var selection: Set<Int> = []
    /// What this book has on the device, chapter by chapter. Re-read whenever it can have changed.
    @State private var audio = BookAudioStatus()
    /// The `⋯`'s Delete, asked for confirmation before `AppEnvironment.deleteDocument` runs.
    @State private var confirmDelete = false
    /// A question the box is asking of itself. Neither of these is a dialog: the box keeps its
    /// shape and changes what it says, so the answer is given where the question was asked (owner,
    /// 2026-09-14). An alert would cover the very thing the reader is deciding about.
    @State private var asking: Asking?
    /// How many of this book's chapters were outstanding when ✕ was pressed — the question's own
    /// scope, held still while it is on screen. See `stopControls`.
    @State private var stopScope = 0
    /// See `trackBatch`.
    @State private var batchSize = 0

    enum Asking { case deleteAudio, stop }

    private static let heroHeight: CGFloat = 200
    /// What `commit` scrolls to once the queue has taken the work.
    private static let progressAnchor = "render-progress"

    private var live: DocumentSummary { env.libraryModel.summaries.first { $0.id == summary.id } ?? summary }
    private var isCurrent: Bool { env.player.current?.id == live.id }
    private var isPlayingHere: Bool { isCurrent && env.player.isPlaying }
    /// The chapter the book would resume in: the first not yet heard through.
    private var resumeIndex: Int? { chapters.first { $0.fraction < 1 }?.index ?? chapters.last?.index }
    /// Whether there's a saved position to pick back up — "Continue" over "Play" once there is.
    private var hasProgress: Bool { live.document.resumePosition != nil }

    /// Time left in the resume chapter, on the Play pill as the Home row shows it ("Play  17m").
    private var timeDetail: String? {
        guard let resumeIndex, let chapter = chapters.first(where: { $0.index == resumeIndex }) else { return nil }
        return DurationFormatter.remaining(chapter.durationSeconds * (1 - chapter.fraction), approximate: false)
    }

    /// The owner's rule for the tilt: never against Reduce Motion, never when the device is already
    /// struggling (thermal, Low Power Mode), only while the app is up front.
    private var shouldTilt: Bool {
        let device = env.deviceMonitor.deviceState
        return scenePhase == .active && !reduceMotion && !device.thermalSerious && !device.lowPowerMode
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    hero
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.section)
                    VStack(spacing: 8) {
                        Text(live.document.title).typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                            .multilineTextAlignment(.center)
                        if let author = live.document.displayAuthor {
                            Text(author).typeRole(.meta).foregroundStyle(Tokens.ink2).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    // The `⋯` beside the pill rather than off in the sheet's corner (owner,
                    // 2026-09-12): what it holds is about the book, so it belongs with the book's
                    // one action instead of hovering over the cover.
                    HStack(spacing: 12) {
                        playPill
                        bookMenu
                    }
                    .frame(maxWidth: .infinity)
                    if isRendering {
                        onDeviceBox
                    } else if let job = runningHere {
                        renderProgress(job).id(Self.progressAnchor)
                    }
                    ChapterListView(chapters: chapters, current: resumeIndex, heading: .groupTitle,
                                    pulsing: pulsingChapter,
                                    // Render mode is about what is on the device, so the rows are
                                    // about that alone: the bookmark pills stand down until it ends.
                                    bookmarks: isCurrent && !isRendering ? env.player.bookmarksByChapter : [:],
                                    renderMarks: renderMarks,
                                    // The tag belongs to the list as it is normally read; in render
                                    // mode the trailing mark says the same thing and says it louder.
                                    onDevice: isRendering ? [] : onDeviceChapters,
                                    headerAction: isRendering ? nil : { enterRendering() },
                                    headerAllAction: isRendering && selection.isEmpty && !renderableChapters.isEmpty
                                        ? { renderAll(scrollingWith: proxy) } : nil,
                                    // The same slot, once there are ticks in the list: with chapters
                                    // in hand the useful offer is not "take everything" — which
                                    // would throw the picking away — but to put them back down
                                    // (owner, 2026-09-14: "clear selection has more usecases").
                                    headerClearAction: isRendering && !selection.isEmpty
                                        ? { clearSelection() } : nil,
                                    headerCloseAction: isRendering ? { endRendering() } : nil,
                                    onSelect: { chapter in
                                        if isRendering { toggle(chapter.index); return }
                                        Task {
                                            if !isCurrent { await env.player.load(live, play: false) }
                                            await env.player.seek(toChapter: chapter.index)
                                            if !env.player.isPlaying { await env.player.togglePlay() }
                                            dismiss()
                                            readerRoute.open(live)
                                        }
                                    },
                                    // The same jump `BookmarksPage` makes from behind the `⋯`:
                                    // under the chapter these are rows you can open now, not just
                                    // marks.
                                    onSelectBookmark: { entry in
                                        Task {
                                            await bookmarkModel().jump(to: entry, in: live)
                                            dismiss()
                                            readerRoute.open(live)
                                        }
                                    },
                                    onEvict: { chapter in evict(chapter: chapter.index) })
                    .padding(.horizontal, -12)                                 // the rows' fill runs into the margin, as in the Reader
                    Color.clear.frame(height: Spacing.section)
                }
                .padding(.horizontal, Spacing.margin)
            }
            .task {
                isRendering = startInRenderMode
                await reload()
                await scrollToResumeChapterAndPulse(proxy)
            }
            // A job finishing, failing or starting changes what a row says and what the store
            // holds; the progress ticks in between do not, so this watches the states rather than
            // the queue, and does not re-read the book once a sentence.
            .onChange(of: env.chapterRenderer.queue.map(\.state)) { _, _ in
                Task { await refreshAudio() }
            }
            .onChange(of: outstandingHere, initial: true) { old, new in trackBatch(from: old, to: new) }
            .safeAreaInset(edge: .bottom) {
                // The bar is up for as long as render mode is, and it is the way out of it: with
                // nothing picked it reads "Done". It used to appear only once something was picked
                // — an inert bar at the foot of a list of ready chapters is a permanent invitation
                // to nothing — but that left the reader who had just pressed Start with the bar
                // gone, the rows still wearing their marks, and no exit but a `Done` buried in the
                // `⋯` (owner, 2026-09-13: "there is no way to exit the render mode"). "Done" is not
                // an invitation to nothing; it is the answer to the question the mode is asking.
                if isRendering {
                    // Blue the moment there is something to render (owner, 2026-09-14). The two
                    // states of this key are not two shades of the same act: "Done" closes a mode
                    // and is the ink key every sheet closes with, while "Render 3 chapters" spends
                    // the phone's battery on the next ten minutes — and blue is what this app has
                    // always called the key that starts something.
                    BarButton(label: doneLabel, tone: selection.isEmpty ? .ink : .blue) {
                        endRendering(startingPicked: true, scrollingWith: proxy)
                    }
                    .padding(.horizontal, Spacing.margin)
                    // Air over the key, and the list fading out under it rather than being cut off
                    // at a straight grey line (owner, 2026-09-13). `BottomFade` is the same ramp
                    // the root pages and the voice sheet's commit bar use — in `raised`, which is
                    // the grey this sheet stands on.
                    .padding(.top, Spacing.grid * 2)
                    .padding(.bottom, Spacing.grid)
                    .background { BottomFade(color: Tokens.raised) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(Tokens.raised)
        .presentationCornerRadius(Spacing.sheetCorner)
        // The book sheet is the likeliest thing to be frontmost when the queue holds — it is where
        // the chapters were just picked — and it owns the one `.sheet` slot, so the notice is drawn
        // here rather than presented over it.
        .renderHoldSheet()
        // A page over the sheet, not a sheet over a sheet: it is the same `BookmarksPage` the
        // Reader opens, so a bookmark reads and behaves the same whichever way you came at it.
        .fullScreenCover(isPresented: $showBookmarks) {
            BookmarksPage(summary: live) {
                dismiss()                                                  // the sheet goes with the page
                readerRoute.open(live)                                     // and the Reader opens where the bookmark is
            }
        }
        .onChange(of: shouldTilt, initial: true) { _, on in motion.setEnabled(on) }
        .onDisappear { motion.setEnabled(false) }
        .confirmationDialog("Delete “\(live.document.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete from this device", role: .destructive) {
                Task { await env.deleteDocument(live.id); dismiss() }
            }
            if env.syncModel.isEnabled {
                Button("Delete everywhere", role: .destructive) {
                    Task { await env.deleteDocument(live.id, everywhere: true); dismiss() }
                }
            }
        } message: {
            Text(env.syncModel.isEnabled ? AppEnvironment.deleteMessageWithSync : AppEnvironment.deleteMessage)
        }
    }

    /// Lands the eye on where the book picks up (owner, 2026-09-11): centres the resume chapter —
    /// off-screen below the fold on any book past its first few chapters — then flashes it once.
    /// Only from Home's book tap (`pulseOnOpen`), and only for a book already in progress — a fresh
    /// book's resume chapter is the first row, already on screen, and the Collection tile opens
    /// straight on the chapter list every time regardless of state.
    private func scrollToResumeChapterAndPulse(_ proxy: ScrollViewProxy) async {
        guard pulseOnOpen, hasProgress, let resumeIndex else { return }
        try? await Task.sleep(for: .milliseconds(50))
        withAnimation(.easeOut(duration: 0.4)) { proxy.scrollTo(resumeIndex, anchor: .center) }
        withAnimation(.easeOut(duration: 0.2)) { pulsingChapter = resumeIndex }
        try? await Task.sleep(for: .milliseconds(700))
        withAnimation(.easeInOut(duration: 0.5)) { pulsingChapter = nil }
    }

    /// The book, a little smaller than before, over a soft ellipse of its own colour — a
    /// backlight, blurred wide so it reads as light and not as a shape — turning with the phone.
    private var hero: some View {
        let cover = BookCover(relativePath: live.document.coverImagePath, paths: env.paths, height: Self.heroHeight,
                              title: live.document.title, author: live.document.displayAuthor,
                              isPDF: live.document.sourceType == .pdf, tilt: motion.tilt)
        return ZStack {
            Ellipse()
                .fill(cover.backlight)
                .frame(width: Self.heroHeight * BookCover.ratio * 1.35, height: Self.heroHeight * 0.95)
                .blur(radius: 44)
                .opacity(0.7)
                .offset(y: Self.heroHeight * 0.06)
                .accessibilityHidden(true)
            cover
        }
    }

    /// The Home row's Play pill, centred: Pause while this book plays, "Continue  17m" once there's
    /// a saved position, "Play  17m" for a book never started.
    /// The book's own menu: what there is to do with this book that is not "play it". The bookmarks
    /// moved out from under the chapters and behind it (owner, 2026-09-12), which keeps the sheet
    /// the length of the book rather than the length of the book plus everything written about it.
    private var bookMenu: some View {
        Menu {
            Button { showBookmarks = true } label: { Label("Bookmarks", systemImage: "bookmark") }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        } label: {
            CircleGlyph(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    /// The storage box: what this book has on the device. Three rows, and they are the rendering
    /// box's three rows exactly (owner, 2026-09-14) — the size where the heading goes, the bar where
    /// the bar goes, the count where the chapter's name goes, one control in the slot the transport
    /// buttons use. Two different questions, one shape.
    ///
    /// "On this device" is gone as a label: the heading is now the answer rather than the question,
    /// and the sheet it sits in has already said which book this is.
    /// Only when there is something to report (owner, 2026-09-14). A box headed "Zero KB" over an
    /// empty bar, with nothing to delete, is a panel about the absence of a thing — and render mode
    /// is where you go to make some, so the chapter list underneath is the whole answer.
    @ViewBuilder private var onDeviceBox: some View {
        if audio.hasAudio {
            let asked = asking == .deleteAudio
            boxBody(
                // "All", and "rendered audio" as Settings → Storage names it (owner, 2026-09-14):
                // this box's trash takes the whole book, and every row under it has a trash of its
                // own that takes one chapter. "Delete this audio?" did not say which of the two had
                // been pressed.
                title: asked ? "Delete all rendered audio?"
                             : "\(BookAudioStatus.sizeText(audio.bytes)) occupied on device",
                titleTint: asked ? Tokens.destructive : Tokens.ink,
                trailing: nil,
                showsBar: chapters.count > 1, isAsking: asked,
                bar: { ChapterBar(total: chapters.count, rendered: onDeviceChapters,
                                  partial: partlyRenderedChapters) },
                // Nothing under the bar while it asks: the question is the heading and the answer is
                // the row, and a sentence between them is one thing too many to read before pressing
                // something irreversible (owner, 2026-09-14).
                detail: asked ? nil : audio.countLine,
                controls: {
                    if asked {
                        yesNo(yesLabel: "Delete this book's audio") { evictAll() }
                    } else {
                        // The chapter row's trash exactly — same glyph, same size, same red
                        // (owner, 2026-09-14). One mark means "take this audio away", whether it is
                        // one chapter's or the book's, and a worded pill up here made the box's
                        // delete look like a different act from the row's.
                        Button { ask(.deleteAudio) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Tokens.destructive)
                                .frame(width: ChapterRow.markColumn)
                                .frame(minHeight: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete this book's audio")
                    }
                })
        }
    }

    /// Both boxes, drawn once: a heading with an optional figure at the far end, a bar, and a line
    /// with the controls at the far end. A quantity and a rate are different questions, and the
    /// owner chose different words for them — but they swap in place on the same spot in the sheet,
    /// so they are the same three rows or the swap reads as a replacement.
    ///
    /// The rhythm is deliberately uneven: the heading and its bar are one thought, so 12 between
    /// them; the controls are a different thought, so 20 (owner, 2026-09-14: "increase the space
    /// above the buttons row… have some spacing hierarchy").
    private func boxBody<Bar: View, Controls: View>(
        title: String, titleTint: Color, trailing: String?, showsBar: Bool = true,
        isAsking: Bool = false,
        @ViewBuilder bar: () -> Bar, detail: String?,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).typeRole(.sectionHeader).foregroundStyle(titleTint).lineLimit(1)
                    .contentTransition(.opacity)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).typeRole(.metaStrong).foregroundStyle(Tokens.ink2).monospacedDigit()
                        .transition(.opacity)
                }
            }
            // No bar, no gap for one: a chapterless document leaves two rows, not two rows and a
            // hole where a measurement would have been.
            if showsBar {
                Spacer().frame(height: 12)
                // While it asks, the bar goes but its room stays (owner, 2026-09-14). A box that
                // shrank to put a question and grew back to answer it would move the very buttons
                // the thumb is travelling towards.
                bar().opacity(isAsking ? 0 : 1)
            }
            Spacer().frame(height: 20)
            // One height for the row whatever stands in it — a 36 pt disc, a bare trash, a pair of
            // pills — so the box is the same height asking as it is telling (owner, 2026-09-14).
            HStack(alignment: .center, spacing: 8) {
                if let detail {
                    Text(detail).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
                        .contentTransition(.opacity)
                    Spacer(minLength: 8)
                }
                controls()
                    // Keyed on the question, so the controls cross-fade rather than being edited in
                    // place — one set of words leaves as the other arrives.
                    .id(isAsking)
                    .transition(.opacity)
            }
            .frame(minHeight: 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        // `ground`, not `surface`: a `.soft` pill *is* `surface`, so a surface box swallowed the
        // capsules whole. The sheet stands on `raised`, so this reads as a well cut into it.
        .background(Tokens.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.snappy(duration: 0.3), value: asking)
    }

    /// The answer, where the question was asked. `No` first: the safe one should be the one a thumb
    /// reaches by accident.
    /// What ✕ asks. With one chapter outstanding there is only one thing it can mean, so it is the
    /// plain yes-or-no; with a batch there are two different intentions behind the same press — drop
    /// the chapter that is being made, or drop everything still to come — and the reader is the only
    /// one who knows which (owner, 2026-09-14). Naming the count is the point: "All 5" is the number
    /// that decides it.
    ///
    /// The count is `stopScope` — what was outstanding when ✕ was pressed — and not the live one
    /// (owner, 2026-09-14: "sometimes I get option to just end 1 chp and sometimes I get option to
    /// end all"). A chapter finishing is a frequent event and it was taking two of the three answers
    /// off the screen mid-decision: the reader who pressed ✕ on a batch found a bare Yes, or reached
    /// for "All 3" and pressed whatever had slid into its place. A question keeps the shape it was
    /// asked in until it is answered.
    @ViewBuilder private func stopControls(_ job: ChapterRenderJob) -> some View {
        let outstanding = stopScope
        Pill(label: "No", style: .soft, fillsWidth: true, compact: true) { ask(nil) }
            .accessibilityLabel("No, keep rendering")
        if outstanding > 1 {
            // `cancel` drops the job, lets the utterance already in the engine finish and be stored,
            // and the drain loop simply takes the next one.
            Pill(label: "This one", style: .destructiveSoft, fillsWidth: true, compact: true) {
                ask(nil); env.chapterRenderer.cancel(job.id)
            }
            .accessibilityLabel("Stop this chapter only")
            Pill(label: "All \(outstanding)", style: .destructiveSoft, fillsWidth: true, compact: true) {
                ask(nil); stopAllHere()
            }
            .accessibilityLabel("Stop all \(outstanding) chapters")
        } else {
            Pill(label: "Yes", style: .destructiveSoft, fillsWidth: true, compact: true) {
                ask(nil); env.chapterRenderer.cancel(job.id)
            }
            .accessibilityLabel("Yes, stop rendering")
        }
    }

    /// Every outstanding chapter of *this* book. Not `cancelAll()`: the queue is the whole app's, and
    /// another book's chapters are none of this sheet's business to throw away.
    private func stopAllHere() {
        for job in jobsHere where job.state == .queued || job.state == .running {
            env.chapterRenderer.cancel(job.id)
        }
    }

    @ViewBuilder private func yesNo(yesLabel: String, yes: @escaping () -> Void) -> some View {
        Pill(label: "No", style: .soft, fillsWidth: true, compact: true) { ask(nil) }
            .accessibilityLabel("No, leave it")
        Pill(label: "Yes", style: .destructiveSoft, fillsWidth: true, compact: true) { ask(nil); yes() }
            .accessibilityLabel(yesLabel)
    }

    private func ask(_ question: Asking?) {
        // The scope is read once, as the question is put. A queue that finishes a chapter while the
        // reader is deciding must not rewrite the answers under their thumb.
        if question == .stop { stopScope = outstandingHere }
        withAnimation(.snappy(duration: 0.28)) { asking = question }
    }

    /// The queue, said in the sheet you are reading rather than only in the mode you have left.
    /// The storage box's three rows, carrying a rate instead of a quantity.
    ///
    /// This book's jobs only. The queue is the whole app's, so another book's chapter is none of
    /// this sheet's business and must not be reported here as though it were this book's.
    @ViewBuilder private func renderProgress(_ job: ChapterRenderJob) -> some View {
        let hold = env.chapterRenderer.hold
        let asked = asking == .stop
        boxBody(
            title: asked ? "Stop rendering?" : progressTitle(job),
            titleTint: asked ? Tokens.destructive : holdTint(hold),
            trailing: asked ? nil : "\(Int((job.fraction * 100).rounded()))%",
            isAsking: asked,
            // Grey while it is stopped, whoever stopped it: the one difference between a queue that
            // is working and a queue that is waiting for you.
            bar: { ProgressBar(fraction: job.fraction,
                               tint: hold == nil && !asked ? Tokens.accent : Tokens.ink2, height: 6) },
            detail: asked ? nil : progressDetail(job),
            controls: {
                if asked {
                    stopControls(job)
                } else {
                    // Glyphs, not words (owner, 2026-09-14). Resume is `play` because resuming a
                    // queue that heat stopped is the "render anyway" the held-queue sheet offers —
                    // one control for either reason. A full store has nothing to press through, so
                    // it gets no Resume at all.
                    if hold != .storeFull {
                        Button { hold == nil ? env.chapterRenderer.pause() : env.chapterRenderer.resume() } label: {
                            CircleGlyph(systemName: hold == nil ? "pause.fill" : "play.fill")
                        }
                        .accessibilityLabel(hold == nil ? "Pause rendering" : "Resume rendering")
                    }
                    Button { ask(.stop) } label: {
                        CircleGlyph(systemName: "xmark", tint: Tokens.destructive)
                    }
                    .accessibilityLabel("Stop rendering")
                }
            })
    }

    private func holdTint(_ hold: ChapterRenderRunner.Hold?) -> Color {
        switch hold {
        case .storeFull: return Tokens.destructive
        case .hot: return Tokens.accent
        case .byReader, .none: return Tokens.ink
        }
    }

    /// "Rendering 2 of 5", or why it has stopped. A hold the reader did not ask for names itself,
    /// since the app-wide sheet that would have said so is dismissible and may already be gone.
    private func progressTitle(_ job: ChapterRenderJob) -> String {
        switch env.chapterRenderer.hold {
        case .byReader: return "Paused"
        case .hot: return "Paused — phone is warm"
        case .storeFull: return "Paused — no room"
        case .none: break
        }
        // Against the batch, not against everything this book has ever been asked for (owner,
        // 2026-09-14: "why does it say rendering 6 of 6 … when I do a single render"). The runner
        // keeps finished jobs in the queue so a row can keep reporting what became of it, so
        // counting them made a fifth single chapter read as the sixth of six.
        let total = max(batchSize, outstandingHere)
        let position = max(1, total - outstandingHere + 1)
        return total > 1 ? "Rendering \(position) of \(total)" : "Rendering"
    }

    /// The line under the bar: the chapter being made, or — when the queue has stopped — what that
    /// means for the work already done, which is the only question a pause actually raises.
    private func progressDetail(_ job: ChapterRenderJob) -> String {
        switch env.chapterRenderer.hold {
        // A pause the reader asked for needs no sentence — the heading has already said it, and the
        // chapter's name is the more useful thing to keep on screen (owner, 2026-09-14). The two
        // holds nobody asked for keep theirs: those carry news.
        case .byReader, .none: return ChapterLabel.text(for: job.title, ordinal: job.chapterIndex + 1)
        case .hot: return "Starts again once it cools"
        case .storeFull: return "Free space in Settings → Storage"
        }
    }

    /// Which of this book's chapters hold some audio but not a whole chapter's worth. The fill tier
    /// leaves these behind and they take up room without playing a chapter through, so the bar has
    /// to say "there is something here" without claiming the chapter is ready.
    /// How many chapters the batch on screen began with — the denominator of "2 of 5", and nothing
    /// to do with what this book was asked for earlier in the session. Set when work appears out of
    /// nothing, grown if more is added while it runs, and forgotten when the queue empties.
    ///
    /// Opening the sheet onto a batch already in flight is the one case it cannot be sure of: it
    /// starts from what is left, so the counter reads "1 of 3" rather than "3 of 5". That is a
    /// smaller lie than counting the session, and it corrects itself with the next batch.
    private func trackBatch(from old: Int, to new: Int) {
        if new == 0 { batchSize = 0 } else if old == 0 { batchSize = new } else { batchSize = max(batchSize, new) }
        // The queue emptying takes the box with it, and a question goes with the box it was asked
        // in — otherwise the next batch opens mid-sentence, already asking whether to stop.
        if new == 0, asking == .stop { asking = nil }
    }

    /// How many of this book's chapters are still to come, the one being made included. Decides
    /// whether ✕ is "stop this chapter" or simply "stop".
    private var outstandingHere: Int {
        jobsHere.count { $0.state == .queued || $0.state == .running }
    }

    private var partlyRenderedChapters: Set<Int> {
        Set(audio.chapters.filter { $0.rendered > 0 && !$0.isFullyRendered }.map(\.chapterIndex))
    }

    /// This book's job that the queue is actually working on, or the next one waiting — nil when
    /// this book has nothing outstanding, which is what takes the block off the screen.
    ///
    /// `jobsHere`, not `jobs.values`: a dictionary has no order, and the difference showed the
    /// moment the queue stopped (owner, 2026-09-14: "when I press pause the entire line and the
    /// subtext reanimate"). Pause sends the running chapter back to `.queued` where it stands, so
    /// the box goes looking for the first waiting job — and out of a dictionary that is any of
    /// them. The heading stayed "Paused" while the name under it and the percentage beside it
    /// jumped to a chapter that had not been started. In the queue's own order the head of the
    /// queue is the chapter that was running, which is the one the box was already describing.
    private var runningHere: ChapterRenderJob? {
        jobsHere.first { $0.state == .running } ?? jobsHere.first { $0.state == .queued }
    }

    /// Which chapters the device holds in full, for the row tag.
    private var onDeviceChapters: Set<Int> {
        Set(audio.chapters.filter(\.isFullyRendered).map(\.chapterIndex))
    }

    /// The one key at the foot of render mode: it commits what was picked and leaves. Two keys —
    /// one to start and one to close — meant the reader who pressed Start was left standing in a
    /// mode with nothing more to do in it (owner, 2026-09-13).
    private var doneLabel: String {
        selection.isEmpty ? "Done" : "Render \(selection.count) \(selection.count == 1 ? "chapter" : "chapters")"
    }

    /// This book's jobs, in the order they were asked for. The queue is the whole app's, so another
    /// book's chapters are in it too and are none of this sheet's business.
    ///
    /// The order is not decoration: it is what "the chapter being made" means. The queue drains
    /// from its head, so the first of these that is running — or, while it is held, the first still
    /// waiting — is the one the progress box speaks for.
    private var jobsHere: [ChapterRenderJob] {
        env.chapterRenderer.queue.filter { $0.documentID == live.id }
    }

    /// The same jobs by chapter, for the row that has to ask "what is happening to me".
    private var jobs: [Int: ChapterRenderJob] {
        var out: [Int: ChapterRenderJob] = [:]
        for job in jobsHere { out[job.chapterIndex] = job }
        return out
    }

    private var renderMarks: [Int: ChapterRenderMark] {
        guard isRendering else { return [:] }
        let jobs = self.jobs
        return Dictionary(uniqueKeysWithValues: chapters.map { chapter in
            (chapter.index, ChapterRenderMark.mark(status: audio.chapter(chapter.index),
                                                   job: jobs[chapter.index],
                                                   isSelected: selection.contains(chapter.index)))
        })
    }

    /// A chapter already waiting or under way is not picked again — re-queueing one is ignored, and
    /// a check beside a running row would promise a second render that never comes.
    private func toggle(_ chapter: Int) {
        switch jobs[chapter]?.state {
        case .queued, .running: return
        default: break
        }
        withAnimation(.snappy) {
            if selection.contains(chapter) { selection.remove(chapter) } else { selection.insert(chapter) }
        }
    }

    /// Every chapter the device does not already hold and the queue is not already making. The
    /// denominator for "Render all", and the reason that control disappears once there is nothing
    /// left for it to do.
    private var renderableChapters: [Int] {
        chapters.map(\.index).filter { index in
            if audio.chapter(index)?.isFullyRendered == true { return false }
            switch jobs[index]?.state {
            case .queued, .running: return false
            default: return true
            }
        }
    }

    /// The whole book, chapter by chapter, in one press (owner, 2026-09-14). It goes to the same
    /// queue as a hand-picked batch and drains the same way — one at a time, pausable, and stoppable
    /// a chapter at a time — so the only thing this saves is the picking.
    ///
    /// It leaves render mode on the way out, like Done: the progress box outside is where a batch
    /// this size is actually watched, and it carries the Stop.
    private func renderAll(scrollingWith proxy: ScrollViewProxy) {
        commit(renderableChapters, scrollingWith: proxy)
    }

    private func enterRendering() {
        withAnimation(.snappy) { isRendering = true }
    }

    /// Puts every tick back down without leaving the mode. Undoing a selection a row at a time is
    /// the one thing render mode made the reader do by hand (owner, 2026-09-14), and the further
    /// down a long book they had got, the more taps it cost to change their mind.
    private func clearSelection() {
        withAnimation(.snappy) { selection.removeAll() }
    }

    /// Leaves render mode, handing whatever was picked to the app's one queue on the way out.
    ///
    /// The two are one action because they are one intention: you came in here to choose chapters,
    /// and the moment you have chosen them there is nothing else to do in the mode. The rows read
    /// their state back off the queue from here on, the progress block outside takes over, and
    /// nothing is stopped by leaving — the queue is the app's and outlives this sheet.
    private func endRendering(startingPicked: Bool = false, scrollingWith proxy: ScrollViewProxy? = nil) {
        commit(startingPicked ? selection.sorted() : [], scrollingWith: proxy)
    }

    /// Leaves render mode, hands what was picked to the app's one queue, and puts the reader in
    /// front of the thing they just started.
    ///
    /// That last part is the whole point (owner, 2026-09-14). Done used to drop you back on the
    /// chapter list wherever you happened to be scrolled, which looks exactly like nothing having
    /// happened — the progress block was up the page, out of sight. The queue is asked first and
    /// the scroll follows its answer, because the block does not exist until there is a job for it
    /// to describe.
    ///
    /// Asking the queue is not enough on its own, which is why the scroll waits a beat afterwards
    /// (owner, 2026-09-14: "press done, the sheet does not go to rendering box … sometimes it
    /// does"). `enqueue` returning means the queue holds the job, not that this sheet has been
    /// drawn again with the block in it — and a `scrollTo` for an anchor SwiftUI has not laid out
    /// yet is not deferred, it is dropped. The wait is what made it a coin toss: a sheet that
    /// already had a block on screen scrolled, and a sheet that was about to grow one did nothing.
    private func commit(_ picked: [Int], scrollingWith proxy: ScrollViewProxy?) {
        asking = nil
        withAnimation(.snappy) {
            isRendering = false
            selection.removeAll()
        }
        guard !picked.isEmpty else { return }
        Task {
            await env.chapterRenderer.enqueue(documentID: live.id, chapters: picked)
            guard let proxy, runningHere != nil else { return }
            // Two frames at 60 Hz, and the bar's own exit is under way in them, so the list has
            // settled at its new length before the scroll starts rather than during it.
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.45)) {
                proxy.scrollTo(Self.progressAnchor, anchor: .center)
            }
        }
    }

    private func evict(chapter: Int) {
        Task {
            try? await env.library.evictAudio(for: live.id, chapter: chapter)
            await refreshAudio()
        }
    }

    /// The whole-document form the rest of the app already uses, unchanged.
    private func evictAll() {
        Task {
            try? await env.library.evictAudio(for: live.id)
            await refreshAudio()
        }
    }

    private var playPill: some View {
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
                dismiss()
                readerRoute.open(live)                                       // the Reader loads and plays a non-current book itself
            }
        }
        .disabled(isStarting)
        .accessibilityHint(isPlayingHere ? "Pauses" : "Plays and opens the reader")
    }

    /// Positions are saved by the coordinator straight to the store, so the library model is
    /// refreshed here before the chapters are rebuilt.
    private func reload() async {
        await env.libraryModel.refresh()
        await loadChapters()
        await bookmarkModel().load(live)
    }

    /// The sheet's one bookmark model, made on first ask: a chapter row's bookmarks can be tapped
    /// before `reload` has run.
    @discardableResult
    private func bookmarkModel() -> BookmarkListModel {
        if let bookmarks { return bookmarks }
        let made = BookmarkListModel(library: env.library, player: env.player)
        bookmarks = made
        return made
    }

    private func loadChapters() async {
        guard let timeline = try? await env.library.timelineForPlayback(live.id) else {
            chapters = []
            audio = BookAudioStatus()
            return
        }
        let progress = DocumentProgress.compute(summary: live, timeline: timeline)
        chapters = ChapterEntry.entries(timeline: timeline, timeIndex: TimeIndex(timeline), elapsed: progress.elapsedSeconds)
        audio = await BookAudioStatus.read(timeline: timeline, audioStore: env.audioStore)
    }

    /// What the store holds for this book, asked again after anything that can have changed it: a
    /// job finishing, a chapter evicted. `currentTimeline` rather than `timelineForPlayback` — the
    /// sheet's own open has already re-derived a stale book, and a refresh must never pay for one.
    private func refreshAudio() async {
        guard let timeline = try? await env.library.currentTimeline(live.id) else { return }
        audio = await BookAudioStatus.read(timeline: timeline, audioStore: env.audioStore)
    }
}
