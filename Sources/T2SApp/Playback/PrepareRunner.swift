import Foundation
import Observation
import T2SCore
import T2SLibrary
import T2SStore

/// Why an otherwise identical Prepare pass was requested. The reason is intentionally metadata
/// only: `RenderPolicy` remains the authority for every selected utterance.
public enum PrepareRunReason: Hashable, Sendable {
    case foreground
    case backgroundProcessing
    /// Spec §3.4.1 tier 2: the first ~30 s of one document, any power state.
    case prime
}

public enum PrepareSkipReason: Hashable, Sendable {
    case unsafeDevice
    case alreadyRunning
}

public enum PrepareStopReason: Hashable, Sendable {
    case completed
    case budgetExhausted
    case cancelled
    case storageFull
    case skipped(PrepareSkipReason)
}

public struct PrepareRunResult: Hashable, Sendable {
    public var reason: PrepareRunReason
    public var stopReason: PrepareStopReason
    public var documentIDs: [UUID]
    public var renderedUtterances: Int
    /// Playback-seconds durably rendered during this pass.
    public var preparedSeconds: TimeInterval
    /// Set only after at least one chapter write succeeds.
    public var recordedAt: Date?

    public init(reason: PrepareRunReason, stopReason: PrepareStopReason, documentIDs: [UUID] = [],
                renderedUtterances: Int = 0, preparedSeconds: TimeInterval = 0, recordedAt: Date? = nil) {
        self.reason = reason
        self.stopReason = stopReason
        self.documentIDs = documentIDs
        self.renderedUtterances = renderedUtterances
        self.preparedSeconds = preparedSeconds
        self.recordedAt = recordedAt
    }

    public var completedSuccessfully: Bool {
        stopReason == .completed || stopReason == .budgetExhausted
    }
}

/// Executes tier-3 Prepare through the same `RenderPolicy` and per-utterance scheduler as
/// playback. It never owns an audio player, so all inference shares the `RenderArbiter` lease.
@MainActor
@Observable
public final class PrepareRunner {
    public private(set) var isRunning = false
    public private(set) var lastResult: PrepareRunResult?
    public private(set) var lastError: String?
    /// Applied only to documents without their own override, mirroring `PlayerModel`.
    public var defaultVoiceID: String?
    /// Resolves an unavailable route to the system default for the whole document before planning,
    /// so Prepare renders the audio playback will actually ask for (spec §6). Mirrors `PlayerModel`.
    public var voiceRouting: any VoiceRouteResolving = PassthroughVoiceRouting()
    /// How long a chapter's rendered metadata may sit unwritten while the pass stays in that chapter.
    /// Rendered audio is already on disk under its key; a lost write self-heals on the next load
    /// (`PlaybackCoordinator.reconcileWithStore`), so this bounds a crash's loss, not correctness.
    public var chapterWriteInterval: TimeInterval = 10
    /// Chapter blobs written by this runner. Internal for one test: coalesced and per-utterance
    /// writes produce the same timeline, minutes of flash I/O apart.
    private(set) var chapterWrites = 0

    private let library: Library
    private let store: LibraryStore
    private let audioStore: any AudioStore
    private let engine: any SynthesisEngine
    private let defaults: UserDefaults
    private let arbiter: RenderArbiter
    private let timeSource: any TimeSource
    private var currentScheduler: RenderScheduler?
    private var cancelRequested = false

    public init(library: Library, store: LibraryStore, audioStore: any AudioStore,
                engine: any SynthesisEngine, defaults: UserDefaults = .standard,
                arbiter: RenderArbiter, timeSource: any TimeSource = SystemTimeSource()) {
        self.library = library
        self.store = store
        self.audioStore = audioStore
        self.engine = engine
        self.defaults = defaults
        self.arbiter = arbiter
        self.timeSource = timeSource
    }

    /// Looks up the persisted continuation document and Queue before executing a normal app or
    /// background invocation. The explicit overload below keeps the policy testable.
    public func run(reason: PrepareRunReason, device: DeviceState) async -> PrepareRunResult {
        let summaries = (try? await store.summaries()) ?? []
        let lastPlayed = summaries.max { ($0.lastPlayedAt ?? .distantPast) < ($1.lastPlayedAt ?? .distantPast) }?.id
        let queue = (try? await store.queue())?.map(\.id) ?? []
        return await run(reason: reason, lastPlayed: lastPlayed, queue: queue, device: device)
    }

