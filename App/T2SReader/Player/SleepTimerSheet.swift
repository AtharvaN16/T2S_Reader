import SwiftUI
import T2SApp

/// Sleep-timer sheet (spec §2.4.5), redrawn on 2026-09-18 after the owner's reference, Tide's
/// focus sheet: one value, large; a ruler under it that the finger drags; the one alternative —
/// the end of the chapter — as a switch at the foot; and the key under that. The reference is the
/// *shape*, nothing of its paint: the moon and the title are the ones this sheet already had, the
/// greys are the Reader's palette, the key is the blue `RaisedButton`.
///
/// The ruler replaced a grid of six tiles. Tiles offer what we chose; a ruler offers what the
/// reader wants, in five-minute stops from 5 to 120 (`SleepDial`), and still draws the old six
/// taller and named so the common answers can be hit without reading the number. The sheet has no
/// state of its own: the length and the switch are `ReaderPreferences`, so it opens on what was
/// chosen last time — a sleep timer is a habit, not a decision made fresh each night.
///
/// The key sits on the floor of the sheet rather than under the content (owner, 2026-09-12), with
/// the air between them doing what an instruction line would: nothing else is asked of you here.
struct SleepTimerSheet: View {
    @Environment(AppEnvironment.self) private var env
    /// True when the Reader presented this, and so when it should wear the book's paper.
    var wearsPaper = false

    /// Read from the model on every pass rather than taken from the environment at presentation
    /// (owner, 2026-09-14: "the UI sheets does not update when switching"). A sheet is its own
    /// presentation: a value handed to it when it opened is the value it keeps, and changing the
    /// paper or the light behind it left every sheet painted in the old one.
    private var palette: ReaderPalette { wearsPaper ? ReaderPalette(env.preferences.readerPaper) : .app }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var preferences = env.preferences
        let timer = env.sleepTimer
        let caption = timer.caption
        let atChapterEnd = preferences.sleepsAtChapterEnd
        VStack(spacing: 0) {
            // The scroll view is what holds the key to the floor: it takes whatever room is left
            // over, so the air above the key grows with the phone rather than the key drifting up
            // to meet the switch. On a short screen, or at the accessibility text sizes, the same
            // view scrolls rather than clipping its last row.
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(palette.ink3)
                        Text("Sleep timer").typeRole(.sectionHeader).foregroundStyle(palette.ink)
                    }
                    .padding(.top, Spacing.margin)
                    .padding(.bottom, Spacing.row)

                    if let caption {
                        Text(caption)
                            .typeRole(.playerTitle)
                            .foregroundStyle(palette.ink)
                            .multilineTextAlignment(.center)
                    } else {
                        // Dimmed, not hidden, while the switch is on: the length is still there
                        // to come back to, and a sheet that reflows when a switch flips reads as
                        // two sheets.
                        VStack(spacing: 22) {
                            SleepValue(minutes: preferences.sleepMinutes)
                            SleepRuler(minutes: $preferences.sleepMinutes)
                        }
                        .opacity(atChapterEnd ? 0.3 : 1)
                        .allowsHitTesting(!atChapterEnd)
                        .accessibilityHidden(atChapterEnd)
                        .animation(.easeInOut(duration: 0.2), value: atChapterEnd)
                        .padding(.bottom, Spacing.row)
                        ChapterEndRow(isOn: $preferences.sleepsAtChapterEnd)
                    }
                }
                .padding(.bottom, Spacing.row)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            if caption != nil {
                Pill(label: "Cancel timer", style: .soft, fillsWidth: true) {
                    timer.cancel()
                    dismiss()
                }
            } else {
                RaisedButton(label: "Start sleep timer", glyph: "play.fill", tone: .blue, size: .bar) {
                    timer.start(atChapterEnd ? .endOfChapter : .minutes(preferences.sleepMinutes))
                    dismiss()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.margin)
        .padding(.bottom, Spacing.margin)
        // `presentationBackground`, not `.background`: the content is only as wide as it needs to
        // be, so a background painted on it left the sheet's own sides unfilled (owner, 2026-09-12).
        .presentationBackground(palette.sheet)
        // Each presentation carries the app's light/dark itself: an override set back on the pager
        // is applied to a sheet when it opens and not again, so flipping it under an open sheet
        // repainted the page behind and left the sheet as it was.
        .appTheme()
        .environment(\.readerPalette, palette)
        // A shade taller than `.medium` (owner, 2026-09-12: air between the content and the key).
        // Medium is a fixed fraction of the screen, and at that height the switch sat on the key;
        // this is the fraction the content actually asks for, with the air the key needs.
        .presentationDetents([.fraction(0.62)])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}

