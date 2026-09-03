import KokoroSwift

/// Facts about the KokoroSwift runtime that the rest of the app needs without importing MLX.
public enum KokoroRuntime: Sendable {
    /// The rate every Kokoro model emits at, read from KokoroSwift rather than hard-coded, so a
    /// model or library change shows up as a test failure instead of pitched-up audio.
    public static let sampleRate: Double = Double(KokoroTTS.Constants.samplingRate)
}
