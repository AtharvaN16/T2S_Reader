// App/T2SReader/Root/RootPager.swift
import SwiftUI
import T2SLibrary
import T2SCore
import T2SApp
import T2SStore
import UIKit
#if KOKORO_ENGINE
import T2SKokoro
#endif

enum RootPage: Hashable, CaseIterable {
    case collection, queue, preferences

    var title: String {
        switch self {
        case .collection: return "Collection"
        case .queue: return "Home"
        case .preferences: return "Settings"
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
    @State private var page: RootPage = .queue
    /// A file handed to us by another app (`onOpenURL`), shown through the Import page like any other
    /// import rather than imported invisibly.
    @State private var openedFiles: [URL]?
    /// Set by that page; opened once it has actually gone.
    @State private var pendingOpen: DocumentSummary?
    @State private var readerDocument: DocumentSummary?
    @State private var chrome = Chrome()

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

                // A page pushed from Settings owns the screen (owner, 2026-09-10): the bar and
                // its fill go, and `PagerLock` (in `PreferencesPage`) holds the pager still, so the
                // only swipe left is the one back to Settings.
                if !chrome.isSubpageOpen {
                    bottomFill(inset: geo.safeAreaInsets.bottom)
                        .transition(.opacity)
                }
                // The bar is the bar again — plain ground, its own job — and the glow goes over it
                // rather than being painted by it (owner, 2026-09-12: "why can't the glow stay on a
                // higher z index?"). It used to be the other way round: a `WarmUpVeil` at the back of
                // this stack, under the pages, with the bar painting the same ramp so the two met
                // without a join. That only ever worked while every layer between the veil and the
                // bar stayed transparent, and where one was not, the glow was cut off at the bar's
                // foot — the Voice page's seam of 2026-09-10, and the cut the owner kept seeing here.
                // The rim is the glow with no ground under it, so laid on top it needs nothing
                // underneath to cooperate: one layer, uncuttable, and the line still rides over it.
                //
                // Both go with a pushed page, like the fill above: that page paints its own bar and
                // its own rim, and this pair was drawing a second copy over them. Two opaque ramps
                // did not show it — the top one simply won — but two rims are transparent and add,
                // so the Voice page wore twice the glow below the bar's foot and a 30 pt ramp from
                // one to two through its fade (owner, 2026-09-12: "there is a top fade messing with
                // the glow"). The warm-up's line is not gated: it belongs wherever the reader is.
                if !chrome.isSubpageOpen {
                    // The fade grows to hold the warm-up's rows while they are up, and eases back
                    // on the glow's own timing so the two leave together rather than the ground
                    // snapping out from under a line that is still fading.
                    let warming = WarmUpVeil.isShowing(env)
                    TopFade(inset: geo.safeAreaInsets.top,
                            extra: warming ? TopFade.warmSolid : 0,
                            fade: warming ? TopFade.warmFade : TopFade.fadeHeight)
                        .animation(.easeInOut(duration: WarmUpVeil.fadeOut), value: warming)
                    WarmRim(edge: .top)
                    // The foot's rim is a sibling of the head's, not a passenger on `bottomFill`.
                    // It rode on the fill while the fill was the only thing that reached past the
                    // home indicator; the rim reaches on its own now, and hanging it off a host
                    // that bleeds its own safe area is the arrangement that cost the Reader its
                    // bottom 34 pt (see `WarmRim`). Above the fill, below the mini-player, as
                    // before.
                    WarmRim(edge: .bottom)
                }
                WarmUpLine(band: geo.safeAreaInsets.top)

                if !chrome.isSubpageOpen {
                    // 10 to the marks, not 12: the row below is 22 pt now where the icons were 32,
                    // and this stack stands on its foot, so the whole of what the marks gave back
                    // carries the player down rather than opening a gap over them. The player took
                    // those 12 pt as height, all of it downward — its top edge is where it was, so
                    // `Spacing.bottomClearance` still clears it (owner, 2026-09-12).
                    VStack(spacing: 10) {
                        if !env.libraryModel.isQueueEmpty || env.player.current != nil {
                            MiniPlayer { readerDocument = $0 }
                        }
                        PageIndicator(page: $page)
                    }
                    .padding(.bottom, Spacing.grid)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // Above the mini-player, where a message about what was just tapped belongs; the
                // Reader draws the same toast over its own page while it is up.
                ToastHost()
                    .padding(.bottom, Spacing.grid + 96)
            }
            .animation(.snappy, value: chrome.isSubpageOpen)
        }
        .environment(chrome)
        .background(Tokens.ground.ignoresSafeArea())
        // The held-queue notice, over whichever page is up. Drawn by each layer that can be
        // frontmost — the Reader and the book sheet have their own — because it is a card in a
        // stack, not a `.sheet`, and a stack only covers what is under it.
        .renderHoldSheet()
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
        .fullScreenCover(item: $readerDocument, onDismiss: refreshHome) { ReaderPage(summary: $0) }

        .playbackTicking(env.player, sleepTimer: env.sleepTimer, continuation: env.continuation, nowPlaying: env.nowPlaying)
        .task {
            await env.libraryModel.refresh()
            #if DEBUG
            // One route back, and only in a debug build: a script-driven simulator cannot tap a
            // book open, and the Reader is where most of this app's look lives. `T2S_OPEN=reader`
            // with an optional `T2S_BOOK=<title fragment>`. The dozen screenshot routes that were
            // dropped on 2026-09-13 stay dropped — this is the one a photograph cannot do without.
            if ProcessInfo.processInfo.environment["T2S_OPEN"] == "reader" {
                let wanted = ProcessInfo.processInfo.environment["T2S_BOOK"]
                readerDocument = env.libraryModel.summaries.first {
                    guard let wanted else { return true }
                    return $0.document.title.localizedCaseInsensitiveContains(wanted)
                } ?? env.libraryModel.summaries.first
            }
            #endif
        }
        .onChange(of: env.deviceMonitor.deviceState, initial: true) { _, state in
            updatePrepareDeviceState(state)
        }
        // Home reads a snapshot (`LibraryModel.summaries`/`progress`), and listening moves the
        // playhead in the store without touching it — so the row kept the chapter, the percent and
        // the excerpt it was built with until the app was relaunched (owner, 2026-09-12). Refreshed
        // where it comes back into view instead: swiping to Home, closing the Reader over it, and a
        // chapter turning under a Home that is already on screen.
        .onChange(of: page) { _, shown in if shown == .queue { refreshHome() } }
        .onChange(of: env.player.chapterIndex) { _, _ in
            if page == .queue, readerDocument == nil { refreshHome() }
        }
        .onChange(of: env.libraryModel.queue.map(\.id), initial: true) { _, ids in
            env.coordinator.queue = ids
            startForegroundPrepareIfNeeded()
        }
        .onChange(of: env.libraryModel.summaries.map(\.id)) { _, ids in
            if let current = env.player.current, !ids.contains(current.id) { env.nowPlaying.clear() }
        }
        // The reader deleted the voice model and then tapped play: say so, and offer the way back.
        // Here rather than at each play button — Home, the Collection, the mini-player, the Reader's
        // transport and a queue continuation all reach the same transport, and this is where they meet.
        .onChange(of: env.player.isPlaying) { was, isPlaying in
            guard !was, isPlaying, env.kokoroStatus.status == .removed else { return }
            env.toasts.show(
                ToastContent(title: "Voice model removed",
                             detail: "Playing with the system voice",
                             actionLabel: "Download",
                             actionGlyph: "arrow.down.circle")
            ) {
                readerDocument = nil
                page = .preferences
                // After the cover has gone: a push into a stack that is still behind a full-screen
                // cover is dropped.
                Task {
                    try? await Task.sleep(for: .seconds(0.35))
                    chrome.opensStorage = true
                }
            }
        }
        .onChange(of: env.preferences.defaultVoiceID) { _, voiceID in
            env.player.defaultVoiceID = voiceID
            env.prepareRunner.defaultVoiceID = voiceID
            env.chapterRenderer.defaultVoiceID = voiceID
        }
        // One message when the queue empties, not one per chapter, and from here rather than the
        // Book sheet: the queue outlives the sheet, so the reader who started it and swiped away is
        // the one who most needs telling.
        .onChange(of: env.chapterRenderer.lastCompletion) { _, completion in
            guard let completion else { return }
            showRenderToast(completion)
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
                // Playing is what puts a book on Home, latest first, three at most (`LibraryModel.notePlaying`).
                if let id = env.player.current?.id { Task { await env.libraryModel.notePlaying(id) } }
            } else {
                startForegroundPrepareIfNeeded()
            }
        }
        // The foreground gate, first and on the initial value: everything that must not run in
        // the background — the Kokoro warm-up's plan builds, the model install's compiles, an
        // unpaced render — waits on it (`AppEnvironment.foregroundGate`). The coordinator learns
        // the same fact on the same line: frontmost and listening is when it renders the rest of
        // the chapter, and a lock replans to the window alone (Plan 18).
        .onChange(of: scenePhase, initial: true) { _, phase in
            env.foregroundGate.set(foreground: phase == .active)
            env.coordinator.isForeground = phase == .active
            if phase == .active { Task { await env.syncModel.refreshAvailability(); await env.syncModel.syncIfEnabled() } }
            // Placement (which set a Kokoro render lands on) reads its own flag, set here from the
            // scene phase directly rather than from the gate above: `.inactive` — Control Center, a
            // banner, the app switcher — must close the gate (a plan build must not be caught
            // running once the app is actually backgrounded) but must *not* place a streamed head
            // in the background, or it parks on the gate or renders in discarded 3 s pieces for
            // every such interruption (2026-09-11 GPU-path review §5 item 3 — R4).
            let phaseKind: ScenePhaseKind = phase == .active ? .active : phase == .background ? .background : .inactive
            env.kokoro.noteScene(isBackground: ScenePlacement.placesInBackground(phase: phaseKind))
            #if KOKORO_ENGINE
            // Into the phone's timing log too, so a lock can be read against the render lines
            // around it rather than against a time noted by hand. The playhead says how far into
            // the buffer the lock landed, to read against the window it then drains
            // (`playAheadWindowSeconds`); no public rendered-horizon figure exists yet on
            // `PlayerModel`/`PlaybackCoordinator` to add beside it (review §5 item 1 gives one).
            KokoroCoreMLEngine.timing("kokoro scene \(phase == .active ? "active" : phase == .background ? "background" : "inactive"); foreground gate \(phase == .active ? "open" : "closed"); playhead \(Int(env.player.elapsed))s of \(Int(env.player.total))s")
            #endif
        }
        // The fill's edges in the phone's timing log, beside the engine's utterance lines.
        .onChange(of: env.coordinator.isFilling) { _, on in env.kokoro.noteFill(on) }
        // The screen stays awake while the one-time setup runs: the download, the compile and the
        // warm-up's plan builds all wait on that gate, so an auto-lock part-way through would stop
        // them until the next unlock — and a first launch is minutes of them (Harsh's 17 Pro,
        // 2026-09-10). Off again the moment the voice is ready, or was never going to be.
        .onChange(of: env.kokoroStatus.status.isWarming || env.kokoroStatus.isBuildingBackgroundSet, initial: true) { _, warming in
            UIApplication.shared.isIdleTimerDisabled = warming
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
        // The app's one bottom ramp (`BottomFade`), drawn here as part of a single gradient
        // because this fill carries the page row's solid band and the home-indicator inset under
        // it as well; the sheets get the same curve from the view.
        let stops = BottomFade.stops(fadeEnd: fadeEnd)
        // Ground only. The rim that goes over it — this fill is opaque exactly where the glow is
        // brightest, and painting under it puts the foot of the light out (owner, 2026-09-12) — is
        // a sibling in `body`, drawn after this.
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
    }

