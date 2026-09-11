// App/T2SReader/Collection/BookSheet.swift
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// Spec §2.4.5 book sheet, after the owner's 2026-09-09 cut: the book alone at the top, lit from
/// behind in its own colour and tilting with the phone, the title and author centred under it,
/// one Play pill in the Home row's form, then the chapters and the bookmarks. Chapters come from
/// the timeline (re-derived if stale) and their progress from the persisted position through
/// `DocumentProgress`. Nothing about a queue: playing is what puts a book on Home.
struct BookSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerRoute) private var readerRoute
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var summary: DocumentSummary

    @State private var chapters: [ChapterEntry] = []
    @State private var bookmarks: BookmarkListModel?
    /// True only while the Play pill's own tap is resuming a paused, already-current document —
    /// the one branch that awaits playback before dismissing, otherwise silently.
    @State private var isStarting = false
    /// The phone's lean for the hero. The sheet owns it: the gyro runs only while the sheet shows.
    @State private var motion = MotionTilt()

    private static let heroHeight: CGFloat = 200

    private var live: DocumentSummary { env.libraryModel.summaries.first { $0.id == summary.id } ?? summary }
    private var isCurrent: Bool { env.player.current?.id == live.id }
    private var isPlayingHere: Bool { isCurrent && env.player.isPlaying }
    /// The chapter the book would resume in: the first not yet heard through.
    private var resumeIndex: Int? { chapters.first { $0.fraction < 1 }?.index ?? chapters.last?.index }

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
                playPill
                    .frame(maxWidth: .infinity)
                ChapterListView(chapters: chapters, current: resumeIndex, heading: .sectionHeader) { chapter in
                    Task {
                        if !isCurrent { await env.player.load(live, play: false) }
                        await env.player.seek(toChapter: chapter.index)
                        if !env.player.isPlaying { await env.player.togglePlay() }
                        dismiss()
                        readerRoute.open(live)
                    }
                }
                .padding(.horizontal, -12)                                 // the rows' fill runs into the margin, as in the Reader
                if let bookmarks, !bookmarks.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Bookmarks").typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
                        ForEach(bookmarks.entries) { entry in
                            BookmarkRow(entry: entry, onJump: {
                                Task {
                                    await bookmarks.jump(to: entry, in: live)
                                    dismiss()
                                    readerRoute.open(live)
                                }
                            }, onDelete: { Task { await bookmarks.delete(entry) } })
                        }
                    }
                }
                Color.clear.frame(height: Spacing.section)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.raised)
        .presentationCornerRadius(Spacing.sheetCorner)
        .task { await reload() }
        .onChange(of: shouldTilt, initial: true) { _, on in motion.setEnabled(on) }
        .onDisappear { motion.setEnabled(false) }
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

    /// The Home row's Play pill, centred: Pause while this book plays, "Play  17m" otherwise.
    private var playPill: some View {
        Pill(label: isPlayingHere ? "Pause" : (isStarting ? "Starting…" : "Play"),
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
        let bookmarks = self.bookmarks ?? BookmarkListModel(library: env.library, player: env.player)
        self.bookmarks = bookmarks
        await bookmarks.load(live)
    }

    private func loadChapters() async {
        guard let timeline = try? await env.library.timelineForPlayback(live.id) else { chapters = []; return }
        let progress = DocumentProgress.compute(summary: live, timeline: timeline)
        chapters = ChapterEntry.entries(timeline: timeline, timeIndex: TimeIndex(timeline), elapsed: progress.elapsedSeconds)
    }
}
