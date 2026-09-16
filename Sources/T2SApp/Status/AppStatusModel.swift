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

    /// When this job's last beat began, or nil while it is still running. The band eases its
    /// ending's colour from this date.
    var endedAt: Date? { get }

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

    /// What the band draws at `now`: the highest-ranked source with something to say, preferring
    /// one that is still asking for the band over one that is only finishing its sentence.
    ///
    /// The two passes are the whole of it. A source keeps answering through the fade after it goes
    /// inactive, so a single pass by rank would let a warm-up that ended an hour ago outrank a
    /// render that is running right now — the band would sit on "Voice ready" for the whole job.
    /// Latent while the voice is the only source, and a trap laid for the second one.
    public func current(now: Date) -> StatusReading? {
        for source in sources where source.isActive {
            if let reading = source.reading(now: now) { return reading }
        }
        for source in sources {
            if let reading = source.reading(now: now) { return reading }
        }
        return nil
    }

    /// How far into the ending's colour, 0…1, eased on the breath's own curve. Smoothstep, as the
    /// cosine is at its ends, so the ending arrives the way the light moved rather than flashing.
    ///
    /// Read from whichever source owns the slot rather than from a date this model stores. It was
    /// stored, and the source set it from inside `reading(now:)` — which the band calls from a
    /// `TimelineView` body, so an `@Observable` property was being written during view update, on
    /// exactly the frame the ending's cross-fade begins. Asking costs nothing and mutates nothing.
    public func endSettle(now: Date) -> Double {
        guard let endedAt = speaking?.endedAt else { return 0 }
        let t = min(1, max(0, now.timeIntervalSince(endedAt) / StatusReading.readyEase))
        return t * t * (3 - 2 * t)
    }

    /// The source currently holding the slot, by the same order ``current(now:)`` uses.
    private var speaking: (any StatusSource)? {
        sources.first(where: { $0.isActive }) ?? sources.first
    }

    public var isShowing: Bool { sources.contains(where: \.isActive) }

}
