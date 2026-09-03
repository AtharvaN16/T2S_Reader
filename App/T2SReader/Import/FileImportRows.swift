// App/T2SReader/Import/FileImportRows.swift
import SwiftUI
import T2SApp

/// One row per chosen file with its state; the sheet closes itself when the batch ends with a success.
struct FileImportRows: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = env.importModel
        VStack(alignment: .leading, spacing: 16) {
            if model.fileRows.isEmpty {
                Text("Choose EPUB or PDF files.").typeRole(.meta).foregroundStyle(Tokens.ink2)
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
