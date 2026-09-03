// App/T2SReader/Import/PasteTextPage.swift
import SwiftUI
import T2SApp

struct PasteTextPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var title = ""
    @State private var body_ = ""

    var body: some View {
        let model = env.importModel
        VStack(alignment: .leading, spacing: 16) {
            TextField("Title (optional)", text: $title)
                .typeRole(.rowTitle)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Tokens.surface, in: Capsule())
            TextEditor(text: $body_)
                .typeRole(.rowTitle)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 160)
                .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if case .importing = model.phase {
                HStack(spacing: 10) { ProgressView().tint(Tokens.ink); Text("Importing…").typeRole(.meta).foregroundStyle(Tokens.ink2) }
            } else {
                Pill(label: "Listen", glyph: "play.fill", style: .accent) { Task { await model.importText(title: title, body: body_) } }
            }
            if case .failed(let message) = model.phase {
                Text(message).typeRole(.meta).foregroundStyle(Tokens.destructive)
            }
        }
    }
}