    private func refreshHome() {
        Task { await env.libraryModel.refresh() }
    }

    /// The one message a drain earns, with the one thing worth doing about it: audio that is ready
    /// is ready *to play*, so the toast offers to play it (owner, 2026-09-13). Only when everything
    /// that finished belongs to one book — a mixed drain has no single thing a Play could mean.
    private func showRenderToast(_ completion: ChapterRenderRunner.Completion) {
        let ready = env.chapterRenderer.queue.filter { $0.state == .ready }
        let ids = Set(ready.map(\.documentID))
        let summary = ids.count == 1 ? env.libraryModel.summaries.first { $0.id == ids.first } : nil
        // One chapter of a book plays from that chapter; anything else picks the book up where the
        // reader left it, which is what the Play pill everywhere else in the app does.
        let chapter = ready.count == 1 ? ready[0].chapterIndex : nil
        let content = Self.renderToast(completion, queue: env.chapterRenderer.queue,
                                       chapters: summary.flatMap { env.libraryModel.progress(for: $0.id)?.chapterCount } ?? 0,
                                       canPlay: summary != nil)
        env.toasts.show(content, action: summary.map { book in
            { playRendered(book, chapter: chapter) }
        })
    }

    /// Opens the book and starts it, from the chapter that was just made when there is one.
    private func playRendered(_ summary: DocumentSummary, chapter: Int?) {
        Task {
            if env.player.current?.id != summary.id { await env.player.load(summary, play: false) }
            if let chapter { await env.player.seek(toChapter: chapter) }
            if !env.player.isPlaying { await env.player.togglePlay() }
            readerDocument = summary
        }
    }

