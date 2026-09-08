import Foundation
import Observation
import T2SCore

public enum PlaybackState: Hashable, Sendable {
    case idle, playing, paused, catchingUp, finished
}

public struct CoordinatorConfiguration: Sendable {
    public var windowSeconds: TimeInterval
    public var primeSeconds: TimeInterval
    public var prepareBudgetSeconds: TimeInterval
    /// Segments kept queued in the player for gapless playback.
    public var queuedSegments: Int

    public init(windowSeconds: TimeInterval = 60, primeSeconds: TimeInterval = 30,
                prepareBudgetSeconds: TimeInterval = 3 * 3600, queuedSegments: Int = 2) {
        self.windowSeconds = windowSeconds
        self.primeSeconds = primeSeconds
        self.prepareBudgetSeconds = prepareBudgetSeconds
        self.queuedSegments = max(1, queuedSegments)
    }
}

/// Owns the playhead, drives the scheduler and the player, publishes highlights (spec §3).
@MainActor
@Observable
public final class PlaybackCoordinator {
    public private(set) var state: PlaybackState = .idle
    public private(set) var playhead = Playhead(utteranceIndex: 0)
    public private(set) var highlight: HighlightRange?
    public private(set) var rate: Double = 1
    public private(set) var availableRates: [Double] = RateLimits.allRates
    public private(set) var measuredRTF: Double?
    /// Set while the measured RTF holds the rate below what the listener asked for; nil once it
    /// recovers or the listener chooses again (spec §3.6: never offered-then-stuttering; audit §3.5:
    /// never left in place until "catching up"). The Reader shows it; `setRate` and `load` clear it.
    public private(set) var rateLoweredTo: Double?
    /// Set from the most recent `.failed` render event; cleared on `load`.
    public private(set) var lastRenderError: String?
    public private(set) var document: Document?
    public private(set) var timeline: Timeline? { didSet { timelineRevision &+= 1 } }
    /// Bumped on every write to `timeline` — a load, and every `.rendered` event that swaps an
    /// estimate for an actual. Anything O(timeline) a view derives can be cached against it
    /// instead of recomputed per body evaluation.
    public private(set) var timelineRevision = 0
    public private(set) var timeIndex = TimeIndex(Timeline(chapters: []))
    /// Set by the app from battery, thermal, and Low Power Mode notifications.
    public var device = DeviceState.unplugged { didSet { replan() } }
    /// Queue order for the prepare tier.
    public var queue: [UUID] = [] { didSet { replan() } }

    private let engine: any SynthesisEngine
    private let store: any AudioStore
    private let player: any AudioPlaying
    private let playheadStore: any PlayheadStore
    private let scheduler: RenderScheduler
    private let configuration: CoordinatorConfiguration
    private var rendered: [Bool] = []
    private var manualRequested = false
    /// The rate the listener last asked for, clamped to what was sustainable when they asked. The
    /// ceiling `refreshRates` raises back towards as the measured RTF recovers; a load leaves it,
    /// since the listener's choice of speed outlives the book.
    private var requestedRate: Double = 1
    private var lastPlayed: UUID?
    /// Index of the segment at the head of the player and the player's consumed time when that
    /// segment started (negative right after a seek into the middle of an utterance). Index-anchored
    /// (spec §3.2): estimates turning into actuals cannot move it.
    private var headIndex = 0
    private var headStartConsumed: TimeInterval = 0
    private var lastEnqueued: Int?
    private var awaitingIndex: Int?
    /// The utterance whose pieces are being enqueued as the engine streams them (Plan 14): its index,
    /// the ordinal the next piece must carry, and the samples still to drop from its front (a seek
    /// into the middle of it). Nil when nothing streams — including a stream joined late, which is
    /// ignored until its `.rendered` puts the whole clip in the store.
    private var streaming: (index: Int, nextOrdinal: Int, pendingDropSamples: Int)?
    /// Re-entrancy guard for `fill()`: `play()` and a `.rendered` event's follow-up can both try
    /// to fill the queue around the same suspension point.
    private var filling = false
    private var pendingWork: Task<Void, Never>?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    /// Idle accounting for `waitForRenderIdle`: plans submitted but not yet acknowledged by the
    /// scheduler, and `.idle` events the scheduler still owes us.
    private var submitsInFlight = 0
    private var expectedIdles = 0
    private var isRenderInFlight: Bool { submitsInFlight > 0 || expectedIdles > 0 }
    private var eventTask: Task<Void, Never>?

