# Plan 0: Spikes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Answer the six unknowns in spec §7 with measured numbers and a written decision each, before any engine-dependent code is committed.

**Architecture:** One throwaway iOS harness app under `spikes/SpikeHarness/` that bundles Kokoro via `kokoro-ios` and loops synthesis over a fixed corpus while logging to a file. Each spike is a mode of that harness plus a measurement protocol. A separate macOS command-line tool compares MisakiSwift against reference Misaki. Everything under `spikes/` is throwaway and is never imported by shipping code.

**Tech Stack:** Swift 6, Xcode 16+, iOS 18+, SwiftUI, `kokoro-ios` (MLX Swift), MisakiSwift, BackgroundTasks, AVFoundation, Python 3 + `misaki` for the G2P reference.

**Spec:** `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` (rev 4). Sections §3.4.1, §3.6, §7.1–§7.7, §9 steps 1–2.

## Global Constraints

- No backend and no accounts in v1 (spec §1.1).
- No GPL, LGPL, or AGPL code may ship; espeak-ng is excluded outright (spec §7.1). G2P is Misaki via MisakiSwift.
- On-device engine is Kokoro-82M (weights Apache 2.0) through `kokoro-ios` (MIT).
- Platform floor is iOS 18, Swift 6, Xcode 16 (plan decision; the spec is silent).
- Measurements are taken on **two devices: one Pro and one non-Pro** iPhone (spec §7.5). Record model and iOS version in every findings file.
- Every spike ends in a findings file at `docs/superpowers/spikes/<YYYY-MM-DD>-<name>.md` using the template in Task 1, and in a one-line RESOLVED note added to the matching spec §7 subsection.
- Spike code lives under `spikes/` and is committed, but nothing in `Sources/` or `App/` may import it.
- Timeboxes are hard. When a timebox expires, write the findings file with what is known and the fallback taken.

---

### Task 1: Spike harness app and findings template

**Files:**
- Create: `spikes/SpikeHarness/` (Xcode iOS app project, SwiftUI, bundle id `com.t2s.spike`)
- Create: `spikes/SpikeHarness/SpikeHarness/Corpus.swift`
- Create: `spikes/SpikeHarness/SpikeHarness/SpikeLog.swift`
- Create: `spikes/SpikeHarness/SpikeHarness/SynthBench.swift`
- Create: `spikes/SpikeHarness/SpikeHarness/ContentView.swift`
- Create: `docs/superpowers/spikes/TEMPLATE.md`
- Create: `spikes/corpus.txt`

**Interfaces:**
- Produces: `SpikeLog.shared.record(_ fields: [String: String])` appends one CSV line; `SynthBench.run(sentences:cycle:)` loops synthesis and logs per-sentence rows; `Corpus.sentences` (50 English sentences, 8–40 words each).

- [ ] **Step 1: Create the Xcode project**

Xcode → New Project → iOS App, name `SpikeHarness`, interface SwiftUI, language Swift, save under `spikes/`. Set deployment target iOS 18.0. In Signing, use the personal team (a free Apple ID is fine for spikes; builds expire in 7 days, which is acceptable here).

- [ ] **Step 2: Add kokoro-ios**

File → Add Package Dependencies → `https://github.com/mlalma/kokoro-ios`. Follow its README to download the model weights and voice files into the app bundle. Record the exact commit hash and the weight file names in `spikes/README.md`.

- [ ] **Step 3: Write the corpus**

`spikes/corpus.txt`: 50 lines of English prose sentences, 8–40 words, taken from public-domain text (Project Gutenberg). Include at least five sentences with numbers, three with abbreviations ("Dr.", "Mr."), and two with proper nouns. Add it to the app target as a bundle resource.

```swift
// Corpus.swift
import Foundation

enum Corpus {
    static let sentences: [String] = {
        let url = Bundle.main.url(forResource: "corpus", withExtension: "txt")!
        let text = try! String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }()
}
```

- [ ] **Step 4: Write the log**

