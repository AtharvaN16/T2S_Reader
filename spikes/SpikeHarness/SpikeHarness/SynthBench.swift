import Foundation
import UIKit
import MLX
import KokoroSwift
import MLXUtilsLibrary

struct BenchCycle {
    /// Audio seconds produced per wall second. 0 = flat out.
    var playbackRate: Double
}

struct BenchProgress: Sendable {
    var iterations = 0
    var lastRTF = Double.nan
    var lastAudioSeconds = 0.0
    var lastSynthSeconds = 0.0
    var footprintMB = 0
    var thermal = ProcessInfo.ThermalState.nominal
    var error = ""
}

/// What `ContentView` drives, so the MLX and Core ML arms are interchangeable behind `SPIKE_ENGINE`.
protocol Bench: AnyObject {
    var voiceName: String { get }
    func run(sentences: [String], cycle: BenchCycle, onProgress: @escaping @Sendable (BenchProgress) -> Void)
    func cancel()
}

/// Which runtime the run measures. `mlxcpu` is the control from the pre-A14 desk research: the same
/// MLX arm with MLX's default device forced to `.cpu`, to see whether the A13 can run Kokoro at all
/// when the GPU path is out. Default stays `mlx` so the existing protocol runs are unchanged.
enum SpikeEngine: String {
    case mlx, mlxcpu, coreml

    static func fromEnvironment() -> SpikeEngine {
        SpikeEngine(rawValue: ProcessInfo.processInfo.environment["SPIKE_ENGINE"] ?? "") ?? .mlx
    }
}

/// Loops Kokoro over a corpus and logs one `sentence` row per synthesis.
final class SynthBench: Bench, @unchecked Sendable {
    enum Failure: LocalizedError {
        case missingModel, missingVoices, noSuchVoice(String)
        var errorDescription: String? {
            switch self {
            case .missingModel: return "kokoro-v1_0.safetensors is not in the bundle. See spikes/README.md."
            case .missingVoices: return "voices.npz is not in the bundle. See spikes/README.md."
            case .noSuchVoice(let v): return "Voice \(v) is not in voices.npz."
            }
        }
    }

    let voiceName: String
    /// `mlxcpu`: force MLX's default device to the CPU. On an A13 the GPU path traps inside Metal's
    /// steel GEMM kernels (Apple GPU family 7), so this is the only way MLX can be measured there.
    let cpuOnly: Bool
    /// A CPU MLX call has no published timing and could take minutes; past this the bench stops.
    static let cpuWatchdogSeconds = 120.0
    private let tts: KokoroTTS
    private let voice: MLXArray
    private var stopped = false

    init(voiceName: String = "af_heart", cpuOnly: Bool = false) throws {
        self.cpuOnly = cpuOnly
        // Set before the weights are loaded: MLX resolves its default device once, lazily.
        if cpuOnly { MLX.Device.setDefault(device: .cpu) }
        guard let modelURL = Bundle.main.url(forResource: "kokoro-v1_0", withExtension: "safetensors") else {
            throw Failure.missingModel
        }
        guard let voicesURL = Bundle.main.url(forResource: "voices", withExtension: "npz"),
              let voices = NpyzReader.read(fileFromPath: voicesURL) else {
            throw Failure.missingVoices
        }
        guard let embedding = voices[voiceName + ".npy"] else { throw Failure.noSuchVoice(voiceName) }
        let t0 = Date()
        tts = KokoroTTS(modelPath: modelURL, g2p: .misaki)
        voice = embedding
        self.voiceName = voiceName
        SpikeLog.shared.record("model.loaded", [
            "engine": cpuOnly ? "mlxcpu" : "mlx",
            "seconds": String(format: "%.2f", Date().timeIntervalSince(t0)),
            "footprintMB": "\(Self.footprintMB())",
            "voices": "\(voices.count)",
        ])
    }

    func cancel() { stopped = true }

