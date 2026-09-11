// App/T2SReader/Import/FileImportRows.swift
import SwiftUI
import T2SApp

/// "Upload a file" on the shared frame: one row per chosen file with its state, and "Choose files"
/// at the foot to open the picker (again, if the first pick failed). When the batch ends with a
/// success the Import page moves on to the done step. No back circle when the files came in from
/// another app — the circle closes instead.
struct FileImportPage: View {
    @Environment(AppEnvironment.self) private var env
    var onBack: (() -> Void)?
    var choose: () -> Void

    var body: some View {
        let model = env.importModel
        ImportFrame(title: "Upload a file", onBack: onBack, action: action(for: model)) {
            FileImportRows()
        }
    }

    private func action(for model: ImportModel) -> ImportAction? {
        if case .importing = model.phase { return .init(label: "Choose files", busyLabel: "Importing…", perform: {}) }
        return .init(label: "Choose files", perform: choose)
    }
}

/// The rows themselves: the file's name and where its import stands.
struct FileImportRows: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = env.importModel
        VStack(alignment: .leading, spacing: 16) {
            if model.fileRows.isEmpty {
                Text("EPUB and PDF files from Files, iCloud Drive or another app.").typeRole(.meta).foregroundStyle(Tokens.ink2)
            }
            ForEach(model.fileRows) { row in
                HStack(spacing: 12) {
                    Image(systemName: "doc").foregroundStyle(Tokens.ink2)
                    Text(row.name).typeRole(.rowTitle).foregroundStyle(Tokens.ink).lineLimit(1)
                    Spacer()
                    switch row.state {
                    case .pending: Text("Waiting").typeRole(.meta).foregroundStyle(Tokens.ink2)
                    case .importing: ProgressView().tint(Tokens.ink)
                    case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.positive)
                    case .failed(let message): Text(message).typeRole(.meta).foregroundStyle(Tokens.destructive).lineLimit(2)
                    }
                }
            }
            if case .failed(let message) = model.phase, model.fileRows.isEmpty {
                Text(message).typeRole(.meta).foregroundStyle(Tokens.destructive)
            }
        }
    }
}
