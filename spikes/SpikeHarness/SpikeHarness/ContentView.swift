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
            }
            bench.run(sentences: Corpus.sentences, cycle: cycle) { p in
                DispatchQueue.main.async { progress = p }
            }
            DispatchQueue.main.async {
                running = false
                status = "Stopped"
            }
        }
    }

    private func stop() {
        bench?.cancel()
        status = "Stopping after current sentence…"
    }
}
