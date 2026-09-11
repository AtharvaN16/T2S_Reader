import Foundation

/// The three states SwiftUI's `ScenePhase` can be in, named without importing SwiftUI so the root
/// package can hold the policy and test it (`ScenePlacementTests`) without the App target.
public enum ScenePhaseKind: Sendable {
    case active
    case inactive
    case background
}

/// Where a Kokoro render is placed — foreground (the main, GPU-capable set) or background (the
/// small CPU set, or a parked wait for it) — as its own question from the foreground *gate* (plan
/// builds, the install's compiles), which today both read the same fact and should not
/// (2026-09-11 GPU-path review, §2.3, §5 item 3).
///
/// `.inactive` is the scene phase for a Control Center pull, a notification banner, the app
/// switcher's zoom-out, or an incoming call: the app is not frontmost, but iOS has not actually
/// revoked GPU submission yet, and the interruption is usually over in under a second. Counting it
/// as background — as the gate does, correctly, for a plan build that must not be caught running
/// when the app is actually backgrounded a moment later — instead parks a streamed head on the
/// gate (no background set yet) or forces it into discarded 3 s-bucket pieces (background set
/// present) for every such interruption, which is R4 in the review. A GPU call that starts in
/// `.inactive` and loses the race a moment later is already covered by the placement retry
/// (`GatedKokoroCoreMLEngine`'s `placedPieces`), so placement can afford to stay optimistic where
/// the gate must not.
public enum ScenePlacement {
    /// True only for `.background` — the phase iOS has actually revoked GPU submission for.
    /// `.active` and `.inactive` both place in the foreground.
    public static func placesInBackground(phase: ScenePhaseKind) -> Bool {
        phase == .background
    }
}
