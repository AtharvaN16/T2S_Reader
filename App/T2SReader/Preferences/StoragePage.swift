import Foundation
import SwiftUI
import T2SApp

/// Preferences → Storage (spec §2.4.5), rebuilt 2026-09-14 on the owner's read of it: one picture
/// of what the app is holding, then the three things it holds, in descending order of what they
/// cost you — the voice, the cache's ceiling, and the books' audio.
///
/// What left: the prepare-on-charge budget, which is about *making* audio and now has its own page
/// (`PreparePage`); the per-document progress bar and its "2%", which measured utterances on a
/// screen whose unit is megabytes; and the word Evict, which the Book sheet had already replaced
/// with Delete.
struct StoragePage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmsVoiceModelDelete = false
    @State private var confirmsPlansClear = false
    @State private var confirmsDeleteAll = false
    @State private var pendingRowDelete: StorageModel.Row?

    var body: some View {
        let storage = env.storage
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                PageTitle(text: "Storage")
                usage
                if env.kokoroModel.isSupported { voice }
                limit
                documents
                if let error = storage.lastError {
                    Text(error).typeRole(.meta).foregroundStyle(Tokens.destructive)
                }
                Color.clear.frame(height: Spacing.bottomClearance)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .settingsSubpage()
        .task { await env.storage.refresh() }
        .task { env.kokoroModel.refresh() }
        // A download that finishes while the page is open leaves the size stale otherwise.
        .onChange(of: env.kokoroStatus.status) { _, _ in env.kokoroModel.refresh() }
    }

    // MARK: - What the app is holding

    /// The one picture: the total, cut into its bands, with the room left on the phone under it.
    /// Not a budget — nothing here caps the app — so the bands are drawn against their own total
    /// and the only ceiling on the page keeps to its own heading below.
    @ViewBuilder private var usage: some View {
        let storage = env.storage
        let measurement = env.kokoroModel.measurement
        let voiceBytes = env.kokoroModel.isSupported ? Int(measurement.model) : 0
        let planBytes = env.kokoroModel.isSupported ? Int(measurement.plans) : 0
        let total = voiceBytes + planBytes + storage.stats.bytes + storage.documentsBytes

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(size(total)).typeRole(.playerTitle).foregroundStyle(Tokens.ink).monospacedDigit()
                Text("used by this app").typeRole(.meta).foregroundStyle(Tokens.ink2)
            }
            StorageBar(bands: [
                .init(label: "Voice", bytes: voiceBytes, color: Tokens.glow),
                .init(label: "Speed-up", bytes: planBytes, color: Tokens.glow.opacity(0.35)),
                .init(label: "Audio", bytes: storage.stats.bytes, color: Tokens.accent),
                .init(label: "Books", bytes: storage.documentsBytes, color: Tokens.ink),
            ])
            HStack {
                Text("Free on this iPhone").typeRole(.meta).foregroundStyle(Tokens.ink2)
                Spacer(minLength: 8)
                Text(ByteCountFormatter.string(fromByteCount: storage.freeBytes, countStyle: .file))
                    .typeRole(.metaStrong).foregroundStyle(Tokens.ink).monospacedDigit()
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Voice

    /// The model and its compute plans as two rows, because they are two things with wildly
    /// different prices: one costs a 620 MB download to undo, the other costs the next warm-up and
    /// nothing at all over the network (owner, 2026-09-14).
    @ViewBuilder private var voice: some View {
        let model = env.kokoroModel
        let measurement = model.measurement
        section("Voice") {
            switch env.kokoroStatus.status {
            case .removed:
                SettingsGroup {
                    SettingsGroupRow(title: "Voice model", subtitle: "Books read with the system voice") {
                        RowAction(label: "Download") { model.download() }
                    }
                }
            case .installing, .checking, .preparing:
                SettingsGroup {
                    SettingsGroupRow(title: "Voice model", subtitle: installingSubtitle)
                }
            case .notLinked, .unavailable:
                Text("This iPhone reads with the system voice. There is nothing to store.")
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            case .available:
                SettingsGroup {
                    SettingsGroupRow(title: "Voice model", value: size(Int(measurement.model))) {
                        RowAction(label: model.isDeleting ? "Deleting…" : "Delete",
                                  isDestructive: true, isEnabled: !model.isDeleting) {
                            confirmsVoiceModelDelete = true
                        }
                    }
                    SettingsGroupRow(title: "Speed-up files", value: size(Int(measurement.plans)), separator: true) {
                        RowAction(label: model.isClearingPlans ? "Clearing…" : "Clear",
                                  isEnabled: !model.isClearingPlans) {
                            confirmsPlansClear = true
                        }
                    }
                }
                Text("Deleting the model costs a 620 MB download. Speed-up files are built here and rebuild themselves free.")
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("Delete the voice model?", isPresented: $confirmsVoiceModelDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await env.deleteVoiceModel() } }
            Button("Keep", role: .cancel) {}
        } message: {
            Text(Self.voiceModelDeleteMessage)
        }
        .confirmationDialog("Clear the speed-up files?", isPresented: $confirmsPlansClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { Task { await env.kokoroModel.clearPlans() } }
            Button("Keep", role: .cancel) {}
        } message: {
            Text(Self.plansClearMessage)
        }
    }

    private var installingSubtitle: String {
        func bytes(_ value: Int) -> String { size(value) }
        switch env.kokoroStatus.installProgress {
        case .waitingForNetwork: return "Waiting for Wi-Fi…"
        case .downloading(let done, let total): return "Downloading… \(bytes(done)) of \(bytes(total))"
        case .retrying(let attempt, let of, _, _): return "Downloading… attempt \(attempt) of \(of)"
        case .compiling(let stage, let total): return "Preparing… \(stage) of \(total)"
        case nil: return "Preparing for this iPhone…"
        }
    }

    // MARK: - The cache's ceiling

    /// The only limit on the screen, and the heading says exactly what it governs (owner,
    /// 2026-09-14). The chips wrap rather than overflow, and their labels are rounded — "512 MB",
    /// not "536.9 MB" — which is most of why four of them now fit between the margins.
    @ViewBuilder private var limit: some View {
        let storage = env.storage
        section("Limit for rendered audio") {
            // `FlowRow`, not `HStack`: a row of `fixedSize` pills has no give, so the row itself is
            // what has to break. Without it the four chips ran straight past the page's right
            // margin (owner, 2026-09-14) — and they would again at any larger text size.
            FlowRow(spacing: 8) {
                ForEach(StorageModel.capacityOptions, id: \.self) { bytes in
                    Pill(label: StorageModel.capacityLabel(bytes),
                         style: storage.stats.capacityBytes == bytes ? .selected : .soft) {
                        Task { await storage.setCapacity(bytes) }
                    }
                }
            }
            Text("\(size(storage.stats.bytes)) used. Over the limit, the audio you played longest ago goes first — it can always be made again.")
                .typeRole(.meta).foregroundStyle(Tokens.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Per document

    /// Name, size, trash. Nothing else: an article, a PDF and a 24-chapter book are the same shape
    /// of row, sorted by what they cost, and a book holding nothing is a number at the foot rather
    /// than a row with a dead control on it.
    @ViewBuilder private var documents: some View {
        let storage = env.storage
        section("Rendered audio") {
            if storage.rows.isEmpty {
                Text(storage.documentsWithoutAudio == 0
                     ? "No books yet."
                     : "No audio on this device yet. It is made as you listen, and while you charge.")
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SettingsGroup {
                    ForEach(Array(storage.rows.enumerated()), id: \.element.id) { index, row in
                        SettingsGroupRow(title: row.summary.document.title,
                                         value: size(row.bytes),
                                         separator: index > 0) {
                            Button { pendingRowDelete = row } label: {
                                // The chapter row's trash exactly — same glyph, same size, same red.
                                Image(systemName: "trash")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Tokens.destructive)
                                    .frame(width: 24, height: 24)
                                    .padding(10)
                                    .contentShape(Rectangle())
                                    .padding(-10)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete this book's audio")
                        }
                    }
                }
                if storage.documentsWithoutAudio > 0 {
                    Text("\(storage.documentsWithoutAudio) other \(storage.documentsWithoutAudio == 1 ? "book has" : "books have") no audio on this device.")
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
                }
                Pill(label: storage.isDeletingAll ? "Deleting…" : "Delete all",
                     style: .destructiveSoft) { confirmsDeleteAll = true }
                    .disabled(storage.isDeletingAll)
            }
        }
        .confirmationDialog(pendingRowDelete.map { "Delete “\($0.summary.document.title)” audio?" } ?? "",
                            isPresented: Binding(get: { pendingRowDelete != nil },
                                                 set: { if !$0 { pendingRowDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let row = pendingRowDelete { Task { await env.storage.evict(row.id) } }
                pendingRowDelete = nil
            }
            Button("Keep", role: .cancel) { pendingRowDelete = nil }
        } message: {
            Text("The book stays. Its audio is made again as you listen, or while you charge.")
        }
        .confirmationDialog("Delete all rendered audio?", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await env.storage.deleteAll() } }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Every book keeps its place and its bookmarks. Only the audio goes, and it is made again as you listen.")
        }
    }

    /// Said before a delete, because both halves of it surprise a reader who is told neither: what
    /// is playing stops, and the model does not come back on its own.
    static let voiceModelDeleteMessage = "Playback stops, and books play with the system voice. The model is not downloaded again until you ask for it here — about 620 MB, over Wi-Fi."

    /// The cheap half, said plainly: nothing is downloaded, and the cost is one slow start.
    static let plansClearMessage = "Nothing is downloaded again — these are built on this iPhone. The next book you play takes about a minute to start while they are rebuilt."

    private func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
            content()
        }
    }
}
