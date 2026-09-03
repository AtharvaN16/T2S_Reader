// App/T2SReader/Root/RootPager.swift
import SwiftUI
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

/// Spec §2.4.4: no tab bar; a three-page pager opening on Queue, a tappable three-glyph indicator,
/// and the floating mini-player above it on every page.
struct RootPager: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var page: RootPage = .queue
    @State private var showPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                CollectionPage().tag(RootPage.collection)
                QueuePage().tag(RootPage.queue)
                PreferencesPage().tag(RootPage.preferences)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)

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
        .playbackTicking(env.player)
        .task { await env.libraryModel.refresh() }
        .onChange(of: env.deviceMonitor.deviceState, initial: true) { _, state in env.coordinator.device = state }
        .onChange(of: env.libraryModel.queue.map(\.id), initial: true) { _, ids in env.coordinator.queue = ids }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { persistUnderBackgroundTask() }
        }
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
