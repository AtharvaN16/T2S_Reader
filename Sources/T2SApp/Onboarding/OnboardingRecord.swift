import Foundation

/// Whether the welcome has been shown on this install (design:
/// `docs/superpowers/specs/2026-09-14-onboarding-design.md`). One flag in `UserDefaults`, in the
/// style of `KokoroWarmUpRecord`: finishing or skipping the flow sets it, and Settings' "Show the
/// welcome again" clears it so the next launch presents the cover once more.
public enum OnboardingRecord {
    public static let key = "onboarding.completed"

    public static func isCompleted(defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: key)
    }

    public static func markCompleted(defaults: UserDefaults) {
        defaults.set(true, forKey: key)
    }

    public static func clear(defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}
