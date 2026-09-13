import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

/// One chapter the reader asked to have on the device now. `rendered` counts what the *store*
/// holds, not what this job produced, so a chapter the fill tier already got halfway through opens
/// at its true progress rather than at zero.
public struct ChapterRenderJob: Identifiable, Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case queued
        case running
        case ready
        /// Some part of the chapter never became audio. The string is written for the reader: it is
        /// what the toast and the row say.
        case failed(String)
    }

    public var documentID: UUID
    public var chapterIndex: Int
    public var title: String
    /// Utterances in the chapter — the denominator, not the work left to do.
    public var utteranceCount: Int
    /// How many of them the store holds.
    public var rendered: Int
    public var state: State

    /// Derived rather than stored, so it cannot drift from the chapter it names: the queue is keyed
    /// by this string, and that identity is the whole of "do not queue a chapter twice".
    public var id: String { Self.id(documentID: documentID, chapterIndex: chapterIndex) }

    /// 0…1. A chapter with no utterances reads as 0 rather than dividing by zero; it is also the
    /// shape of a job whose document could not be read at all, which the queue fails rather than
    /// shows as complete.
    public var fraction: Double {
        guard utteranceCount > 0 else { return 0 }
        return min(1, max(0, Double(rendered) / Double(utteranceCount)))
    }

    public init(documentID: UUID, chapterIndex: Int, title: String, utteranceCount: Int,
                rendered: Int = 0, state: State = .queued) {
        self.documentID = documentID
        self.chapterIndex = chapterIndex
        self.title = title
        self.utteranceCount = utteranceCount
        self.rendered = rendered
        self.state = state
    }

    public static func id(documentID: UUID, chapterIndex: Int) -> String {
        "\(documentID.uuidString)-\(chapterIndex)"
    }
}

/// The foreground, reader-initiated "render this chapter" queue — one for the whole app, drained
/// strictly one job at a time.
///
/// It renders at ``RenderTier/manual`` through a `RenderScheduler` that shares the app's one
/// `RenderArbiter`, which is the point of the design: "one render at a time", "playback wins", and
/// "don't fight Prepare" are then inherited from the arbiter's lease rather than reimplemented here
/// as conditionals in the subsystem playback depends on.
///
/// It owns no player and never calls `load()`, so a chapter of a book you are not listening to can
/// be rendered without quietly becoming the book you are listening to.
@MainActor
@Observable
public final class ChapterRenderRunner {
    /// Why the queue is stopped with work still in it. None of them is an error, and all of them
    /// keep the running chapter's progress: the job goes back to the head of the queue with what it
    /// has, and picks up from there (owner, 2026-09-13: thermal pause and pause-on-demand are the
    /// same pause, and differ only in the sentence they carry).
    public enum Hold: Hashable, Sendable {
        /// The reader pressed Pause. Cleared only by ``resume()``; nothing about the device can
        /// clear it, which is the whole of "on demand".
        case byReader
        /// `thermalSerious` or Low Power Mode. Lifts on its own when the phone cools, and
        /// ``resume()`` overrides it for the rest of this drain.
        case hot
        /// The store refused a write. Not overridable — the constraint is real, and the way out is
        /// Settings → Storage.
        case storeFull
    }

    /// What one drain of the queue came to, for the single toast the design asks for: one summary
    /// when the queue empties, not one message per chapter.
    public struct Completion: Hashable, Sendable {
        public var ready: Int
        public var failed: Int
        public init(ready: Int, failed: Int) {
            self.ready = ready
            self.failed = failed
        }
    }

    /// Every job this session has been asked for, in the order asked. Finished jobs stay so a row
    /// can keep reporting what became of it; ``cancelAll()`` is what clears the list.
    public private(set) var queue: [ChapterRenderJob] = []
    public private(set) var hold: Hold?
    /// Whether the reader has already put this hold's notice away. The notice is app-wide now — it
    /// is drawn over whatever is frontmost, not only inside the book sheet — so it needs a way to
    /// be dismissed that is not "fix the phone", and the flag belongs with the hold rather than in
    /// one of the three views that draw it. Cleared whenever the hold changes, so a second reason
    /// to stop is a second notice.
    public private(set) var holdNoticeDismissed = false
    /// The last drain's tally, for the toast. Nil until one drain has finished with work in it.
    public private(set) var lastCompletion: Completion?