    /// Testable policy execution: continuation document first, then Queue, using one playback
    /// budget. The budget is reread at every run so a changed preference needs no relaunch.
    public func run(lastPlayed: UUID?, queue: [UUID], device: DeviceState) async -> PrepareRunResult {
        await run(reason: .foreground, lastPlayed: lastPlayed, queue: queue, device: device)
    }

    public func cancel() {
        cancelRequested = true
        let scheduler = currentScheduler
        Task { await scheduler?.cancel() }
    }

    /// Claims the one run slot — the flags every pass starts from. The caller has already checked
    /// `isRunning`; a pass and a prime share this slot, which is why neither can start under the other.
    private func beginRun() {
        isRunning = true
        cancelRequested = false
        lastError = nil
    }

    /// Releases the slot, however the pass left.
    private func endRun() {
        isRunning = false
        currentScheduler = nil
    }

    /// Spec §3.4.1 tier 2 (`RenderPolicy`'s `primeSeconds`).
    public static let primeSeconds: TimeInterval = 30

    /// Renders the first ``primeSeconds`` of `documentID` from its resume position, in any power
    /// state, so its next tap plays with no spin-up: after an import (from the start) and at launch
    /// for the continue-document (from where the reader left it). Refused while a Prepare pass runs —
    /// `.skipped(.alreadyRunning)` — since the two share one scheduler slot; a prime is three
    /// utterances, so nothing waits long. Never records a Prepare run.
    public func prime(_ documentID: UUID) async -> PrepareRunResult {
        guard !isRunning else {
            return finish(PrepareRunResult(reason: .prime, stopReason: .skipped(.alreadyRunning)))
        }
        beginRun()
        defer { endRun() }

        let documents = await loadDocuments(lastPlayed: documentID, queue: [])
        guard let document = documents.first else {
            return finish(PrepareRunResult(reason: .prime, stopReason: .completed))
        }
        var input = PolicyInput(documents: [document.id: document.snapshot], primes: [document.id], device: .unplugged)
        input.primeSeconds = Self.primeSeconds
        let jobs = RenderPolicy.plan(input).filter { $0.tier == .prime }

        var result = PrepareRunResult(reason: .prime, stopReason: .completed)
        guard !jobs.isEmpty else { return finish(result) }
        // Every utterance, not coalesced: a prime is three of them, and the coordinator may load
        // this document a moment later — a cache hit then carries no word timings, so anything the
        // prime has not flushed is lost (the Plan 13 final review, finding 2).
        let groupResult = await render(jobs, document: document, writeEveryUtterance: true)
        result.renderedUtterances = groupResult.renderedUtterances
        result.preparedSeconds = groupResult.preparedSeconds
        if groupResult.renderedUtterances > 0 { result.documentIDs = [document.id] }
        if groupResult.storageFull {
            result.stopReason = .storageFull
        } else if cancelRequested || Task.isCancelled {
            result.stopReason = .cancelled
        }
        return finish(result)
    }

    /// ``prime(_:)`` for the continue-document — the one played most recently — so the mini-player's
    /// first tap after a launch is instant. Nothing played yet means nothing to do.
    public func primeContinueDocument() async -> PrepareRunResult {
        let summaries = (try? await store.summaries()) ?? []
        guard let last = summaries.filter({ $0.lastPlayedAt != nil })
            .max(by: { $0.lastPlayedAt! < $1.lastPlayedAt! })?.id
        else { return finish(PrepareRunResult(reason: .prime, stopReason: .completed)) }
        return await prime(last)
    }

