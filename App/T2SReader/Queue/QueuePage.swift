// App/T2SReader/Queue/QueuePage.swift
import SwiftUI
import T2SApp
import T2SStore

struct QueuePage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.readerRoute) private var readerRoute
    @State private var showAdd = false
    /// Set by the Import page; opened from its `onDismiss`, once it has actually gone.
    @State private var pendingOpen: DocumentSummary?
    @State private var details: DocumentSummary?

    private var rows: [DocumentSummary] { env.libraryModel.visibleRows }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                if rows.isEmpty {
                    // Header's Import pill is the only control; nothing else to show here.
                } else {
                    SectionHeader(title: "Continue Listening")
                        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                }
                ForEach(rows) { summary in
                    QueueRow(summary: summary, onOpen: {
                        readerRoute.open(summary)
                    }, onDetails: { details = summary })
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { Task { await env.libraryModel.archive(summary.id) } } label: { Label("Archive", systemImage: "archivebox") }
                            .tint(Tokens.destructive)
                    }
                }
                Color.clear.frame(height: Spacing.bottomClearance)        // room for the mini-player, indicator and their fade
                    .listRowInsets(EdgeInsets())
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)            // the pager's ground shows through, and the warm-up wash with it
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await env.libraryModel.refresh() }
        .fullScreenCover(isPresented: $showAdd, onDismiss: openPending) { ImportPage(imported: $pendingOpen) }
        .sheet(item: $details) { DetailsSheet(summary: $0) }
    }

    private func openPending() {
        guard let doc = pendingOpen else { return }
        pendingOpen = nil
        readerRoute.open(doc)
    }

    /// Search lives on Collection now; Home's one control is the way in.
    private var header: some View {
        HStack(alignment: .top) {
            PageTitle(text: "Home")
            Spacer(minLength: 12)
            Pill(label: "Import", glyph: "plus", style: .soft) { showAdd = true }
                .accessibilityLabel("Import")
                .padding(.top, Spacing.titleTop + 4)
        }
    }
}
