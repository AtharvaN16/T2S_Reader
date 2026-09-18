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
    @State private var showChapters = false
    @State private var showAppearance = false
    @State private var showSpeed = false
    @State private var showBookmarks = false
    @State private var showSleepTimer = false
    @State private var showVoiceChange = false
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
    /// Whether the front-matter offer has had its say. See the `.task` that sets it.
    @State private var skipOfferExpired = false
    /// The save confirmation, and the bookmark it is about so "Add a note" knows what to open.
    /// Up for four seconds after a render is asked for, then gone. See `flashRenderNotice`.
    @State private var renderNotice = false
    @State private var renderNoticeTask: Task<Void, Never>?
    @State private var toast: ToastContent?
    @State private var toastBookmark: Bookmark?
    @State private var noteTarget: BookmarkEntry?
    @State private var toastTask: Task<Void, Never>?
    /// The chapter under the finger while the scrubber is dragged, so the picker names where the
    /// release would land rather than where playback still is (owner, 2026-09-12).
    @State private var scrubChapter: Int?

    /// The page's own paper, and the only place in the app it is decided (owner, 2026-09-14). The
    /// page reads it directly; everything under the page — the transport, the scrubber, the chip —
    /// takes it from the environment, which is what keeps it to this screen.
    private var palette: ReaderPalette { ReaderPalette(env.preferences.readerPaper) }

    /// How far the Reader's own chrome stands off the top while the status band is showing, and
    /// how tall the ground under it is. Zero when nothing is showing, so neither reader needs a
    /// gate of its own.
    ///
    /// Read from the model, which is the only thing this page and the band both see. The band
    /// does not publish its height into this view tree and cannot: since 2026-09-15 it is drawn in
    /// a `UIWindow` of its own (`StatusBandHost`), so there is no environment value and no
    /// preference travelling between the two. `StatusRows.bandHeight` is the shared constant, and
    /// the model says whether anything is standing in it.
    private var statusBandHeight: CGFloat {
        env.appStatus.isShowing ? StatusRows.bandHeight : 0
    }

    var body: some View {
        let reader = env.readerModel
        ZStack {
            palette.page.ignoresSafeArea()
            if let text {
                ReaderTextView(
                    text: text,
                    textScale: env.preferences.textScale,
                    lineHeight: env.preferences.lineHeight,
                    highlight: reader.activeHighlight,
                    palette: palette,
                    isFollowing: reader.isFollowing,
                    onTap: handleTap,
                    onUserScroll: { reader.suspendFollowing() },
                    onSaveSelection: saveSelection
                )
                .ignoresSafeArea(edges: .bottom)
            } else if let error {
                Text(error).typeRole(.meta).foregroundStyle(palette.destructive).padding(Spacing.margin)
            } else if env.kokoroStatus.status.isWarming {
                VStack(spacing: 10) {
                    WarmingDot()
                    Text("Preparing the voice…").typeRole(.meta).foregroundStyle(palette.glow)
                }
            } else {
                ProgressView().tint(palette.ink)
            }

            VStack(spacing: 0) {
                topBar.opacity(chromeVisible ? 1 : 0)
                // Both pills live under the header (owner, 2026-09-12): they are about where you
                // are in the book, which belongs with the title, not down by the transport.
                if !reader.isFollowing {
                    readerKey("Back to current", glyph: "text.line.first.and.arrowtriangle.forward") {
                        reader.resumeFollowing()
                    }
                    .padding(.top, 12)
                    .zIndex(1)
                } else if let skip = skipTarget, chromeVisible, !skipOfferExpired {
                    // One tap past the title page, dedication and reviews to the first numbered
                    // chapter (owner's ask, 2026-09-09). Goes with the chrome, so a tap on the text
                    // dismisses it. Blue, unlike the ink "Back to current": this one moves you on
                    // through the book rather than back to where you were (owner, 2026-09-12).
                    readerKey(skip.number.map { "Skip to Chapter \($0)" } ?? "Skip the front matter",
                              glyph: "forward.end.fill") {
                        Task { await env.player.seek(toChapter: skip.index) }
                    }
                    .padding(.top, 12)
                    .zIndex(1)
                    .accessibilityHint("Skips the front matter")
                }
                Spacer()
                bottomBar.opacity(chromeVisible ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        }
        .environment(\.readerPalette, palette)
        // The ground the rows stand on, and it is the book's paper. `TopFade` painted `Tokens.ground`
        // unconditionally until 2026-09-15, so while a warm-up was up the top 54 pt of the Reader was
        // app grey standing on whatever paper the reader had chosen — near enough to miss on Paper,
        // a seam on Sepia, and a white slab across the top of Cherry (owner: "the warm-up glow in the
        // reader looks weird, it has like a different color sometimes").
        //
        // The host paints this rather than the band, because the three surfaces that show the band
        // want three different grounds and this one wants solid through the rows' full reach —
        // `topBar` brings its own ground and picks up where they end, so there is nothing to see
        // through and every reason to give the bar and its megabytes an opaque page to sit on. See
        // `StatusBandOverlay` for the other two, and for the second reason the band cannot paint
        // this: the band is in a window above everything, and this ground has to sit *under* the
        // book's title bar. The inset is measured rather than read off `safeAreaInsets`: this
        // reader is a child of a stack that already sits inside the safe area, so it reports its
        // own inset as zero.
        //
        // Outside the chrome's fade, and deliberately not painted into `topBar`. A warm-up is the
        // app's state, not the bar's, and tapping the text away must not take the ground out from
        // under the rows: the bar's ground goes when the chrome does, and the rows — which are
        // above this page entirely — would be left standing on bare book text. It never *looked*
        // as though the bar going took the light with it, because the veil underneath carried the
        // same pixels; the bar going was invisible only by luck.
        .overlay {
            GeometryReader { geo in
                // `extra` is the *animating* height, not the constant, and that is the whole of the
                // ending's look. Held at `StatusRows.bandHeight` the ground kept its full depth and
                // dissolved by opacity over 1.5 s while `topBar` travelled the same 54 pt by
                // position — so halfway through, a half-transparent ground let the book's text
                // through a strip the header had not yet reached, and the reader watched a hole
                // open at the top of the page and then be filled in by the title bar (owner,
                // 2026-09-15: "it leaves like a hole in the reader UI ... it looks really bad").
                // Two kinds of animation doing one job. Tied to the same number, the ground's foot
                // and the header's crown are the same edge on every frame: the band retracts
                // upward and the header follows it, and no text is ever uncovered.
                //
                // The warm ramp, not the default 30 pt edge, and the reason is the chrome. While
                // the title bar is up its own ground is opaque from `bandHeight` down past 112,
                // so a 30 pt fade ends well inside it and nothing of the cut ever reaches the
                // screen. Tap the chrome away and the bar's ground goes with it while this stays,
                // by design — and what the reader is left with is a slab of paper ending in a
                // straight line across the book's text. The long ramp is already what every other
                // surface shows the veil as; here it also means the veil looks the same whether
                // the chrome is up or not. Below the bar it costs nothing: where the bar's own
                // ground lets go, this is down to about 5%.
                TopFade(inset: geo.frame(in: .global).minY,
                        extra: statusBandHeight,
                        fade: TopFade.warmFade,
                        curve: TopFade.warmCurve,
                        colour: palette.page)
                    .opacity(statusBandHeight > 0 ? 1 : 0)
                    .animation(.easeInOut(duration: StatusGlow.leave), value: statusBandHeight)
            }
            .allowsHitTesting(false)
        }
        // The band's paper, handed across to the window the band is drawn in. It cannot read
        // `\.readerPalette` from here — a `UIWindow` is the root of its own view tree and inherits
        // no environment — so the page that owns the paper pushes it, and puts the app's own back
        // when it leaves. Without this the top of the band goes on painting app grey over Cherry
        // or Cobalt, which is the defect that started all of this (owner, 2026-09-15: "the warm-up
        // glow in the reader looks weird, it has like a different color sometimes").
        //
        // `onDisappear` resets rather than trusting the next screen to set its own: every other
        // surface in the app wants `.app`, and a Reader that left its paper behind would tint the
        // band on the library page it just returned to.
        .onAppear { env.statusAppearance.palette = palette }
        .onChange(of: env.preferences.readerPaper) { _, paper in
            env.statusAppearance.palette = ReaderPalette(paper)
        }
        .onDisappear { env.statusAppearance.palette = .app }
        // The Reader is a `fullScreenCover`, which is its own presentation: the pager's copy of the
        // app-wide light and dark cannot reach it, and an override applied when it opened is not
        // re-applied when the reader flips the switch inside it (owner, 2026-09-14).
        .appTheme()
        // The queue holds while a book is being read as often as while the book sheet is up, and
        // the Reader is a `fullScreenCover` over the pager, so the pager's copy cannot reach here.
        .renderHoldSheet()
        // The press, answered. False → true is the moment this book joined the queue, which is the
        // moment "Render this chapter" was pressed — from here, or from anywhere else.
        .onChange(of: isRenderingThisBook) { _, on in if on { flashRenderNotice() } }
        .onDisappear { renderNoticeTask?.cancel() }
        .task(id: summary.id) { await open() }
        // Eighteen seconds is an answer (owner, 2026-09-14): a reader who has listened through the
        // front matter that long is reading it on purpose, and a pill offering to skip what they
        // are listening to is a button that has stopped being an offer and become furniture. It
        // does not come back — for this opening of the book, the question has been asked.
        .task(id: skipTarget != nil) {
            guard skipTarget != nil, !skipOfferExpired else { return }
            try? await Task.sleep(for: .seconds(18))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { skipOfferExpired = true }
        }
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
        .onChange(of: shownVoiceID, initial: true) { _, id in resolveVoiceName(id) }
        .onDisappear {
            Task { await env.player.persistRenderedChapters() }
        }
        // The Reader's sheets are the book's, not the app's: each takes the page's paper with it
        // (owner, 2026-09-14). A sheet does not inherit this on its own, so each is handed it.
        .sheet(isPresented: $showChapters) { ChapterList() }
        .sheet(isPresented: $showAppearance) { ReaderPreferencesSheet() }
        .sheet(isPresented: $showSpeed) { SpeedPicker(wearsPaper: true) }
        // A page, not a sheet, and the same one the Book sheet opens (owner, 2026-09-12).
        .fullScreenCover(isPresented: $showBookmarks) {
            if let current = env.player.current { BookmarksPage(summary: current) }
        }
        .sheet(isPresented: $showSleepTimer) { SleepTimerSheet(wearsPaper: true) }
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
                .foregroundStyle(palette.ink)
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
                    Button { showAppearance = true } label: { Label("Preferences", systemImage: "slider.horizontal.3") }
                    Button { showVoiceChange = true } label: { Label("Change voice", systemImage: "person.wave.2") }
                    Button { showSleepTimer = true } label: { Label("Sleep timer", systemImage: "moon.zzz") }
                    Button { showDetails = true } label: { Label("Details", systemImage: "info.circle") }
                    Button(action: renderThisChapter) {
                        Label(env.player.chapters.count > 1 ? "Render chapter" : "Render whole document", systemImage: "waveform")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .frame(width: 36, height: 36)
                        .background(palette.surface, in: Circle())
                }
            }
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, 2 * Spacing.grid)
        .padding(.bottom, 2 * Spacing.grid)                                  // a taller band, at the owner's ask
        .background(alignment: .top) {
            palette.page                                                   // plain: the glow is the rim over this, not this
                .mask(Self.groundShape(solidAtTop: true, span: 0.5))
                .padding(.bottom, -48)                                     // hangs below the bar, over the text
                .ignoresSafeArea(edges: .top)
        }
        // One header, not two. The bar used to pad down by exactly the band's height while a wait
        // was up, on the glow's own timing, so a warm-up stacked the status band above the book's
        // title bar (owner, 2026-09-15). It reads the band's height from the environment now, so
        // there is one number and one animation rather than two of each kept in step by hand — and
        // the height is zero while nothing is showing, so there is no gate to keep in step either.
        //
        // **After the background, not before it.** Folding the step into `.padding(.top)` above is
        // the obvious way and it is wrong: that padding is inside the bar's frame, so the ground
        // behind it grows by 54 too — and the ground's mask is solid for the top *half* of whatever
        // it covers, so a taller band pushes the ramp up over the title and the book's text ghosts
        // through the letters (measured: 98% opaque behind the title before, 79% after). Padding
        // out here moves the bar and its ground together and leaves the mask the proportions it
        // was drawn for. The gap it opens above the bar is `TopFade`'s, which is up whenever these
        // rows are.
        .padding(.top, statusBandHeight)
        .animation(.easeInOut(duration: StatusGlow.leave), value: statusBandHeight)
    }

    /// The shape of a ground bar, as a mask over the ground it paints: easing between solid and
    /// clear with zero slope at both ends, so
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
                // Clear of the controls, over the tail of the text fade, its foot `statusLineGap`
                // above the picker (owner, 2026-09-13) — hung off the picker itself so that is the
                // thing the gap is measured from. An overlay rather than a row in the stack: it
                // comes and goes mid-sentence, and a row would push the whole transport down and
                // back every time it did.
                .overlay(alignment: .top) {
                    if let status = statusText {
                        // Lifted by its own full height plus the gap, so adding the dots on top
                        // cannot eat into the space below them.
                        PlayerStatusLine(text: status)
                            .frame(height: Self.statusLineHeight, alignment: .bottom)
                            .offset(y: -(Self.statusLineHeight + Self.statusLineGap))
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: statusText)
            // 10 pt under the bar rather than 2 (owner, 2026-09-13): the scrubber's hit area is the
            // full 40 pt frame and the chip below is a target of its own, so the two need air
            // between them or a thumb aiming at one finds the other. The rest of that air is made
            // inside `ThinScrubber`, which lifts the bar within the same 40 pt frame.
            VStack(spacing: 10) {
                ThinScrubber(model: player.scrubber, segments: chapterSegments,
                             bookmarkFractions: env.preferences.showsBookmarkMarks ? player.bookmarkFractions : [],
                             scope: scrubberScope, currentChapter: player.chapterIndex,
                             onSeek: { fraction in Task { await player.seek(fraction: fraction) } },
                             onScrub: { scrubChapter = $0 })
                // Elapsed on the left, time left on the right (Apple Music's "-1:02:33"), in the
                // app's own face with tabular digits rather than the system monospace. In chapter
                // scope both read the chapter instead: a bar that spans one chapter with the
                // book's own 24-hour countdown under it is two different questions on one line.
                //
                // The chip is an overlay across the whole row rather than a third item between two
                // `Spacer()`s, because two spacers centre a thing between its *neighbours*, not on
                // the row: the clocks are different widths, and changing scope changes them again
                // (the remaining side loses a whole hour field), so a spacer-centred chip would
                // lurch sideways on every tap. This is the same fix the state line needed here on
                // 2026-09-12, and the chip has inherited that slot along with its lesson. An
                // overlay is also outside layout, so the chip cannot push the transport down.
                HStack {
                    Text(scopedClocks.elapsed).monospacedDigit()
                    Spacer()
                    Text(scopedClocks.remaining).monospacedDigit()
                }
                .overlay {
                    if chapterSegments.count > 1 {
                        ScopeChip(palette: palette, scope: scrubberScope) { env.preferences.scrubberScope = $0 }
                            .equatable()
                    }
                }
                .typeRole(.meta).foregroundStyle(palette.ink2)
                if let error = player.renderError {
                    Text(error).typeRole(.meta).foregroundStyle(palette.destructive).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let offer = syncOffer, let where_ = player.describe(offer.position), let id = player.current?.id {
                    HStack(spacing: 8) {
                        Text("Continue from \(offer.deviceName) · \(where_)").typeRole(.meta).foregroundStyle(palette.ink2).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Jump") { Task { await player.jump(to: offer.position); await env.syncModel.dismissOffer(for: id); syncOffer = nil } }
                            .typeRole(.pill)
                        Button { Task { await env.syncModel.dismissOffer(for: id); syncOffer = nil } } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.ink3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // 22 pt between the chip row and the transport (owner, 2026-09-13). The block is
            // bottom-anchored, so air made here pushes the scrubber group up rather than the
            // transport down; the foot is set by the block's own bottom padding below.
            .padding(.bottom, 22)
            // 20 pt under the transport rather than 10 (owner, 2026-09-13): the tool row is a
            // different kind of thing from the keys above it — type size, voice, bookmark, none of
            // them playback — and at 10 it read as a fourth row of the transport. The block is
            // bottom-anchored, so most of this air lifts the transport rather than lowering the
            // row; the few points the row itself drops come from the foot below.
            ReaderControls(onSleepTimer: { showSleepTimer = true }, onSpeed: { showSpeed = true })
                .padding(.bottom, 20)
            toolRow
        }
        .padding(.horizontal, Spacing.margin)
        .padding(.top, 12)
        // The whole block's foot, and so the whole assembly's position: the `ground` fade is a
        // background on this same view, so raising the foot lifts the fade with it rather than
        // leaving the controls to climb out of their own gradient. The state-line overlay rides up
        // too — it hangs off the chapter picker.
        //
        // 12 pt: a shade under `2 * Spacing.grid`, which is the top bar's band and was this foot
        // until the owner asked for the row to sit lower (2026-09-13) — "but don't move too much
        // towards bottom safe area", so it gives up 4 pt and no more. The home-indicator inset is
        // still whole underneath, and the row keeps a margin of its own above it rather than
        // standing on the edge.
        .padding(.bottom, 12)
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
            palette.page
                .mask(Self.groundShape(solidAtTop: false, span: 0.25))
                .padding(.top, -64)                                        // hangs above the block, over the text
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// The Reader's two pills — "Back to current" and the front-matter skip.
    ///
    /// On a zen paper this is the app's blue key, because a tinted page can host it. On a pop paper
    /// it is the page's own ink with the page's own colour lettering, and flat rather than raised:
    /// a lit blue key on a cobalt page is an object hiding inside its own background, and the key
    /// that gets you out of the front matter is the last thing that should be hard to find. It is
    /// still the loudest object on the screen — it is simply loud in the page's own voice.
    @ViewBuilder private func readerKey(_ label: String, glyph: String,
                                        action: @escaping () -> Void) -> some View {
        if palette.isPop {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: glyph).font(.system(size: 13, weight: .bold))
                    Text(label).typeRole(.pill)
                }
                .lineLimit(1)
                .foregroundStyle(palette.page)
                .padding(.horizontal, 18)
                .frame(minHeight: 40)
                .background(palette.ink, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        } else {
            RaisedButton(label: label, glyph: glyph, tone: .blue, size: .compact, action: action)
        }
    }

    /// The chapter now playing, on the device, whole — not `chapterAhead`'s five-minute window:
    /// it continues while paused, while backgrounded, and through heat if overruled
    /// (chapter-rendering design, "Entry points"). It goes to the app's queue rather than to the
    /// transport, so nothing about what is playing changes.
    ///
    /// The Reader can be up before the transport has this document — the page opens and the load
    /// follows — and then there is no chapter now playing; the book's resume chapter is what the
    /// reader is looking at, and is what the queue is given.
    private func renderThisChapter() {
        let renderer = env.chapterRenderer
        let id = summary.id
        guard env.player.current?.id == id, let chapter = env.player.chapterIndex else {
            Task { await renderer.enqueueResumeChapter(of: id) }
            return
        }
        Task { await renderer.enqueue(documentID: id, chapters: [chapter]) }
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
            show(ToastContent(title: "Bookmark saved", detail: detail, actionLabel: "Add a note",
                               secondaryActionLabel: "Go to bookmark", icon: "checkmark"))
        case .alreadyBookmarked(let bookmark):
            toastBookmark = bookmark
            show(ToastContent(title: "Already bookmarked", detail: detail, actionLabel: "Edit note",
                               secondaryActionLabel: "Go to bookmark", icon: "checkmark"))
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

    /// Clear space between the state line's foot and the chapter picker (owner, 2026-09-13). It
    /// has to stay inside the `ground` fade: the line is tinted and carries no background of its
    /// own, so over the opaque body text above the fade it is a blue sentence written through a
    /// black one. The fade starts 64 pt above the block, which is the ceiling here whatever this
    /// number says.
    private static let statusLineGap: CGFloat = 20
    /// The line's own height — 13 pt of padding, a row of 5 pt dots, 5 pt of air, one `pill` line,
    /// 13 pt again. Stated rather than measured so the gap below is exactly `statusLineGap` and has
    /// survived the dots moving above the words, the fill going in and the padding growing twice:
    /// the frame is bottom-aligned and does not clip, so a Dynamic Type size needing more room
    /// grows upward into the fade, not down into the picker.
    private static let statusLineHeight: CGFloat = 56

    /// The scope the bar and the clocks are in. A document with one chapter or none has nothing to
    /// zoom to, so it reads `.book` however the preference is set — the chip is hidden there too.
    private var scrubberScope: ScrubberScope {
        chapterSegments.count > 1 ? env.preferences.scrubberScope : .book
    }

    /// The pair under the bar. Chapter scope measures the chapter the playhead is in; without one
    /// it falls back to the book rather than showing two zeroes.
    private var scopedClocks: (elapsed: String, remaining: String) {
        let player = env.player
        if scrubberScope == .chapter, let index = player.chapterIndex {
            let chapters = player.chapters
            if chapters.indices.contains(index) {
                let chapter = chapters[index]
                return (DurationFormatter.clock(chapter.playedSeconds),
                        "-" + DurationFormatter.clock(chapter.remainingSeconds))
            }
        }
        return (player.elapsedText,
                "-" + DurationFormatter.clock(max(0, player.total - player.elapsed)))
    }

    /// What the state line says, or nil when the engine has nothing to report. Warming wins: it is
    /// the one the reader is waiting on before any sound at all. Catching up comes next, since that
    /// one is holding up the words on this very page.
    ///
    /// A render is last and is not a wait at all — the reader asked for a chapter and went back to
    /// reading, and this is the app saying it did not forget (owner, 2026-09-14). "Render this
    /// chapter" from the Reader's `⋯` had been the app's most silent action: the queue is app-wide
    /// and its only face was inside the Book sheet, so the press produced nothing on screen.
    private var statusText: String? {
        if env.isWarmingUp { return "Preparing The Voice" }
        if env.player.isCatchingUp { return "Catching Up" }
        if renderNotice { return "Rendering" }
        return nil
    }

    /// The render notice is a flash, not a state (owner, 2026-09-14). It answers one question —
    /// "did that press do anything?" — and a chip that sat there for the twenty minutes a batch
    /// takes would be answering it long after it had been asked, over the words the reader went
    /// back to. The Book sheet is where a render is watched; this is only the receipt.
    private func flashRenderNotice() {
        renderNoticeTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) { renderNotice = true }
        renderNoticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { renderNotice = false }
        }
    }

    /// Whether the app's one queue has outstanding work for the book on this page. Another book's
    /// chapter is not this page's news.
    private var isRenderingThisBook: Bool {
        env.chapterRenderer.queue.contains {
            $0.documentID == summary.id && ($0.state == .running || $0.state == .queued)
        }
    }

    /// "Chapter title ▾" on the left opens the chapter list (after the reference the owner sent,
    /// 2026-09-09). Hidden for a document with one chapter or none — an article has nothing to pick.
    @ViewBuilder private var chapterRow: some View {
        let player = env.player
        let chapters = player.chapters
        if chapters.count > 1, let index = scrubChapter ?? player.chapterIndex, chapters.indices.contains(index) {
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
                    .foregroundStyle(palette.ink)
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
                        .fill(palette.ink3)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text(voiceName.prefix(1).uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.ink)
                        )
                    Text(voiceName).typeRole(.pill)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(palette.ink)
                .background(palette.surface, in: Capsule())
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
                .foregroundStyle(palette.ink)
                .frame(width: 36, height: 36)
                .background(palette.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// A passage picked out by hand becomes a bookmark at its first word, keeping the words as
    /// selected rather than the utterance they sit in (owner, 2026-09-12).
    private func saveSelection(_ range: Range<Int>, passage: String) {
        guard let text, let timeline = env.player.coordinator.timeline else { return }
        // A selection can open in text that is never spoken — a drawn chapter title — so the anchor
        // is the first offset in it that belongs to an utterance.
        let anchor = range.indices.first { text.hit(at: $0) != nil } ?? range.lowerBound
        guard let hit = text.hit(at: anchor),
              let playhead = ReaderModel.playhead(utteranceIndex: hit.utteranceIndex,
                                                  sourceOffset: hit.sourceOffset, in: timeline)
        else { return }
        let position = PositionResolver.position(for: playhead, in: timeline)
        Task {
            let result = await env.player.saveBookmark(at: position, passageText: passage)
            let stamp = DurationFormatter.clock(env.player.coordinator.timeIndex.time(at: playhead))
            switch result {
            case .saved(let bookmark):
                toastBookmark = bookmark
                show(ToastContent(title: "Bookmark saved", detail: stamp, actionLabel: "Add a note",
                                  secondaryActionLabel: "Go to bookmark", icon: "checkmark"))
            case .alreadyBookmarked(let bookmark):
                toastBookmark = bookmark
                show(ToastContent(title: "Already bookmarked", detail: stamp, actionLabel: "Edit note",
                                  secondaryActionLabel: "Go to bookmark", icon: "checkmark"))
            case .failed:
                toastBookmark = nil
                show(ToastContent(title: "Could not save a bookmark", detail: nil, actionLabel: nil))
            }
        }
    }

    /// A tap on a word plays from it; a tap anywhere else shows or hides the chrome.
    private func handleTap(_ tap: ReaderTextView.Tap) {
        Task {
            if case .word(let index, let offset) = tap,
               await env.readerModel.seek(toUtterance: index, sourceOffset: offset) {
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
