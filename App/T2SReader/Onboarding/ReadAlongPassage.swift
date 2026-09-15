// App/T2SReader/Onboarding/ReadAlongPassage.swift
import SwiftUI
import T2SApp

/// The hero's lines under the settled cover, read along: a faded, oversized cut of the Reader's
/// page (the owner, 2026-09-14: "our faded chapter reader interface for Alice moving, thick and
/// bigger font than what we use"). Words already spoken are ink, the word being spoken sits on
/// `accentSoft` as it does in the Reader, and the rest wait in `ink2`. The block scrolls itself so
/// the spoken word stays in the middle — the Reader's own following — and nothing else scrolls it.
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

    var body: some View {
        let tokens = tokens
        let current = current
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                FlowLayout(spacing: 7, lineSpacing: 2) {
                    ForEach(tokens) { token in
                        let isCurrent = token.id == current
                        let isSpoken = current.map { token.id < $0 } ?? false
                        Text(token.text)
                            .font(.custom("Inter-Bold", size: 22))
                            .foregroundStyle(isCurrent || isSpoken ? Tokens.ink : Tokens.ink2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isCurrent ? Tokens.accentSoft : .clear)
                            )
                            .padding(.horizontal, -4)
                            .id(token.id)
                    }
                }
                .padding(.horizontal, Spacing.margin)
                .padding(.vertical, 60)
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .onChange(of: current) { _, index in
                guard let index else { return }
                withAnimation(.smooth(duration: 0.5)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .accessibilityLabel(timings?.spoken ?? fallback)
    }
}

/// Words laid left to right and wrapped, each on its own baseline row — a paragraph out of views,
/// so one word can wear a highlight. Rows are as tall as their tallest word.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return place(in: width, subviews: subviews, apply: false, origin: .zero)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        _ = place(in: bounds.width, subviews: subviews, apply: true, origin: bounds.origin)
    }

    @discardableResult
    private func place(in width: CGFloat, subviews: Subviews, apply: Bool, origin: CGPoint) -> CGSize {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            if apply {
                subview.place(at: CGPoint(x: origin.x + x, y: origin.y + y), proposal: .unspecified)
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: width.isFinite ? width : widest, height: y + rowHeight)
    }
}
