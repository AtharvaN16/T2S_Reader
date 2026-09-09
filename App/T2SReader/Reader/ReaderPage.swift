import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// Full-screen read-along page. The text view and audio player share the same ReaderModel, so
/// closing the page never stops playback.
struct ReaderPage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var summary: DocumentSummary

    @State private var text: ReaderText?
    @State private var error: String?
    @State private var chromeVisible = true
    @State private var showChapters = RootPage.launchOpen == "chapters"      // screenshots, see `RootPage.launchOpen`
    @State private var showAppearance = false
    @State private var showSpeed = false
    @State private var showBookmarks = false
    @State private var showSleepTimer = false
    @State private var showVoiceChange = false
    @State private var showDetails = false
    @State private var voiceName = "Voice"
    /// Where the book proper starts, for the "Skip to Chapter 1" pill; nil when there is no front
    /// matter to skip. Read once per document in `open`.
    @State private var bodyStart: (index: Int, number: Int)?

    var body: some View {
        let reader = env.readerModel
        ZStack {
            Tokens.ground.ignoresSafeArea()
            if let text {
                ReaderTextView(
                    text: text,
                    textScale: env.preferences.textScale,
                    lineHeight: env.preferences.lineHeight,
                    highlight: reader.activeHighlight,
                    highlightTheme: env.preferences.highlightTheme,
                    isFollowing: reader.isFollowing,
                    onTap: handleTap,
                    onUserScroll: { reader.suspendFollowing() }
                )
                .ignoresSafeArea(edges: .bottom)
            } else if let error {
                Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive).padding(Spacing.margin)
            } else if env.kokoroStatus.status.isWarming {
                VStack(spacing: 10) {
                    WarmingDot()
                    Text("Preparing the voice…").typeRole(.meta).foregroundStyle(Tokens.accent)
                }
            } else {
                ProgressView().tint(Tokens.ink)
            }

            VStack(spacing: 0) {
                topBar.opacity(chromeVisible ? 1 : 0)
                Spacer()
                if !reader.isFollowing {
                    // Above the bottom block's fade in both senses: 32 pt up from it, and drawn
                    // over the fade the block hangs above itself (a later sibling would otherwise
                    // paint that fade across the pill).
                    Pill(label: "Back to current", glyph: "text.line.first.and.arrowtriangle.forward", style: .selected) {
                        reader.resumeFollowing()
                    }
                    .padding(.bottom, 32)
                    .zIndex(1)
                } else if let skip = skipTarget, chromeVisible {
                    // The same pill while the playhead is still in the front matter (owner's ask,
                    // 2026-09-09): one tap past the title page, dedication and reviews to the
                    // first numbered chapter. Goes with the chrome, so a tap on the text dismisses it.
                    Pill(label: "Skip to Chapter \(skip.number)", glyph: "forward.end.fill", style: .selected) {
                        Task { await env.player.seek(toChapter: skip.index) }
                    }
                    .padding(.bottom, 32)
                    .zIndex(1)
                    .accessibilityHint("Skips the front matter")
                }
                bottomBar.opacity(chromeVisible ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        }
        .task(id: summary.id) { await open() }
        .appTheme()
        .task(id: summary.id) { await resolveVoiceName() }
        .onChange(of: showVoiceChange) { _, shown in
            if !shown { Task { await resolveVoiceName() } }
        }
        .onDisappear {
            Task { await env.player.persistRenderedChapters() }
        }
        .sheet(isPresented: $showChapters) { ChapterList() }
        .sheet(isPresented: $showAppearance) { AppearanceSheet() }
        .sheet(isPresented: $showSpeed) { SpeedPicker() }
        .sheet(isPresented: $showBookmarks) {
            if let current = env.player.current { BookmarksSheet(summary: current) }
        }
        .sheet(isPresented: $showSleepTimer) { SleepTimerSheet() }
        .sheet(isPresented: $showVoiceChange) {
            if let current = env.player.current { VoiceChangeSheet(summary: current) }
        }
        .sheet(isPresented: $showDetails) {
            if let current = env.player.current { DetailsSheet(summary: current) }
        }
    }

    /// The first numbered chapter, while the playhead is before it.
    private var skipTarget: (index: Int, number: Int)? {
        guard let bodyStart, let index = env.player.chapterIndex, index < bodyStart.index else { return nil }
        return bodyStart
    }

    /// Back on the left, the overflow on the right, the document's title between them (owner's
    /// ask, 2026-09-09; the bookmark moved down to the tool row). The circles sit on solid `ground`
    /// that eases to clear from their band down through 48 pt below the bar, so the header itself
    /// visibly fades into the text (the first cut faded within the bar alone and read as no fade
    /// at all).
    private var topBar: some View {
        ZStack {
            Text(summary.document.title)
                .typeRole(.pill)
                .foregroundStyle(Tokens.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 60)                                  // clear of one circle each side
                .accessibilityAddTraits(.isHeader)
            HStack {
                icon("chevron.left", "Back") { dismiss() }
                Spacer()
                Menu {
                    Button { showChapters = true } label: { Label("Chapters", systemImage: "list.bullet") }
                    Button { showBookmarks = true } label: { Label("Bookmarks", systemImage: "bookmark.circle") }
                    Button { showAppearance = true } label: { Label("Appearance", systemImage: "textformat.size") }
                    Button { showVoiceChange = true } label: { Label("Change voice", systemImage: "person.wave.2") }
                    Button { showSleepTimer = true } label: { Label("Sleep timer", systemImage: "moon.zzz") }
                    Button { showDetails = true } label: { Label("Details", systemImage: "info.circle") }
                    Button { env.player.renderWholeDocument() } label: { Label("Render whole document", systemImage: "waveform") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.ink)
                        .frame(width: 36, height: 36)
                        .background(Tokens.surface, in: Circle())
                }
            }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, 2 * Spacing.grid)
        .padding(.bottom, 2 * Spacing.grid)                                  // a taller band, at the owner's ask
        .background(alignment: .top) {
            Self.groundFade(solidAtTop: true, span: 0.5)
                .padding(.bottom, -48)                                     // hangs below the bar, over the text
                .ignoresSafeArea(edges: .top)
        }
    }

    /// `ground` easing between solid and clear with zero slope at both ends, so neither edge of a
    /// fade reads as a line across the text (the Home bar's lesson). `solidAtTop`: solid from the
    /// top, easing to clear over the bottom `span` of the height. Otherwise clear at the top, easing
    /// to solid over the top `span`, then solid to the bottom.
    private static func groundFade(solidAtTop: Bool, span: Double = 1) -> LinearGradient {
        let steps = 12
        var stops: [Gradient.Stop] = []
        if solidAtTop, span < 1 { stops.append(.init(color: Tokens.ground, location: 0)) }
        stops += (0...steps).map { i -> Gradient.Stop in
            let t = Double(i) / Double(steps)
            let s = t * t * (3 - 2 * t)
            return .init(color: Tokens.ground.opacity(solidAtTop ? 1 - s : s),
                         location: solidAtTop ? (1 - span) + t * span : t * span)
        }
        if !solidAtTop, span < 1 { stops.append(.init(color: Tokens.ground, location: 1)) }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    /// Chapter row, progress bar + times, transport row, tool row (spec §2.4.5, after ElevenReader).
    /// The `ground` fade starts 64 pt above the block and is solid by the chapter row's foot, so the
    /// chapter picker sits on ground too (the owner's second cut) and the text fades out above it.
    private var bottomBar: some View {
        let player = env.player
        return VStack(spacing: 10) {
            chapterRow
            VStack(spacing: 2) {
                ThinScrubber(model: player.scrubber, segments: chapterSegments) { fraction in
                    Task { await player.seek(fraction: fraction) }
                }
                // Elapsed on the left, time left on the right (Apple Music's "-1:02:33"), in the
                // app's own face with tabular digits rather than the system monospace.
                HStack {
                    Text(player.elapsedText).monospacedDigit()
                    Spacer()
                    if env.isWarmingUp {
                        Text("preparing the voice…").foregroundStyle(Tokens.accent)
                    } else if player.isCatchingUp {
                        Text("catching up…")
                    }
                    Spacer()
                    Text("-" + DurationFormatter.clock(max(0, player.total - player.elapsed))).monospacedDigit()
                }
                .typeRole(.meta).foregroundStyle(Tokens.ink2)
                if let error = player.renderError {
                    Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ReaderControls(onSleepTimer: { showSleepTimer = true }, onSpeed: { showSpeed = true })
            toolRow
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, 12)
        .padding(.bottom, Spacing.grid)
        .background(alignment: .bottom) {
            Self.groundFade(solidAtTop: false, span: 0.25)
                .padding(.top, -64)                                        // hangs above the block, over the text
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// The chapters as spans of the whole, for the scrubber's segments; empty for a document whose
    /// duration is not known yet, which draws one bar.
    private var chapterSegments: [Range<Double>] {
        let player = env.player
        let total = player.total
        guard total > 0 else { return [] }
        return player.chapters.map { chapter in
            let start = min(1, max(0, chapter.startSeconds / total))
            return start..<min(1, max(start, (chapter.startSeconds + chapter.durationSeconds) / total))
        }
    }

    /// "Chapter title ▾" on the left opens the chapter list (after the reference the owner sent,
    /// 2026-09-09). Hidden for a document with one chapter or none — an article has nothing to pick.
    @ViewBuilder private var chapterRow: some View {
        let player = env.player
        let chapters = player.chapters
        if chapters.count > 1, let index = player.chapterIndex, chapters.indices.contains(index) {
            HStack {
                Button { showChapters = true } label: {
                    // The arrow stands 8 pt off the title, centred on its height, in `ink` like
                    // the title (owner's third cut, 2026-09-09).
                    HStack(alignment: .center, spacing: 8) {
                        Text(ChapterLabel.text(for: chapters[index].title, ordinal: index + 1))
                            .typeRole(.rowTitle)
                            .lineLimit(1)
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Tokens.ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chapter")
                .accessibilityValue(chapters[index].title)
                .accessibilityHint("Opens the chapter list")
                Spacer(minLength: 12)
            }
            .frame(height: 36)
        }
    }

    /// Appearance (left) · voice chip (centred) · bookmark (right). The chip shows the voice
    /// actually routed for this document, resolved once per document in `resolveVoiceName`. The
    /// bookmark took the contents circle's place (owner's ask, 2026-09-09; the chapter row above
    /// already opens the list): filled while the sentence under the playhead is bookmarked, and a
    /// tap then removes that bookmark rather than adding a second.
    private var toolRow: some View {
        let bookmarked = env.player.isBookmarkedAtPlayhead
        return ZStack {
            HStack {
                icon("textformat.size", "Appearance") { showAppearance = true }
                Spacer()
                icon(bookmarked ? "bookmark.fill" : "bookmark", bookmarked ? "Bookmarked" : "Bookmark") {
                    Task { await env.player.toggleBookmark() }
                }
                .accessibilityHint(bookmarked ? "Removes the bookmark" : "Saves this place and its sentence")
            }
            Button { showVoiceChange = true } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Tokens.ink3)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text(voiceName.prefix(1).uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Tokens.ink)
                        )
                    Text(voiceName).typeRole(.pill)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(Tokens.ink)
                .background(Tokens.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change voice")
            .accessibilityValue(voiceName)
        }
        .frame(height: 44)
    }

    private func icon(_ glyph: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tokens.ink)
                .frame(width: 36, height: 36)
                .background(Tokens.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func handleTap(_ tap: ReaderTextView.Tap) {
        Task {
            if case .word(let index, let offset) = tap, await env.readerModel.seek(toUtterance: index, sourceOffset: offset) {
                return
            }
            withAnimation { chromeVisible.toggle() }
        }
    }

    /// Loads and starts the requested document when necessary, then draws its timeline's text
    /// (spec 2026-09-07 §5). The model is built off the main actor; a 24-hour book is about a
    /// million characters.
    private func open() async {
        // A page reopened on another document starts blank rather than showing the last one's text.
        text = nil
        error = nil
        if env.player.current?.id != summary.id {
            await env.player.load(summary, play: true)
        }
        guard let timeline = env.player.coordinator.timeline, timeline.utteranceCount > 0 else {
            error = env.player.renderError ?? "This document has no readable text."
            return
        }
        bodyStart = ChapterLabel.bodyStart(titles: timeline.chapters.map(\.title))
        let document = summary.document
        let model = await Task.detached(priority: .userInitiated) {
            ReaderText(documentID: document.id, timeline: timeline, title: document.title, author: document.author)
        }.value
        // The page was dismissed, or moved to another document, while the model was building.
        guard !Task.isCancelled else { return }
        text = model
    }

    /// The voice chip's name: not necessarily the document's stored voice, but the one actually
    /// routed for playback on this device (spec §6), resolved once per document.
    private func resolveVoiceName() async {
        let requested = summary.document.voiceID ?? env.preferences.defaultVoiceID ?? VoiceOption.systemDefault.id
        let id = await env.voiceRouting.effectiveVoiceID(requested)
        voiceName = env.voices.voices().first { $0.id == id }?.name ?? "Voice"
    }
}
