import SwiftUI

/// Core ML arm settings read from the launch environment, resolved exactly once.
///
/// A `static let` and not a stored property on the view: SwiftUI re-creates the `ContentView`
/// struct freely, and anything that logs from an initialiser would log once per re-creation.
struct CoreMLLaunchConfig {
    let policy: CoreMLStagePolicy
    let buckets: [Int]
    let durationTokens: [Int]

    static let shared = CoreMLLaunchConfig()

    private init() {
        let env = ProcessInfo.processInfo.environment
        let rawPolicy = env["SPIKE_COREML_POLICY"] ?? "default"
        if let named = CoreMLStagePolicy.named(rawPolicy) {
            policy = named
        } else {
            // Silently falling back to `gistDefault` would label a `cpuonly` run "default" in the
            // CSV, which is worse than failing: the numbers would look measured and be wrong.
            SpikeLog.shared.record("policy.unknown", [
                "value": rawPolicy, "known": CoreMLStagePolicy.knownNames,
                "using": CoreMLStagePolicy.gistDefault.name,
            ])
            policy = .gistDefault
        }
        buckets = Self.ints(env["SPIKE_COREML_BUCKETS"], default: CoreMLModelBundle.stagedBuckets,
                            what: "buckets")
        durationTokens = Self.ints(env["SPIKE_COREML_DURATION_TOKENS"],
                                   default: CoreMLModelBundle.stagedDurationTokenLengths,
                                   what: "durationTokens")
    }

    /// "7,15" -> [7, 15]. An unparseable or empty value keeps the default and logs a row.
    private static func ints(_ raw: String?, default fallback: [Int], what: String) -> [Int] {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return fallback }
        let parsed = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parsed.isEmpty, parsed.count == raw.split(separator: ",").count else {
            SpikeLog.shared.record("config.unknown", [
                "key": what, "value": raw,
                "using": fallback.map(String.init).joined(separator: ","),
            ])
            return fallback
        }
        return parsed.sorted()
    }
}