```swift
// SpikeLog.swift
import Foundation
import os

final class SpikeLog: @unchecked Sendable {
    static let shared = SpikeLog()
    private let url: URL
    private let queue = DispatchQueue(label: "spikelog")
    private let logger = Logger(subsystem: "com.t2s.spike", category: "bench")

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("spike-\(Int(Date().timeIntervalSince1970)).csv")
        FileManager.default.createFile(atPath: url.path, contents: "ts,event,k,v\n".data(using: .utf8))
    }

    func record(_ event: String, _ fields: [String: String] = [:]) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let lines = fields.isEmpty
            ? ["\(ts),\(event),,"]
            : fields.map { "\(ts),\(event),\($0.key),\($0.value)" }
        let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
        queue.sync {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            }
        }
        logger.info("\(event, privacy: .public) \(fields.description, privacy: .public)")
    }
}
```

- [ ] **Step 5: Write the bench loop**

```swift
// SynthBench.swift
import Foundation
import UIKit
// import the kokoro-ios module per its README

struct BenchCycle {
    /// Target duty cycle: audio seconds produced per wall second. 0 = flat out.
    var playbackRate: Double
}

final class SynthBench: @unchecked Sendable {
    private let engine: KokoroTTS   // type name per kokoro-ios; adjust to its API
    private var stop = false

    init() throws { engine = try KokoroTTS() }

    func cancel() { stop = true }

    /// Loops over `sentences` until cancelled. When `cycle.playbackRate > 0`,
    /// sleeps after each sentence so that audioSeconds / wallSeconds ≈ playbackRate.
    func run(sentences: [String], cycle: BenchCycle) async {
        stop = false
        SpikeLog.shared.record("bench.start", ["rate": "\(cycle.playbackRate)"])
        var i = 0
        while !stop {
            let s = sentences[i % sentences.count]
            let t0 = Date()
            let samples = try? await engine.synthesize(text: s, voice: "af_heart")  // returns Float PCM at 24 kHz
            let synthSec = Date().timeIntervalSince(t0)
            let audioSec = Double(samples?.count ?? 0) / 24_000
            let rtf = audioSec > 0 ? synthSec / audioSec : .nan
            SpikeLog.shared.record("sentence", [
                "i": "\(i)", "synth": String(format: "%.3f", synthSec),
                "audio": String(format: "%.3f", audioSec), "rtf": String(format: "%.3f", rtf),
                "thermal": "\(ProcessInfo.processInfo.thermalState.rawValue)",
                "footprintMB": "\(Self.footprintMB())",
                "battery": "\(UIDevice.current.batteryLevel)",
                "lowPower": "\(ProcessInfo.processInfo.isLowPowerModeEnabled)",
            ])
            if cycle.playbackRate > 0 {
                let budget = audioSec / cycle.playbackRate
                let sleep = max(0, budget - synthSec)
                try? await Task.sleep(for: .seconds(sleep))
            }
            i += 1
        }
        SpikeLog.shared.record("bench.stop")
    }

    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}
```

- [ ] **Step 6: Write the UI**

```swift
// ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var bench: SynthBench?
    @State private var running = false
    @State private var rate = 0.0

    var body: some View {
        VStack(spacing: 24) {
            Text("Spike Harness").font(.largeTitle.bold())
            Picker("Rate", selection: $rate) {
                Text("flat out").tag(0.0); Text("1x").tag(1.0); Text("3x").tag(3.0)
            }.pickerStyle(.segmented)
            Button(running ? "Stop" : "Start bench") {
                if running { bench?.cancel(); running = false; return }
                running = true
                Task {
                    bench = try? SynthBench()
                    await bench?.run(sentences: Corpus.sentences, cycle: .init(playbackRate: rate))
                }
            }
            Text("Log in Files → On My iPhone → SpikeHarness").font(.footnote)
        }
        .padding()
        .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true }
    }
}
```

In `Info.plist` set `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` to YES so the CSV is visible in the Files app.

- [ ] **Step 7: Run once in the foreground**

Build to the Pro device. Start "flat out" for 60 seconds, stop. Open the CSV in Files. Expected: ≥ 30 `sentence` rows, `rtf` values present, `footprintMB` > 0.