    /// True while anything is outstanding — held included, since a held queue is work waiting, not
    /// work finished.
    public var isWorking: Bool {
        queue.contains { $0.state == .queued || $0.state == .running }
    }

    /// Applied only to documents without their own override, mirroring `PlayerModel` and
    /// `PrepareRunner`.
    public var defaultVoiceID: String?
    /// The same resolver the player and Prepare use, so a chapter rendered here is the audio
    /// playback will actually ask for (spec §6).
    public var voiceRouting: any VoiceRouteResolving = PassthroughVoiceRouting()
    /// How long a chapter's rendered metadata may sit unwritten while the job is still in it. The
    /// audio is already on disk under its key, so this bounds what a crash costs in re-derivation,
    /// not correctness — the same trade `PrepareRunner` makes.
    public var chapterWriteInterval: TimeInterval = 10

    private let library: Library
    private let store: LibraryStore
    private let audioStore: any AudioStore
    private let engine: any SynthesisEngine
    private let arbiter: RenderArbiter
    private let timeSource: any TimeSource
    /// Paces renders against iOS's background CPU limit (`CPUBudget`) when the app hands one over.
    /// A chapter render deliberately continues while backgrounded, which is exactly the case the
    /// budget exists for.
    private let cpuBudget: CPUBudget?

    private var device: DeviceState = .unplugged
    /// ``resume()``: ignores heat until the queue drains, then forgets itself. Deliberately not
    /// persisted, so it cannot quietly become the permanent setting.
    private var ignoringHeat = false
    /// ``pause()``. Outranks every other reason to be stopped: if the reader paused, "you paused
    /// this" is the true answer even on a phone that has since gone warm.
    private var pausedByReader = false
    /// Set by the scheduler's `.storeFull`; cleared when the device next reports room, which is what
    /// makes "evict something in Settings → Storage" the way out rather than a relaunch.
    private var storeRefused = false
    private var drainTask: Task<Void, Never>?
    private var cancelTask: Task<Void, Never>?
    private var currentScheduler: RenderScheduler?

    public init(library: Library, store: LibraryStore, audioStore: any AudioStore,
                engine: any SynthesisEngine, arbiter: RenderArbiter,
                timeSource: any TimeSource = SystemTimeSource(), budget: CPUBudget? = nil) {
        self.library = library
        self.store = store
        self.audioStore = audioStore
        self.engine = engine
        self.arbiter = arbiter
        self.timeSource = timeSource
        self.cpuBudget = budget
    }

    // MARK: Enqueueing

    /// Appends the chapters that are not already waiting and starts the drain if nothing is running.
    /// Appending while a job runs simply appends: there is one queue for the app, never a second one
    /// started alongside the first.
    public func enqueue(documentID: UUID, chapters: [Int]) async {
        await enqueue(documentID: documentID, chapters: chapters, loaded: await load(documentID))
    }

    /// The book's resume chapter, or chapter 0 when it has never been played — Home's row menu,
    /// which must not `load()` the book to find out.
    public func enqueueResumeChapter(of documentID: UUID) async {
        let loaded = await load(documentID)
        var chapter = 0
        if let loaded {
            let resume = Library.renderSnapshot(for: loaded.document, timeline: loaded.timeline).resumeIndex
            chapter = loaded.timeline.chapterIndex(forUtterance: resume) ?? 0
        }
        // An unreadable document still gets a job: it is the job that carries the failure message,
        // and without a row there is nothing for the reader's tap to have produced.
        await enqueue(documentID: documentID, chapters: [chapter], loaded: loaded)
    }

    private func enqueue(documentID: UUID, chapters: [Int], loaded: Loaded?) async {
        for chapterIndex in chapters where chapterIndex >= 0 {
            let job = makeJob(documentID: documentID, chapterIndex: chapterIndex, loaded: loaded)
            if let existing = queue.firstIndex(where: { $0.id == job.id }) {
                // Already waiting or under way: leave it alone rather than restart its progress. A
                // finished job is replaced, which is how a failed chapter is retried.
                guard queue[existing].state != .queued, queue[existing].state != .running else { continue }
                queue[existing] = job
            } else {
                queue.append(job)
            }
        }
        startDraining()
    }

