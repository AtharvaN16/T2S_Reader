// App/T2SReader/Root/RootPager.swift
import SwiftUI
import T2SStore
import UIKit

enum RootPage: Hashable, CaseIterable {
    case collection, queue, preferences

    var glyph: String {
        switch self {
        case .collection: return "books.vertical"
        case .queue: return "list.bullet"
        case .preferences: return "gearshape"
        }
    }

    var title: String {
        switch self {
        case .collection: return "Collection"
        case .queue: return "Queue"
        case .preferences: return "Preferences"
        }
    }
}

/// Every Reader entry point goes through this closure (spec §2.4.5 lists Queue, book chapters,
/// PlayerSheet, and imports). It keeps page presentation owned by the root rather than duplicated
/// in each source view.
struct ReaderRoute: Sendable {
    var open: @MainActor @Sendable (DocumentSummary) -> Void
}

private struct ReaderRouteKey: EnvironmentKey {
    static let defaultValue = ReaderRoute(open: { _ in })
}

extension EnvironmentValues {
    var readerRoute: ReaderRoute {
        get { self[ReaderRouteKey.self] }
        set { self[ReaderRouteKey.self] = newValue }
    }
}

/// Spec §2.4.4: no tab bar; a three-page pager opening on Queue, a tappable three-glyph indicator,
/// and the floating mini-player above it on every page.
struct RootPager: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var page: RootPage = .queue
    @State private var showPlayer = false
    /// A file handed to us by another app (`onOpenURL`), shown through the Add sheet like any other
    /// import rather than imported invisibly.
    @State private var openedFiles: [URL]?
    /// Set by that sheet; opened once it has actually gone.
    @State private var pendingOpen: DocumentSummary?
    @State private var readerDocument: DocumentSummary?

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                CollectionPage().tag(RootPage.collection)
                QueuePage().tag(RootPage.queue)
                PreferencesPage().tag(RootPage.preferences)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
            .environment(\.readerRoute, ReaderRoute(open: { readerDocument = $0 }))

            VStack(spacing: 12) {
                if !env.libraryModel.isQueueEmpty || env.player.current != nil {
                    MiniPlayer { showPlayer = true }
                }
                PageIndicator(page: $page)
            }
            .padding(.bottom, Spacing.grid)
        }
        .background(Tokens.ground.ignoresSafeArea())
        .sheet(isPresented: $showPlayer) {
            PlayerSheet()
                .presentationCornerRadius(Spacing.sheetCorner)
                .presentationBackground(Tokens.raised)
        }
        .onOpenURL { url in openedFiles = [url] }
        .sheet(isPresented: Binding(get: { openedFiles != nil }, set: { if !$0 { openedFiles = nil } }),
               onDismiss: openPending) {
            AddSheet(imported: $pendingOpen, initialFiles: openedFiles ?? [])
        }
        .fullScreenCover(item: $readerDocument) { ReaderPage(summary: $0) }
        .playbackTicking(env.player, sleepTimer: env.sleepTimer, continuation: env.continuation, nowPlaying: env.nowPlaying)
        .task { await env.libraryModel.refresh() }
        .onChange(of: env.deviceMonitor.deviceState, initial: true) { _, state in env.coordinator.device = state }
        .onChange(of: env.libraryModel.queue.map(\.id), initial: true) { _, ids in
            env.coordinator.queue = ids
        }
        .onChange(of: env.libraryModel.summaries.map(\.id)) { _, ids in
            if let current = env.player.current, !ids.contains(current.id) { env.nowPlaying.clear() }
        }
        .onChange(of: env.preferences.defaultVoiceID) { _, voiceID in
            env.player.defaultVoiceID = voiceID
        }
        .onChange(of: env.preferences.defaultRate) { _, rate in
            env.player.setRate(rate)
        }
        .onChange(of: env.player.current?.id, initial: true) { _, _ in env.nowPlaying.update() }
        .onChange(of: env.player.state) { _, _ in env.nowPlaying.update() }
        .onChange(of: env.player.elapsed) { _, _ in env.nowPlaying.update() }
        .onChange(of: env.player.chapterIndex) { _, _ in env.nowPlaying.update() }
        .onChange(of: env.coordinator.rate) { _, _ in env.nowPlaying.update() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { persistUnderBackgroundTask() }
        }
    }

    private func openPending() {
        guard let doc = pendingOpen else { return }
        pendingOpen = nil
        readerDocument = doc
    }

    /// iOS can suspend the app as soon as the scene-phase handler returns, which would abandon the
    /// chapter write mid-flight; a background task buys the time to finish it.
    private func persistUnderBackgroundTask() {
        var id = UIBackgroundTaskIdentifier.invalid
        id = UIApplication.shared.beginBackgroundTask(withName: "persist-chapters") {
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
        Task {
            await env.player.persistRenderedChapters()
            if id != .invalid { UIApplication.shared.endBackgroundTask(id); id = .invalid }
        }
    }
}