- [ ] **Step 8: Write the findings template**

```markdown
# Spike: <name>

**Spec section:** §7.x
**Date:** YYYY-MM-DD
**Devices:** <model, iOS version> ; <model, iOS version>
**Harness commit:** <sha>

## Question
<one sentence>

## Method
<what was run, for how long, how measured>

## Results
| Metric | Pro | non-Pro |
|---|---|---|

## Decision
<one paragraph: what the architecture does as a result, and which spec section changes>

## Fallback taken (if any)
```

- [ ] **Step 9: Commit**

```bash
git add spikes docs/superpowers/spikes/TEMPLATE.md
git commit -m "Add spike harness app, corpus, and findings template"
```

---

### Task 2: Spike §7.2 — sustained inference under the `audio` background mode

**Timebox:** 2 hours of engineering plus one 15-minute screen-off run per device.

**Files:**
- Modify: `spikes/SpikeHarness/SpikeHarness/SilentPlayer.swift` (create)
- Modify: `spikes/SpikeHarness/SpikeHarness/ContentView.swift`
- Modify: `spikes/SpikeHarness/SpikeHarness/Info.plist` (add `UIBackgroundModes: audio`)
- Create: `docs/superpowers/spikes/2026-09-XX-background-audio-compute.md`

**Interfaces:**
- Consumes: `SynthBench.run(sentences:cycle:)`, `SpikeLog`.
- Produces: the go/no-go for spec §3.4 render-ahead in the background.

- [ ] **Step 1: Add a silent audio session**

```swift
// SilentPlayer.swift
import AVFoundation

final class SilentPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24_000)!
        silence.frameLength = 24_000
        player.scheduleBuffer(silence, at: nil, options: .loops)
        player.play()
    }
}
```

Add `UIBackgroundModes` → `audio` to Info.plist. In `ContentView`, add a toggle "Background audio" that calls `SilentPlayer().start()` before the bench starts.

- [ ] **Step 2: Run the protocol on each device**

1. Toggle background audio on, start bench "flat out", note the time.
2. Lock the screen. Leave for 15 minutes.
3. Unlock, stop, export the CSV.

- [ ] **Step 3: Evaluate**

Compute per-minute median `rtf` and count of `sentence` rows. Pass when, for the full 15 minutes: no gap > 10 s between rows, and median `rtf` in minutes 5–15 is within 25% of minute 1. Also record the last `thermal` value.

Repeat once with Low Power Mode on and record separately.

- [ ] **Step 4: Write findings and mark the spec**

Fill the template. In the spec, under §7.2's heading, append a line `**RESOLVED (date):** <verdict, one sentence>` and, if it failed, open the §7.2 fallback as a new spec revision before Plan 2 starts.

- [ ] **Step 5: Commit**

```bash
git add spikes docs
git commit -m "Spike 7.2: background audio compute findings"
```

---

### Task 3: Spike §7.7 — idle-time inference under `BGProcessingTask`

**Timebox:** 2 hours of engineering plus three overnight runs on each device.

**Files:**
- Create: `spikes/SpikeHarness/SpikeHarness/PrepareTask.swift`
- Modify: `spikes/SpikeHarness/SpikeHarness/SpikeHarnessApp.swift`
- Modify: `spikes/SpikeHarness/SpikeHarness/Info.plist`
- Create: `docs/superpowers/spikes/2026-09-XX-bgprocessing-compute.md`

**Interfaces:**
- Produces: whether spec §3.4.1 tier 3's idle mechanism exists, and the typical granted runtime.

- [ ] **Step 1: Register and schedule the task**

Info.plist: `BGTaskSchedulerPermittedIdentifiers` = `[com.t2s.spike.prepare]`; `UIBackgroundModes` add `processing`.

