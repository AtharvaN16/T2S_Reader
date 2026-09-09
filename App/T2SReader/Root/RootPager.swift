// App/T2SReader/Root/RootPager.swift
import SwiftUI
import T2SCore
import T2SApp
import T2SStore
import UIKit

enum RootPage: Hashable, CaseIterable {
    case collection, queue, preferences

    var glyph: String {
        switch self {
        case .collection: return "books.vertical"
        case .queue: return "house"
        case .preferences: return "gearshape"
        }
    }

    var title: String {
        switch self {
        case .collection: return "Collection"
        case .queue: return "Home"
        case .preferences: return "Settings"
        }
    }

    /// The page the app opens on: Queue (spec §2.4.4), unless `T2S_PAGE` in the environment names
    /// another — `collection` or `preferences`. A simulator driven by script cannot tap the
    /// indicator, so this is how a screenshot of another page is taken:
    /// `SIMCTL_CHILD_T2S_PAGE=collection xcrun simctl launch <udid> com.t2s.reader`.
    static var launchPage: RootPage {
        switch ProcessInfo.processInfo.environment["T2S_PAGE"] {
        case "collection": return .collection
        case "preferences": return .preferences
        default: return .queue
        }
    }
}

/// Every Reader entry point goes through this closure (spec §2.4.5 lists Queue, book chapters,
/// the mini-player, and imports). It keeps page presentation owned by the root rather than
/// duplicated in each source view.
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
    @State private var page: RootPage = RootPage.launchPage
    /// A file handed to us by another app (`onOpenURL`), shown through the Import page like any other
    /// import rather than imported invisibly.
    @State private var openedFiles: [URL]?
    /// Set by that page; opened once it has actually gone.
    @State private var pendingOpen: DocumentSummary?
    @State private var readerDocument: DocumentSummary?

    var body: some View {
        // The reader is for the safe-area inset: `bottomFill` has to know how far below the page
        // row the screen goes, and a fixed frame plus `ignoresSafeArea` alone cannot tell it.
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                TabView(selection: $page) {
                    CollectionPage().tag(RootPage.collection)
                    QueuePage().tag(RootPage.queue)
                    PreferencesPage().tag(RootPage.preferences)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .bottom)
                .environment(\.readerRoute, ReaderRoute(open: { readerDocument = $0 }))

                bottomFill(inset: geo.safeAreaInsets.bottom)

                VStack(spacing: 12) {
                    if !env.libraryModel.isQueueEmpty || env.player.current != nil {
                        MiniPlayer { readerDocument = $0 }
                    }
                    PageIndicator(page: $page)
                }
                .padding(.bottom, Spacing.grid)
            }
        }
        .background(Tokens.ground.ignoresSafeArea())
        .appTheme()
        .onOpenURL { url in
            if let id = LibraryHandoff.documentID(from: url) {
                Task { @MainActor in await openSharedDocument(id) }
            } else {
                openedFiles = [url]
            }
        }
        .fullScreenCover(isPresented: Binding(get: { openedFiles != nil }, set: { if !$0 { openedFiles = nil } }),
                         onDismiss: openPending) {
            ImportPage(imported: $pendingOpen, initialFiles: openedFiles ?? [])
        }
        .fullScreenCover(item: $readerDocument) { ReaderPage(summary: $0) }
        .playbackTicking(env.player, sleepTimer: env.sleepTimer, continuation: env.continuation, nowPlaying: env.nowPlaying)
        .task { await env.libraryModel.refresh() }
        .onChange(of: env.deviceMonitor.deviceState, initial: true) { _, state in
            updatePrepareDeviceState(state)
        }
        .onChange(of: env.libraryModel.queue.map(\.id), initial: true) { _, ids in
            env.coordinator.queue = ids
            startForegroundPrepareIfNeeded()
        }
        .onChange(of: env.libraryModel.summaries.map(\.id)) { _, ids in
            if let current = env.player.current, !ids.contains(current.id) { env.nowPlaying.clear() }
        }
        .onChange(of: env.preferences.defaultVoiceID) { _, voiceID in
            env.player.defaultVoiceID = voiceID
            env.prepareRunner.defaultVoiceID = voiceID
        }
        .onChange(of: env.preferences.defaultRate) { _, rate in
            env.player.setRate(rate)
        }
        .onChange(of: env.player.current?.id, initial: true) { _, _ in env.nowPlaying.update() }
        .onChange(of: env.player.state) { _, _ in env.nowPlaying.update() }
        .onChange(of: env.player.elapsed) { _, _ in env.nowPlaying.update() }
        .onChange(of: env.player.chapterIndex) { _, _ in env.nowPlaying.update() }
        .onChange(of: env.coordinator.rate) { _, _ in env.nowPlaying.update() }
        .onChange(of: env.player.state) { _, state in
            if state == .playing || state == .catchingUp {
                env.prepareRunner.cancel()
            } else {
                startForegroundPrepareIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                PrepareTask.schedule()
                startForegroundPrepareIfNeeded()
                Task { await env.libraryModel.refresh() }
            case .background:
                env.prepareRunner.cancel()
                persistUnderBackgroundTask()
                if env.deviceMonitor.deviceState.charging { PrepareTask.schedule() }
            default:
                break
            }
        }
    }

    private func openPending() {
        guard let doc = pendingOpen else { return }
        pendingOpen = nil
        readerDocument = doc
    }

    /// The fill is fully clear this far above the page row: the mini-player's band (52 + 12) and
    /// well past it, so a page's last row can scroll wholly out from under it (`Spacing.bottomClearance`).
    static let fadeHeight: CGFloat = 180

    /// The bottom bar's ground. Solid from the top of the page row down through the home-indicator
    /// inset — nothing shows through under the glyphs — and a gentle fade above that, through the
    /// mini-player's band, so the page stays visible behind it. Anchored to the screen bottom by
    /// filling the safe-area-ignoring frame and aligning to its foot: a fixed-height view under
    /// `ignoresSafeArea` alone sits at the top of the expanded region and leaves the inset bare,
    /// which is what let a row show through under the page row. Hit testing is off so the pager
    /// underneath still gets its taps.
    private func bottomFill(inset: CGFloat) -> some View {
        let solid = PageIndicator.height + Spacing.grid + inset
        let height = Self.fadeHeight + solid
        let fadeEnd = Self.fadeHeight / height
        // An eased ramp, not a straight one: a linear fade that stops dead at solid has a kink
        // the eye reads as a line across the screen (a Mach band). Smoothstep squared starts and
        // ends with zero slope, and keeps the lower half of the fade light so the page shows.
        let steps = 12
        var stops = (0...steps).map { i -> Gradient.Stop in
            let t = Double(i) / Double(steps)
            let eased = pow(t * t * (3 - 2 * t), 2)
            return .init(color: Tokens.ground.opacity(eased), location: fadeEnd * t)
        }
        stops.append(.init(color: Tokens.ground, location: 1))
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
        .frame(height: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }

    /// A foreground pass is only a convenience while the app is awake and idle. The scheduler's
    /// shared lease means a user starting playback always receives the next render slot.
    private func startForegroundPrepareIfNeeded() {
        let device = env.deviceMonitor.deviceState
        guard device.charging, !device.thermalSerious, !device.lowPowerMode, !device.storeFull,
              !env.player.isPlaying, !env.prepareRunner.isRunning
        else { return }
        Task {
            let result = await env.prepareRunner.run(reason: .foreground, device: device)
            if let recordedAt = result.recordedAt { env.storage.recordPrepareRun(recordedAt) }
            await env.storage.refresh()
            await env.libraryModel.refresh()
        }
    }

    private func updatePrepareDeviceState(_ state: DeviceState) {
        env.coordinator.device = state
        if state.charging && !state.thermalSerious && !state.lowPowerMode && !state.storeFull {
            startForegroundPrepareIfNeeded()
        } else {
            env.prepareRunner.cancel()
        }
    }

    /// The extension's URL contains only a durable ID. The app reads the shared store itself
    /// rather than accepting an arbitrary file URL from another process.
    private func openSharedDocument(_ id: UUID) async {
        await env.libraryModel.refresh()
        if let summary = try? await env.store.summary(id: id) { readerDocument = summary }
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
