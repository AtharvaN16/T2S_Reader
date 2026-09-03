import Foundation
import SwiftUI
import T2SApp

/// Preferences → Storage (spec §2.4.5): prepare-on-charge budget, prepared amount and last run,
/// cache size and cap, per-document eviction.
struct StoragePage: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let storage = env.storage
        @Bindable var preferences = env.preferences
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                PageTitle(text: "Storage")
                section("Prepare on charge") {
                    Text("Render ahead while charging, so listening later costs no battery.")
                        .typeRole(.meta)
                        .foregroundStyle(Tokens.ink2)
                    HStack(spacing: 8) {
                        ForEach(ReaderPreferences.prepareBudgetOptions, id: \.seconds) { option in
                            Pill(
                                label: option.label,
                                style: preferences.prepareBudgetSeconds == option.seconds ? .selected : .soft
                            ) {
                                preferences.prepareBudgetSeconds = option.seconds
                            }
                        }
                    }
                    Text(
                        "Prepared: \(DurationFormatter.long(storage.preparedSeconds)) · Last run: \(storage.lastPrepareRun.map { DurationFormatter.age(of: $0) + " ago" } ?? "never")"
                    )
                    .typeRole(.meta)
                    .foregroundStyle(Tokens.ink2)
                }
                section("Rendered audio") {
                    Text(
                        "\(ByteCountFormatter.string(fromByteCount: Int64(storage.stats.bytes), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(storage.stats.capacityBytes), countStyle: .file)) · \(storage.stats.entries) clips"
                    )
                    .typeRole(.meta)
                    .foregroundStyle(Tokens.ink2)
                    HStack(spacing: 8) {
                        ForEach(StorageModel.capacityOptions, id: \.self) { bytes in
                            Pill(
                                label: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file),
                                style: storage.stats.capacityBytes == bytes ? .selected : .soft
                            ) {
                                Task { await storage.setCapacity(bytes) }
                            }
                        }
                    }
                }
                section("Per document") {
                    ForEach(storage.rows) { row in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.summary.document.title)
                                    .typeRole(.rowTitle)
                                    .foregroundStyle(Tokens.ink)
                                    .lineLimit(1)
                                ProgressBar(fraction: row.renderedFraction)
                            }
                            Text("\(Int((row.renderedFraction * 100).rounded()))%")
                                .typeRole(.mono)
                                .foregroundStyle(Tokens.ink2)
                            Pill(label: "Evict", style: .destructiveSoft) {
                                Task { await storage.evict(row.id) }
                            }
                            .disabled(row.renderedFraction == 0)
                        }
                    }
                }
                if let error = storage.lastError {
                    Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive)
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.ground)
        .task { await storage.refresh() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
            content()
        }
    }
}