    /// What the row shows before the job runs. `rendered` comes from the timeline's `audioRef`s, at
    /// no cost — the run checks those against the store and corrects the count, which is the only
    /// place the answer has to be exact.
    private func makeJob(documentID: UUID, chapterIndex: Int, loaded: Loaded?) -> ChapterRenderJob {
        guard let timeline = loaded?.timeline, timeline.chapters.indices.contains(chapterIndex) else {
            return ChapterRenderJob(documentID: documentID, chapterIndex: chapterIndex,
                                    title: "Chapter \(chapterIndex + 1)", utteranceCount: 0)
        }
        let chapter = timeline.chapters[chapterIndex]
        return ChapterRenderJob(documentID: documentID, chapterIndex: chapterIndex, title: chapter.title,
                                utteranceCount: chapter.utterances.count,
                                rendered: chapter.utterances.count { $0.audioRef != nil })
    }

    // MARK: Cancelling and holding

    /// Drops one job. The running job's scheduler is cancelled with it; the utterance in flight is
    /// allowed to finish and be stored, since half a clip is worth nothing and a whole one is cache.
    public func cancel(_ jobID: String) {
        guard let index = queue.firstIndex(where: { $0.id == jobID }) else { return }
        let wasRunning = queue[index].state == .running
        queue.remove(at: index)
        if wasRunning { stopScheduler() }
    }

    public func cancelAll() {
        queue.removeAll()
        ignoringHeat = false
        storeRefused = false
        pausedByReader = false
        updateHold()
        stopScheduler()
    }

    /// Stops the queue where it stands, at the reader's word. The chapter in flight keeps the
    /// utterances it has already stored and goes back to the head of the queue — the same thing
    /// heat does to it, because it is the same mechanism.
    public func pause() {
        guard !pausedByReader else { return }
        pausedByReader = true
        updateHold()
        stopScheduler()
    }

    /// The one Resume, for either reason to be stopped. From the reader's own pause it simply
    /// starts again; from heat it is also the override — pressing Resume on a warm phone means
    /// "render anyway", and like every such override it lapses when the queue drains. There is
    /// nothing it can do about `.storeFull`: that constraint is real, and the way out is Settings →
    /// Storage.
    public func resume() {
        pausedByReader = false
        if device.thermalSerious || device.lowPowerMode { ignoringHeat = true }
        startDraining()
    }

    /// The old name for the heat half of ``resume()``, which is what the held-queue sheet's
    /// "Continue anyway" has always meant.
    public func continueAnyway() { resume() }

    /// Whether the reader is the reason nothing is happening.
    public var isPaused: Bool { hold == .byReader }

    /// Called by the app when `DeviceMonitor`'s state changes. Heat and Low Power Mode stop the
    /// queue where it stands; room in the store releases a `.storeFull` hold without a relaunch.
    public func deviceStateChanged(_ state: DeviceState) {
        device = state
        if !state.storeFull { storeRefused = false }
        updateHold()
        if hold == nil {
            startDraining()
        } else {
            // The running job goes back to the head of the queue with its progress: the utterances
            // already on disk are skipped when it resumes.
            stopScheduler()
        }
    }

    private var blockingHold: Hold? {
        if pausedByReader { return .byReader }
        if storeRefused || device.storeFull { return .storeFull }
        if !ignoringHeat, device.thermalSerious || device.lowPowerMode { return .hot }
        return nil
    }

    /// The reader has read the notice. Only the notice goes: the queue stays held, and a new hold
    /// — or the same one arriving again after it lifted — says so again.
    public func dismissHoldNotice() { holdNoticeDismissed = true }

    /// A hold is a queue stopped with work still in it, so an empty queue is never held: a phone
    /// that happens to be hot must not make the sheet claim it is holding something back.
    private func updateHold() {
        let next = isWorking ? blockingHold : nil
        if next != hold { holdNoticeDismissed = false }
        hold = next
    }

    /// The scheduler is an actor and this is the main one, so the cancellation is a hop away; the
    /// utterance already in the engine finishes and is stored, and nothing after it starts.
    private func stopScheduler() {
        let scheduler = currentScheduler
        cancelTask = Task { await scheduler?.cancel() }
    }

    // MARK: Draining