/// The number, large, and its unit after it in a quieter role. The digits roll rather than swap
/// as the ruler moves under them, so a drag reads as one number changing and not as a flicker of
/// twenty-four.
private struct SleepValue: View {
    @Environment(\.readerPalette) private var palette
    var minutes: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(minutes)")
                .typeRole(.pageTitle)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(minutes)))
                .foregroundStyle(palette.ink)
            Text("min").typeRole(.groupTitle).foregroundStyle(palette.ink2)
        }
        .animation(.snappy(duration: 0.22), value: minutes)
        // The ruler speaks the value; two readings of the same number would be noise.
        .accessibilityHidden(true)
    }
}

/// The ruler: one tick per stop of `SleepDial`, the chosen one tallest and `ink`, the landmarks
/// taller than the rest and named under the bar, the ticks behind the finger `ink2` and the ones
/// ahead `ink3` — the scrubber's own reading of behind and ahead. The finger's place along the
/// bar *is* the value: a drag anywhere on the row picks the stop under it rather than nudging
/// from where it was, so a length is reached in one movement and the whole row is the target.
private struct SleepRuler: View {
    @Environment(\.readerPalette) private var palette
    @Binding var minutes: Int

    private static let tickWidth: CGFloat = 2
    private static let chosenHeight: CGFloat = 26
    private static let landmarkHeight: CGFloat = 14
    private static let minorHeight: CGFloat = 7
    /// The names under the bar: their gap above, their row, and the width each is centred in —
    /// wide enough for "120" in the fine role with air either side.
    private static let labelGap: CGFloat = 7
    private static let labelRow: CGFloat = 12
    private static let labelWidth: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            // Tick centres run from half a tick in from the left edge to half a tick in from the
            // right, so the first and last stand inside the margin rather than astride it.
            let span = max(1, width - Self.tickWidth)
            ZStack(alignment: .bottomLeading) {
                ForEach(SleepDial.stops, id: \.self) { stop in
                    Capsule(style: .continuous)
                        .fill(colour(of: stop))
                        .frame(width: Self.tickWidth, height: height(of: stop))
                        .offset(x: CGFloat(SleepDial.fraction(of: stop)) * span)
                }
            }
            .frame(width: width, height: Self.chosenHeight, alignment: .bottomLeading)
            .animation(.snappy(duration: 0.18), value: minutes)
            .overlay(alignment: .topLeading) {
                ForEach(SleepDial.landmarks, id: \.self) { stop in
                    let centre = CGFloat(SleepDial.fraction(of: stop)) * span + Self.tickWidth / 2
                    // A name centred on its tick, except at the two ends, where it is held inside
                    // the bar's width rather than overhanging the margin.
                    let x = min(width - Self.labelWidth / 2, max(Self.labelWidth / 2, centre))
                    Text("\(stop)")
                        .typeRole(.fine)
                        .monospacedDigit()
                        .foregroundStyle(stop == minutes ? palette.ink : palette.ink2)
                        .frame(width: Self.labelWidth)
                        .offset(x: x - Self.labelWidth / 2, y: Self.chosenHeight + Self.labelGap)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = Double((value.location.x - Self.tickWidth / 2) / span)
                        let stop = SleepDial.minutes(atFraction: fraction)
                        if stop != minutes { minutes = stop }
                    }
            )
        }
        .frame(height: Self.chosenHeight + Self.labelGap + Self.labelRow)
        .sensoryFeedback(.selection, trigger: minutes)
        .accessibilityElement()
        .accessibilityLabel("Sleep timer length")
        .accessibilityValue("\(minutes) minutes")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = SleepDial.snapped(minutes + SleepDial.step)
            case .decrement: minutes = SleepDial.snapped(minutes - SleepDial.step)
            @unknown default: break
            }
        }
    }

    private func height(of stop: Int) -> CGFloat {
        if stop == minutes { return Self.chosenHeight }
        return SleepDial.landmarks.contains(stop) ? Self.landmarkHeight : Self.minorHeight
    }

    private func colour(of stop: Int) -> Color {
        if stop == minutes { return palette.ink }
        return stop < minutes ? palette.ink2 : palette.ink3
    }
}

/// The other answer, as a switch on its own `surface` slab: the whole row is the switch's label,
/// so a tap on the words flips it too.
private struct ChapterEndRow: View {
    @Environment(\.readerPalette) private var palette
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text("End of chapter").typeRole(.settingsRow).foregroundStyle(palette.ink)
                Text("Stop when this chapter ends")
                    .typeRole(.meta)
                    .foregroundStyle(palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
