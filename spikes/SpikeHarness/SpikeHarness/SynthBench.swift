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

/// Loops Kokoro over a corpus and logs one `sentence` row per synthesis.
final class SynthBench: @unchecked Sendable {
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
    private let tts: KokoroTTS
    private let voice: MLXArray
    private var stopped = false

    init(voiceName: String = "af_heart") throws {
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
            "rate": "\(cycle.playbackRate)", "voice": voiceName, "sentences": "\(sentences.count)",
        ])
        var i = 0
        var progress = BenchProgress()
        while !stopped, !sentences.isEmpty {
            let text = sentences[i % sentences.count]
            let t0 = Date()
            var samples: [Float] = []
            var tokens: [MToken]? = nil
            var errorText = ""
            do {
                (samples, tokens) = try tts.generateAudio(voice: voice, language: .enUS, text: text)
            } catch {
                errorText = "\(error)"
            }
            let synthSec = Date().timeIntervalSince(t0)
            let audioSec = Double(samples.count) / Double(KokoroTTS.Constants.samplingRate)
            let rtf = audioSec > 0 ? synthSec / audioSec : .nan
            let footprint = Self.footprintMB()
            let thermal = ProcessInfo.processInfo.thermalState

            SpikeLog.shared.record("sentence", [
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
        SpikeLog.shared.record("bench.stop", ["iterations": "\(i)"])
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
