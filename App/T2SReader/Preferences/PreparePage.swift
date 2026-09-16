import Foundation
import SwiftUI
import T2SApp
import T2SCore
import T2SStore

/// Settings → Prepare on charge (owner, 2026-09-14). It used to be a section of the Storage page —
/// four chips reading "1 hour · 3 hours · 8 hours · Everything" directly above four more reading
/// "536.9 MB · 1.07 GB · 2.15 GB · 4.29 GB", which taught a reader that the two rows were the same
/// kind of dial when one was a budget of *listening* and the other a ceiling on *disk*.
///
/// Off that page, the question turns out not to need a number at all. It needs a switch, a when,
/// and a what — and the what is books.
struct PreparePage: View {
    @Environment(AppEnvironment.self) private var env
    @State private var picking: DocumentSummary?
    /// Document → how many of its picked chapters are still to make, and how many chapters it has
    /// in total. Read once when the page appears; a book with one chapter is picked from the row.
    @State private var outstanding: [UUID: PickState] = [:]

    struct PickState: Equatable {
        var chapterCount: Int
        var pickedChapters: Int
        var isSingleChapter: Bool { chapterCount <= 1 }
    }

    var body: some View {
        @Bindable var settings = env.prepareSettings
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                PageTitle(text: "Prepare on charge", topPadding: Spacing.subpageTitleTop)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Prepare while charging").typeRole(.settingsRow).foregroundStyle(Tokens.ink)
                        Spacer(minLength: 8)
                        Toggle("", isOn: $settings.isEnabled).labelsHidden()
                    }
                    Text("Audio is made while you charge, so listening later costs no battery.")
                        .typeRole(.meta).foregroundStyle(Tokens.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if settings.isEnabled {
                    when
                    what
                    if settings.mode == .picked { picks }
                    ready
                }

                Color.clear.frame(height: Spacing.bottomClearance)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .settingsSubpage()
        .task { await reload() }
        // Coming back from the chapter sheet, the counts have moved.
        .onChange(of: picking == nil) { _, closed in if closed { Task { await reload() } } }
        .onChange(of: env.prepareSettings.mode) { _, _ in Task { await reload() } }
        .sheet(item: $picking) { summary in
            PreparePickSheet(summary: summary)
                .presentationDetents([.large])
        }
    }

    // MARK: - When

