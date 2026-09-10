// App/T2SReader/Import/PasteLinkPage.swift
import SwiftUI
import T2SApp
import UIKit

/// "Paste website link" (ElevenReader's page, the owner's reference, 2026-09-09): a bare address
/// field prefilled from the clipboard, a tip about the Share sheet, and one Import bar at the foot
/// (it was Listen while the import played by itself). Import fetches the page and, unless the extraction looks thin, imports it straight away; the
/// done step then offers Play or Done. Only a thin page stops to ask first: its title, its word
/// count, and "Import anyway".
struct PasteLinkPage: View {
    @Environment(AppEnvironment.self) private var env
    var onBack: (() -> Void)?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let model = env.importModel
        ImportFrame(title: "Paste website link", onBack: onBack, action: action(for: model)) {
            VStack(alignment: .leading, spacing: Spacing.row) {
                TextField("https://…", text: $text)
                    .typeRole(.rowTitle)
                    .foregroundStyle(Tokens.ink)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit { fetch() }
                if case .failed(let message) = model.phase {
                    Text(message).typeRole(.meta).foregroundStyle(Tokens.destructive)
                }
                if case .preview(let article) = model.phase, model.isThinPreview {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(article.content.title).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                        HStack(spacing: 6) {
                            if let site = article.content.siteName { Text(site); Text("·") }
                            Text("\(article.wordCount) words")
                        }
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
                        Text("This looks thin — the page may not have a readable article.")
                            .typeRole(.meta).foregroundStyle(Tokens.destructive)
                    }
                }
                tip
            }
        }
        .onAppear {
            if text.isEmpty, UIPasteboard.general.hasURLs, let url = UIPasteboard.general.url { text = url.absoluteString }
            focused = text.isEmpty
        }
        .onChange(of: model.phase) { _, phase in
            // A page that read fine goes straight in; there is nothing to confirm about it.
            if case .preview = phase, !model.isThinPreview { Task { await model.confirmPreview() } }
        }
    }

    /// The tip in the reference's card: a hairline box, the sentence, and the share extension's
    /// name ("Add to t2s") so the reader knows what to look for in the sheet.
    private var tip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tip: open any page in Safari and use Share to send it here.")
                .typeRole(.rowTitle).foregroundStyle(Tokens.ink)
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
                Text("Share  ›  Add to t2s")
            }
            .typeRole(.meta).foregroundStyle(Tokens.ink2)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Tokens.ink3, lineWidth: 0.5))
    }

    private func action(for model: ImportModel) -> ImportAction? {
        switch model.phase {
        case .fetching: return .init(label: "Import", busyLabel: "Fetching…", perform: {})
        case .importing: return .init(label: "Import", busyLabel: "Importing…", perform: {})
        case .preview where model.isThinPreview:
            return .init(label: "Import anyway") { Task { await model.confirmPreview() } }
        default:
            let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return .init(label: "Import", isEnabled: hasText, perform: fetch)
        }
    }

    private func fetch() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        focused = false
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        Task { await env.importModel.fetch(link: URL(string: candidate) ?? URL(string: "invalid://")!) }
    }
}
