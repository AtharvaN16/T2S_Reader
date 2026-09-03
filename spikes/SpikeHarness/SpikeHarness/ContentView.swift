import SwiftUI

struct ContentView: View {
    @State private var bench: SynthBench?
    @State private var running = false
    @State private var loading = false
    @State private var rate = 0.0
    @State private var progress = BenchProgress()
    @State private var status = "Model not loaded"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Spike Harness").font(.largeTitle.bold())

            Picker("Rate", selection: $rate) {
                Text("flat out").tag(0.0)
                Text("1x").tag(1.0)
                Text("3x").tag(3.0)
            }
            .pickerStyle(.segmented)
            .disabled(running)

            Button(running ? "Stop" : "Start bench") { running ? stop() : start() }
                .buttonStyle(.borderedProminent)
                .disabled(loading)

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
        SpikeLog.shared.record("autorun", ["seconds": "\(seconds)", "rate": "\(rate)"])
        start()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if running { stop() }
        }
    }

    private func start() {
        loading = true
        status = "Loading model…"
        let cycle = BenchCycle(playbackRate: rate)
        DispatchQueue.global(qos: .userInitiated).async {
            let bench: SynthBench
            do {
                bench = try SynthBench()
            } catch {
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
                status = "Running (\(bench.voiceName))"
                UIApplication.shared.isIdleTimerDisabled = true      // Auto-Lock would suspend a foreground run
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