    public init(engine: any SynthesisEngine, store: any AudioStore, player: any AudioPlaying,
                playheadStore: any PlayheadStore, timeSource: any TimeSource,
                configuration: CoordinatorConfiguration = CoordinatorConfiguration(),
                arbiter: RenderArbiter = RenderArbiter()) {
        self.engine = engine
        self.store = store
        self.player = player
        self.playheadStore = playheadStore
        self.configuration = configuration
        self.scheduler = RenderScheduler(engine: engine, store: store, timeSource: timeSource, arbiter: arbiter)
        player.onSegmentFinished = { [weak self] tag in self?.segmentFinished(tag) }
        eventTask = Task { [weak self, scheduler] in
            for await event in scheduler.events {
                guard let self else { return }
                self.apply(event)
            }
        }
    }

    // MARK: Loading

    public func load(_ document: Document, timeline: Timeline) {
        self.document = document
        self.timeline = timeline
        timeIndex = TimeIndex(timeline)
        rendered = []
        rendered.reserveCapacity(timeline.utteranceCount)
        let voice = document.voiceID ?? "default"
        for i in 0..<timeline.utteranceCount {
            let expected = RenderKey(documentID: document.id, utteranceIndex: i, voiceID: voice,
                                     engineID: engine.engineID, normalizerVersion: timeline.normalizerVersion,
                                     segmenterVersion: timeline.segmenterVersion)
            let isCurrent = timeline[utterance: i].audioRef == expected.rawValue
            rendered.append(isCurrent)
            // `audioRef` is cache metadata, not proof that this build/voice still owns the clip.
            // Clear old identities so the next persistence cannot revive an invalid cache hit.
            if !isCurrent { self.timeline?[utterance: i].audioRef = nil }
        }
        manualRequested = false
        lastPlayed = document.id
        lastRenderError = nil
        rateLoweredTo = nil
        player.reset()
        playhead = timeIndex.clamp(document.resumePosition.map { PositionResolver.resolve($0, in: timeline) } ?? Playhead(utteranceIndex: 0))
        headIndex = playhead.utteranceIndex
        headStartConsumed = -playhead.offset
        lastEnqueued = nil
        awaitingIndex = nil
        streaming = nil
        state = timeline.utteranceCount == 0 ? .finished : .paused
        refreshHighlight()
        replan()
        reconcileWithStore()
    }

    /// The store is cache, never truth (spec §3.7.3): a `rendered[i] == true` seeded from a
    /// persisted `audioRef` can be stale if the entry was evicted while the app was closed.
    /// Flips any such index back to unrendered and clears its `audioRef` so `replan()` asks the
    /// scheduler to produce it again, instead of the plan quietly believing it's already there.
    private func reconcileWithStore() {
        let staleCandidates = rendered.indices.filter { rendered[$0] }
        guard !staleCandidates.isEmpty else { return }
        let store = self.store
        chain {
            // One hop for the whole document, not one per rendered utterance (audit §5.4).
            let keyed = staleCandidates.compactMap { i -> (index: Int, key: RenderKey)? in
                guard let ref = self.timeline?[utterance: i].audioRef else { return nil }
                return (i, RenderKey(rawValue: ref))
            }
            let present = await store.contains(keyed.map(\.key))
            var flipped = false
            for (entry, isPresent) in zip(keyed, present) where !isPresent {
                self.rendered[entry.index] = false
                self.timeline?[utterance: entry.index].audioRef = nil
                flipped = true
            }
            if flipped { self.replan() }
        }
    }

    // MARK: Transport

    public func play() async {
        guard let timeline, timeline.utteranceCount > 0, state != .playing else { return }
        if state == .finished {
            await seek(to: Playhead(utteranceIndex: 0))
        }
        await pendingWork?.value
        await fill()
        guard queuedCount > 0 else {                              // head utterance not rendered yet (spec §3.6)
            player.pause()
            state = .catchingUp
            replan()
            return
        }
        player.play()
        state = .playing
    }

    public func pause() {
        guard state == .playing || state == .catchingUp else { return }
        player.pause()
        state = .paused
        tick()
        save()
    }