    /// Blocking; call on a background queue. Logs token timestamps for the first three sentences
    /// so spike §7.4 has data without a separate probe.
    func run(sentences: [String], cycle: BenchCycle, onProgress: @escaping @Sendable (BenchProgress) -> Void) {
        stopped = false
        SpikeLog.shared.record("bench.start", [
            "engine": cpuOnly ? "mlxcpu" : "mlx",
            "rate": "\(cycle.playbackRate)", "voice": voiceName, "sentences": "\(sentences.count)",
        ])
        var i = 0
        var progress = BenchProgress()
        while !stopped, !sentences.isEmpty {
          // One pool per sentence — see the same comment in `CoreMLBench.run`. The whole bench is a
          // single work item on a global queue, so nothing drains between iterations otherwise and
          // a memory curve would be measuring the harness, not the runtime.
          autoreleasepool {
            let text = sentences[i % sentences.count]
            let t0 = Date()
            var samples: [Float] = []
            var tokens: [MToken]? = nil
            var errorText = ""
            if cpuOnly {
                // A CPU MLX synthesis is unbounded in principle (no kernel fusion on iOS at all), so
                // it runs on its own thread behind a watchdog: one row either way and the run stops.
                switch Self.withWatchdog(seconds: Self.cpuWatchdogSeconds, {
                    try MLX.Device.withDefaultDevice(.cpu) {
                        try self.tts.generateAudio(voice: self.voice, language: .enUS, text: text)
                    }
                }) {
                case .value(let out):
                    (samples, tokens) = out
                case .failed(let error):
                    errorText = "\(error)"
                case .timedOut:
                    SpikeLog.shared.record("sentence.timeout", [
                        "engine": "mlxcpu", "i": "\(i)",
                        "seconds": String(format: "%.0f", Self.cpuWatchdogSeconds),
                        "chars": "\(text.utf16.count)",
                    ])
                    errorText = "timed out after \(Int(Self.cpuWatchdogSeconds)) s"
                    stopped = true
                }
            } else {
                do {
                    (samples, tokens) = try tts.generateAudio(voice: voice, language: .enUS, text: text)
                } catch {
                    errorText = "\(error)"
                }
            }
            let synthSec = Date().timeIntervalSince(t0)
            let audioSec = Double(samples.count) / Double(KokoroTTS.Constants.samplingRate)
            let rtf = audioSec > 0 ? synthSec / audioSec : .nan
            let footprint = Self.footprintMB()
            let thermal = ProcessInfo.processInfo.thermalState

            SpikeLog.shared.record("sentence", [
                "engine": cpuOnly ? "mlxcpu" : "mlx",
                "i": "\(i)",
                "chars": "\(text.utf16.count)",
                "synth": String(format: "%.3f", synthSec),
                "audio": String(format: "%.3f", audioSec),
                "rtf": String(format: "%.3f", rtf),
                "thermal": "\(thermal.rawValue)",
                "footprintMB": "\(footprint)",
                "battery": String(format: "%.2f", UIDevice.current.batteryLevel),
                "charging": "\(UIDevice.current.batteryState != .unplugged)",
                "lowPower": "\(ProcessInfo.processInfo.isLowPowerModeEnabled)",
                "error": errorText,
            ])
            if i < 3, let tokens {
                for (k, t) in tokens.enumerated() {
                    SpikeLog.shared.record("timing", [
                        "i": "\(i)", "k": "\(k)", "token": t.text,
                        "start": t.start_ts.map { String(format: "%.3f", $0) } ?? "",
                        "end": t.end_ts.map { String(format: "%.3f", $0) } ?? "",
                    ])
                }
                // §7.4: the same three sentences as WAVs, next to the CSV, for the listening check.
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let wav = docs.appendingPathComponent("sentence-\(i).wav")
                do {
                    try WavWriter.write(samples: samples, sampleRate: KokoroTTS.Constants.samplingRate, to: wav)
                    SpikeLog.shared.record("wav.written", ["i": "\(i)", "file": wav.lastPathComponent, "text": text])
                } catch {
                    SpikeLog.shared.record("wav.failed", ["i": "\(i)", "error": "\(error)"])
                }
            }

            progress.iterations = i + 1
            progress.lastRTF = rtf
            progress.lastAudioSeconds = audioSec
            progress.lastSynthSeconds = synthSec
            progress.footprintMB = footprint
            progress.thermal = thermal
            progress.error = errorText
            onProgress(progress)

            if cycle.playbackRate > 0 {
                let budget = audioSec / cycle.playbackRate
                let sleep = budget - synthSec
                if sleep > 0 { Thread.sleep(forTimeInterval: sleep) }
            }
            i += 1
          }
        }
        SpikeLog.shared.record("bench.stop", ["engine": cpuOnly ? "mlxcpu" : "mlx", "iterations": "\(i)"])
    }

    enum WatchdogOutcome<T> {
        case value(T)
        case failed(Error)
        case timedOut
    }

    /// Written by the worker thread before `signal()`, read only after `wait()` returns success.
    private final class WatchdogBox<T>: @unchecked Sendable {
        var value: WatchdogOutcome<T> = .timedOut
    }

    /// Runs `work` on its own thread and gives up waiting after `seconds`. A timed-out thread is
    /// left running — MLX offers no cancellation — but the bench stops, so it is the last one.
    static func withWatchdog<T>(seconds: Double, _ work: @escaping () throws -> T) -> WatchdogOutcome<T> {
        let box = WatchdogBox<T>()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            do { box.value = .value(try work()) } catch { box.value = .failed(error) }
            done.signal()
        }
        thread.stackSize = 4 << 20
        thread.start()
        return done.wait(timeout: .now() + seconds) == .success ? box.value : .timedOut
    }

    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}
