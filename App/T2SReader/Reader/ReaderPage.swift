import ReadiumShared
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// Full-screen read-along page. The navigator and audio player share the same ReaderModel, so
/// closing the page never stops playback.
struct ReaderPage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var summary: DocumentSummary

    @State private var publication: Publication?
    @State private var timeline: Timeline?
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
            if let publication, let timeline {
                Group {
                    if summary.document.sourceType == .pdf {
                        PDFReaderView(
                            publication: publication, reader: reader, timeline: timeline,
                            onTap: handleTap,
                            onError: handleReaderError,
                            onTearDown: releasePublication
                        )
                    } else {
                        EPUBReaderView(
                            publication: publication,
                            reader: reader,
                            preferences: env.preferences,
                            timeline: timeline,
                            httpServer: env.publications.httpServer,
                            onTap: handleTap,
                            onError: handleReaderError,
                            onTearDown: releasePublication
                        )
                    }
                }
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
        .task(id: summary.id) { await resolveVoiceName() }
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

    private func handleTap(_ hit: SourceHit?) {
        Task {
            if let hit, await env.readerModel.seek(to: hit) { return }
            withAnimation { chromeVisible.toggle() }
        }
    }

    /// Readium rejects restricted publications at navigator construction. Keep the failure in the
    /// SwiftUI page instead of allowing an initializer failure to terminate the app.
    private func handleReaderError(_ message: String) {
        releasePublication()
        publication = nil
        timeline = nil
        error = message
    }

    private func releasePublication() {
        env.publications.release(summary.id)
    }

    /// Loads and starts the requested document when necessary, then opens its cached Readium
    /// publication. `Position` remains the only persisted location; Readium locators stay here.
    private func open() async {
        if env.player.current?.id != summary.id {
            await env.player.load(summary, play: true)
        }
        timeline = env.player.coordinator.timeline
        do {
            publication = try await env.publications.publication(
                for: summary.id,
                at: env.paths.sourceURL(summary.id, type: summary.document.sourceType)
            )
        } catch {
            self.error = "This document can't be displayed: \(error)"
        }
    }

    /// The voice chip's name: not necessarily the document's stored voice, but the one actually
    /// routed for playback on this device (spec §6), resolved once per document.
    private func resolveVoiceName() async {
        let requested = summary.document.voiceID ?? env.preferences.defaultVoiceID ?? VoiceOption.systemDefault.id
        let id = await env.voiceRouting.effectiveVoiceID(requested)
        voiceName = env.voices.voices().first { $0.id == id }?.name ?? "Voice"
    }
}