    public func seek(to target: Playhead) async {
        guard let timeline, timeline.utteranceCount > 0 else { return }
        let wasPlaying = state == .playing || state == .catchingUp
        await pendingWork?.value
        player.reset()
        playhead = timeIndex.clamp(target)
        headIndex = playhead.utteranceIndex
        headStartConsumed = -playhead.offset                       // consumed 0 ⇔ `offset` into the head segment
        lastEnqueued = nil
        awaitingIndex = nil
        streaming = nil
        // A seek landing on or past the very end of the last utterance has nothing left to play.
        let pastEnd = playhead.utteranceIndex == timeline.utteranceCount - 1
            && playhead.offset >= timeIndex.duration(ofUtterance: playhead.utteranceIndex)
        state = pastEnd ? .finished : .paused
        refreshHighlight()
        save()
        replan()
        if wasPlaying, !pastEnd { await play() }
    }

    public func seek(toTime t: TimeInterval) async { await seek(to: timeIndex.playhead(atTime: t)) }

    /// Recreates hardware after AVAudioSession reports a media-services reset. The saved anchor is
    /// semantic source position rather than a timeline index, so a rebuilt timeline can still
    /// resume at the same sentence/word.
    public func recoverAfterMediaServicesReset() async {
        guard let timeline, timeline.utteranceCount > 0 else { return }
        let resume = PositionResolver.position(for: playhead, in: timeline)
        let shouldPlay = state == .playing || state == .catchingUp
        player.rebuildAfterMediaServicesReset()
        player.reset()
        let target = PositionResolver.resolve(resume, in: timeline)
        await seek(to: target)
        if shouldPlay { await play() }
    }

    public func setRate(_ r: Double) {
        guard r.isFinite else { return }
        let clamped = min(max(r, RateLimits.allRates.first!), RateLimits.maxSustainableRate(rtf: measuredRTF))
        // What the listener asked for, remembered: `refreshRates` follows the cap in both directions
        // and never raises the rate above this.
        requestedRate = clamped
        rate = clamped
        player.rate = clamped
        rateLoweredTo = nil
        replan()
    }

    public func renderWholeDocument() {
        manualRequested = true
        replan()
    }

    /// After the storage manager frees space (spec §6): un-pause the scheduler and replan.
    public func resumeRendering() async {
        await scheduler.resume()
        device.storeFull = false          // didSet replans
    }

    /// Call on a timer while playing (and after advancing a fake player in tests): derives the
    /// playhead from the player's consumed time and refreshes the highlight.
    public func tick() {
        guard let timeline, timeline.utteranceCount > 0, state == .playing || state == .paused else { return }
        let offset = max(0, player.consumedSeconds - headStartConsumed)
        playhead = timeIndex.clamp(Playhead(utteranceIndex: headIndex, offset: offset))
        refreshHighlight()
    }

    /// Awaits segment-feeding work started by a player callback or a render event.
    public func settle() async { await pendingWork?.value }

    /// Resolves once the scheduler has drained the current plan and the resulting work has settled.
    public func waitForRenderIdle() async {
        if isRenderInFlight {
            await withCheckedContinuation { idleWaiters.append($0) }
        }
        await settle()
    }

    // MARK: Segments

    private var queuedCount: Int { lastEnqueued.map { max(0, $0 - headIndex + 1) } ?? 0 }

    /// Enqueues rendered segments from the head until `queuedSegments` are queued; stops at the
    /// first unrendered one and remembers it as `awaitingIndex`.
    private func fill() async {
        // `play()` and a `.rendered` event's follow-up can both call this around the same
        // suspension point (`await store.read` below); only one pass may be enqueuing at a time,
        // or the same segment could be double-booked into the player.
        guard !filling else { return }
        filling = true
        defer { filling = false }
        guard timeline != nil else { return }
        // Re-reads `self.timeline` and recomputes `next` from `self.lastEnqueued` at the top of
        // every iteration (rather than a snapshot taken once): the `await store.read` below is a
        // real suspension point, during which a concurrently processed `.rendered` event — or a
        // `seek` that reset `lastEnqueued` — can change state a stale local copy would miss.
        while let timeline, queuedCount < configuration.queuedSegments {
            let next = lastEnqueued.map { $0 + 1 } ?? headIndex
            guard next < timeline.utteranceCount else { break }
            // A streaming utterance owns the player until its last piece: enqueueing the utterance
            // after it now would play out of order, and the stream itself is enqueued by `apply`.
            if let streaming, next >= streaming.index { return }
            guard rendered[next] else {
                awaitingIndex = next
                return
            }
            guard let ref = timeline[utterance: next].audioRef,
                  let audio = try? await store.read(RenderKey(rawValue: ref)) else {
                // `rendered` says this utterance is ready but the store disagrees — an LRU
                // eviction, most likely (spec §3.7.3). Self-heal: clear the stale record and ask
                // the scheduler to render it again rather than deadlocking here forever.
                rendered[next] = false
                self.timeline?[utterance: next].audioRef = nil
                awaitingIndex = next
                replan()
                return
            }
            var clip = audio
            if next == headIndex, headStartConsumed < 0 {
                let drop = min(clip.samples.count, Int((-headStartConsumed * clip.sampleRate).rounded()))
                clip.samples.removeFirst(drop)
            }
            // A clip trimmed down to nothing (a seek landing exactly on its end) has already been
            // fully consumed: advance past it without enqueueing, since the player will never fire
            // a completion for a segment it was never given.
            if !clip.samples.isEmpty {
                player.enqueue(clip, tag: next)
            }
            lastEnqueued = next
        }
        awaitingIndex = nil
    }

