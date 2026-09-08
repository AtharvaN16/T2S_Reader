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
                    isFollowing: reader.isFollowing,
                    onTap: handleTap,
                    onUserScroll: { reader.suspendFollowing() }
                )
                .ignoresSafeArea(edges: .bottom)
            } else if let error {
                Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive).padding(Spacing.margin)
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

    /// Two floating circles over a short `ground` fade (spec §2.4.5, after ElevenReader): no bar,
    /// no chapter title — the title moved to the tool row's Contents button below.
    private var topBar: some View {
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
        .padding(.horizontal, Spacing.margin)
        .padding(.top, Spacing.grid)
        .background(alignment: .top) {
            // Opaque through the circles' own band, then a fade the text scrolls under.
            LinearGradient(stops: [.init(color: Tokens.ground, location: 0),
                                   .init(color: Tokens.ground, location: 0.62),
                                   .init(color: Tokens.ground.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .ignoresSafeArea(edges: .top)
        }
    }

    /// Progress bar + times, transport row, tool row — pinned over the existing `ground` fade
    /// (spec §2.4.5, after ElevenReader).
    private var bottomBar: some View {
        let player = env.player
        return VStack(spacing: 10) {
            VStack(spacing: 6) {
                ThinScrubber(model: player.scrubber) { fraction in
                    Task { await player.seek(fraction: fraction) }
                }
                HStack {
                    Text(player.elapsedText)
                    Spacer()
                    if player.isCatchingUp { Text("catching up…").typeRole(.meta) }
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
        .padding(.top, 40)
        .padding(.bottom, Spacing.grid)
        .background(
            // Opaque behind every control; the fade lives in the 40 pt of top padding above them.
            LinearGradient(
                stops: [.init(color: Tokens.ground.opacity(0), location: 0),
                        .init(color: Tokens.ground, location: 0.16),
                        .init(color: Tokens.ground, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
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
