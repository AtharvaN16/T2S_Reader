// App/T2SReader/Import/ImportPage.swift
import SwiftUI
import T2SApp
import T2SStore
import UniformTypeIdentifiers

/// Spec §2.4.5 rev 7: a picture and three rows, then the chosen path as its own step on `ImportFrame` — a back
/// circle, a centred title, the path's field, and one Listen bar at the foot (ElevenReader's
/// import, the owner's reference, 2026-09-09). An import that lands does not play by itself any
/// more (owner, 2026-09-10): the page moves to `ImportDonePage`, which shows what came in, a Play
/// pill per book and Done at the foot. A pill writes that document back through `imported`; the
/// owner opens it from the cover's `onDismiss`, never from here — presenting the player while this
/// page is still animating out is the classic SwiftUI case where the second presentation simply
/// never appears. Done leaves `imported` nil, so nothing opens.
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

    var body: some View {
        let model = env.importModel
        // No Back when the page opened on files from another app: there was no choice to return
        // to. Back also clears the model, so a failure from one path is not shown under the next.
        let back: (() -> Void)? = initialFiles.isEmpty ? { model.reset(); path = nil } : nil
        Group {
            if case .done(let documents) = model.phase {
                ImportDonePage(documents: documents,
                               play: { imported = $0; dismiss() },
                               done: { dismiss() })
            } else {
                switch path {
                case .link: PasteLinkPage(onBack: back)
                case .text: PasteTextPage(onBack: back)
                case .files: FileImportPage(onBack: back) { showFilePicker = true }
                case nil: hub
                }
            }
        }
        .background(Tokens.ground)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.epub, .pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await model.importFiles(urls) }
            case .failure: break                                               // the step stays; Choose files is there again
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

    /// The three ways in, as rows under a picture and two lines (owner, 2026-09-16, from a reference
    /// import sheet). They were two columns of tiles, which had room for a word each and so could
    /// only name a path, never say what it takes; a row carries the formats on a second line, which
    /// is the question this page is actually asked — "will it take my PDF?". The page's big `Import`
    /// title goes with them: the headline over the picture says it, centred, the way the empty
    /// shelves do, and the only thing left in the top row is the way out.
    private var hub: some View {
        ScrollView {
            VStack(spacing: 0) {
                closeRow
                ImportGraphic()
                VStack(spacing: 8) {
                    Text("Bring anything in").typeRole(.playerTitle).foregroundStyle(Tokens.ink)
                    Text("A book, a paper, a page you saved, or your own words.")
                        .typeRole(.rowTitle).foregroundStyle(Tokens.ink2)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.row)
                VStack(spacing: 12) {
                    // The file row leads: it is the heaviest path, and the only one with formats
                    // worth naming. The same sentence greets an empty file step (`FileImportRows`),
                    // so a reader who taps through is told the same thing twice rather than first.
                    way("Upload a file", "EPUB and PDF, from Files or iCloud Drive.", "doc") {
                        path = .files
                        showFilePicker = true
                    }
                    way("Paste a link", "Any article or web page.", "link") { path = .link }
                    way("Write or paste text", "Notes, an email, anything you've copied.", "text.alignleft") { path = .text }
                }
                .padding(.top, Spacing.section)
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.section)
        }
        .overlay { GeometryReader { geo in TopFade(inset: geo.safeAreaInsets.top) } }
    }

    /// The way out, alone in the top row where the page title used to be — the reference's shape,
    /// and the one the import steps already wear (`ImportFrame`'s bar, at the same height).
    private var closeRow: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: { CircleGlyph(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
        }
        .padding(.top, Spacing.grid * 2)
    }

    /// One of the three ways in: a glyph on its own disc, the path's name, a line saying what it
    /// takes, and a chevron, on a `surface` card at the tiles' own 20 pt corner. The disc is
    /// `ground` — the page's colour, carried up onto the card — so the glyph reads as set into the
    /// row rather than laid on it, in both themes.
    private func way(_ title: String, _ detail: String, _ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: glyph)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Tokens.ink)
                    .frame(width: 44, height: 44)
                    .background(Tokens.ground, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                    Text(detail).typeRole(.meta).foregroundStyle(Tokens.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.ink2)
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}
