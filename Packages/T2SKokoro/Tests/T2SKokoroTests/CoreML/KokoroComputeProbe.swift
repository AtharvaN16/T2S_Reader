import Foundation
import Testing
import T2SAudio
import T2SCore
@testable import T2SKokoro

/// Renders one passage under every compute-unit policy and prints the load and render times — the
/// mechanism behind the `kokoro.computeUnits` switch, checked on this Mac before the phone
/// measurement the audit (§3.7) asks for. Not a test of anything: `.enabled` only when
/// `spikes/findings/compute-probe/` exists, which `scripts/compute-probe.sh` creates, so the ordinary
/// suite never pays the minutes it takes. The per-stage split of every call is in the unified log
/// (`kokoro.timing`); this prints the totals and writes them to `report.md` in that directory.
@Suite(.serialized) struct KokoroComputeProbe {
    static let outputDirectory: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 6 { root.deleteLastPathComponent() }
        return root.appending(path: "spikes/findings/compute-probe", directoryHint: .isDirectory)
    }()

    static var isRequested: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: outputDirectory.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    @Test(.enabled(if: KokoroTestSupport.haveCoreMLFiles && KokoroComputeProbe.isRequested))
    func renderUnderEveryPolicy() async throws {
        KokoroTestSupport.locatePackageResourceBundles()
        let resources = try await KokoroTestSupport.compiledCoreMLResources()
        let passage = KokoroAudioProbe.passage
        let voice = KokoroVoiceID(engineID: KokoroCoreMLEngine.identity, voice: "af_heart").rawValue
        var report = ["# Compute-unit probe — \(Date().ISO8601Format())", "",
                      "| policy | load (all buckets) | first render | second render | audio | RTF (second) |", "|---|---|---|---|---|---|"]
        let reportURL = Self.outputDirectory.appending(path: "report.md")
        // GPU before the Neural Engine: the two policies that touch the Neural Engine spend five to
        // nine minutes per generator stage failing to compile it (`ANECCompile() FAILED`, this Mac,
        // 2026-09-10 — the audit's §3.7 finding), so the rows worth having come first, and the
        // report is written after every row so a probe stopped early still leaves them.
        let policies: [KokoroComputeUnits] = [.cpu, .cpuAndGPU, .all, .cpuAndNeuralEngine]
        for policy in policies {
            var options = KokoroCoreMLEngine.Options.default
            options.computeUnits = policy
            let engine = KokoroCoreMLEngine(resources: resources, options: options)
            let clock = ContinuousClock()
            let loadStarted = clock.now
            try await engine.preload()
            try await engine.awaitFullLoad()
            let load = KokoroCoreMLEngine.seconds(clock.now - loadStarted)
            let firstStarted = clock.now
            let first = try await engine.synthesize(.init(spoken: passage, voiceID: voice))
            let firstSeconds = KokoroCoreMLEngine.seconds(clock.now - firstStarted)
            let secondStarted = clock.now
            let second = try await engine.synthesize(.init(spoken: passage, voiceID: voice))
            let secondSeconds = KokoroCoreMLEngine.seconds(clock.now - secondStarted)
            #expect(second.audio.duration > 10)
            let line = String(format: "| %@ | %.2f s | %.2f s | %.2f s | %.2f s | %.3f |", policy.runtimeName, load, firstSeconds,
                              secondSeconds, second.audio.duration, secondSeconds / second.audio.duration)
            print("kokoro compute probe " + line)
            report.append(line)
            _ = first
            try (report.joined(separator: "\n") + "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        }
    }
}
