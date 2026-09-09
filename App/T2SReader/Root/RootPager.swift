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
        case .preferences: return "Preferences"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: RootPage = .queue
    /// A file handed to us by another app (`onOpenURL`), shown through the Import page like any other
    /// import rather than imported invisibly.
    @State private var openedFiles: [URL]?
    /// Set by that page; opened once it has actually gone.
    @State private var pendingOpen: DocumentSummary?
    @State private var readerDocument: DocumentSummary?

    /// The owner's rule for the tilting covers: "disable this if under load, when using the local
    /// model". Load is the device already struggling (thermal, Low Power Mode) or the on-device
    /// engine doing work — Kokoro is linked and present, and something is rendering through it:
    /// playback (`isPlaying` covers catching up), a Prepare pass, the launch warm-up, or a voice
    /// preview. Playing a system or cloud voice on a Kokoro build counts too; telling them apart
    /// is not worth the plumbing for a fraction-of-a-degree effect.
    private var isUnderLoad: Bool {
        let device = env.deviceMonitor.deviceState
        if device.thermalSerious || device.lowPowerMode { return true }
        guard isKokoroPresent else { return false }
        return env.player.isPlaying || env.prepareRunner.isRunning
            || env.kokoroStatus.status.isWarming || env.voicePreview.isRendering
    }

    /// Whether this build links the on-device engine and this device has its files — the states
    /// in which Kokoro can be the thing under load.
    private var isKokoroPresent: Bool {
        switch env.kokoroStatus.status {
        case .checking, .preparing, .available: true
        case .notLinked, .unavailable: false
        }
    }

    /// Home is the only page that shows the tilting covers and a full-screen Reader hides them, so
    /// the gyro runs only while they are on screen — and never against Reduce Motion or under load.
    private var shouldTilt: Bool {
        scenePhase == .active && !reduceMotion && page == .queue && readerDocument == nil && !isUnderLoad
    }

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

            /// The bottom bar floats over the pager with nothing behind it, so rows would scroll
            /// straight through the mini-player and indicator. This merges the bar into the page
            /// instead: solid `ground` through the bar's own band (mini-player 52, gap 12,
            /// indicator 32, padding 8, home-indicator inset 34 ≈ 138 pt from the screen bottom,
            /// which ignoring the safe area makes the frame's origin) and a ~70 pt fade above it,
            /// like the Reader's bars. Hit testing is off so the pager underneath still gets taps.
            LinearGradient(stops: [.init(color: Tokens.ground.opacity(0), location: 0),
                                   .init(color: Tokens.ground, location: 0.34)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)

            VStack(spacing: 12) {
                if !env.libraryModel.isQueueEmpty || env.player.current != nil {
                    MiniPlayer { readerDocument = $0 }
                }
                PageIndicator(page: $page)
            }
            .padding(.bottom, Spacing.grid)
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
        // `shouldTilt` reads observable state inside `body`, so SwiftUI re-evaluates it as the
        // player, Prepare, Kokoro status or device state change — no timer or polling needed.
        .onChange(of: shouldTilt, initial: true) { _, on in env.motionTilt.setEnabled(on) }
    }

    private func openPending() {
        guard let doc = pendingOpen else { return }
        pendingOpen = nil
        readerDocument = doc
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
