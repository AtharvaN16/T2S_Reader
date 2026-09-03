// App/T2SReader/Import/PasteLinkPage.swift
import SwiftUI
import T2SApp
import UIKit

/// URL field prefilled from the clipboard, one `accent` "Listen" pill, then the extraction preview
/// in place (title, site, first lines, word count) with "Listen" and "Cancel".
struct PasteLinkPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let model = env.importModel
        VStack(alignment: .leading, spacing: 20) {
            switch model.phase {
            case .preview(let article):
                VStack(alignment: .leading, spacing: 10) {
                    Text(article.content.title).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                    HStack(spacing: 6) {
                        if let site = article.content.siteName { Text(site); Text("·") }
                        Text("\(article.wordCount) words")
                    }
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    Text(String(article.plainText.prefix(280))).typeRole(.meta).foregroundStyle(Tokens.ink2).lineLimit(5)
                    if model.isThinPreview {
                        Text("This looks thin — the page may not have a readable article.").typeRole(.meta).foregroundStyle(Tokens.destructive)
                    }
                }
                HStack(spacing: 8) {
                    Pill(label: "Listen", glyph: "play.fill", style: .accent) { Task { await model.confirmPreview() } }
                    Pill(label: "Cancel", style: .soft) { model.reset() }
                }
            case .fetching:
                HStack(spacing: 10) { ProgressView().tint(Tokens.ink); Text("Fetching…").typeRole(.meta).foregroundStyle(Tokens.ink2) }
            case .importing:
                HStack(spacing: 10) { ProgressView().tint(Tokens.ink); Text("Importing…").typeRole(.meta).foregroundStyle(Tokens.ink2) }
            default:
                TextField("https://", text: $text)
                    .typeRole(.rowTitle)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Tokens.surface, in: Capsule())
                    .onSubmit { fetch() }
                Pill(label: "Listen", glyph: "play.fill", style: .accent) { fetch() }
                if case .failed(let message) = model.phase {
                    Text(message).typeRole(.meta).foregroundStyle(Tokens.destructive)
                }
            }
        }
        .onAppear {
            if text.isEmpty, UIPasteboard.general.hasURLs, let url = UIPasteboard.general.url { text = url.absoluteString }
            focused = text.isEmpty
        }
    }

    private func fetch() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        Task { await env.importModel.fetch(link: URL(string: candidate) ?? URL(string: "invalid://")!) }
    }
}