    @ViewBuilder private var when: some View {
        @Bindable var settings = env.prepareSettings
        section("When") {
            FlowRow(spacing: 8) {
                ForEach(PrepareWindow.allCases, id: \.self) { window in
                    Pill(label: window.label, style: settings.window == window ? .selected : .soft) {
                        settings.window = window
                    }
                }
            }
            Text(settings.window == .overnight
                 ? "Between \(hour(PrepareWindow.overnightStartHour)) and \(hour(PrepareWindow.overnightEndHour)). Your iPhone decides exactly when — we only ever say no outside these hours."
                 : "Whenever the iPhone is on a charger and not busy.")
                .typeRole(.meta).foregroundStyle(Tokens.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - What

    @ViewBuilder private var what: some View {
        @Bindable var settings = env.prepareSettings
        section("What") {
            SettingsGroup {
                modeRow(.keepUp, title: "Keep up with my reading",
                        subtitle: "The chapter you're in, in every book.")
                modeRow(.picked, title: "Only what I pick", subtitle: nil, separator: true)
            }
        }
    }

    private func modeRow(_ mode: PrepareMode, title: String, subtitle: String?, separator: Bool = false) -> some View {
        Button {
            env.prepareSettings.mode = mode
        } label: {
            SettingsGroupRow(title: title, subtitle: subtitle, separator: separator) {
                RadioMark(isOn: env.prepareSettings.mode == mode)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(env.prepareSettings.mode == mode ? .isSelected : [])
    }

    // MARK: - The picks

    /// Every document in one list. A book with chapters carries a count and opens the chapter
    /// sheet; a document with one chapter — a PDF, an article — has no sheet worth opening, so the
    /// row itself is the switch.
    @ViewBuilder private var picks: some View {
        let summaries = env.libraryModel.summaries
        section("Books") {
            if summaries.isEmpty {
                Text("Nothing imported yet.").typeRole(.meta).foregroundStyle(Tokens.ink2)
            } else {
                SettingsGroup {
                    ForEach(Array(ordered(summaries).enumerated()), id: \.element.id) { index, summary in
                        pickRow(summary, separator: index > 0)
                    }
                }
                Text("Picked chapters are made on the next charge, then leave this list.")
                    .typeRole(.meta).foregroundStyle(Tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Picked books first, so the list is also the answer to "what have I picked"; the rest keep
    /// the library's own order under them.
    private func ordered(_ summaries: [DocumentSummary]) -> [DocumentSummary] {
        let picked = env.prepareSettings.picks
        return summaries.sorted { a, b in
            let left = picked[a.id] != nil, right = picked[b.id] != nil
            return left == right ? false : left
        }
    }

    @ViewBuilder private func pickRow(_ summary: DocumentSummary, separator: Bool) -> some View {
        let state = outstanding[summary.id]
        let count = env.prepareSettings.chapters(for: summary.id).count
        if state?.isSingleChapter == true {
            Button {
                env.prepareSettings.toggleChapter(0, for: summary.id)
            } label: {
                SettingsGroupRow(title: summary.document.title, separator: separator, isQuiet: count == 0) {
                    RadioMark(isOn: count > 0)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button {
                picking = summary
            } label: {
                SettingsGroupRow(title: summary.document.title,
                                 value: count > 0 ? "\(count) \(count == 1 ? "chapter" : "chapters")" : "—",
                                 separator: separator,
                                 isQuiet: count == 0) {
                    RowChevron()
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Proof it is working

    @ViewBuilder private var ready: some View {
        let storage = env.storage
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Ready to listen").typeRole(.meta).foregroundStyle(Tokens.ink2)
            Spacer(minLength: 8)
            Text(DurationFormatter.long(storage.preparedSeconds))
                .typeRole(.metaStrong).foregroundStyle(Tokens.ink).monospacedDigit()
        }
    }

    // MARK: -

    private func reload() async {
        await env.libraryModel.refresh()
        await env.storage.refresh()
        env.prepareSettings.prunePicks(keeping: Set(env.libraryModel.summaries.map(\.id)))

        var states: [UUID: PickState] = [:]
        for summary in env.libraryModel.summaries {
            // `currentTimeline`, never `timelineForPlayback`: a settings page must not pay to
            // re-derive a stale book, and a book we cannot read the chapters of is simply one the
            // reader picks whole.
            guard let timeline = try? await env.library.currentTimeline(summary.id) else {
                states[summary.id] = PickState(chapterCount: 1, pickedChapters: 0)
                continue
            }
            // A picked chapter already on the device leaves the pick here too, so the list reads as
            // what is still to do whether or not a pass has run since (`PrepareRunner` does the
            // same from its own snapshot).
            let audio = await BookAudioStatus.read(timeline: timeline, audioStore: env.audioStore)
            for chapter in env.prepareSettings.chapters(for: summary.id)
            where audio.chapter(chapter)?.isFullyRendered == true {
                env.prepareSettings.clearPick(document: summary.id, chapter: chapter)
            }
            states[summary.id] = PickState(chapterCount: max(timeline.chapters.count, 1),
                                           pickedChapters: env.prepareSettings.chapters(for: summary.id).count)
        }
        outstanding = states
    }

    private func hour(_ value: Int) -> String {
        var components = DateComponents()
        components.hour = value
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).typeRole(.sectionHeader).foregroundStyle(Tokens.ink)
            content()
        }
    }
}

/// Picking one book's chapters for the next charge. The Book sheet's render mode, unchanged but
/// for the verb: there, the key spends the next ten minutes of battery making the chapters now;
/// here it spends nothing until the phone is on a charger.
struct PreparePickSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var summary: DocumentSummary

    @State private var chapters: [ChapterEntry] = []
    @State private var audio = BookAudioStatus()
    @State private var selection: Set<Int> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.document.title).typeRole(.groupTitle).foregroundStyle(Tokens.ink)
                    if let author = summary.document.displayAuthor {
                        Text(author).typeRole(.meta).foregroundStyle(Tokens.ink2)
                    }
                }
                .padding(.top, Spacing.section)

                ChapterListView(chapters: chapters, current: nil, variant: .book,
                                renderMarks: marks,
                                headerAllAction: pickableChapters.isEmpty ? nil : { pickAll() },
                                headerAllLabel: "Pick all",
                                onSelect: { chapter in toggle(chapter.index) })
                    .padding(.horizontal, -12)                             // the rows' fill runs into the margin
                Color.clear.frame(height: Spacing.section)
            }
            .padding(.horizontal, Spacing.margin)
        }
        .background(Tokens.raised)
        .presentationCornerRadius(Spacing.sheetCorner)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.grid) {
                BarButton(label: keyLabel, tone: selection.isEmpty ? .ink : .blue) {
                    env.prepareSettings.setChapters(selection, for: summary.id)
                    dismiss()
                }
            }
            .padding(.horizontal, Spacing.margin)
            .padding(.top, Spacing.grid * 2)
            .padding(.bottom, Spacing.grid)
            .background { BottomFade(color: Tokens.raised) }
        }
        .task { await load() }
    }

    /// "Done" when nothing is picked — it closes a sheet — and the count when something is, because
    /// that is a different act: it commits work the charger will do tonight.
    private var keyLabel: String {
        selection.isEmpty ? "Done" : "Prepare \(selection.count) \(selection.count == 1 ? "chapter" : "chapters")"
    }

    /// A chapter already on the device wears the size and the waveform rather than a ring: there is
    /// nothing left to prepare in it, so it is not pickable either.
    private var marks: [Int: ChapterRenderMark] {
        Dictionary(uniqueKeysWithValues: chapters.map { chapter in
            (chapter.index, ChapterRenderMark.mark(status: audio.chapter(chapter.index), job: nil,
                                                   isSelected: selection.contains(chapter.index)))
        })
    }

    private var pickableChapters: [Int] {
        chapters.map(\.index).filter { audio.chapter($0)?.isFullyRendered != true }
    }

    private func pickAll() { selection = Set(pickableChapters) }

    private func toggle(_ chapter: Int) {
        guard audio.chapter(chapter)?.isFullyRendered != true else { return }
        if selection.contains(chapter) { selection.remove(chapter) } else { selection.insert(chapter) }
    }

    private func load() async {
        selection = env.prepareSettings.chapters(for: summary.id)
        guard let timeline = try? await env.library.currentTimeline(summary.id) else { return }
        let progress = DocumentProgress.compute(summary: summary, timeline: timeline)
        chapters = ChapterEntry.entries(timeline: timeline, timeIndex: TimeIndex(timeline),
                                        elapsed: progress.elapsedSeconds)
        audio = await BookAudioStatus.read(timeline: timeline, audioStore: env.audioStore)
    }
}