    private func segmentFinished(_ tag: Int) {
        guard let timeline, tag == headIndex else { return }
        headStartConsumed = player.consumedSeconds
        if tag + 1 >= timeline.utteranceCount {
            state = .finished
            // The utterance's own duration, not `timeIndex.clamp(…, offset: .infinity)`: `TimeIndex`
            // derives a duration from a subtraction of accumulated prefix sums, which can be off from
            // the utterance's stored duration by a floating-point ULP or two.
            playhead = Playhead(utteranceIndex: tag, offset: timeline[utterance: tag].duration.seconds)
            refreshHighlight()
            save()
            return
        }
        headIndex = tag + 1
        playhead = Playhead(utteranceIndex: headIndex, offset: 0)
        refreshHighlight()
        save()
        chain {
            await self.fill()
            if self.queuedCount == 0, self.state == .playing {     // ran into the frontier (spec §3.6)
                self.player.pause()
                self.state = .catchingUp
            }
            self.replan()
        }
    }

    /// Serializes asynchronous follow-up work so `settle()` can await all of it.
    private func chain(_ work: @escaping @MainActor () async -> Void) {
        let previous = pendingWork
        pendingWork = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    // MARK: Rendering

    private func replan() {
        guard let document, let timeline else { return }
        let snapshot = RenderSnapshot(documentID: document.id, timeline: timeline, rendered: rendered, resumeIndex: playhead.utteranceIndex)
        var input = PolicyInput(documents: [document.id: snapshot],
                                playing: PlayingState(documentID: document.id, playhead: playhead, rate: rate),
                                lastPlayed: lastPlayed, queue: queue, primes: [],
                                manual: manualRequested ? [document.id] : [], device: device)
        input.windowSeconds = configuration.windowSeconds
        input.primeSeconds = configuration.primeSeconds
        input.prepareBudgetSeconds = configuration.prepareBudgetSeconds
        // Nothing queued: the next `fill()` will wait on the head, so the head renders in pieces and
        // the first sound needs one short piece, not the whole utterance (audit #2, Plan 14).
        let streamIndex = queuedCount == 0 && streaming == nil ? headIndex : nil
        let requests = RenderPolicy.plan(input).map { job in
            RenderRequest(job: job,
                          key: renderKey(for: document, timeline: timeline, utteranceIndex: job.utteranceIndex),
                          spoken: timeline[utterance: job.utteranceIndex].spoken,
                          voiceID: document.voiceID ?? "default",
                          stream: job.utteranceIndex == streamIndex && job.tier == .playAhead)
        }
        submitsInFlight += 1
        let scheduler = self.scheduler
        chain {
            let owesIdle = await scheduler.setPlan(requests)
            self.submitsInFlight -= 1
            if owesIdle { self.expectedIdles += 1 }
            self.releaseIdleWaitersIfSettled()
        }
    }

    /// Re-reads the scheduler's rolling RTF and moves the rate to the highest the machine can hold
    /// that the listener still wants — down when a phone throttles, back up when it recovers. A
    /// changed rate resizes the window, so it replans from here.
    private func refreshRates() async {
        measuredRTF = await scheduler.measuredRTF
        availableRates = RateLimits.availableRates(rtf: measuredRTF)
        let cap = RateLimits.maxSustainableRate(rtf: measuredRTF)
        let target = min(requestedRate, cap)
        guard abs(target - rate) > 1e-9 else { return }
        rate = target
        player.rate = target
        rateLoweredTo = target < requestedRate - 1e-9 ? target : nil
        replan()
    }

    private func apply(_ event: RenderEvent) {
        switch event {
        case .piece(let documentID, let index, let audio, let ordinal, let isLast):
            guard let document, document.id == documentID, timeline != nil, index < rendered.count else { return }
            if streaming == nil {
                // A stream starts only at its first piece, only for the head, only when the player
                // holds nothing — otherwise the pieces would land behind or inside another segment.
                guard ordinal == 0, index == headIndex, queuedCount == 0 else { return }
                streaming = (index, 0, headStartConsumed < 0 ? Int((-headStartConsumed * audio.sampleRate).rounded()) : 0)
            }
            guard var s = streaming, s.index == index, s.nextOrdinal == ordinal else { return }
            var clip = audio
            if s.pendingDropSamples > 0 {
                let drop = min(clip.samples.count, s.pendingDropSamples)
                clip.samples.removeFirst(drop)
                s.pendingDropSamples -= drop
            }
            s.nextOrdinal += 1
            streaming = isLast ? nil : s
            if !clip.samples.isEmpty || isLast {
                player.enqueue(clip, tag: index, isFinal: isLast)
            }
            lastEnqueued = index
            awaitingIndex = nil
            if state == .catchingUp, !clip.samples.isEmpty {
                player.play()
                state = .playing
            }
            if isLast {
                chain { await self.fill() }                          // the rest of the window may follow now
            }
        case .rendered(let r):
            guard let document, document.id == r.documentID, timeline != nil, r.utteranceIndex < rendered.count else { return }
            if streaming?.index == r.utteranceIndex { closeStream(r.utteranceIndex) }
            var u = timeline![utterance: r.utteranceIndex]
            u.duration = .actual(r.duration)
            // A cache-hit `.rendered` carries empty word timings (spec: RenderScheduler); don't
            // let it clobber real timings this utterance already has.
            if !r.wordTimings.isEmpty || (u.wordTimings ?? []).isEmpty {
                u.wordTimings = r.wordTimings
            }
            u.audioRef = r.key.rawValue
            timeline![utterance: r.utteranceIndex] = u
            rendered[r.utteranceIndex] = true
            timeIndex = TimeIndex(timeline!)
            refreshHighlight()
            // The RTF moves with every render, and a throttling phone shows it here first (§3.6).
            chain { await self.refreshRates() }
            if awaitingIndex == r.utteranceIndex {
                chain {
                    await self.fill()
                    if self.state == .catchingUp, self.queuedCount > 0 {
                        self.player.play()
                        self.state = .playing
                    }
                }
            }
        case .failed(_, let utteranceIndex, let message):
            lastRenderError = "utterance \(utteranceIndex): \(message)"   // spec §6: logged; silence follows as .rendered
            if streaming?.index == utteranceIndex { closeStream(utteranceIndex) }
        case .storeFull:
            device.storeFull = true                                 // surfaces the storage manager (spec §6)
            if let streaming { closeStream(streaming.index) }      // no `.rendered` will follow a refused write
        case .idle:
            expectedIdles = max(0, expectedIdles - 1)
            releaseIdleWaitersIfSettled()
            chain { await self.refreshRates() }
        }
    }

    /// Releases everyone waiting in `waitForRenderIdle()` once no plan submission and no owed
    /// `.idle` remain outstanding — never on a single `.idle` that might be stale (buffered from a
    /// run loop that already ended, arriving after a new plan has been submitted but not yet
    /// acknowledged by the scheduler).
    private func releaseIdleWaitersIfSettled() {
        guard !isRenderInFlight else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    // MARK: Helpers

    /// A stream that will get no last piece — the engine failed, or the store refused the clip — is
    /// closed with an empty final buffer, so the player's completion still fires behind the pieces it
    /// holds and the next utterance follows.
    private func closeStream(_ index: Int) {
        streaming = nil
        player.enqueue(PCMAudio(sampleRate: PCMAudio.defaultSampleRate, samples: []), tag: index, isFinal: true)
    }

    private func refreshHighlight() {
        guard let timeline else { highlight = nil; return }
        highlight = Highlighter.highlight(at: playhead, in: timeline)
    }

    private func renderKey(for document: Document, timeline: Timeline, utteranceIndex: Int) -> RenderKey {
        RenderKey(documentID: document.id, utteranceIndex: utteranceIndex, voiceID: document.voiceID ?? "default",
                  engineID: engine.engineID, normalizerVersion: timeline.normalizerVersion,
                  segmenterVersion: timeline.segmenterVersion)
    }

    private func save() {
        guard let document, let timeline else { return }
        let position = PositionResolver.position(for: playhead, in: timeline)
        let store = playheadStore
        chain { await store.save(position, for: document.id) }
    }
}
