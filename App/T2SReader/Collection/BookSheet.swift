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

    private static let heroHeight: CGFloat = 200

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
                    if isRendering { renderBanner }
                    ChapterListView(chapters: chapters, current: resumeIndex, heading: .groupTitle,
                                    pulsing: pulsingChapter,
                                    // Render mode is about what is on the device, so the rows are
                                    // about that alone: the bookmark pills stand down until it ends.
                                    bookmarks: isCurrent && !isRendering ? env.player.bookmarksByChapter : [:],
                                    renderMarks: renderMarks,
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
            .safeAreaInset(edge: .bottom) {
                // The bar is up for as long as render mode is, and it is the way out of it: with
                // nothing picked it reads "Done". It used to appear only once something was picked
                // — an inert bar at the foot of a list of ready chapters is a permanent invitation
                // to nothing — but that left the reader who had just pressed Start with the bar
                // gone, the rows still wearing their marks, and no exit but a `Done` buried in the
                // `⋯` (owner, 2026-09-13: "there is no way to exit the render mode"). "Done" is not
                // an invitation to nothing; it is the answer to the question the mode is asking.
                if isRendering {
                    BarButton(label: selection.isEmpty ? "Done" : "Start rendering (\(selection.count))") {
                        if selection.isEmpty { endRendering() } else { startRendering() }
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
            // In and out by the same door: render mode was entered from here, so it is left from
            // here too, rather than by closing the sheet on the reader who only wanted a look.
            Button {
                if isRendering { endRendering() } else { withAnimation(.snappy) { isRendering = true } }
            } label: {
                Label(isRendering ? "Done" : "Render chapters",
                      systemImage: isRendering ? "checkmark" : "waveform")
            }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        } label: {
            CircleGlyph(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    /// What sits above the chapter list in render mode: this book's own total — not the whole
    /// cache, which Settings → Storage keeps — with the one control that undoes it. Why a held
    /// queue has stopped was here too until 2026-09-13; it is `RenderHoldSheet` now, app-wide and
    /// up from the foot, because at the top of this sheet nobody ever saw it.
    private var renderBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(audio.summary).typeRole(.meta).foregroundStyle(Tokens.ink2)
            Spacer(minLength: 8)
            if audio.hasAudio {
                Pill(label: "Evict all", glyph: "trash", style: .destructiveSoft, action: evictAll)
            }
        }
    }

    /// This book's jobs, by chapter. The queue is the whole app's, so another book's chapters are
    /// in it too and are none of this sheet's business.
    private var jobs: [Int: ChapterRenderJob] {
        var out: [Int: ChapterRenderJob] = [:]
        for job in env.chapterRenderer.queue where job.documentID == live.id { out[job.chapterIndex] = job }
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

    /// Hands the picked chapters to the app's one queue and lets go of them: the rows read their
    /// state back off the queue from here on, and the sheet can close without stopping anything.
    private func startRendering() {
        let picked = selection.sorted()
        withAnimation(.snappy) { selection.removeAll() }
        Task { await env.chapterRenderer.enqueue(documentID: live.id, chapters: picked) }
    }

    /// Leaves render mode: the marks come off the rows, the bookmarks come back, and the bar goes.
    /// Nothing is stopped by it — the queue is the app's and outlives this sheet — so a reader who
    /// has started four chapters can close the mode and watch them arrive on the rows underneath.
    private func endRendering() {
        withAnimation(.snappy) {
            isRendering = false
            selection.removeAll()
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
