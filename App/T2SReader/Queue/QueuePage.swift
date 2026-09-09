// App/T2SReader/Queue/QueuePage.swift
import SwiftUI
import T2SApp
import T2SStore

struct QueuePage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.readerRoute) private var readerRoute
    @State private var showAdd = false
    /// Set by the Add sheet; opened from its `onDismiss`, once it has actually gone.
    @State private var pendingOpen: DocumentSummary?
    @State private var details: DocumentSummary?
    @State private var searchText = ""
    @State private var isSearching = false

    private var rows: [DocumentSummary] {
        let all = env.libraryModel.visibleRows
        guard isSearching, !searchText.isEmpty else { return all }
        return all.filter { $0.document.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                if isSearching {
                    TextField("Search", text: $searchText)
                        .typeRole(.rowTitle)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Tokens.surface, in: Capsule())
                        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                }
                if rows.isEmpty {
                    if isSearching {
                        Text("No matches.")
                            .typeRole(.meta).foregroundStyle(Tokens.ink2)
                            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                    } else {
                        EmptyQueue { showAdd = true }
                            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.margin, bottom: Spacing.row, trailing: Spacing.margin))
                    }
                } else if !isSearching {
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
                Color.clear.frame(height: 120)                            // room for the mini-player and indicator
                    .listRowInsets(EdgeInsets())
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Tokens.ground)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Tokens.ground)
        .refreshable { await env.libraryModel.refresh() }
        .sheet(isPresented: $showAdd, onDismiss: openPending) { AddSheet(imported: $pendingOpen) }
        .sheet(item: $details) { DetailsSheet(summary: $0) }
    }

    private func openPending() {
        guard let doc = pendingOpen else { return }
        pendingOpen = nil
        readerRoute.open(doc)
    }

    private var header: some View {
        HStack(alignment: .top) {
            PageTitle(text: "Home")
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.ink).frame(width: 36, height: 36)
                        .background(Tokens.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add")
                Pill(label: isSearching ? "Done" : "Search", style: isSearching ? .selected : .soft) {
                    withAnimation(.snappy) { isSearching.toggle(); if !isSearching { searchText = "" } }
                }
            }
            .padding(.top, Spacing.titleTop + 4)
        }
    }
}
