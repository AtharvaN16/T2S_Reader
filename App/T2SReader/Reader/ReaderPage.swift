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
    @State private var showChapters = RootPage.launchOpen == "chapters"      // screenshots, see `RootPage.launchOpen`
    @State private var showAppearance = false
    @State private var showSpeed = false
    @State private var showBookmarks = false
    @State private var showSleepTimer = false
    @State private var showVoiceChange = RootPage.launchOpen == "voice"       // screenshots, see `RootPage.launchOpen`
    @State private var showDetails = false
    @State private var voiceName = "Voice"
    /// Where the book proper starts, for the "Skip to Chapter 1" pill; nil when there is no front
    /// matter to skip. Read once per document in `open`.
    @State private var bodyStart: (index: Int, number: Int?)?
    /// The other device's saved place for the loaded document, while it is still worth offering
    /// (sync spec §4); nil once dismissed, jumped to, or ten seconds of listening have passed.
    @State private var syncOffer: SyncedPosition?
    /// `player.elapsed` when `syncOffer` last appeared, so the ten-second auto-dismiss measures
    /// listening time from there rather than from playback's own start.
    @State private var offerShownAt: TimeInterval = 0
    /// The save confirmation, and the bookmark it is about so "Add a note" knows what to open.
    @State private var toast: ToastContent?
    @State private var toastBookmark: Bookmark?
    @State private var noteTarget: BookmarkEntry?
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        let reader = env.readerModel
        ZStack {
            Tokens.ground.ignoresSafeArea()
            // Over the ground and under the text (`ReaderTextView` draws on a clear background),
            // so the page is lit from behind rather than washed over (owner, 2026-09-10). The
            // header's ground paints the same glow while it shows (`WarmGround`), so there is no
            // join between the bar and the page.
            WarmUpVeil()
            if let text {
                ReaderTextView(
                    text: text,
                    textScale: env.preferences.textScale,
                    lineHeight: env.preferences.lineHeight,
                    highlight: reader.activeHighlight,
                    highlightTheme: env.preferences.highlightTheme,
                    isFollowing: reader.isFollowing,
                    onTap: handleTap,
                    onUserScroll: { reader.suspendFollowing() }
                )
                .ignoresSafeArea(edges: .bottom)
            } else if let error {
                Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive).padding(Spacing.margin)
            } else if env.kokoroStatus.status.isWarming {
                VStack(spacing: 10) {
                    WarmingDot()
                    Text("Preparing the voice…").typeRole(.meta).foregroundStyle(Tokens.glow)
                }
            } else {
                ProgressView().tint(Tokens.ink)
            }

            VStack(spacing: 0) {
                topBar.opacity(chromeVisible ? 1 : 0)
                Spacer()
                if !reader.isFollowing {
                    // Above the bottom block's fade in both senses: 32 pt up from it, and drawn
                    // over the fade the block hangs above itself (a later sibling would otherwise
                    // paint that fade across the pill).
                    RaisedButton(label: "Back to current", glyph: "text.line.first.and.arrowtriangle.forward",
                                 tone: .ink, size: .compact) {
                        reader.resumeFollowing()
                    }
                    .padding(.bottom, 32)
                    .zIndex(1)
                } else if let skip = skipTarget, chromeVisible {
                    // The same pill while the playhead is still in the front matter (owner's ask,
                    // 2026-09-09): one tap past the title page, dedication and reviews to the
                    // first numbered chapter. Goes with the chrome, so a tap on the text dismisses it.
                    // Blue, unlike its ink sibling above: this one moves you on through the book
                    // rather than back to where you were (owner, 2026-09-12).
                    RaisedButton(label: skip.number.map { "Skip to Chapter \($0)" } ?? "Skip the front matter",
                                 glyph: "forward.end.fill", tone: .blue, size: .compact) {
                        Task { await env.player.seek(toChapter: skip.index) }
                    }
                    .padding(.bottom, 32)
                    .zIndex(1)
                    .accessibilityHint("Skips the front matter")
                }
                bottomBar.opacity(chromeVisible ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        }
        .task(id: summary.id) { await open() }
        .task(id: env.player.current?.id) {
            // Not `player.current.map { await … }`: `Optional.map`'s transform is synchronous, and
            // a closure with `await` inside cannot satisfy that (confirmed against the compiler).
            if let id = env.player.current?.id {
                syncOffer = await env.syncModel.offer(for: id)
            } else {
                syncOffer = nil
            }
            if syncOffer != nil { offerShownAt = env.player.elapsed }
        }
        .onChange(of: env.player.elapsed) { _, new in
            guard syncOffer != nil, new - offerShownAt > 10 else { return }
            if let id = env.player.current?.id { Task { await env.syncModel.dismissOffer(for: id) } }
            syncOffer = nil
        }
        .appTheme()
        .onChange(of: shownVoiceID, initial: true) { _, id in resolveVoiceName(id) }
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
        .sheet(item: $noteTarget) { entry in
            if let current = env.player.current {
                BookmarkNoteSheet(summary: current, entry: entry,
                                  onSaved: { Task { await env.player.refreshBookmarks() } })
            }
        }
    }

    /// The first numbered chapter, while the playhead is before it.
    private var skipTarget: (index: Int, number: Int?)? {
        guard let bodyStart, let index = env.player.chapterIndex, index < bodyStart.index else { return nil }
        return bodyStart
    }

    /// Back on the left, the overflow on the right, the document's title between them (owner's
    /// ask, 2026-09-09; the bookmark moved down to the tool row). The circles sit on solid `ground`
    /// that eases to clear from their band down through 48 pt below the bar, so the header itself
    /// visibly fades into the text (the first cut faded within the bar alone and read as no fade
    /// at all).
    private var topBar: some View {
        ZStack {
            Text(summary.document.title)
                .typeRole(.pill)
                .foregroundStyle(Tokens.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 60)                                  // clear of one circle each side
                .accessibilityAddTraits(.isHeader)
            HStack {
                icon("chevron.left", "Back") { dismiss() }
                Spacer()
                Menu {
                    Button { showChapters = true } label: { Label("Chapters", systemImage: "list.bullet") }
                    Button { showBookmarks = true } label: { Label("Bookmarks", systemImage: "bookmark.circle") }
                    Button { showAppearance = true } label: { Label("Appearance", systemImage: "textformat.size") }
                    Button { showVoiceChange = true } label: { Label("Change voice", systemImage: "person.wave.2") }
                    Button { showSleepTimer = true } label: { Label("Sleep timer", systemImage: "moon.zzz") }
                    Button { showDetails = true } label: { Label("Details", systemImage: "info.circle") }
                    Button { env.player.renderCurrentChapter() } label: {
                        Label(env.player.chapters.count > 1 ? "Render chapter" : "Render whole document", systemImage: "waveform")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.ink)
                        .frame(width: 36, height: 36)
                        .background(Tokens.surface, in: Circle())
                }
            }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, 2 * Spacing.grid)
        .padding(.bottom, 2 * Spacing.grid)                                  // a taller band, at the owner's ask
        .background(alignment: .top) {
            WarmGround()
                .mask(Self.groundShape(solidAtTop: true, span: 0.5))
                .padding(.bottom, -48)                                     // hangs below the bar, over the text
                .ignoresSafeArea(edges: .top)
        }
    }

    /// The shape of a ground bar, as a mask over whatever it paints (`ground`, or the warm-up glow
    /// through `WarmGround`): easing between solid and clear with zero slope at both ends, so
    /// neither edge of a fade reads as a line across the text (the Home bar's lesson).
    /// `solidAtTop`: solid from the top, easing to clear over the bottom `span` of the height.
    /// Otherwise clear at the top, easing to solid over the top `span`, then solid to the bottom.
    private static func groundShape(solidAtTop: Bool, span: Double = 1) -> LinearGradient {
        let steps = 12
        var stops: [Gradient.Stop] = []
        if solidAtTop, span < 1 { stops.append(.init(color: .black, location: 0)) }
        stops += (0...steps).map { i -> Gradient.Stop in
            let t = Double(i) / Double(steps)
            let s = t * t * (3 - 2 * t)
            return .init(color: Color.black.opacity(solidAtTop ? 1 - s : s),
                         location: solidAtTop ? (1 - span) + t * span : t * span)
        }
        if !solidAtTop, span < 1 { stops.append(.init(color: .black, location: 1)) }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    /// Chapter row, progress bar + times, transport row, tool row (spec §2.4.5, after ElevenReader).
    /// The `ground` fade starts 64 pt above the block and is solid by the chapter row's foot, so the
    /// chapter picker sits on ground too (the owner's second cut) and the text fades out above it.
    private var bottomBar: some View {
        let player = env.player
        return VStack(spacing: 0) {
            // 2 pt under the picker rather than the stack's 10, so it sits lower — nearer the
            // scrubber, further from the text it hangs under (owner, 2026-09-10).
            chapterRow
                .padding(.bottom, 2)
            VStack(spacing: 2) {
                ThinScrubber(model: player.scrubber, segments: chapterSegments,
                             bookmarkFractions: player.bookmarkFractions) { fraction in
                    Task { await player.seek(fraction: fraction) }
                }
                // Elapsed on the left, time left on the right (Apple Music's "-1:02:33"), in the
                // app's own face with tabular digits rather than the system monospace.
                HStack {
                    Text(player.elapsedText).monospacedDigit()
                    Spacer()
                    if env.isWarmingUp {
                        Text("preparing the voice…").foregroundStyle(Tokens.glow)
                    } else if player.isCatchingUp {
                        Text("catching up…")
                    }
                    Spacer()
                    Text("-" + DurationFormatter.clock(max(0, player.total - player.elapsed))).monospacedDigit()
                }
                .typeRole(.meta).foregroundStyle(Tokens.ink2)
                if let error = player.renderError {
                    Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let offer = syncOffer, let where_ = player.describe(offer.position), let id = player.current?.id {
                    HStack(spacing: 8) {
                        Text("Continue from \(offer.deviceName) · \(where_)").typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Jump") { Task { await player.jump(to: offer.position); await env.syncModel.dismissOffer(for: id); syncOffer = nil } }
                            .typeRole(.pill)
                        Button { Task { await env.syncModel.dismissOffer(for: id); syncOffer = nil } } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Tokens.ink3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 10)
            ReaderControls(onSleepTimer: { showSleepTimer = true }, onSpeed: { showSpeed = true })
                .padding(.bottom, 10)
            toolRow
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, 12)
        .padding(.bottom, Spacing.grid)
        .overlay(alignment: .top) {
            // One slot, and the Reader's own toast has it: a bookmark saved here is answered here.
            // An app-wide message (`ToastCenter` — the voice model removed under a play) uses the
            // slot when the Reader has nothing of its own to say, which is all but four seconds.
            Group {
                if let toast {
                    Toast(content: toast,
                          onAction: { openNoteEditor(); dismissToast() },
                          // The body of it opens the list, rather than only getting out of the way:
                          // "bookmark saved" invites you to go and look (owner, 2026-09-12).
                          onTap: { dismissToast(); showBookmarks = true })
                        .padding(.horizontal, Spacing.margin)
                } else {
                    ToastHost()
                }
            }
            // The toast's bottom sits on the block's top edge, 10 pt clear, so it floats
            // over the text and never covers the chapter row, the scrubber or the transport.
            .alignmentGuide(.top) { d in d[.bottom] + 10 }
        }
        .background(alignment: .bottom) {
            Tokens.ground
                .mask(Self.groundShape(solidAtTop: false, span: 0.25))
                .padding(.top, -64)                                        // hangs above the block, over the text
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Saves, says so, and offers the note there and then.
    private func saveBookmark() async {
        let result = await env.player.saveBookmark()
        let chapter = env.player.chapterIndex.flatMap { i in env.player.chapters.first { $0.index == i }?.title } ?? ""
        let stamp = DurationFormatter.clock(env.player.elapsed)
        let detail = chapter.isEmpty ? stamp : "\(chapter) · \(stamp)"
        switch result {
        case .saved(let bookmark):
            toastBookmark = bookmark
            show(ToastContent(title: "Bookmark saved", detail: detail, actionLabel: "Add a note"))
        case .alreadyBookmarked(let bookmark):
            toastBookmark = bookmark
            show(ToastContent(title: "Already bookmarked", detail: detail, actionLabel: "Edit note"))
        case .failed:
            toastBookmark = nil
            show(ToastContent(title: "Could not save a bookmark", detail: nil, actionLabel: nil))
        }
    }

    /// Four seconds, restarted by a second save so two taps do not leave a stale message.
    private func show(_ content: ToastContent) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { toast = content }
        UIAccessibility.post(notification: .announcement, argument: content.title)
        toastTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { toast = nil }
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = nil }
    }

    /// The toast's action: resolve the bookmark just saved into a display entry, then edit it.
    private func openNoteEditor() {
        guard let bookmark = toastBookmark, let timeline = env.player.coordinator.timeline else { return }
        noteTarget = BookmarkListModel.displayEntry(for: bookmark, timeline: timeline,
                                                    index: env.player.coordinator.timeIndex)
    }

    /// The chapters as spans of the whole, for the scrubber's segments; empty for a document whose
    /// duration is not known yet, which draws one bar.
    private var chapterSegments: [Range<Double>] {
        let player = env.player
        let total = player.total
        guard total > 0 else { return [] }
        return player.chapters.map { chapter in
            let start = min(1, max(0, chapter.startSeconds / total))
            return start..<min(1, max(start, (chapter.startSeconds + chapter.durationSeconds) / total))
        }
    }

    /// "Chapter title ▾" on the left opens the chapter list (after the reference the owner sent,
    /// 2026-09-09). Hidden for a document with one chapter or none — an article has nothing to pick.
    @ViewBuilder private var chapterRow: some View {
        let player = env.player
        let chapters = player.chapters
        if chapters.count > 1, let index = player.chapterIndex, chapters.indices.contains(index) {
            HStack {
                Button { showChapters = true } label: {
                    // The chevron stands 8 pt off the title, centred on its height, in `ink` like
                    // the title (owner's third cut, 2026-09-09; outlined and pointing on rather
                    // than a filled arrow, 2026-09-12).
                    HStack(alignment: .center, spacing: 8) {
                        Text(ChapterLabel.text(for: chapters[index].title, ordinal: index + 1))
                            .typeRole(.rowTitle)
                            .lineLimit(1)
                            // Scrubbing walks the chapters past; the name crossfades rather than
                            // snapping from one to the next (owner, 2026-09-12).
                            .contentTransition(.opacity)
                            .id(index)
                            .transition(.opacity)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Tokens.ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.22), value: index)
                .accessibilityLabel("Chapter")
                .accessibilityValue(chapters[index].title)
                .accessibilityHint("Opens the chapter list")
                Spacer(minLength: 12)
            }
            .frame(height: 36)
            .padding(.top, 10)                                 // a touch lower off the text above
        }
    }

    /// Appearance (left) · voice chip (centred) · bookmark (right). The chip shows the voice
    /// actually routed for this document (`shownVoiceID`), named in `resolveVoiceName`. The
    /// bookmark took the contents circle's place (owner's ask, 2026-09-09; the chapter row above
    /// already opens the list). Momentary since 2026-09-11: a tap saves and says so in a toast,
    /// which offers the note in the same breath. Saving twice on one sentence does not make two
    /// rows — `saveBookmark()` checks the resolved list — and removing is done from the list.
    private var toolRow: some View {
        ZStack {
            HStack {
                icon("textformat.size", "Appearance") { showAppearance = true }
                Spacer()
                // Momentary, never filled (2026-09-11 spec §5): the old toggle's fill meant "the
                // sentence under the playhead is bookmarked", which paused looked stuck and playing
                // looked like the bookmark had been lost. Removing is done from the list.
                icon("bookmark", "Bookmark") { Task { await saveBookmark() } }
                    .accessibilityHint("Saves this place and its sentence")
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
        bodyStart = ChapterLabel.bodyStart(titles: timeline.chapters.map(\.title))
        let document = summary.document
        let model = await Task.detached(priority: .userInitiated) {
            ReaderText(documentID: document.id, timeline: timeline, title: document.title, author: document.displayAuthor)
        }.value
        // The page was dismissed, or moved to another document, while the model was building.
        guard !Task.isCancelled else { return }
        text = model
    }

    /// The voice the chip names: the one the player routed for this document when it loaded it
    /// (spec §6) — not the stored choice in `summary`, which is the snapshot this page was opened
    /// with and which a voice change never updates (the change reloads the player instead, so this
    /// moves the moment the sheet applies it; owner, 2026-09-10). Nil until the player holds this
    /// document.
    private var shownVoiceID: String? {
        env.player.current?.id == summary.id ? env.player.routedVoiceID : nil
    }

    /// Names `shownVoiceID` from the catalog. Called from `onChange`, not the body: the catalog is
    /// built on every `voices()` call, and the body runs at 10 Hz while playing.
    private func resolveVoiceName(_ id: String?) {
        voiceName = id.flatMap { id in env.voices.voices().first { $0.id == id }?.name } ?? "Voice"
    }
}