```swift
// PrepareTask.swift
import BackgroundTasks
import Foundation

enum PrepareTask {
    static let id = "com.t2s.spike.prepare"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            handle(task as! BGProcessingTask)
        }
    }

    static func schedule() {
        let req = BGProcessingTaskRequest(identifier: id)
        req.requiresExternalPower = true
        req.requiresNetworkConnectivity = false
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do { try BGTaskScheduler.shared.submit(req); SpikeLog.shared.record("bg.scheduled") }
        catch { SpikeLog.shared.record("bg.scheduleFailed", ["error": "\(error)"]) }
    }

    private static func handle(_ task: BGProcessingTask) {
        SpikeLog.shared.record("bg.begin")
        let bench = try? SynthBench()
        let work = Task {
            await bench?.run(sentences: Corpus.sentences, cycle: .init(playbackRate: 0))
        }
        task.expirationHandler = {
            SpikeLog.shared.record("bg.expired")
            bench?.cancel()
            work.cancel()
            schedule()
            task.setTaskCompleted(success: true)
        }
    }
}
```

In `SpikeHarnessApp.init()` call `PrepareTask.register()`; in `ContentView` add a "Schedule prepare task" button calling `PrepareTask.schedule()`.

- [ ] **Step 2: Force a run under the debugger**

Run from Xcode, tap Schedule, background the app, pause in the debugger and evaluate:

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.t2s.spike.prepare"]
```

Expected: `bg.begin` then `sentence` rows in the log. If synthesis crashes or hangs here, the ANE/GPU is not usable in this context; record it and skip to Step 5.

- [ ] **Step 3: Real-world protocol**

On each device: tap Schedule, kill nothing, plug in overnight for three nights. Each morning export the CSV and note: did `bg.begin` occur; seconds between `bg.begin` and `bg.expired`; median `rtf` inside the task versus foreground.

- [ ] **Step 4: Evaluate**

Pass when the task ran on ≥ 2 of 3 nights on both devices and median granted runtime ≥ 3 minutes. Record the distribution either way; the tier-3 budget in Plan 2 is sized from it.

- [ ] **Step 5: Write findings and mark the spec**

Fill the template. Append `**RESOLVED (date):** ...` under §7.7. If it failed, note in the findings that Prepare runs only in the foreground and during background playback on charge, per §7.7's stated fallback; no spec change is needed.

- [ ] **Step 6: Commit**

```bash
git add spikes docs
git commit -m "Spike 7.7: BGProcessingTask compute findings"
```

---

### Task 4: Spike §7.3 and §7.5 — runtime RTF, memory, thermals, battery

**Timebox:** MLX path 1 day. CoreML path 1 additional day; if no working CoreML build of Kokoro exists by then, record "MLX only" and stop.

**Files:**
- Modify: `spikes/SpikeHarness/SpikeHarness/ContentView.swift` (rate picker already present)
- Create: `spikes/analyze.py`
- Create: `docs/superpowers/spikes/2026-09-XX-runtime-benchmark.md`

**Interfaces:**
- Consumes: CSV rows from `SpikeLog`.
- Produces: the runtime decision (MLX or CoreML), the RTF the §3.6 safety threshold is computed from, the memory figure for §7.5, and mAh/hour at 1x and 3x for §3.6.

- [ ] **Step 1: Write the analyzer**

```python
# spikes/analyze.py — usage: python3 analyze.py spike-*.csv
import csv, statistics, sys
from collections import defaultdict

rows = defaultdict(dict)
for path in sys.argv[1:]:
    with open(path) as f:
        for ts, event, k, v in csv.reader(f):
            if event == "sentence":
                rows[(path, ts)][k] = v

by_min = defaultdict(list)
battery = []
footprint = []
thermal = []
for (path, ts), r in sorted(rows.items()):
    minute = ts[:16]
    try:
        by_min[minute].append(float(r["rtf"]))
        footprint.append(int(r["footprintMB"]))
        thermal.append(int(r["thermal"]))
        battery.append((ts, float(r["battery"])))
    except (KeyError, ValueError):
        pass

for m, xs in sorted(by_min.items()):
    print(f"{m}  n={len(xs):3d}  median rtf={statistics.median(xs):.3f}")
