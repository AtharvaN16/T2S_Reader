// App/T2SReader/Player/ChapterList.swift
import SwiftUI
import T2SApp

/// The `Chapter 3 ▾` row's sheet: title and duration per chapter, current chapter marked, tap to jump.
struct ChapterList: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let player = env.player
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Chapters").typeRole(.sectionHeader).foregroundStyle(Tokens.ink).padding(.top, Spacing.section)
                ForEach(player.chapters) { chapter in
                    Button {
                        Task { await player.seek(toChapter: chapter.index); dismiss() }
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(chapter.index == player.chapterIndex ? Tokens.ink : Tokens.ink3).frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(chapter.title).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(1)
                                ProgressBar(fraction: chapter.fraction)
                            }
                            Text(DurationFormatter.long(chapter.durationSeconds, approximate: player.isTotalApproximate))
                                .typeRole(.mono).foregroundStyle(Tokens.ink2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }
}