    private func run(reason: PrepareRunReason, lastPlayed: UUID?, queue: [UUID], device: DeviceState) async -> PrepareRunResult {
        guard !isRunning else {
            return finish(PrepareRunResult(reason: reason, stopReason: .skipped(.alreadyRunning)))
        }
        guard Self.isSafe(device) else {
            return finish(PrepareRunResult(reason: reason, stopReason: .skipped(.unsafeDevice)))
        }

        beginRun()
        defer { endRun() }

        let documents = await loadDocuments(lastPlayed: lastPlayed, queue: queue)
        guard !documents.isEmpty else {
            return finish(PrepareRunResult(reason: reason, stopReason: .completed))
        }

        var input = PolicyInput(documents: Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0.snapshot) }),
                                lastPlayed: lastPlayed, queue: queue, device: device)
        input.prepareBudgetSeconds = budget()
        let jobs = RenderPolicy.plan(input).filter { $0.tier == .prepare }

        var unlimited = input
        unlimited.prepareBudgetSeconds = .greatestFiniteMagnitude
        let isBudgetLimited = Set(RenderPolicy.plan(unlimited).filter { $0.tier == .prepare }) != Set(jobs)

        var result = PrepareRunResult(reason: reason, stopReason: jobs.isEmpty ? .completed : .completed)
        for group in groupedByDocument(jobs) {
            guard !cancelRequested, !Task.isCancelled else {
                result.stopReason = .cancelled
                break
            }
            guard let document = documents.first(where: { $0.id == group.documentID }) else { continue }
            let groupResult = await render(group.jobs, document: document)
            result.renderedUtterances += groupResult.renderedUtterances
            result.preparedSeconds += groupResult.preparedSeconds
            if groupResult.renderedUtterances > 0 { result.documentIDs.append(group.documentID) }

            if groupResult.storageFull {
                result.stopReason = .storageFull
                break
            }
            if cancelRequested || Task.isCancelled {
                result.stopReason = .cancelled
                break
            }
        }

        if result.stopReason == .completed, isBudgetLimited, result.renderedUtterances > 0 {
            result.stopReason = .budgetExhausted
        }
        if result.renderedUtterances > 0 {
            let now = Date()
            defaults.set(now, forKey: StorageModel.lastPrepareRunKey)
            result.recordedAt = now
        }
        return finish(result)
    }

    private func loadDocuments(lastPlayed: UUID?, queue: [UUID]) async -> [PreparedDocument] {
        var ids: [UUID] = []
        for id in [lastPlayed].compactMap({ $0 }) + queue where !ids.contains(id) { ids.append(id) }

        var documents: [PreparedDocument] = []
        for id in ids {
            guard let document = try? await store.document(id: id),
                  let timeline = try? await library.timelineForPlayback(id),
                  var snapshot = try? await library.renderSnapshot(for: id)
            else { continue }

            let voiceID = await voiceRouting.effectiveVoiceID(document.voiceID ?? defaultVoiceID ?? "default")
            // Only an utterance whose reference already matches can be rendered; those are checked
            // against the store in one hop, the rest are unrendered without asking (audit §5.4).
            var candidates: [(index: Int, key: RenderKey)] = []
            for index in snapshot.rendered.indices {
                let expected = renderKey(documentID: id, utteranceIndex: index, voiceID: voiceID, timeline: timeline)
                if timeline[utterance: index].audioRef == expected.rawValue {
                    candidates.append((index, expected))
                } else {
                    snapshot.rendered[index] = false
                }
            }
            let present = await audioStore.contains(candidates.map(\.key))
            for (candidate, isPresent) in zip(candidates, present) where !isPresent {
                snapshot.rendered[candidate.index] = false
            }
            documents.append(PreparedDocument(document: document, timeline: timeline, snapshot: snapshot, voiceID: voiceID))
        }
        return documents
    }

    /// `writeEveryUtterance` flushes after every rendered event instead of coalescing (spec §5.2):
    /// a prime is a handful of utterances whose timings must be on disk before the next load.
    private func render(_ jobs: [RenderJob], document: PreparedDocument, writeEveryUtterance: Bool = false) async -> GroupResult {
        guard !jobs.isEmpty else { return GroupResult() }
        let scheduler = RenderScheduler(engine: engine, store: audioStore, timeSource: timeSource, arbiter: arbiter)
        currentScheduler = scheduler

        let requests = jobs.map { job in
            RenderRequest(job: job,
                          key: renderKey(documentID: document.id, utteranceIndex: job.utteranceIndex,
                                         voiceID: document.voiceID, timeline: document.timeline),
                          spoken: document.timeline[utterance: job.utteranceIndex].spoken,
                          voiceID: document.voiceID)
        }
        _ = await scheduler.setPlan(requests)

        var timeline = document.timeline
        var outcome = GroupResult()
        var dirtyChapters: Set<Int> = []
        var lastWrite = timeSource.now()

        func flush() async {
            for chapterIndex in dirtyChapters.sorted() {
                do {
                    try await store.saveChapter(timeline.chapters[chapterIndex], at: chapterIndex, of: document.id)
                    chapterWrites += 1
                    dirtyChapters.remove(chapterIndex)
                } catch {
                    // Stays dirty: the next flush retries it. The audio is on disk either way (spec §3.7.3).
                    lastError = "\(error)"
                }
            }
            lastWrite = timeSource.now()
        }

        for await event in scheduler.events {
            if Task.isCancelled, !cancelRequested { cancel() }
            switch event {
            case .rendered(let rendered):
                guard rendered.documentID == document.id,
                      let chapterIndex = timeline.chapterIndex(forUtterance: rendered.utteranceIndex)
                else { continue }

                var utterance = timeline[utterance: rendered.utteranceIndex]
                let useNewTimings = !rendered.wordTimings.isEmpty || (utterance.wordTimings ?? []).isEmpty
                let changed = utterance.audioRef != rendered.key.rawValue
                    || utterance.duration != .actual(rendered.duration)
                    || (useNewTimings && utterance.wordTimings != rendered.wordTimings)
                guard changed else { continue }

                utterance.audioRef = rendered.key.rawValue
                utterance.duration = .actual(rendered.duration)
                if useNewTimings { utterance.wordTimings = rendered.wordTimings }
                timeline[utterance: rendered.utteranceIndex] = utterance
                outcome.renderedUtterances += 1
                outcome.preparedSeconds += rendered.duration

                // Write when the pass leaves a chapter, or when the interval has passed inside one —
                // never per utterance (audit §5.2).
                let movedToAnotherChapter = !dirtyChapters.isEmpty && !dirtyChapters.contains(chapterIndex)
                dirtyChapters.insert(chapterIndex)
                if writeEveryUtterance || movedToAnotherChapter || timeSource.now() - lastWrite >= chapterWriteInterval {
                    await flush()
                }
            case .failed(_, _, let message):
                lastError = message
            case .storeFull:
                outcome.storageFull = true
                await scheduler.cancel()
            case .idle:
                await flush()
                currentScheduler = nil
                return outcome
            }
        }
        await flush()
        currentScheduler = nil
        return outcome
    }

    private func budget() -> TimeInterval {
        guard let stored = defaults.object(forKey: AppPaths.prepareBudgetKey) as? Double else {
            return 3 * 3600
        }
        if stored == .infinity { return .greatestFiniteMagnitude }
        return stored.isFinite && stored > 0 ? stored : 3 * 3600
    }

    private func renderKey(documentID: UUID, utteranceIndex: Int, voiceID: String, timeline: Timeline) -> RenderKey {
        RenderKey(documentID: documentID, utteranceIndex: utteranceIndex, voiceID: voiceID,
                  engineID: engine.engineID, normalizerVersion: timeline.normalizerVersion,
                  segmenterVersion: timeline.segmenterVersion)
    }

    private func groupedByDocument(_ jobs: [RenderJob]) -> [(documentID: UUID, jobs: [RenderJob])] {
        var groups: [(documentID: UUID, jobs: [RenderJob])] = []
        for job in jobs {
            if groups.last?.documentID == job.documentID {
                groups[groups.count - 1].jobs.append(job)
            } else {
                groups.append((job.documentID, [job]))
            }
        }
        return groups
    }

    private func finish(_ result: PrepareRunResult) -> PrepareRunResult {
        lastResult = result
        return result
    }

    private static func isSafe(_ device: DeviceState) -> Bool {
        device.charging && !device.thermalSerious && !device.lowPowerMode && !device.storeFull
    }

    private struct PreparedDocument {
        var document: Document
        var timeline: Timeline
        var snapshot: RenderSnapshot
        var voiceID: String
        var id: UUID { document.id }
    }

    private struct GroupResult {
        var renderedUtterances = 0
        var preparedSeconds: TimeInterval = 0
        var storageFull = false
    }
}