struct ContentView: View {
    @State private var bench: Bench?
    /// `SPIKE_ENGINE=mlx|mlxcpu|coreml`; read once at launch so the UI and the CSV agree.
    private let engine = SpikeEngine.fromEnvironment()
    /// `SPIKE_COREML_POLICY=default|cpuOnly`, `SPIKE_COREML_BUCKETS`, `SPIKE_COREML_DURATION_TOKENS`.
    private let coreML = CoreMLLaunchConfig.shared
    @State private var running = false
    @State private var loading = false
    @State private var rate = 0.0
    @State private var progress = BenchProgress()
    @State private var status = "Model not loaded"
    @State private var backgroundAudio = false
    @State private var silentPlayer: SilentPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Spike Harness").font(.largeTitle.bold())
            Text(engine == .coreml
                 ? "engine: coreml (\(coreML.policy.name), buckets \(coreML.buckets.map(String.init).joined(separator: "+")))"
                 : "engine: \(engine.rawValue)")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)

            Picker("Rate", selection: $rate) {
                Text("flat out").tag(0.0)
                Text("1x").tag(1.0)
                Text("3x").tag(3.0)
            }
            .pickerStyle(.segmented)
            .disabled(running)

            Toggle("Background audio (§7.2)", isOn: $backgroundAudio)
                .disabled(running || silentPlayer != nil)

            Button(running ? "Stop" : "Start bench") { running ? stop() : start() }
                .buttonStyle(.borderedProminent)
                .disabled(loading)

            Button("Schedule prepare task (§7.7)") { PrepareTask.schedule(); status = "Prepare task scheduled — plug in and leave overnight" }
                .disabled(running)

            Group {
                Text(status)
                Text("iterations: \(progress.iterations)")
                Text("last RTF: \(progress.lastRTF.isNaN ? "—" : String(format: "%.3f", progress.lastRTF))")
                Text("last audio: \(String(format: "%.2f", progress.lastAudioSeconds)) s in \(String(format: "%.2f", progress.lastSynthSeconds)) s")
                Text("footprint: \(progress.footprintMB) MB")
                Text("thermal: \(progress.thermal.rawValue)  (0 nominal, 1 fair, 2 serious, 3 critical)")
                if !progress.error.isEmpty { Text("error: \(progress.error)").foregroundStyle(.red) }
            }
            .font(.system(.body, design: .monospaced))

            Spacer()
            Text("Log: \(SpikeLog.shared.url.lastPathComponent)\nFiles → On My iPhone → Spike Harness")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear(perform: autorunIfRequested)
    }

    /// Hands-off protocol runs: launch with `SPIKE_AUTORUN_SECONDS=300` (and optionally
    /// `SPIKE_AUTORUN_RATE=0|1|3`) and the bench starts on appear and stops itself on time, so a
    /// measurement is the same on every device and needs no taps.
    private func autorunIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let seconds = env["SPIKE_AUTORUN_SECONDS"].flatMap(Double.init), seconds > 0,
              !running, !loading else { return }
        rate = env["SPIKE_AUTORUN_RATE"].flatMap(Double.init) ?? 0
        backgroundAudio = env["SPIKE_BACKGROUND_AUDIO"] == "1"     // §7.2: then lock the screen
        SpikeLog.shared.record("autorun", [
            "seconds": "\(seconds)", "rate": "\(rate)", "backgroundAudio": "\(backgroundAudio)",
            "engine": engine.rawValue, "policy": engine == .coreml ? coreML.policy.name : "",
            "buckets": engine == .coreml ? coreML.buckets.map(String.init).joined(separator: "+") : "",
        ])
        // The clock starts when the bench does, not when the app launches: the Core ML arm's four
        // models take minutes to load on an A13, and a launch-relative timer fires during the load
        // and then never stops the run.
        start(stopAfter: seconds)
    }

    private func start(stopAfter: Double? = nil) {
        if backgroundAudio, silentPlayer == nil {
            do {
                let player = SilentPlayer()
                try player.start()
                silentPlayer = player
                SpikeLog.shared.record("bg.audio.started")
            } catch {
                SpikeLog.shared.record("bg.audio.failed", ["error": "\(error)"])
                status = "Background audio failed: \(error.localizedDescription)"
            }
        }
        loading = true
        status = "Loading model…"
        let cycle = BenchCycle(playbackRate: rate)
        let engine = self.engine
        let coreML = self.coreML
        DispatchQueue.global(qos: .userInitiated).async {
            let bench: Bench
            do {
                switch engine {
                case .mlx: bench = try SynthBench()
                case .mlxcpu: bench = try SynthBench(cpuOnly: true)
                case .coreml:
                    bench = try CoreMLBench(policy: coreML.policy,
                                            buckets: coreML.buckets,
                                            durationTokenLengths: coreML.durationTokens)
                }
            } catch {
                SpikeLog.shared.record("model.failed", ["engine": engine.rawValue, "error": "\(error)"])
                DispatchQueue.main.async {
                    status = "Load failed: \(error.localizedDescription)"
                    loading = false
                }
                return
            }
            DispatchQueue.main.async {
                self.bench = bench
                loading = false
                running = true
                status = "Running \(engine.rawValue) (\(bench.voiceName))"
                UIApplication.shared.isIdleTimerDisabled = true      // Auto-Lock would suspend a foreground run
                if let stopAfter {
                    SpikeLog.shared.record("autorun.armed", ["seconds": "\(stopAfter)"])
                    DispatchQueue.main.asyncAfter(deadline: .now() + stopAfter) {
                        if running { stop() }
                    }
                }
            }
            bench.run(sentences: Corpus.sentences, cycle: cycle) { p in
                DispatchQueue.main.async { progress = p }
            }
            DispatchQueue.main.async {
                running = false
                status = "Stopped"
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    private func stop() {
        bench?.cancel()
        status = "Stopping after current sentence…"
    }
}
