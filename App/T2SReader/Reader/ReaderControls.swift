import SwiftUI
import T2SApp

/// Sleep timer · back 15 · play · forward 30 · speed — the Reader page's transport row (spec
/// §2.4.5, after ElevenReader). Size and weight rank the controls: play is the biggest (44pt glyph
/// in 72), the skips second (28 in 52), both at regular weight so size does the ranking rather than
/// heft, and the three huddle 12 pt apart as one transport unit in the middle; the sleep timer and
/// the speed label are the small pair at the ends — one glyph weight, one type weight, both in
/// `ink2` — flush with the margins so their centres line up with the tool row's circles below.
/// Skip amounts stay synchronized with the reading preferences.
struct ReaderControls: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.readerPalette) private var palette
    var onSleepTimer: () -> Void
    var onSpeed: () -> Void

    var body: some View {
        let player = env.player
        let preferences = env.preferences
        HStack(spacing: 0) {
            control(
                env.sleepTimer.active == nil ? "moon.zzz" : "moon.zzz.fill", "Sleep timer",
                size: 20, frame: 36, action: onSleepTimer
            )
            .foregroundStyle(palette.ink2)
            Spacer()
            HStack(spacing: 12) {
                SkipControl(
                    glyph: "gobackward.\(preferences.skipBackSeconds)",
                    label: "Back \(preferences.skipBackSeconds) seconds",
                    holdGlyph: "backward.end.fill", holdLabel: "Previous chapter",
                    holds: preferences.holdSkipChangesChapter && chapter(by: -1) != nil,
                    onTap: { Task { await player.skip(by: -Double(preferences.skipBackSeconds)) } },
                    onHold: { jump(by: -1) }
                )
                Button {
                    Task { await player.togglePlay() }
                } label: {
                    // The glyph holds its place and breathes instead of being swapped out
                    // (owner, 2026-09-12: "just keep the play button and fade it out, don't show
                    // the tiny dot"). A 10 pt dot and a spinner where a 44 pt glyph was is a hole
                    // in the middle of the transport, and it read as the button having gone away
                    // rather than as the app working; the words for what is happening are already
                    // on the line above the scrubber. `TransportGlyph` owns the breath so the
                    // repeating animation is not restarted by every unrelated redraw of this row.
                    TransportGlyph(isPlaying: player.isPlaying, isBusy: player.isCatchingUp)
                        .frame(width: 72, height: 72)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                .accessibilityValue(player.isCatchingUp ? (env.isWarmingUp ? "Preparing the voice" : "Buffering") : "")
                SkipControl(
                    glyph: "goforward.\(preferences.skipForwardSeconds)",
                    label: "Forward \(preferences.skipForwardSeconds) seconds",
                    holdGlyph: "forward.end.fill", holdLabel: "Next chapter",
                    holds: preferences.holdSkipChangesChapter && chapter(by: 1) != nil,
                    onTap: { Task { await player.skip(by: Double(preferences.skipForwardSeconds)) } },
                    onHold: { jump(by: 1) }
                )
            }
            Spacer()
            Button(action: onSpeed) {
                /// Tabular digits so "1x" → "1.5x" changes width only by the added glyphs.
                Text(SpeedPickerModel.label(for: player.coordinator.rate))
                    .monospacedDigit()
                    .typeRole(.rowTitle)
                    .foregroundStyle(palette.ink2)
                    .frame(minWidth: 36)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed")
        }
        .foregroundStyle(palette.ink)
        .frame(height: 72)                                                 // no side padding: ends align with the circles below
    }

    /// The chapter a hold on one of the skips would land in, or nil at that end of the book — which
    /// is what takes the hold off the button rather than letting a reader hold a dead one.
    private func chapter(by delta: Int) -> Int? {
        guard let index = env.player.chapterIndex else { return nil }
        let target = index + delta
        return env.player.chapters.contains { $0.index == target } ? target : nil
    }

    private func jump(by delta: Int) {
        guard let target = chapter(by: delta) else { return }
        Task { await env.player.seek(toChapter: target) }
    }

    /// `size` is the glyph's point size and `frame` its square tap target.
    private func control(
        _ glyph: String, _ label: String, size: CGFloat, frame: CGFloat, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: size, weight: .regular))
                .frame(width: frame, height: frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The transport's play/pause glyph, dimmed and breathing while the player is catching up or the
/// voice is warming. One view so `.repeatForever` lives on state this view owns: driven from the
/// caller's `isBusy` directly, SwiftUI restarts the animation on every redraw of the row — and the
/// row redraws on every tick of the clock beside it.
private struct TransportGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isPlaying: Bool
    var isBusy: Bool

    /// Off until the first frame after `isBusy` turns on, so the breath animates *into* the dim
    /// rather than appearing already there.
    @State private var breathing = false

    var body: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 44, weight: .regular))
            .opacity(isBusy ? (breathing ? 0.28 : 0.6) : 1)
            .animation(breathAnimation, value: breathing)
            .animation(.easeInOut(duration: 0.25), value: isBusy)
            .onChange(of: isBusy, initial: true) { _, busy in breathing = busy && !reduceMotion }
            // A live toggle of Reduce Motion settles the glyph without waiting for the next stall.
            .onChange(of: reduceMotion) { _, reduce in breathing = isBusy && !reduce }
    }

    /// Nil once the breath is over, so the ease back to full opacity is not caught by a repeating
    /// curve and left pulsing after playback has started.
    private var breathAnimation: Animation? {
        breathing ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : nil
    }
}