    /// What one drain of the chapter queue came to. A chapter that failed carries its own sentence
    /// — how many sentences never became audio, or why the book could not be read — so the detail
    /// line quotes it rather than saying "something went wrong": the reader can act on the first
    /// and not on the second.
    private static func renderToast(_ completion: ChapterRenderRunner.Completion,
                                    queue: [ChapterRenderJob],
                                    chapters: Int, canPlay: Bool) -> ToastContent {
        let reason = queue.compactMap { job -> String? in
            if case .failed(let message) = job.state { return message }
            return nil
        }.last
        // A document with one chapter is not a book with a chapter in it — an article, or a PDF the
        // reader imported — and calling its one piece "1 chapter" is the app describing its own
        // data model rather than the thing on the screen.
        let ready: String
        if completion.ready == 1 {
            ready = chapters == 1 ? "Document ready to play" : "Chapter ready to play"
        } else {
            ready = "\(completion.ready) chapters ready to play"
        }
        let play = canPlay ? "Play" : nil
        guard completion.failed > 0 else {
            return ToastContent(title: ready, actionLabel: play, actionGlyph: "play.fill")
        }
        let failed = completion.failed == 1 ? "1 chapter could not be rendered"
                                            : "\(completion.failed) chapters could not be rendered"
        if completion.ready == 0 { return ToastContent(title: failed, detail: reason, actionLabel: nil) }
        return ToastContent(title: ready, detail: failed, actionLabel: play, actionGlyph: "play.fill")
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
        // The chapter queue decides for itself what heat and a full store mean to it — it holds
        // rather than stops, and a `.storeFull` it hit itself is released by the next report of
        // room. It only needs to be told (chapter-rendering design, "State machine").
        env.chapterRenderer.deviceStateChanged(state)
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
