// App/T2SReader/Import/ImportPage.swift
import SwiftUI
import T2SApp
import T2SStore
import UniformTypeIdentifiers

/// Spec §2.4.5 rev 7: three tiles, then the chosen path in place. The first imported document
/// is written back through `imported`; the owner opens it from the cover's `onDismiss`, never from
/// here — presenting the player while this page is still animating out is the classic SwiftUI case
/// where the second presentation simply never appears.
struct ImportPage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Binding var imported: DocumentSummary?
    /// Files handed to the app from elsewhere (`onOpenURL`): the page opens straight on the file
    /// path with the import already running, so the result and any failure are visible (spec §6).
    var initialFiles: [URL] = []

    enum Path { case link, text, files }
    @State private var path: Path?
    @State private var showFilePicker = false

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        let model = env.importModel
        // A ScrollView rather than a fixed stack so the link and text fields stay reachable with
        // the keyboard up.
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                header
                if let path {
                    VStack(alignment: .leading, spacing: Spacing.section) {
                        // No Back when the page opened on files from another app: there was no
                        // choice to return to. Back also clears the model, so a failure from one
                        // path is not shown under the next.
                        if initialFiles.isEmpty {
                            Pill(label: "Back", glyph: "chevron.left", style: .soft) { model.reset(); self.path = nil }
                        }
                        switch path {
                        case .link: PasteLinkPage()
                        case .text: PasteTextPage()
                        case .files: FileImportRows()
                        }
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        tile("Paste a link", "link") { path = .link }
                        tile("Upload a file", "doc") { path = .files; showFilePicker = true }
                        tile("Paste text", "text.alignleft") { path = .text }
                    }
                }
            }
            .padding(.horizontal, Spacing.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.ground)
        // A full-screen cover is its own presentation, so the theme is applied here as on the Reader.
        .appTheme()
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
        .task {
            if !initialFiles.isEmpty {
                path = .files
                await model.importFiles(initialFiles)
            }
        }
        .onDisappear { model.reset() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            PageTitle(text: "Import")
            Spacer(minLength: 12)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.ink).frame(width: 36, height: 36)
                    .background(Tokens.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(.top, Spacing.titleTop + 4)
        }
    }

    /// One of the three ways in: a tile rather than a row, so the choice reads as a menu, not a list.
    private func tile(_ label: String, _ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: glyph).font(.system(size: 24, weight: .medium))
                Text(label).typeRole(.rowTitle)
            }
            .foregroundStyle(Tokens.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 128)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