/// One of the two skips. A tap is the skip it has always been; a hold turns the button into a
/// chapter jump (owner, 2026-09-14) — the glyph becomes the transport's own next/previous mark and
/// a grey disc grows from the centre out under it, so the reader can see how much longer to hold
/// and, just as importantly, that letting go now costs them nothing.
///
/// The morph waits `reveal` before it starts: a tap is over in about a tenth of a second, and a
/// button that changed shape under every ordinary press would flicker all evening. Nothing is
/// coloured — greys and the glyph's own ink, on the owner's word — because this is a measurement of
/// a press, not a state of the book.
///
/// Built on one `DragGesture(minimumDistance: 0)` rather than a `Button` with a long press beside
/// it: those two fire together on a long press, and the reader who held for a chapter would also
/// have skipped thirty seconds on the way out of it. Here the hold cancels the tap by definition —
/// whichever of the two happens, the other cannot.
private struct SkipControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readerPalette) private var palette
    var glyph: String
    var label: String
    var holdGlyph: String
    var holdLabel: String
    /// False at the ends of the book and when the reader has turned the gesture off in Preferences:
    /// then this is the plain skip button it was before, tap and all.
    var holds: Bool
    var onTap: () -> Void
    var onHold: () -> Void

    /// How long the press has to last before the button admits what it is offering.
    private static let reveal: Double = 0.18
    /// And how long the disc then takes to fill. `reveal + fill` is the whole hold. 0.9 rather than
    /// the 0.55 it was (owner, 2026-09-14): the fill is the only thing telling the reader how much
    /// longer to hold, and at half a second it was over before it had been read.
    private static let fill: Double = 0.9
    private static let frame: CGFloat = 52
    /// The disc the hold draws, wider than the button it grows out of — and wider than a fingertip,
    /// which is the point (owner, 2026-09-14: "I can't see it, my finger covers it"). It is drawn
    /// as a background, so it overhangs the 52 pt button without moving the transport; 76 stops
    /// exactly at the play button's frame, whose own glyph is another 14 pt inside that.
    private static let holdFrame: CGFloat = 76
    /// How far the finger may wander and still count as a tap on release.
    private static let slop: CGFloat = 24

    @State private var isHolding = false
    @State private var filled: Double = 0
    @State private var press: Task<Void, Never>?
    /// Set when the hold completed, so the release that follows is not also a skip.
    @State private var jumped = false
    /// Counts completed holds, for the one bump of haptic feedback.
    @State private var jumps = 0

    var body: some View {
        Image(systemName: isHolding ? holdGlyph : glyph)
            .font(.system(size: isHolding ? 30 : 28, weight: .regular))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: Self.frame, height: Self.frame)
            .background { if isHolding { disc } }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in begin() }
                    .onEnded { value in
                        let wandered = max(abs(value.translation.width), abs(value.translation.height)) > Self.slop
                        end(tapping: !wandered)
                    }
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: jumps)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityAction { onTap() }
            // The gesture is a hold, which VoiceOver does not do; the jump is a named action instead.
            .accessibilityAction(named: holdLabel) { if holds { onHold() } }
    }

    /// The disc under the glyph while the hold runs, and the fill measuring it: one grey circle
    /// growing inside another, clipped to it, so it reads as the button filling up rather than as a
    /// circle getting bigger. The fill is a clear step off the disc — `ink3` was a grey on a grey
    /// and the measurement disappeared into the thing it was measuring — and neither is a colour.
    private var disc: some View {
        ZStack {
            Circle().fill(palette.surface)
            Circle().fill(palette.ink2.opacity(0.7)).scaleEffect(filled)
        }
        .frame(width: Self.holdFrame, height: Self.holdFrame)
        .clipShape(Circle())
        .transition(.opacity)
    }

    /// The finger has landed. `onChanged` fires on every movement, so this runs once per press —
    /// and `jumped` keeps it once per press even after the hold has fired, or a finger left down
    /// would walk the book a chapter every three quarters of a second.
    private func begin() {
        guard press == nil, !jumped else { return }
        press = Task {
            guard holds else { return }
            try? await Task.sleep(for: .seconds(Self.reveal))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.14)) { isHolding = true }
            withAnimation(reduceMotion ? nil : .linear(duration: Self.fill)) { filled = 1 }
            try? await Task.sleep(for: .seconds(Self.fill))
            guard !Task.isCancelled else { return }
            jumped = true
            jumps += 1
            onHold()
            // A beat at the full disc, so the press is seen to have been answered before the
            // button goes back to being a skip.
            try? await Task.sleep(for: .milliseconds(160))
            settle()
        }
    }

    private func end(tapping: Bool) {
        press?.cancel()
        press = nil
        if !jumped, tapping { onTap() }
        jumped = false
        settle()
    }

    /// Back to a skip button. The fill is wound down rather than dropped so a released hold reads
    /// as abandoned, not as something that happened.
    private func settle() {
        press = nil
        withAnimation(.easeOut(duration: 0.18)) {
            isHolding = false
            filled = 0
        }
    }
}
