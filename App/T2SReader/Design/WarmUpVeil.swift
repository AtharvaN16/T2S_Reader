// App/T2SReader/Design/WarmUpVeil.swift
import SwiftUI

/// The one-time voice warm-up, shown wherever the reader is (owner, 2026-09-10, Tabby's launch
/// gradient as the reference): a soft orange wash over the top half of the screen that breathes
/// until the stages are loaded, and — where there is room under the status bar — one short line
/// with how long it usually takes on this phone and a hairline of progress. The wash is an overlay
/// at low opacity, so the page underneath stays readable and gets its taps; nothing here is hit-
/// tested. Gone (with a fade) the moment the status leaves `preparing`.
///
/// What it knows: the stage count as each compute plan finishes (`KokoroStatusModel.warmUpStages`,
/// eight stages), and the last warm-up's length on this phone (`expectedWarmUpSeconds`). The bar is
/// the larger of the two readings — stages are exact but coarse, the clock is smooth but a guess —
/// and never claims done. A first launch after install has no remembered length, and says so.
struct WarmUpVeil: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The line and bar under the status bar; off in the Reader, whose own bar sits there and
    /// whose transport already says "preparing the voice…".
    var showsMessage = true
    @State private var bright = false

    var body: some View {
        let status = env.kokoroStatus
        if status.status.isWarming {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    LinearGradient(stops: [
                        .init(color: Tokens.accent.opacity(0.26), location: 0),
                        .init(color: Tokens.accent.opacity(0.10), location: 0.55),
                        .init(color: Tokens.accent.opacity(0), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.size.height * 0.5 + geo.safeAreaInsets.top)
                    .opacity(bright ? 1 : 0.5)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: bright)
                    .onAppear { bright = true }

                    if showsMessage {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            message(status, now: context.date)
                        }
                        .padding(.top, geo.safeAreaInsets.top + 6)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    private func message(_ status: KokoroStatusModel, now: Date) -> some View {
        let elapsed = status.warmUpStarted.map { now.timeIntervalSince($0) } ?? 0
        let byStages = status.warmUpStages.map { Double($0.loaded) / Double(max(1, $0.total)) } ?? 0
        let byClock = status.expectedWarmUpSeconds.map { min(0.92, elapsed / max(1, $0)) } ?? 0
        let progress = max(byStages, byClock)
        return VStack(spacing: 7) {
            Text(line(status, elapsed: elapsed))
                .typeRole(.caption)
                .foregroundStyle(Tokens.ink)
            Capsule().fill(Tokens.ink3)
                .frame(width: 120, height: 3)
                .overlay(alignment: .leading) {
                    Capsule().fill(Tokens.accent).frame(width: 120 * progress)
                        .animation(.easeOut(duration: 0.6), value: progress)
                }
                .opacity(progress > 0 ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// "Warming up the voice · about 6 s", or on a first launch "Warming up the voice · a few
    /// minutes the first time". Once the estimate is spent, "almost there" rather than a number
    /// that has gone wrong.
    private func line(_ status: KokoroStatusModel, elapsed: TimeInterval) -> String {
        guard let expected = status.expectedWarmUpSeconds else {
            return "Warming up the voice · a few minutes the first time"
        }
        let left = expected - elapsed
        if left <= 1 { return "Warming up the voice · almost there" }
        let rounded = left < 10 ? Int(left.rounded(.up)) : Int((left / 5).rounded(.up)) * 5
        return "Warming up the voice · about \(rounded) s"
    }
}
