import Foundation

/// Moves the bearer key the build carries (Info.plist `T2SCloudVoiceKey`, from the per-Mac
/// `Local.xcconfig`) into the Keychain once, so the shipped route works from the first launch
/// without anything typed (cloud-first bootstrap spec). A key already stored is left alone;
/// nothing is logged.
public enum CloudVoiceKeySeeder {
    /// True when a key was stored. An empty value, or an unset build setting — which reaches the
    /// plist as its own name, `$(T2S_CLOUD_VOICE_KEY)` — seeds nothing.
    @discardableResult
    public static func seed(infoValue: String?, into store: any SecretStoring) throws -> Bool {
        guard let value = infoValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, !value.hasPrefix("$(")
        else { return false }
        if let existing = try store.load(), !existing.isEmpty { return false }
        try store.save(value)
        return true
    }
}
