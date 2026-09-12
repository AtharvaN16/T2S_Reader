import Foundation
import SwiftUI
import T2SApp

/// Preferences → Storage (spec §2.4.5): prepare-on-charge budget, prepared amount and last run,
/// cache size and cap, per-document eviction — and the voice model, which is the largest thing the
/// app puts on the phone and the one a reader comes here to reclaim.
struct StoragePage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmsVoiceModelDelete = false

    var body: some View {
        let storage = env.storage
        @Bindable var preferences = env.preferences
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                PageTitle(text: "Storage")
                if env.kokoroModel.isSupported {
                    section("Voice model") { voiceModel }
                }
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
                Color.clear.frame(height: Spacing.bottomClearance)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .settingsSubpage()                                                 // paints the (warm) ground
        .task { await storage.refresh() }
        .task { env.kokoroModel.refresh() }
        // A download that finishes while the page is open leaves the size stale otherwise.
        .onChange(of: env.kokoroStatus.status) { _, _ in env.kokoroModel.refresh() }
    }

    /// The on-device voice: what it occupies, and the one pill that changes it. Delete asks first —
    /// it stops playback and costs a 620 MB download to undo — and download says what it will spend.
    @ViewBuilder private var voiceModel: some View {
        let model = env.kokoroModel
        Text(voiceModelLine)
            .typeRole(.meta)
            .foregroundStyle(Tokens.ink2)
            .fixedSize(horizontal: false, vertical: true)
        switch env.kokoroStatus.status {
        case .removed:
            Pill(label: "Download", glyph: "arrow.down.circle", style: .soft) { model.download() }
        case .installing, .checking, .preparing:
            EmptyView()                                                    // the veil is already saying so
        case .notLinked, .unavailable:
            EmptyView()
        case .available:
            Pill(label: model.isDeleting ? "Deleting…" : "Delete", style: .destructiveSoft) {
                confirmsVoiceModelDelete = true
            }
            .disabled(model.isDeleting)
            .confirmationDialog("Delete the voice model?", isPresented: $confirmsVoiceModelDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await env.deleteVoiceModel() } }
                Button("Keep", role: .cancel) {}
            } message: {
                Text(Self.voiceModelDeleteMessage)
            }
        }
    }

    /// What the section says above its pill: the size while the model is here, what was freed and
    /// what a download costs once it is gone, and the install's own progress while one runs.
    private var voiceModelLine: String {
        let measurement = env.kokoroModel.measurement
        func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
        switch env.kokoroStatus.status {
        case .removed:
            return "Removed from this device. Books play with the system voice until it is downloaded again (about 620 MB, over Wi-Fi)."
        case .installing:
            guard let progress = env.kokoroStatus.installProgress else { return "Downloading…" }
            switch progress {
            case .waitingForNetwork: return "Waiting for Wi-Fi…"
            case .downloading(let done, let total): return "Downloading… \(bytes(Int64(done))) of \(bytes(Int64(total)))"
            case .retrying(let attempt, let of, _, _): return "Downloading… (attempt \(attempt) of \(of))"
            case .compiling(let stage, let total): return "Preparing… \(stage) of \(total)"
            }
        case .checking, .preparing:
            return "Preparing the voice for this device…"
        case .notLinked, .unavailable:
            return "This device speaks with the system voice; there is no model to store."
        case .available:
            return "\(bytes(measurement.total)) on this device · \(bytes(measurement.model)) model, \(bytes(measurement.plans)) compute plans"
        }
    }

    /// Said before a delete, because both halves of it surprise a reader who is told neither: what
    /// is playing stops, and the model does not come back on its own.
    static let voiceModelDeleteMessage = "Playback stops, and books play with the system voice. The model is not downloaded again until you ask for it here — about 620 MB, over Wi-Fi."

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
            content()
        }
    }
}
