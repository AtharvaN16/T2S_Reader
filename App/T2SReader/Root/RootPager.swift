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

/// The two facts the sleep Live Activity is drawn from, together, so `onChange` sees a restart of
/// the option that is already running. `SleepOption` alone does not change when the reader picks
/// "30 min" a second time, but the deadline does.
private struct SleepCardKey: Equatable {
    var option: SleepOption?
    var deadline: Date?
}

/// Spec §2.4.4: no tab bar; a three-page pager opening on Queue, a tappable three-glyph indicator,
/// and the floating mini-player above it on every page.
struct RootPager: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @State private var page: RootPage = .queue
    /// A file handed to us by another app (`onOpenURL`), shown through the Import page like any other
    /// import rather than imported invisibly.
    @State private var openedFiles: [URL]?
    /// Set by that page; opened once it has actually gone.
    @State private var pendingOpen: DocumentSummary?
    @State private var readerDocument: DocumentSummary?
    @State private var chrome = Chrome()
    /// The welcome (`OnboardingCover`), up on a fresh install until it is finished or skipped, and
    /// again after Settings' "Show the welcome again". Held as the manifest it plays, loaded from
    /// the bundle at launch; nil is "not shown".
    @State private var welcome: OnboardingManifest?

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
                .sensoryFeedback(.selection, trigger: page)
                .environment(\.readerRoute, ReaderRoute(open: { readerDocument = $0 }))

                // A page pushed from Settings owns the screen (owner, 2026-09-10): the bar and
                // its fill go, and `PagerLock` (in `PreferencesPage`) holds the pager still, so the
                // only swipe left is the one back to Settings.
                //
                // Plain ground and nothing else. The status band's foot glow is laid over this
                // whole stack from a window above it (`StatusBandHost`), so nothing down here has
                // to paint a matching copy of the light for the two to meet without a join. It was
                // the other way round until 2026-09-12 — a veil behind the pages, with every bar
                // painting the same ramp into itself — and that only works while every layer
                // between the veil and the bar stays transparent. Where one was not, the glow was
                // cut off at the bar's foot with nothing in the code to say why (the Voice page's
                // seam, 2026-09-10, and the cut the owner kept seeing here).
                if !chrome.isSubpageOpen {
                    bottomFill(inset: geo.safeAreaInsets.bottom)
                        .transition(.opacity)
                }
                // No top edge at this level. A page carries its own (`pageTopEdge`): one drawn
                // here sits above the `TabView`, outside the navigation transition, so every push
                // left it bright across the screen while UIKit dimmed the pages under it.
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
                // Clear of the mini-player, not stacked on it (owner, 2026-09-14: "animate it a bit
                // higher"). At 8 pt the toast's card and the player's capsule read as one column of
                // chrome; a band of page between them is what says the message is not transport.
                ToastHost()
                    .padding(.bottom, Spacing.grid + 152)
            }
            .animation(.easeInOut(duration: 0.3), value: chrome.isSubpageOpen)
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
        .fullScreenCover(isPresented: Binding(get: { welcome != nil }, set: { if !$0 { welcome = nil } })) {
            if let welcome {
                OnboardingCover(manifest: welcome) {
                    OnboardingRecord.markCompleted(defaults: .standard)
                    self.welcome = nil
                }
            }
        }

        .playbackTicking(env.player, sleepTimer: env.sleepTimer, soundscape: env.soundscape, continuation: env.continuation, nowPlaying: env.nowPlaying)
        .task {
            // `System` left the picker with the Reader's papers (owner, 2026-09-14), so a reader
            // who was on it settles once, here, on whatever the device was showing at that moment.
            // Done in a view rather than in `ReaderPreferences`: this is the first place that can
            // ask what the device actually resolved to, and with `.system` in force `appTheme()`
            // sets no override, so `colorScheme` *is* the device's answer.
            if env.preferences.theme == .system { env.preferences.theme = scheme == .dark ? .dark : .light }
            await env.libraryModel.refresh()
            presentWelcomeIfNeeded()
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
        // Settings' "Show the welcome again" (`Chrome.showsWelcome`): forget that it was seen and
        // present it now, over Settings.
        .onChange(of: chrome.showsWelcome) { _, wanted in
            guard wanted else { return }
            chrome.showsWelcome = false
            OnboardingRecord.clear(defaults: .standard)
            presentWelcomeIfNeeded()
        }
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
        // Per chapter, not per drain (owner, 2026-09-14). A chapter becoming playable is the
        // event worth a message: it is the thing the reader can act on, and "3 chapters ready"
        // was a summary of something that had already stopped being news twice over.
        .onChange(of: env.chapterRenderer.finishCount) { _, _ in
            guard let job = env.chapterRenderer.lastFinished else { return }
            showRenderToast(job)
        }
        // The card follows the queue even when nothing finished — a batch starting, a hold
        // arriving, the last job leaving. `event: nil` keeps every one of these silent.
        .onChange(of: env.chapterRenderer.queue.count) { _, _ in updateRenderActivity(event: nil) }
        .onChange(of: env.chapterRenderer.hold) { _, _ in updateRenderActivity(event: nil) }
        // The sleep card needs no updates while it counts — the view ticks from the deadline on
        // its own — so this fires only when the timer starts, changes or is cancelled.
        //
        // Both facts, not just the option: choosing "30 min" while "30 min" is already running is
        // a common gesture, and it moves the deadline without changing the option. Watching the
        // option alone left the Lock Screen counting down to the moment the reader had just
        // replaced (review I8).
        .onChange(of: SleepCardKey(option: env.sleepTimer.active,
                                   deadline: env.sleepTimer.deadlineDate)) { _, key in
            let reading = SleepCardReading.make(option: key.option,
                                                deadline: key.deadline,
                                                chapterTitle: env.sleepTimer.sleepChapterTitle)
            env.activities.updateSleep(reading, bookTitle: env.player.current?.document.title ?? "")
        }
        .onChange(of: env.preferences.defaultRate) { _, rate in
            env.player.setRate(rate)
        }
        .onChange(of: env.player.current?.id, initial: true) { _, _ in env.nowPlaying.update() }
        // A seek made while paused, so the Lock Screen moves with it at once rather than on the
        // idle ticker's next second. Only while paused: `elapsed` moves ten times a second while
        // playing, and watching it here re-ran this whole body — the pager, its three pages and
        // every observer below — at that rate to make a call the ticker already makes on every
        // tick (audit §7, the one item left open). The `isPlaying` test comes first so the body
        // never reads `elapsed` while playing and takes no dependency on it.
        .onChange(of: env.player.isPlaying ? nil : env.player.elapsed) { _, _ in env.nowPlaying.update() }
        .onChange(of: env.player.chapterIndex) { _, _ in env.nowPlaying.update() }
        .onChange(of: env.coordinator.rate) { _, _ in env.nowPlaying.update() }
        .onChange(of: env.player.state) { _, state in
            env.nowPlaying.update()
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
                // A pause made right as the screen locks can lose the race with the `onChange`/ticker
                // publish that would otherwise carry it to the Lock Screen — this transition is
                // guaranteed to run before the process suspends, so it is the last safe point to make
                // sure the Lock Screen isn't left showing a stale playing state (`update()` no-ops if
                // nothing changed).
                env.nowPlaying.update()
            default:
                break
            }
        }
    }

    /// The welcome on a fresh install, and on demand for a photograph: `T2S_OPEN=onboarding` in a
    /// debug build presents it whatever the record says. A bundle without the manifest — a build
    /// that dropped the resources — shows nothing rather than an empty scene.
    private func presentWelcomeIfNeeded() {
        var wanted = !OnboardingRecord.isCompleted(defaults: .standard)
        #if DEBUG
        if ProcessInfo.processInfo.environment["T2S_OPEN"] == "onboarding" { wanted = true }
        #endif
        guard wanted, let manifest = try? OnboardingManifest.load(from: .main) else { return }
        welcome = manifest
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

    /// The one message a finished chapter earns, sent to exactly one surface.
    ///
    /// App on screen: the capsule at the top says it, wherever in the app the reader is — which
    /// is the whole reason it exists, since the Book sheet's progress box only exists while that
    /// sheet is open. App backgrounded: the Live Activity alerts instead. Never both (owner,
    /// 2026-09-16).
    private func showRenderToast(_ job: ChapterRenderJob) {
        guard let book = env.libraryModel.summaries.first(where: { $0.id == job.documentID }) else { return }
        let cover = ToastContent.Cover(relativePath: book.document.coverImagePath,
                                       title: book.document.title,
                                       isPDF: book.document.sourceType == .pdf)
        let chapters = env.libraryModel.progress(for: book.id)?.chapterCount ?? 0
        let message = ChapterReadyMessage.make(job: job, documentTitle: book.document.title,
                                               chapterCount: chapters)
        let play: (() -> Void)? = message.isFailure
            ? nil
            : { playRendered(book, chapter: chapters > 1 ? job.chapterIndex : nil) }

        switch Announcement.route(isForeground: scenePhase == .active) {
        case .island:
            env.island.show(message, cover: cover, action: play)
            // And the card moves too, silently. `RenderCardReading.make` is handed `canAlert:
            // false` below while the app is on screen, so the number on the Lock Screen follows
            // the queue without anything breaking through — which is what "the card updates
            // silently" asks for. Leaving it out stranded the card at "0 of 8" for hours,
            // because the queue does not shrink on a finish and nothing else fires (review C2).
            updateRenderActivity(event: nil, documentID: job.documentID)
        case .liveActivity:
            // A failure carries its own two lines rather than the chapter's name: away from the
            // phone this card is the only place the reader will ever hear about it (review I6).
            let event: RenderCardReading.Event = message.isFailure
                ? .failed(title: message.title, reason: message.detail)
                : .finished(name: message.name)
            updateRenderActivity(event: event, documentID: job.documentID)
        }
    }

    /// Pushes one book's share of the queue to the Live Activity. `event` is what makes the
    /// update break through: a chapter landing, or failing, is the only thing worth a banner —
    /// and only while the reader is somewhere else.
    ///
    /// - Parameter documentID: the book the event belongs to, when the caller knows it. The
    ///   queue is the whole session's across every document, so without this the card names
    ///   whichever book the session started with (review C3).
    private func updateRenderActivity(event: RenderCardReading.Event?, documentID: UUID? = nil) {
        let jobs = RenderCardReading.focus(env.chapterRenderer.queue, preferring: documentID)
        let book = jobs.first.flatMap { job in
            env.libraryModel.summaries.first { $0.id == job.documentID }
        }
        let title = book?.document.title ?? ""
        let reading = RenderCardReading.make(jobs: jobs, bookTitle: title,
                                             hold: env.chapterRenderer.hold,
                                             event: event,
                                             canAlert: scenePhase != .active)
        env.activities.updateRender(reading, bookTitle: title,
                                    coverPath: book?.document.coverImagePath)
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
