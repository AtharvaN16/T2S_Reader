// App/T2SReader/Onboarding/ReadAlongPassage.swift
import SwiftUI
import T2SApp

/// The hero's lines under the settled cover, read along: a bigger cut of the Reader's own text
/// (the owner, 2026-09-14: "our faded chapter reader interface for Alice moving, thick and bigger
/// font than what we use"). The Reader's read-along is a boundary, not a tint (`ReaderTextView`):
/// everything up to the word being spoken is `ink`, everything after it `inkUnread` — no
/// highlighter box on the current word, which the owner pointed out on 2026-09-15 ("we don't use
/// highlighter effect in our reader mode"). This mirrors that exactly, at word granularity. The
/// block scrolls itself so the spoken word stays in the middle — the Reader's own following — and
/// nothing else scrolls it; the top and bottom edges use the app's own bottom-fade curve
/// (`BottomFade.stops`), not a hand-rolled mask, and only over a few points so the text stays
/// mostly visible (the owner, 2026-09-15: "this fade is too aggressive, I can only see a small
/// part of text").
///
/// No fade of its own (the owner, 2026-09-15: "the only fade is the bottom fade of the button, so
/// the voice boxes are over the text, so make the text more visible") — the voice carousel floats
/// over its lower reach as opaque, coloured containers, so the text needs no edge of its own to
/// hide under; the one fade left in the scene is `BottomFade` behind the Continue key.
///
/// Built from the clip's timing file: each word's range in the spoken text, with the punctuation
/// and space that follow it attached, so the line reads as prose and not as a list of words.
struct ReadAlongPassage: View {
    var timings: OnboardingClipTimings?
    /// Shown whole and quiet when there is no timing file for the voice.
    var fallback: String
    /// The clip's position, once a frame.
    var time: TimeInterval
    /// True once the passage has been heard through: every word stays ink rather than falling
    /// back to waiting when the player's clock resets.
    var isFinished: Bool = false

    private struct Token: Identifiable {
        var id: Int
        var text: String
    }

    private var tokens: [Token] {
        guard let timings else {
            return fallback.split(separator: " ").enumerated().map { Token(id: $0.offset, text: String($0.element)) }
        }
        let utf16 = Array(timings.spoken.utf16)
        return timings.words.enumerated().map { index, word in
            let lower = max(0, min(word.range.first ?? 0, utf16.count))
            let upper = index + 1 < timings.words.count
                ? max(lower, min(timings.words[index + 1].range.first ?? utf16.count, utf16.count))
                : utf16.count
            let text = String(utf16CodeUnits: Array(utf16[lower ..< upper]), count: upper - lower)
            return Token(id: index, text: text.trimmingCharacters(in: .whitespaces))
        }
    }

    /// The word being spoken; past the end, one beyond the last, so every word reads as spoken.
    private var current: Int? {
        if isFinished { return timings?.words.count }
        return timings?.wordIndex(at: time)
    }

    /// The Reader's own body type (the owner, 2026-09-15: "use the font we use in the regular
    /// reader"): `Inter-Regular` at `ReaderTypesetter.bodySize`, so a change there carries here.
    /// The gap between rows is the Reader's 1.5 line-height multiple less the font's own height —
    /// `FlowLayout` spaces rows in points where the Reader sets a multiple.
    static var bodyFont: Font { .custom("Inter-Regular", size: ReaderTypesetter.bodySize) }
    static var lineGap: CGFloat { ReaderTypesetter.bodySize * (1.5 - 1.22) }

    var body: some View {
        let tokens = tokens
        let current = current
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                FlowLayout(spacing: 6, lineSpacing: Self.lineGap) {
                    ForEach(tokens) { token in
                        let isSpoken = current.map { token.id < $0 } ?? false
                        Text(token.text)
                            .font(Self.bodyFont)
                            .foregroundStyle(isSpoken ? Tokens.ink : Tokens.inkUnread)
                            .animation(.easeOut(duration: 0.25), value: isSpoken)
                            .id(token.id)
                    }
                }
                .padding(.horizontal, Spacing.margin)
                .padding(.vertical, Spacing.grid)
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            .onChange(of: current) { _, index in
                guard let index else { return }
                withAnimation(.smooth(duration: 0.5)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .accessibilityLabel(timings?.spoken ?? fallback)
    }
}

/// Words laid left to right and wrapped, each on its own baseline row — a paragraph out of views,
/// so one word can be lit on its own. Rows are as tall as their tallest word, and each row is
/// centred in the width (the owner, 2026-09-15: "the text and the boxes are in the center"), which
/// a plain `Text` would do with `.multilineTextAlignment(.center)` but a layout has to do itself:
/// rows are gathered first, then placed, since a row's inset is only known once it is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(in: width, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: width.isFinite ? width : widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// The words gathered into rows, each row's width being its words and the gaps between them.
    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, next > width {
                rows.append(row)
                row = Row()
                row.indices = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.indices.append(index)
                row.width = next
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
