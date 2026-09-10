// App/T2SReader/Import/PasteTextPage.swift
import SwiftUI
import T2SApp

/// "Write text" (ElevenReader's page, the owner's reference, 2026-09-09): a bare title line, the
/// text itself under it, and one Import bar at the foot that stays grey until there is text (it
/// was Listen while the import played by itself; now the done step offers Play).
struct PasteTextPage: View {
    @Environment(AppEnvironment.self) private var env
    var onBack: (() -> Void)?
    @State private var title = ""
    @State private var body_ = ""
    @FocusState private var focused: Bool

    var body: some View {
        let model = env.importModel
        let hasText = !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ImportFrame(title: "Write text", onBack: onBack, action: action(for: model, hasText: hasText)) {
            VStack(alignment: .leading, spacing: Spacing.row) {
                TextField("Title (optional)", text: $title)
                    .typeRole(.sectionHeader)
                    .foregroundStyle(Tokens.ink)
                    .submitLabel(.next)
                    .onSubmit { focused = true }
                TextEditor(text: $body_)
                    .typeRole(.rowTitle)
                    .foregroundStyle(Tokens.ink)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)                                          // the page scrolls; the editor grows
                    .focused($focused)
                    .frame(minHeight: 200)
                    .overlay(alignment: .topLeading) {
                        if body_.isEmpty {
                            Text("Write or paste text…")
                                .typeRole(.rowTitle).foregroundStyle(Tokens.ink2)
                                .padding(.top, 8).padding(.leading, 5)                 // the editor's own text inset
                                .allowsHitTesting(false)
                        }
                    }
                if case .failed(let message) = model.phase {
                    Text(message).typeRole(.meta).foregroundStyle(Tokens.destructive)
                }
            }
        }
        .onAppear { focused = true }
    }

    private func action(for model: ImportModel, hasText: Bool) -> ImportAction? {
        if case .importing = model.phase { return .init(label: "Import", busyLabel: "Importing…", perform: {}) }
        return .init(label: "Import", isEnabled: hasText) {
            focused = false
            Task { await model.importText(title: title, body: body_) }
        }
    }
}
