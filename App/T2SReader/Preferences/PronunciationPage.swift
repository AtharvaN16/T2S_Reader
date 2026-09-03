import SwiftUI
import T2SApp
import T2SCore

struct PronunciationPage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var editing: PronunciationEntry?
    @State private var adding = false

    var body: some View {
        let model = env.pronunciation
        List {
            Section {
                PageTitle(
                    text: "Pronunciation",
                    subtitle: "Say names and jargon your way. Applies to documents imported or reprocessed from now on."
                )
                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))

                Pill(label: "Add word", glyph: "plus", style: .soft) { adding = true }
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))

                ForEach(model.entries) { entry in
                    Button { editing = entry } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.term).typeRole(.rowTitle).foregroundStyle(Tokens.ink)
                            Text("→ \(entry.replacement)\(entry.caseSensitive ? " · case-sensitive" : "")")
                                .typeRole(.meta)
                                .foregroundStyle(Tokens.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: 20, trailing: Spacing.margin))
                    .swipeActions(edge: .trailing) {
                        Button { Task { await model.delete(id: entry.id) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(Tokens.destructive)
                    }
                }
                Color.clear.frame(height: 120).listRowInsets(EdgeInsets())
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Tokens.ground)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Tokens.ground)
        .task { await model.refresh() }
        .sheet(isPresented: $adding) { PronunciationEditor(entry: nil) }
        .sheet(item: $editing) { PronunciationEditor(entry: $0) }
    }
}

private struct PronunciationEditor: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var entry: PronunciationEntry?
    @State private var term = ""
    @State private var replacement = ""
    @State private var caseSensitive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(entry == nil ? "Add word" : "Edit word")
                .typeRole(.sectionHeader)
                .foregroundStyle(Tokens.ink)
                .padding(.top, Spacing.section)
            TextField("Word or name", text: $term)
                .typeRole(.rowTitle)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Tokens.surface, in: Capsule())
            TextField("Say it as", text: $replacement)
                .typeRole(.rowTitle)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Tokens.surface, in: Capsule())
            Toggle(isOn: $caseSensitive) {
                Text("Match case").typeRole(.rowTitle).foregroundStyle(Tokens.ink)
            }
            .tint(Tokens.ink)
            Pill(label: "Save", style: .accent) {
                Task {
                    await env.pronunciation.save(
                        term: term,
                        replacement: replacement,
                        caseSensitive: caseSensitive,
                        id: entry?.id
                    )
                    dismiss()
                }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.margin)
        .background(Tokens.raised)
        .presentationDetents([.medium])
        .presentationCornerRadius(Spacing.sheetCorner)
        .onAppear {
            if let entry {
                term = entry.term
                replacement = entry.replacement
                caseSensitive = entry.caseSensitive
            }
        }
    }
}
