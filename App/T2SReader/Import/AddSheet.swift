// App/T2SReader/Import/AddSheet.swift
import SwiftUI
import T2SApp
import T2SStore
import UniformTypeIdentifiers

/// Spec §2.4.5 rev 7: three soft pills, then the chosen path in place. The first imported document
/// is written back through `imported`; the owner opens it from the sheet's `onDismiss`, never from
/// here — presenting the player while this sheet is still animating out is the classic SwiftUI case
/// where the second sheet simply never appears.
struct AddSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Binding var imported: DocumentSummary?

    enum Path { case link, text, files }
    @State private var path: Path?
    @State private var showFilePicker = false

    var body: some View {
        let model = env.importModel
        VStack(alignment: .leading, spacing: Spacing.section) {
            Text("Add").typeRole(.sectionHeader).foregroundStyle(Tokens.ink).padding(.top, Spacing.section)
            switch path {
            case nil:
                VStack(spacing: 12) {
                    option("Paste a link", "link") { path = .link }
                    option("Open a file", "doc") { path = .files; showFilePicker = true }
                    option("Paste text", "text.alignleft") { path = .text }
                }
            case .link:
                PasteLinkPage()
            case .text:
                PasteTextPage()
            case .files:
                FileImportRows()
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Spacing.sheetCorner)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.epub, .pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await model.importFiles(urls) }
            case .failure: path = nil
            }
        }
        .onChange(of: model.phase) { _, phase in
            if case .done(let docs) = phase, let first = docs.first {
                imported = first
                dismiss()
            }
        }
        .onDisappear { model.reset() }
    }

    private func option(_ label: String, _ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: glyph).font(.system(size: 17, weight: .medium)).frame(width: 24)
                Text(label).typeRole(.rowTitle)
                Spacer()
            }
            .foregroundStyle(Tokens.ink)
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(Tokens.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