    private func startDraining() {
        updateHold()
        guard drainTask == nil, hold == nil, queue.contains(where: { $0.state == .queued }) else { return }
        drainTask = Task { await self.drainQueue() }
    }

    /// One job at a time, in the order they were asked for, until the queue has nothing queued left
    /// or a hold stops it. Nothing here decides priority: the arbiter does, at every batch boundary.
    private func drainQueue() async {
        var completion = Completion(ready: 0, failed: 0)
        while true {
            updateHold()
            guard hold == nil, let next = queue.first(where: { $0.state == .queued }) else { break }
            setState(next.id, .running)
            await run(next.id)
            switch queue.first(where: { $0.id == next.id })?.state {
            case .ready: completion.ready += 1
            case .failed: completion.failed += 1
            default: break                                  // held back to `.queued`, or cancelled away
            }
        }
        drainTask = nil
        if completion.ready > 0 || completion.failed > 0 { lastCompletion = completion }
        // The override buys one drain, not a setting: once there is nothing queued it lapses, and
        // the next request meets the heat again.
        if !isWorking { ignoringHeat = false }
    }

    /// Renders whatever of one chapter the store does not already hold, writing each utterance's
    /// reference, duration and word timings back as they land.
    private func run(_ jobID: String) async {
        guard let job = queue.first(where: { $0.id == jobID }) else { return }
        let documentID = job.documentID
        let chapterIndex = job.chapterIndex

        guard let loaded = await load(documentID) else {
            // A document mid-re-derivation has no current timeline, and a deleted one has nothing at
            // all. Either way this job is done and the queue goes on (design §Error handling).
            let stale = (try? await store.isStale(id: documentID)) ?? false
            setState(jobID, .failed(stale ? "This book changed since it was imported. Open it once, then try again."
                                          : "This book is no longer available."))
            return
        }
        guard loaded.timeline.chapters.indices.contains(chapterIndex) else {
            setState(jobID, .failed("This chapter is no longer part of the book."))
            return
        }

        let range = loaded.timeline.utteranceRange(ofChapter: chapterIndex)
        update(jobID) {
            $0.title = loaded.timeline.chapters[chapterIndex].title
            $0.utteranceCount = range.count
        }

        // Only an utterance whose reference already matches the voice and versions in force can be a
        // cache hit; those are checked against the store in one hop and the rest are simply
        // unrendered (`PrepareRunner.loadDocuments`). Skipping them is what makes this cooperate
        // with `chapterAhead` instead of rendering the same audio a second time.
        var chapter: [(index: Int, key: RenderKey)] = []
        var candidates: [(index: Int, key: RenderKey)] = []
        for index in range {
            let key = renderKey(documentID: documentID, utteranceIndex: index, voiceID: loaded.voiceID,
                                timeline: loaded.timeline)
            chapter.append((index, key))
            if loaded.timeline[utterance: index].audioRef == key.rawValue { candidates.append((index, key)) }
        }
        let present = await audioStore.contains(candidates.map(\.key))
        var done = Set(zip(candidates, present).filter(\.1).map(\.0.index))
        update(jobID) { $0.rendered = done.count }

        let requests = chapter.filter { !done.contains($0.index) }.map { utterance in
            RenderRequest(job: RenderJob(documentID: documentID, utteranceIndex: utterance.index, tier: .manual),
                          key: utterance.key,
                          spoken: loaded.timeline[utterance: utterance.index].spoken,
                          voiceID: loaded.voiceID)
        }
        guard !requests.isEmpty else {
            setState(jobID, .ready)
            return
        }

        let scheduler = RenderScheduler(engine: engine, store: audioStore, timeSource: timeSource,
                                        arbiter: arbiter, budget: cpuBudget)
        currentScheduler = scheduler
        var timeline = loaded.timeline
        var dirty = false
        var failures = 0
        // Counted from before the plan is set, so the first flush cannot be missed under load.
        var lastWrite = timeSource.now()
        _ = await scheduler.setPlan(requests)

        func flush() async {
            guard dirty else { return }
            do {
                try await store.saveChapter(timeline.chapters[chapterIndex], at: chapterIndex, of: documentID)
                dirty = false
            } catch {
                // Stays dirty and the next flush retries it. The audio is on disk under its key
                // either way, and a lost write self-heals on the document's next load.
            }
            lastWrite = timeSource.now()
        }

        events: for await event in scheduler.events {
            switch event {
            case .rendered(let rendered):
                guard rendered.documentID == documentID, range.contains(rendered.utteranceIndex) else { continue }
                var utterance = timeline[utterance: rendered.utteranceIndex]
                // A cache hit carries no word timings; the ones already on the utterance are then the
                // better record (`PrepareRunner`).
                let useNewTimings = !rendered.wordTimings.isEmpty || (utterance.wordTimings ?? []).isEmpty
                if utterance.audioRef != rendered.key.rawValue || utterance.duration != .actual(rendered.duration)
                    || (useNewTimings && utterance.wordTimings != rendered.wordTimings) {
                    utterance.audioRef = rendered.key.rawValue
                    utterance.duration = .actual(rendered.duration)
                    if useNewTimings { utterance.wordTimings = rendered.wordTimings }
                    timeline[utterance: rendered.utteranceIndex] = utterance
                    dirty = true
                }
                done.insert(rendered.utteranceIndex)
                update(jobID) { $0.rendered = done.count }
                if timeSource.now() - lastWrite >= chapterWriteInterval { await flush() }
            case .piece:
                continue                                    // a chapter render never streams
            case .failed:
                // The scheduler stores 200 ms of silence and still emits `.rendered` (spec §6), so
                // the count advances and the queue does not stall on one bad sentence.
                failures += 1
            case .storeFull:
                storeRefused = true
                await scheduler.cancel()
            case .idle:
                break events
            }
        }
        // Always, and before the job yields its place: a resumed job re-reads the timeline, and an
        // unwritten `audioRef` would make it plan audio the store already holds.
        await flush()
        currentScheduler = nil

        guard let final = queue.first(where: { $0.id == jobID }) else { return }   // cancelled under us
        updateHold()
        if failures == 0, final.rendered >= final.utteranceCount {
            setState(jobID, .ready)
        } else if hold != nil {
            setState(jobID, .queued)                        // stays at the head, with what it has
        } else if failures > 0 {
            setState(jobID, .failed("\(failures) of \(final.utteranceCount) sentences could not be rendered."))
        } else {
            setState(jobID, .failed("Stopped after \(final.rendered) of \(final.utteranceCount) sentences."))
        }
    }

