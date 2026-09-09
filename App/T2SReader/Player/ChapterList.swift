// App/T2SReader/Player/ChapterList.swift
import SwiftUI
import T2SApp

/// The chapter row's sheet (after Apple Podcasts' chapter list, owner's ask 2026-09-09): one
/// `ChapterRow` per chapter, the current chapter on a `surface` fill. Tap to jump.
struct ChapterList: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let player = env.player
        let current = player.chapterIndex
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Chapters").typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                    .padding(.top, Spacing.section)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                ForEach(player.chapters) { chapter in
                    ChapterRow(chapter: chapter, isCurrent: chapter.index == current,
                               isHeard: current.map { chapter.index < $0 } ?? false) {
                        Task { await player.seek(toChapter: chapter.index); dismiss() }
                    }
                }
                Color.clear.frame(height: Spacing.section)
            }
            .padding(.horizontal, Spacing.margin - 12)                     // the fill's own 12 pt makes up the margin
        }
        .background(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}

/// One chapter, the same in the Reader's list and the Book sheet (owner's ask, 2026-09-09): its
/// name over its length, close-set, and at the right end a ring of how far through the current
/// one we are, or a `positive` check for a chapter already heard. The title sits a step under
/// `rowTitle` and the time a step over `meta`, so the two read closer in size.
struct ChapterRow: View {
    var chapter: ChapterEntry
    var isCurrent: Bool
    var isHeard: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ChapterLabel.text(for: chapter.title, ordinal: chapter.index + 1))
                        .typeRole(.settingsRow).foregroundStyle(Tokens.ink).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(DurationFormatter.remaining(chapter.durationSeconds, approximate: false))
                        .typeRole(.pill).foregroundStyle(Tokens.ink2)
                }
                Spacer(minLength: 12)
                if isCurrent {
                    CircularProgress(fraction: chapter.fraction, lineWidth: 2, size: 18)
                } else if isHeard {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Tokens.positive)
                        .accessibilityLabel("Heard")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isCurrent ? Tokens.surface : Tokens.surface.opacity(0),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityValue(isCurrent ? "\(Int((chapter.fraction * 100).rounded())) percent" : (isHeard ? "Heard" : ""))
    }
}
