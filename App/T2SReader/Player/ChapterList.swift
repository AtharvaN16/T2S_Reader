// App/T2SReader/Player/ChapterList.swift
import SwiftUI
import T2SApp

/// The chapter row's sheet (after Apple Podcasts' chapter list, owner's ask 2026-09-09): one row
/// per chapter — its name over its length — with generous air between rows, the current chapter on
/// a `surface` fill, and at the right end a ring of how far through the current one we are, a check
/// for each chapter already heard. Tap to jump.
struct ChapterList: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let player = env.player
        let current = player.chapterIndex
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Chapters").typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
                    .padding(.top, Spacing.section)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                ForEach(player.chapters) { chapter in
                    let isCurrent = chapter.index == current
                    let isHeard = current.map { chapter.index < $0 } ?? false
                    Button {
                        Task { await player.seek(toChapter: chapter.index); dismiss() }
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ChapterLabel.text(for: chapter.title, ordinal: chapter.index + 1))
                                    .typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(DurationFormatter.remaining(chapter.durationSeconds, approximate: false))
                                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                            }
                            Spacer(minLength: 12)
                            if isCurrent {
                                CircularProgress(fraction: chapter.fraction, lineWidth: 2, size: 18)
                            } else if isHeard {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Tokens.ink2)
                                    .accessibilityLabel("Heard")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(isCurrent ? Tokens.surface : Tokens.surface.opacity(0),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    .accessibilityValue(isCurrent ? "\(Int((chapter.fraction * 100).rounded())) percent" : (isHeard ? "Heard" : ""))
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