    // MARK: Helpers

    /// Everything one job needs about its document, read without loading it into the player.
    private struct Loaded {
        var document: Document
        var timeline: Timeline
        var voiceID: String
    }

    private func load(_ id: UUID) async -> Loaded? {
        guard let document = try? await store.document(id: id),
              let timeline = try? await library.currentTimeline(id)
        else { return nil }
        // The same voice route playback will render with, delivery included, so what this puts on
        // the device is the audio the next tap plays.
        let voiceID = Delivery.applied(to: await voiceRouting.effectiveVoiceID(document.voiceID ?? defaultVoiceID ?? "default"))
        return Loaded(document: document, timeline: timeline, voiceID: voiceID)
    }

    private func renderKey(documentID: UUID, utteranceIndex: Int, voiceID: String, timeline: Timeline) -> RenderKey {
        RenderKey(documentID: documentID, utteranceIndex: utteranceIndex, voiceID: voiceID,
                  engineID: engine.engineID, normalizerVersion: timeline.normalizerVersion,
                  segmenterVersion: timeline.segmenterVersion)
    }

    /// Jobs are addressed by id rather than index throughout: a cancellation can remove one from
    /// under a running job, and an index taken before an `await` would then name someone else's.
    private func update(_ jobID: String, _ change: (inout ChapterRenderJob) -> Void) {
        guard let index = queue.firstIndex(where: { $0.id == jobID }) else { return }
        change(&queue[index])
    }

    private func setState(_ jobID: String, _ state: ChapterRenderJob.State) {
        update(jobID) { $0.state = state }
    }

    /// Waits for the drain in flight; tests only.
    func awaitDrain() async { await drainTask?.value }

    /// Waits for the cancellation a hold or a `cancel` sent to the running scheduler; tests only,
    /// so one can be sure the scheduler has stopped taking work before releasing a held engine.
    func awaitSchedulerCancel() async { await cancelTask?.value }
}
