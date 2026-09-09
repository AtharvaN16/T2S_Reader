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
    @State private var showChapters = false
    @State private var showAppearance = false
    @State private var showSpeed = false
    @State private var showBookmarks = false
    @State private var showSleepTimer = false
    @State private var showVoiceChange = false
    @State private var showDetails = false
    @State private var bookmarkSaved = false
    @State private var voiceName = "Voice"

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
                    Pill(label: "Back to current", glyph: "text.line.first.and.arrowtriangle.forward", style: .selected) {
                        reader.resumeFollowing()
                    }
                    .padding(.bottom, 12)
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
        .onChange(of: env.player.coordinator.playhead) { _, _ in bookmarkSaved = false }
    }

    /// Back on the left, bookmark and the overflow on the right, the document's title between them
    /// (owner's ask, 2026-09-09). The circles float on a `ground` fade that lives inside the
    /// header's own band — solid at the status bar, clear by the circles' foot — rather than a solid
    /// block with a fade hanging below it over the text.
    private var topBar: some View {
        ZStack {
            Text(summary.document.title)
                .typeRole(.pill)
                .foregroundStyle(Tokens.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 92)                                  // clear of one circle left, two right
                .accessibilityAddTraits(.isHeader)
            HStack {
                icon("chevron.left", "Back") { dismiss() }
                Spacer()
                icon(bookmarkSaved ? "bookmark.fill" : "bookmark", bookmarkSaved ? "Bookmarked" : "Bookmark") {
                    Task { bookmarkSaved = await env.player.addBookmark() }
                }
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
        .padding(.top, Spacing.grid)
        .padding(.bottom, Spacing.grid)
        .background {
            Self.groundFade(solidAtTop: true).ignoresSafeArea(edges: .top)
        }
    }

    /// `ground` easing between solid and clear with zero slope at both ends, so neither edge of a
    /// fade reads as a line across the text (the Home bar's lesson). `solidAtTop` runs solid → clear
    /// down the whole height; otherwise clear → solid over the top `span` of it, then solid.
    private static func groundFade(solidAtTop: Bool, span: Double = 1) -> LinearGradient {
        let steps = 12
        var stops = (0...steps).map { i -> Gradient.Stop in
            let t = Double(i) / Double(steps)
            let s = t * t * (3 - 2 * t)
            return .init(color: Tokens.ground.opacity(solidAtTop ? 1 - s : s), location: t * span)
        }
        if span < 1 { stops.append(.init(color: Tokens.ground.opacity(solidAtTop ? 0 : 1), location: 1)) }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    /// Chapter row, progress bar + times, transport row, tool row (spec §2.4.5, after ElevenReader).
    /// The `ground` fade lives inside the block — clear at the chapter row, solid by the transport —
    /// so the text is seen through the top of the controls rather than under a fade above them.
    private var bottomBar: some View {
        let player = env.player
        return VStack(spacing: 10) {
            chapterRow
            VStack(spacing: 6) {
                ThinScrubber(model: player.scrubber) { fraction in
                    Task { await player.seek(fraction: fraction) }
                }
                HStack {
                    Text(player.elapsedText)
                    Spacer()
                    if env.isWarmingUp {
                        Text("preparing the voice…").typeRole(.meta).foregroundStyle(Tokens.accent)
                    } else if player.isCatchingUp {
                        Text("catching up…").typeRole(.meta)
                    }
                    Spacer()
                    Text(player.totalText)
                }
                .typeRole(.mono).foregroundStyle(Tokens.ink2)
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
        .background {
            Self.groundFade(solidAtTop: false, span: 0.5).ignoresSafeArea(edges: .bottom)
        }
    }

    /// "Chapter title ▾" on the left opens the chapter list; "→" on the right jumps to the next
    /// chapter (after the reference the owner sent, 2026-09-09). Hidden for a document with one
    /// chapter or none — an article has nothing to pick.
    @ViewBuilder private var chapterRow: some View {
        let player = env.player
        let chapters = player.chapters
        if chapters.count > 1, let index = player.chapterIndex, chapters.indices.contains(index) {
            HStack {
                Button { showChapters = true } label: {
                    HStack(spacing: 6) {
                        Text(chapters[index].title).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Tokens.ink2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chapter")
                .accessibilityValue(chapters[index].title)
                .accessibilityHint("Opens the chapter list")
                Spacer(minLength: 12)
                if index + 1 < chapters.count {
                    Button {
                        Task { await player.seek(toChapter: index + 1) }
                    } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Tokens.ink)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next chapter")
                }
            }
            .frame(height: 36)
        }
    }

    /// Appearance (left) · voice chip (centred) · contents (right) — spec §2.4.5. The chip shows
    /// the voice actually routed for this document, resolved once per document in `resolveVoiceName`.
    private var toolRow: some View {
        ZStack {
            HStack {
                icon("textformat.size", "Appearance") { showAppearance = true }
                Spacer()
                icon("list.bullet", "Contents") { showChapters = true }
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