print(f"peak footprint MB: {max(footprint)}")
print(f"max thermal state: {max(thermal)}  (0 nominal, 1 fair, 2 serious, 3 critical)")
if len(battery) >= 2:
    (t0, b0), (t1, b1) = battery[0], battery[-1]
    print(f"battery {b0:.2f} -> {b1:.2f} between {t0} and {t1}")
```

- [ ] **Step 2: RTF and memory, flat out, 5 minutes, both devices**

Run "flat out" in the foreground for 5 minutes. Analyzer output gives median RTF per minute and peak footprint. Record both per device.

- [ ] **Step 3: Thermals, 20 minutes at 3x, both devices**

Run rate "3x" for 20 minutes screen on. Record the minute at which thermal state first reaches 2 (serious), if ever, and the RTF trend.

- [ ] **Step 4: Battery, three 30-minute runs per device**

Charge to 100%, unplug, wait 5 minutes. Then, in this order, each 30 minutes, screen locked with background audio on:
1. Control: background audio only, bench not running.
2. Rate 1x.
3. Rate 3x.

Battery percentage delta × device capacity (mAh, from Apple's published figure for the model) ÷ 0.5 h = mAh/hour. Subtract the control from runs 2 and 3 to get the synthesis cost.

- [ ] **Step 5: CoreML path, timeboxed**

Search for an existing CoreML conversion of Kokoro-82M with word-duration outputs. If one exists with a permissive license, integrate it behind the same `SynthBench` interface and repeat Steps 2–4. If none exists, do not attempt a conversion here; record "MLX only" and the reason.

- [ ] **Step 6: Decide**

Decision rule (plan decision; adjust in findings if evidence argues otherwise): the runtime ships if, on the **non-Pro** device, median RTF ≤ 0.35, peak footprint ≤ 400 MB, 3x runs 20 minutes without reaching thermal state 2, and 1x synthesis costs ≤ 250 mAh/hour. The §3.6 UI threshold is then `maxRate = floor(0.8 / RTF, to 0.5)`.

- [ ] **Step 7: Write findings, mark the spec, commit**

Fill the template with the table for both devices. Append `**RESOLVED (date):** ...` under §7.3 and §7.5, including the measured RTF, footprint, and mAh/hour figures.

```bash
git add spikes docs
git commit -m "Spike 7.3/7.5: runtime benchmark findings"
```

---

### Task 5: Spike §7.4 — word timings from the chosen runtime

**Timebox:** 1 day.

**Files:**
- Create: `spikes/SpikeHarness/SpikeHarness/TimingProbe.swift`
- Create: `docs/superpowers/spikes/2026-09-XX-word-timings.md`

**Interfaces:**
- Produces: confirmation that per-token `(start, end)` are retrievable, the frame-to-seconds constant, and the shape of the timing output Plan 2's `SynthesisEngine` must return.

- [ ] **Step 1: Locate the duration predictor output**

In the `kokoro-ios` sources, find where the decoder consumes predicted durations (search for `duration`, `pred_dur`, `alignment`). Note whether the per-token duration tensor is reachable from the public synthesis call. If not, patch the local checkout (MIT) to return it alongside the audio.

- [ ] **Step 2: Write the probe**

```swift
// TimingProbe.swift
import Foundation

struct TokenTiming { let token: String; let start: Double; let end: Double }

