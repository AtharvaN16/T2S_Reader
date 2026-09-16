// Sources/T2SApp/Status/AppStatusModel.swift
import Foundation
import Observation

/// A job that can speak in the status band. Implemented once per job, and it says nothing about
/// views: given the time, either it has something for the reader or it does not.
@MainActor
public protocol StatusSource: AnyObject {
    var kind: StatusKind { get }

    /// Whether this job wants the band on screen. Going false is what starts the fade.
    var isActive: Bool { get }

    /// This job's state as the band would say it, or nil when the job has nothing to show.
    ///
    /// **This must keep answering through the fade that ``isActive`` going false starts**, and
    /// that is the whole reason it is separate from `isActive` rather than one nil-able call.
    /// The last thing a reader sees of a wait has to be the end of it — the green, the words, the
    /// full bar — *going*, held for the length of the fade. A source that fell silent on the same
    /// frame `isActive` dropped would blank its own words on the first frame of a 1.5 s fade and
    /// leave a lit rim over nothing. The warm-up learned this the other way round in 2026-09-12,
    /// when clearing its ready date to take the glow off screen also put the line back to an
    /// estimate and slid the bar backwards out of full, in full view.
    func reading(now: Date) -> StatusReading?
}

/// The band's one slot.
///
/// **One at a time, and never a queue.** A source that is outranked simply does not show; it is
/// not held to be shown later, because by the time the slot frees a stale wait is not news. The
/// order is `StatusKind.rank` and it is fixed.
///
/// Sources are *pulled*, not pushed. The warm-up's clock re-resolves twice a second and pushing
/// each tick through an `@Observable` would wake every observer of this model for a number only
/// the band reads. `current(now:)` is called from the band's own `TimelineView` instead.
@MainActor
@Observable
public final class AppStatusModel {
    private var sources: [any StatusSource] = []

    public init() {}

    /// Adds a source, replacing any earlier one of the same kind so a re-registration on a view's
    /// second appearance cannot leave two of them answering for one job.
    public func register(_ source: any StatusSource) {
        sources.removeAll { $0.kind == source.kind }
        sources.append(source)
        sources.sort { $0.kind.rank < $1.kind.rank }
    }

    /// What the band draws at `now`: the highest-ranked source with something to say.
    ///
    /// Not the same question as ``isShowing``, and the gap between them is deliberate — see the
    /// note on `StatusSource.reading(now:)`. This one keeps answering through the fade, so the
    /// band has something to draw while it goes.
    public func current(now: Date) -> StatusReading? {
        for source in sources {
            if let reading = source.reading(now: now) { return reading }
        }
        return nil
    }

    /// Whether the band is up — the fade gate, and a plain `Bool` because an `.animation(value:)`
    /// cannot be driven by something that changes every frame.
    ///
    /// Asked of ``StatusSource/isActive`` rather than of `current(now:) != nil`: a source's words
    /// outlive its claim on the band by exactly one fade, so a gate read off the words would never
    /// go false and the band would never leave the screen.
    public var isShowing: Bool { sources.contains(where: \.isActive) }

    // MARK: the ending

    /// How far into the ending's colour, 0…1, eased on the breath's own curve. Smoothstep, as the
    /// cosine is at its ends, so the ending arrives the way the light moved rather than flashing.
    public func endSettle(now: Date) -> Double {
        guard let endedAt else { return 0 }
        let t = min(1, max(0, now.timeIntervalSince(endedAt) / StatusReading.readyEase))
        return t * t * (3 - 2 * t)
    }

    /// When the showing job began its last beat, set by the source that owns the slot.
    public private(set) var endedAt: Date?
    public func markEnding(at date: Date?) { endedAt = date }
}
