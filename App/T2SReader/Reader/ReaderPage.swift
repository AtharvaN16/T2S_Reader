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
    @State private var bookmarkSaved = false

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
        .onDisappear {
            Task { await env.player.persistRenderedChapters() }
        }
        .sheet(isPresented: $showChapters) { ChapterList() }
        .sheet(isPresented: $showAppearance) { AppearanceSheet() }
        .sheet(isPresented: $showSpeed) { SpeedPicker() }
        .onChange(of: env.player.coordinator.playhead) { _, _ in bookmarkSaved = false }
    }

    private var topBar: some View {
        HStack {
            icon("chevron.left", "Back") { dismiss() }
            Spacer()
            Button { showChapters = true } label: {
                Text(env.readerModel.chapterTitle)
                    .typeRole(.rowTitle)
                    .lineLimit(1)
                    .foregroundStyle(Tokens.ink)
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button {
                    Task { bookmarkSaved = await env.player.addBookmark() }
                } label: {
                    Label(bookmarkSaved ? "Bookmarked" : "Bookmark", systemImage: bookmarkSaved ? "bookmark.fill" : "bookmark")
                }
                Button { showAppearance = true } label: {
                    Label("Appearance", systemImage: "textformat.size")
                }
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
        .background(Tokens.ground.opacity(0.94))
    }

    private var bottomBar: some View {
        let player = env.player
        return VStack(spacing: 10) {
            TickScrubber(model: player.scrubber) { fraction in
                Task { await player.seek(fraction: fraction) }
            }
            if player.isCatchingUp {
                Text("catching up…").typeRole(.meta).foregroundStyle(Tokens.ink2)
            }
            ReaderControls { showSpeed = true }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, 16)
        .padding(.bottom, Spacing.grid)
        .background(
            LinearGradient(
                colors: [Tokens.ground.opacity(0), Tokens.ground, Tokens.ground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
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
}
