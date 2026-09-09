// App/T2SReader/System/MotionTilt.swift
import CoreMotion
import Foundation
import Observation

/// The phone's lean, as a few degrees for `BookCover` to add to its rotation so the book on the
/// Collection's book sheet visibly turns with the hand that holds it (owner's ask, 2026-09-09,
/// made bolder same day after the first cut read as too subtle to notice — the Home rows had this
/// once and lost it at the owner's request; only the sheet's book has it). Relative, not absolute:
/// a slowly adapting baseline makes whatever angle the phone rests at neutral within a few
/// seconds, so only the *change* shows — flat on a table reads the same as held upright.
/// `BookSheet` switches it on only while it is showing and the device is not under load.
@MainActor
@Observable
final class MotionTilt {
    /// Degrees. `x` turns about the vertical axis (from roll), `y` about the horizontal axis (from
    /// pitch). Clamped to ±10°, `.zero` whenever updates are off or motion is unavailable (the
    /// simulator).
    private(set) var tilt: CGPoint = .zero
    /// What the caller last asked for. Stays true on the simulator even though `tilt` never moves,
    /// so `RootPager`'s on/off bookkeeping behaves the same everywhere.
    private(set) var isEnabled = false

    /// 30 Hz is plenty for a filter whose output moves a fraction of a degree, and cheap on the
    /// motion coprocessor.
    private static let updateInterval: TimeInterval = 1.0 / 30
    private let manager = CMMotionManager()
    /// Mutated on every sample and read by nobody, so kept out of Observation's bookkeeping.
    @ObservationIgnored private var filter = TiltFilter(sampleInterval: MotionTilt.updateInterval)

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        if on { start() } else { stop() }
    }

    private func start() {
        // The simulator (and a few very old devices) report no device motion at all; `tilt` then
        // stays `.zero` and `BookCover` draws exactly as it did before.
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = Self.updateInterval
        // `.xArbitraryZVertical` needs no magnetometer: roll and pitch come from gravity alone,
        // which is all a lean is.
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let attitude = motion?.attitude else { return }
            let roll = attitude.roll, pitch = attitude.pitch
            // `.main` is the main thread, which is what makes the hop into the actor sound.
            MainActor.assumeIsolated { self?.ingest(roll: roll, pitch: pitch) }
        }
    }

    private func stop() {
        manager.stopDeviceMotionUpdates()
        filter.reset()
        tilt = .zero
    }

    private func ingest(roll: Double, pitch: Double) {
        // A stop can race a sample already queued on main; the filter is reset by then and must
        // not be fed, or `tilt` would leave `.zero` while off.
        guard isEnabled else { return }
        let next = filter.step(roll: roll, pitch: pitch)
        // Publishing every 30 Hz sample would redraw every cover for sub-visible noise; only a move
        // a viewer could see is worth an Observation change.
        guard abs(next.x - tilt.x) > 0.05 || abs(next.y - tilt.y) > 0.05 else { return }
        tilt = next
    }
}

/// The maths, kept as plain value code apart from the actor: a slow baseline so the resting angle
/// is neutral, a fast low-pass so the output is smooth, then scale and clamp.
private struct TiltFilter {
    /// How long a new resting angle takes to become neutral (the exponential average's time
    /// constant): a few seconds, so a shift of the hand fades out while a deliberate tip shows.
    private static let baselineSeconds: TimeInterval = 3
    /// Per-sample weight of the smoothing low-pass; 0.2 at 30 Hz settles in about a quarter second.
    private static let smoothing = 0.2
    /// Degrees of tilt per degree of lean — bolder than the first cut (owner's ask, 2026-09-09: "too
    /// subtle"): a 10° tip of the phone now moves a cover 9°, close to one-for-one, clamped below.
    private static let scale = 0.9
    private static let limitDegrees = 10.0

    private let baselineWeight: Double
    private var baseline: (roll: Double, pitch: Double)?
    private var smoothed = CGPoint.zero

    init(sampleInterval: TimeInterval) {
        baselineWeight = sampleInterval / Self.baselineSeconds
    }

    mutating func reset() {
        baseline = nil
        smoothed = .zero
    }

    /// Feeds one attitude sample (radians) and returns the tilt it implies, in degrees.
    mutating func step(roll: Double, pitch: Double) -> CGPoint {
        // The first sample is the baseline outright, so switching on never starts from a lean.
        guard var base = baseline else {
            baseline = (roll, pitch)
            return .zero
        }
        base.roll += baselineWeight * (roll - base.roll)
        base.pitch += baselineWeight * (pitch - base.pitch)
        baseline = base
        let target = CGPoint(x: Self.degrees(roll - base.roll) * Self.scale,
                             y: Self.degrees(pitch - base.pitch) * Self.scale)
        smoothed.x += Self.smoothing * (target.x - smoothed.x)
        smoothed.y += Self.smoothing * (target.y - smoothed.y)
        return CGPoint(x: Self.clamp(smoothed.x), y: Self.clamp(smoothed.y))
    }

    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
    private static func clamp(_ value: Double) -> Double { min(max(value, -limitDegrees), limitDegrees) }
}
