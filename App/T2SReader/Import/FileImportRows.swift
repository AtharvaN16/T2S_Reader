// App/T2SReader/Import/FileImportRows.swift
import SwiftUI
import T2SApp

/// "Upload a file" as a bottom sheet over the hub (owner, 2026-09-17), rather than a step that
/// replaced the whole page. A file picker is itself a sheet, so the step it is opened from has no
/// business owning the screen: the hub stays visible behind, and dismissing by drag is the same
/// gesture as dismissing the picker.
///
/// The page it replaces was almost empty — a title, one grey line and the key at the foot — which
/// is what the owner was looking at when they asked for the picture. `FileMark` fills it: a plain
/// document while there is nothing chosen, a spinner while the library takes one, a green tick once
/// a file is in. The rows under it name each file and where its import stands.
struct FileImportSheet: View {
    @Environment(AppEnvironment.self) private var env
    var choose: () -> Void

    var body: some View {
        let model = env.importModel
        VStack(spacing: 0) {
            Text("Upload a file").typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
                .padding(.top, Spacing.row)
            FileMark(stage: stage(for: model))
                .padding(.top, Spacing.row)
            Text("EPUB and PDF files from Files, iCloud Drive or another app.")
                .typeRole(.meta).foregroundStyle(Tokens.ink2)
                .multilineTextAlignment(.center)
                .padding(.top, Spacing.row)
                .padding(.horizontal, Spacing.margin)
            if !model.fileRows.isEmpty || isFailed(model) {
                ScrollView {
                    FileImportRows().padding(.horizontal, Spacing.margin)
                }
                .padding(.top, Spacing.row)
            }
            Spacer(minLength: Spacing.row)
            BarButton(label: "Choose files",
                      busyLabel: isImporting(model) ? "Importing…" : nil,
                      isEnabled: true,
                      action: choose)
                .padding(.horizontal, Spacing.margin)
                .padding(.bottom, Spacing.grid * 2)
        }
        .frame(maxWidth: .infinity)
        .background(Tokens.ground)
    }

    /// The picture's state, read off the model: a tick the moment anything has landed, so the sheet
    /// says "you have a file" before the done step says what the file was.
    private func stage(for model: ImportModel) -> FileMark.Stage {
        if isImporting(model) { return .working }
        let landed = model.fileRows.contains { if case .done = $0.state { return true } else { return false } }
        return landed ? .ready : .waiting
    }

    private func isImporting(_ model: ImportModel) -> Bool {
        if case .importing = model.phase { return true }
        return false
    }

    private func isFailed(_ model: ImportModel) -> Bool {
        if case .failed = model.phase { return true }
        return false
    }
}

/// The rows themselves: the file's name and where its import stands.
struct FileImportRows: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = env.importModel
        VStack(alignment: .leading, spacing: 16) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