enum TimingProbe {
    /// durations: per-token frame counts from the duration predictor.
    /// samplesPerFrame: measured as totalSamples / durations.sum() on the same call.
    static func timings(tokens: [String], durations: [Int], totalSamples: Int, sampleRate: Double = 24_000) -> [TokenTiming] {
        let totalFrames = durations.reduce(0, +)
        let samplesPerFrame = Double(totalSamples) / Double(totalFrames)
        var t = 0.0
        return zip(tokens, durations).map { tok, d in
            let dur = Double(d) * samplesPerFrame / sampleRate
            defer { t += dur }
            return TokenTiming(token: tok, start: t, end: t + dur)
        }
    }
}
```

Log `samplesPerFrame` for five sentences; it should be constant. Record it.

- [ ] **Step 3: Verify by ear**

For three sentences, write the WAV to Documents alongside a text dump of `TokenTiming`. Open in Audacity or Logic, place the cursor at the logged `start` of a mid-sentence word, and confirm it lands within ±100 ms of the word onset.

- [ ] **Step 4: Decide**

Pass: timings retrievable and within ±100 ms on all three sentences. Fail: record the cost of the ONNX timestamped fallback (`onnxruntime` dependency, model size, RTF) in the findings for Plan 5 to pick up.

- [ ] **Step 5: Write findings, mark the spec, commit**

```bash
git add spikes docs
git commit -m "Spike 7.4: word timing findings"
```

---

### Task 6: Spike §7.1 — MisakiSwift coverage, plus the license audit

**Timebox:** 1 day.

**Files:**
- Create: `spikes/g2p/Package.swift` (macOS executable target `g2pdump` depending on MisakiSwift)
- Create: `spikes/g2p/Sources/g2pdump/main.swift`
- Create: `spikes/g2p/reference.py`
- Create: `spikes/g2p/compare.py`
- Create: `docs/licenses.md`
- Create: `docs/superpowers/spikes/2026-09-XX-g2p-coverage.md`

**Interfaces:**
- Produces: the English-only decision confirmed or widened, and `docs/licenses.md` as the input to `scripts/check-licenses.sh` (Plan 1 Task 1).

- [ ] **Step 1: Swift dump**

```swift
// main.swift — reads sentences on stdin, prints one phoneme string per line
import Foundation
import MisakiSwift   // adjust module name to the package's product

let g2p = EnglishG2P()  // adjust to MisakiSwift's API
while let line = readLine() {
    let (phonemes, _) = g2p.phonemize(text: line)
    print(phonemes)
}
```

Run: `cat ../corpus.txt | swift run g2pdump > swift.txt`

- [ ] **Step 2: Python reference**

```python
# reference.py — pip install misaki[en]
import sys
from misaki import en
g2p = en.G2P(trf=False, british=False, fallback=None)
for line in sys.stdin:
    ps, _ = g2p(line.strip())
    print(ps)
```

Run: `python3 reference.py < ../corpus.txt > ref.txt`. Use 200 sentences here, not 50: extend `corpus.txt` to 200 lines for this spike.

- [ ] **Step 3: Compare**

```python
# compare.py
import sys
a = open(sys.argv[1]).read().splitlines()
b = open(sys.argv[2]).read().splitlines()
assert len(a) == len(b), (len(a), len(b))
exact = sum(1 for x, y in zip(a, b) if x == y)
print(f"exact match: {exact}/{len(a)} = {exact/len(a):.1%}")
for i, (x, y) in enumerate(zip(a, b)):
    if x != y:
        print(f"--- {i}\nswift: {x}\nref:   {y}")
```

Pass: ≥ 95% exact match and zero crashes. List divergence classes (numbers, names, contractions) in the findings.

- [ ] **Step 4: License audit**

Write `docs/licenses.md` as a table: dependency, version or commit, SPDX id, URL to the license file, and whether it is load-bearing. Cover: Readium swift-toolkit, kokoro-ios, Kokoro-82M weights, MisakiSwift, Inter, Readability.js, and any transitive dependency `swift package show-dependencies` lists for those. Any copyleft entry blocks the plan; raise it before proceeding.

- [ ] **Step 5: Write findings, mark the spec, commit**

```bash
git add spikes docs
git commit -m "Spike 7.1: MisakiSwift coverage and license audit"
```

---

### Task 7: Consolidate decisions into the spec

**Files:**
- Modify: `docs/superpowers/specs/2026-09-01-t2s-reader-design.md` §7, §3.6, §11

- [ ] **Step 1: Update the spec**

For each of §7.1–§7.5 and §7.7 confirm a `**RESOLVED (date):**` line exists with the number or verdict. In §3.6 replace the illustrative `RTF ≈ 0.08` and `≈ 0.3` figures with the measured non-Pro figure and the derived `maxRate`. Add a rev 5 entry to §11 listing the resolutions.

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-09-01-t2s-reader-design.md
git commit -m "Record spike resolutions in spec (rev 5)"
```
