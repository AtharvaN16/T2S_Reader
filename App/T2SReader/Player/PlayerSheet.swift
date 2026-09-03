// App/T2SReader/Player/PlayerSheet.swift
import SwiftUI
import T2SApp
import T2SStore

struct PlayerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showChapters = false
    @State private var showDetails = false
    @State private var bookmarkSaved = false

    var body: some View {
        let player = env.player
        VStack(alignment: .leading, spacing: Spacing.section) {
            HStack(alignment: .top) {
                Artwork(relativePath: player.current?.document.coverImagePath, paths: env.paths, size: 56, radius: Spacing.artworkSmall)
                Spacer()
                HStack(spacing: 8) {
                    icon(bookmarkSaved ? "bookmark.fill" : "bookmark", "Bookmark") {
                        Task { bookmarkSaved = await player.addBookmark() }
                    }
                    icon("moon.zzz", "Sleep timer (arrives with the Reader)") {}
                        .disabled(true)
                        .opacity(0.4)
                    Menu {
                        Button { player.renderWholeDocument() } label: { Label("Render whole document", systemImage: "waveform") }
                        Button { showDetails = true } label: { Label("Details", systemImage: "info.circle") }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.ink)
                            .frame(width: 36, height: 36).background(Tokens.surface, in: Circle())
                    }
                }
            }
            .padding(.top, Spacing.section)

            VStack(alignment: .leading, spacing: 8) {
                if let current = player.current {
                    HStack(spacing: 6) {
                        Text(sourceName(current))
                        Text("·")
                        Text(DurationFormatter.age(of: current.document.addedAt))
                    }
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    Text(current.document.title).typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                    if let author = current.document.author { Text(author).typeRole(.meta).foregroundStyle(Tokens.ink2) }
                } else {
                    Text("Nothing playing").typeRole(.playerTitle).foregroundStyle(Tokens.ink2)
                }
            }

            if let index = player.chapterIndex, player.chapters.count > 1 {
                Button { showChapters = true } label: {
                    HStack(spacing: 6) {
                        Text("Chapter \(index + 1)").typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(Tokens.ink2)
                    }
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                TickScrubber(model: player.scrubber) { fraction in Task { await player.seek(fraction: fraction) } }
                HStack {
                    Text(player.elapsedText)
                    Spacer()
                    if player.isCatchingUp { Text("catching up…").typeRole(.meta) }
                    Spacer()
                    Text(player.totalText)
                }
                .typeRole(.mono).foregroundStyle(Tokens.ink2)
            }

            ControlPill { showDetails = true }

            if let error = player.renderError {
                Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive).lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .background(Tokens.raised)
        .sheet(isPresented: $showChapters) { ChapterList() }
        .sheet(isPresented: $showDetails) {
            if let current = player.current { DetailsSheet(summary: current) }
        }
        .onChange(of: player.coordinator.playhead) { _, _ in bookmarkSaved = false }
    }

    private func icon(_ glyph: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.ink)
                .frame(width: 36, height: 36).background(Tokens.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func sourceName(_ s: DocumentSummary) -> String {
        switch s.document.sourceType {
        case .epub: return "EPUB"
        case .pdf: return "PDF"
        case .article: return s.document.sourceURL?.host() ?? "Article"
        }
    }
}
