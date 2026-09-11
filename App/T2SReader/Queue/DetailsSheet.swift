// App/T2SReader/Queue/DetailsSheet.swift
import SwiftUI
import T2SApp
import T2SStore

/// Context-menu "Details": what the library knows about a document, and a place to delete it
/// (delete removes from Queue and Collection both, spec §2.3; the Collection's menus offer it too,
/// and every path asks first and goes through `AppEnvironment.deleteDocument`).
struct DetailsSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var summary: DocumentSummary
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.document.title).typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                if let author = summary.document.author { Text(author).typeRole(.meta).foregroundStyle(Tokens.ink2) }
            }
            VStack(alignment: .leading, spacing: 12) {
                row("Source", summary.document.sourceType.rawValue.uppercased())
                if let url = summary.document.sourceURL { row("Link", url.absoluteString) }
                row("Added", summary.document.addedAt.formatted(date: .abbreviated, time: .shortened))
                row("Chapters", "\(summary.chapterCount)")
                row("Length", DurationFormatter.long(summary.totalSeconds, approximate: !summary.isFullyRendered))
                row("Rendered", summary.utteranceCount > 0 ? "\(summary.renderedCount * 100 / summary.utteranceCount)%" : "—")
            }
            Spacer()
            Pill(label: "Reprocess", glyph: "arrow.clockwise", style: .soft) {
                Task {
                    if await env.player.performDestructiveChange(for: summary.id, {
                        _ = try await env.library.reprocess(summary.id)
                    }) {
                        await env.libraryModel.refresh()
                    }
                }
            }
            Text("Re-reads the file with the current pronunciation dictionary. Rendered audio is discarded.")
                .typeRole(.meta)
                .foregroundStyle(Tokens.ink2)
            Pill(label: "Delete from library", glyph: "trash", style: .destructiveSoft) { confirmDelete = true }
        }
        .padding(Spacing.margin)
        .padding(.top, Spacing.grid)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("Delete “\(summary.document.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete from this device", role: .destructive) {
                Task { await env.deleteDocument(summary.id); dismiss() }
            }
            if env.syncModel.isEnabled {
                Button("Delete everywhere", role: .destructive) {
                    Task { await env.deleteDocument(summary.id, everywhere: true); dismiss() }
                }
            }
        } message: {
            Text(env.syncModel.isEnabled ? AppEnvironment.deleteMessageWithSync : AppEnvironment.deleteMessage)
        }
        .presentationBackground(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).typeRole(.meta).foregroundStyle(Tokens.ink2).frame(width: 84, alignment: .leading)
            Text(value).typeRole(.rowTitle).foregroundStyle(Tokens.ink).textSelection(.enabled)
        }
    }
}
