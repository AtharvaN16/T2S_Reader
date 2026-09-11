<!-- Web research, 2026-09-10 late evening: seven search agents (one per angle, 98 findings with URLs) and a
     synthesis, run for the owner after the 11 Pro session in crashreport.md on `phone-warmup-download-cloud`.
     Agent-written; the claims are the sources', not measurements from this repo, except where noted.
     Checked on this Mac before filing: the deduplication figure in the summary and item 3 — the 72 manifest
     files total 619 MB and hash to 238 MB of unique content (decoder_pre, decoder_har_post and f0ntrain
     weights are byte-identical across their four bucket sizes: 67.2 MB × 4, 39.4 MB × 4, 20.5 MB × 4).
     Items 1–10 under "What this means" are recommendations to weigh, not decisions. -->

# On-device Kokoro on iPhone: what others do, and what it means for t2s_reader

## Summary

Nothing measured tonight is a t2s_reader-specific bug. The multi-minute first-launch plan build is Core ML's per-device "specialization", which every large-model app on iPhone pays once per (model path, configuration, OS build) and which Apple gives no API to detect or skip before iOS 27 [S1][S2]; the A13 GPU `std::bad_alloc` matches a four-year-old unanswered Apple thread on A13 GPU over-allocation [S12] compounded by concurrent stage loads that Apple's own guidance says to serialize [S1][S4]; the background GPU refusal and the MLX abort are documented, permanent behaviour on every iPhone (Apple DTS: background GPU is iPad M3+ only) [S17][S19][S24]; and the CPU monitor that forces the 36 s/60 s pacing counts thread-summed CPU time against a limit Apple says never to approach [S30][S31]. The shipping projects that cope (WhisperKit, Apple's Stable Diffusion, Draw Things, the two Kokoro Core ML ports) do so with the same handful of practices: precompiled `.mlmodelc` at a stable path, one stage loading at a time, a device tier table, a visible one-time warm-up, CPU-only in the background, and deep render-ahead while frontmost. The largest single win found is not on the phone at all: the manifest downloads 619 MB of which only 238 MB is unique content. Inference speed itself is not the problem: A13 CPU RTF 0.17 and A19 Pro GPU RTF 0.05 both beat the upstream port's published iPhone numbers (RTF ~0.41 on iPhone 12 Pro, ~0.21 on 15 Pro Max) [S57].

## What others do

### First-launch compile and warm-up

- Apple (WWDC23 10049): on load, Core ML segments the graph per compute device and compiles each segment; the artifacts are cached on disk, "tied to the model's path and configuration", persist across launches and reboots, and are deleted on low disk, OS update, or when the compiled model changes. Verify with the Core ML Instrument, which labels loads "prepare and cache" vs "cached" [S1]. There is no public cache-probe API as of iOS 18; the accepted community answer (no Apple reply) says the key is the absolute `.mlmodelc` path and that app updates usually move the container, forcing a recompile [S2].
- `.mlpackage` recompiles on every load; `.mlmodelc` caches. Apple's own SD package loads `.mlmodelc` by default and reports first loads of 2-3 min dropping to seconds afterwards [S6]. Apple's doc for `compileModel(at:)` says the output lands in a temp dir and must be moved to a permanent location (Application Support), excluded from backup [S7]. An Apple engineer recommends compiling off-device with `xcrun coremlcompiler compile` and downloading `.mlmodelc` [S8]. Note this removes only the MIL compile step; device specialization is still done on the phone, and no source shows anyone shipping the E5RT cache.
- WhisperKit: sequential loads only, plus a `prewarm` mode that loads each model with its target compute units and immediately drops it, because otherwise "peak memory will bloat to all model weights combined plus the peak compilation memory"; cost is ~2x load time on a cache hit [S3][S4]. Their doc comment says the cache is "evicted after every OS update and if the models are not used for extended periods" [S3].
- Practitioners shipping ~1 GB Core ML models accept the wait and make it visible: Breeze ASR documents "~10-12 minutes per component" on first use with no mitigation [S75]; WWDC26 326 recommends a dedicated first-run screen that overlaps download and specialization [S66].
- `MLOptimizationHints.specializationStrategy` has no "fast compile" setting; `.fastPrediction` explicitly trades more specialization time, memory and disk for latency [S10]. `MLComputePlan` (iOS 17.4+) and the Xcode performance report expose per-op device placement, estimated cost and "why unsupported" hints [S11][S77].
- iOS 27 Core AI adds ahead-of-time compilation (`xcrun coreai-build compile`, one `.aimodelc` per device class), an explicit `AIModelCache`, `specialize(... cachePolicy: .persistent)`, and a `.cpuOnly` specialization option, but only for A17 Pro+ and only from a PyTorch re-export; no `.mlpackage` migration path is documented [S63][S64].

### Choosing compute units per device

- WhisperKit picks compute units per stage (mel on `.cpuAndGPU`, encoder/decoder on `.cpuAndNeuralEngine`, simulator forced `.cpuOnly`) and gates model size by device-identifier prefix with a remote JSON over a compiled-in fallback: `iPhone11*`/`iPhone12*` (A12/A13; the 11 Pro is `iPhone12,3`) get only tiny/base (~150 MB); A14 adds small; A15+ gets the 600-955 MB variants [S5][S74]. A ~620 MB pipeline is ~4x what they serve to an A13.
- Apple's ml-stable-diffusion sets the floor at A14, recommends `.cpuAndNeuralEngine` + `reduceMemory` on phones, and never recommends GPU on phones; on 4 GB (iPhone 12) CPU+GPU jetsams even with 6-bit weights [S14]; on 6 GB `.cpuAndGPU` OOMs and ANE load takes 300+ s [S15].
- A13 specifically: the same model peaks >2 GB on the A13 GPU vs ~750 MB CPU vs ~350 MB ANE, buffers are not freed after prediction, and a failed ANE compile leaks ~800 MB (FB11871301, open since Dec 2022, re-confirmed Jul 2026, no Apple reply). The reporter's fix: `.cpuOnly` on A13 [S12]. Medium confidence (single thread) but consistent with tonight's `bad_alloc`.
- ANECCompile failing after minutes is the norm for large stages: 9 min then `ANECCompile() FAILED (11)` on a 13 Pro Max [S13]; the upstream Kokoro port says the A14/A17 Pro ANE compiler rejects the full-ANE plan, so on iPhone it puts only `decoder-pre` on the ANE and everything else on CPU+GPU [S57].
- Apple engineer: load-time optimizations depend on `computeUnits` and mostly happen only at first load; a 3.5 MB model loaded in 188 ms on `.cpuAndGPU` vs 4 s on `.all` [S9]. Each distinct configuration is its own cache entry [S1].
- Runtime signals used by others: TFLite's Core ML delegate parses `utsname.machine` / `MLAllComputeDevices()` [S68]; a MediaPipe write-up gates GPU on `thermalState == .nominal && identifier >= "iPhone14,2"` after seeing an iPhone 12 throttle after ~8 min on GPU (third-party, medium) [S69]; Argmax's iPhone 17 benchmarks show the A19 Pro GPU 2.5-3.1x faster than A18 Pro while the ANE barely moved, so the GPU/ANE choice flips by generation [S70].
- Conflict to flag: one angle quotes "use cpuOnly if your app might run in the background" as Apple's `MLComputeUnits` doc [S18]; another traces that sentence to ONNX Runtime's Core ML EP docs [S76]. Treat the Metal background article [S17] as the authoritative statement.

### Background execution limits and audio

- The CPU monitor: crash logs read "CPU limit: 48s, Limit duration: 60s" (80% over 60 s), thread-summed, so >100% is possible [S29][S30]. A 60%/15 s window also appears (VoIP category) and iOS 15.2-15.3 briefly enforced 15%/60 s [S31]. Apple publishes no numbers; DTS: the limits "should NOT be treated as the acceptable limit you can/should grow toward" [S31]. Audio background mode does not exempt the process (Quinn: "a limited amount of processing") [S32], and an active audio session appears to override the BGProcessingTask exemption [S33].
- The only documented way to disable the monitor is `BGProcessingTask` with `requiresExternalPower = true` ("several minutes ... at system friendly times"), which runs only while idle and charging and is killed when the user picks up the phone [S34].
- iOS 26 `BGContinuedProcessingTask`: submitted from a user action, shows a Live Activity, must report progress, "can also use the network and perform intensive CPU-based operations"; GPU needs an entitlement and `supportedResources.contains(.gpu)`, which is false on every iPhone (DTS: iPad M3+ only) [S19][S20][S21]. One report of a `.cpuAndNeuralEngine` Core ML job running 4-5x slower in the background at 153% CPU without a kill (medium; single thread, no Apple statement that the monitor is relaxed) [S23].
- Metal in the background: iOS blocks command buffers after backgrounding; apps must stop committing on resign-active and `waitUntilScheduled()` [S17]. Core ML does not fall back to CPU when this happens: a GPU-placed model fails the prediction (`Failed to evaluate model 0 in pipeline`) [S22]. MLX throws inside a Metal completion handler on libdispatch, which is uncatchable from Swift; the same abort is reproduced by a Kokoro MLX iOS port on backgrounding [S24][S25]; llama.cpp/whisper.cpp behave the same [S26][S27].
- Shipping Kokoro MLX apps simply stop generation on `.background` [S28]; nobody in the open-source Kokoro ecosystem renders while locked.
- Audio session: DTS says the audio mode does not guarantee survival; a long silent gap is treated as an interruption that never resumes; mixable sessions get no Now Playing protection; keep background memory around 100 MB to avoid jetsam [S35]. `cpu_resource_fatal` kills are invisible to crash reporters; use `MXCPUExceptionDiagnostic` [S36].
- iOS 27 adds a "Background Inference" entitlement required for any Neural Engine access in the background [S65], and a report (no Apple reply) that iOS 27 attributes ANE memory to the app, with 300 MB peaks turning into 5+ GB [S71] (medium).

### Model download and hosting

- Hugging Face resolver limits are 3,000 requests per 5-minute fixed window per anonymous IP; every 429 carries `RateLimit: "resolvers";r=<remaining>;t=<seconds>` [S37]. Verified live tonight against the app's repo: `ratelimit: "resolvers";r=2998;t=217`. A Kokoro-specific HF forum thread shows 429s at a few runs per day from cloud IPs that never triggered locally, diagnosed as IP blocklisting rather than quota [S39] (medium). Do not ship a token: quotas are per account and a leaked token is revocable by anyone [S38].
- Neither of HF's Swift clients retries a 429 or handles background sessions: `HubApi` throws on 429 and has no Range resume [S40]; the new `swift-huggingface` has resume data but no retry/backoff [S41]. FluidAudio's downloader (4 retries, exponential from 1 s, honours Retry-After capped at 30 s, Range/If-Range resume) is a compact reference [S42].
- Resolve responses carry `X-Linked-Etag` (sha256), `X-Linked-Size`, `X-Repo-Commit`; a HEAD confirms the pin before downloading [S47]. The CDN redirect is a signed URL valid ~1 h, so URLSession resume data (which embeds it) goes stale; resume from the `huggingface.co` resolve URL with a Range header.
- Apple: one background `URLSessionConfiguration.background` for all files, tasks survive suspension/termination, relaunch by identifier; "perform fewer, larger transfers" [S43]. Background Assets: unmanaged self-hosted packs work from iOS 16 (`BAManifestURL`, essential-before-launch from iOS 18); Apple-hosted managed packs need iOS 26, 200 GB hosting included, with "machine learning models" a listed asset type [S44][S45].
- Mirroring: the repo is Apache-2.0. Cloudflare R2 has zero egress and 10 GB free; CloudFront gives 1 TB/month free [S46].
- The app's own manifest (computed from `KokoroCoreMLManifest.swift`): 72 files, 619,234,624 bytes, but 63 distinct sha256 and 238,107,928 unique bytes; three `weight.bin` blobs (decoder_pre 67.2 MB, decoder_har_post 39.4 MB, f0ntrain 20.5 MB) each appear four times.

### Memory on 4 GB phones

- The per-app limit on 4 GB iPhones is ~2 GB (`ActiveHard 2098 MB` jetsam) [S48]; Draw Things measured 2 GiB on 4 GB and 2.8 GiB on 6 GB devices [S49]; the Increased Memory Limit entitlement is "only available on some device models" [S50] and reportedly changes nothing on iPhone 11 and earlier, while a 12 GB iPhone 17 Pro crashed at 3.65 GB without it and peaked at ~4.65 GB with it (blog, medium) [S51]. `os_proc_available_memory()` is the sanctioned runtime signal and is advisory [S52].
- Only dirty and compressed memory count; file-backed clean pages (mmapped weights) can be evicted instead of killing the process [S53]. Whether Core ML keeps `weight.bin` clean on the CPU backend is undocumented; the GPU/MPSGraph path materializes copies.
- Apple's SD pipeline `reduceMemory` loads each stage just-in-time and `unloadResources()` right after, at "up to 2 s" cost, for 4 GB phones [S16]. Draw Things fit SD in 2 GiB by limiting concurrently submitted MPSGraph operations (peak 6 GB to 4 GB at 8) [S49]. The App Store cannot gate compatibility on RAM, so the app must tier itself.
- On iOS 17+ palettized weights can stay compressed in memory (up to 75% lower peak in Apple's SD numbers), but "some compiler backends may choose to decompress fully" and the gain is mainly on the ANE [S54]; int8 has been seen to fail plan building on A16 and to abort MPSGraph's MLIR pass under `.all` [S60]; palettization gives near-zero latency gain on CPU/GPU. So compression is a download-size lever, not a compile or A13-speed lever (medium).
- MLX: `memoryLimit` defaults to 1.5x `recommendedMaxWorkingSetSize` (8,192 MB on a 12 GB iPhone Air), unrelated to the jetsam limit [S55][S78]; the iOS guide recommends `cacheLimit` ~20 MB [S56]; a Kokoro MLX port retained a ~3 GB buffer cache after inference [S62].

### On-device TTS projects to learn from

- mattmireles/kokoro-coreml (the repo t2s_reader pulls from): five models with enumerated static buckets (duration T=32..512, decoder 3/7/10/15/30 s), fp16; iPhone staged policy with only `decoder-pre` on the ANE; 30 s in 12.3 s on a 4 GB iPhone 12 Pro where the MLX port is OOM-killed; "cold start takes a few seconds" is not broken out per device and the benchmarks are warm medians [S57]. t2s's 14 stages are presumably these models times buckets, which is where the 4x-duplicated weights come from.
- FluidInference/FluidAudio: seven stages, four on `.cpuAndNeuralEngine`, three on `.all`, ships both `.mlmodelc` and `.mlpackage`, bakes a 2000-frame / 510-phoneme cap for static shapes; ~15-20 s cold compile on M1, 2 s warm (Mac only) [S58]. Their contributor found the Noise/Tail stages need fp32 or fp16 produces high-frequency hiss [S67] (medium). Their maintainers report (Sept 2026) a libBNNS CPU segfault on iOS 26.4-26.6 (#844), an MPSGraph SIGABRT on iOS 27 betas, and a `vadd_fp16_sme` SIGSEGV 54 min into a foreground listen on an iPhone 17 Pro / iOS 27.0, while the same graph ran 2.5 h on ONNX Runtime CPU [S59]. Single source; treat as a warning, not a fact.
- sherpa-onnx (ONNX CPU): fp32 319 MB vs int8 103 MB on iPhone 15, but int8 is 2x slower; its Core ML EP fails on Kokoro [S61]. kokoro-ios (MLX): 3.3x realtime on iPhone 13 Pro, background abort, simulator abort, buffer-cache retention [S25][S62]. Piper as a system voice extension fails on memory even for medium models; keep synthesis in-app [S73].

## What this means for t2s_reader

1. **Serialize every stage load, and pin the A13 tier to `.cpuOnly` permanently.** The A13 GPU `bad_alloc` in `MILToMLIRRewriter` happened with several stages compiling at once on a device whose whole app budget is ~2 GB [S48] and whose GPU path is known to peak >2 GB for one model [S12]. Adopt WhisperKit's prewarm (load one stage with its final configuration, let it specialize, release, next) [S3][S4] on all devices including the 17 Pro GPU path, and never fall back from CPU to GPU or attempt ANE on `iPhone12,x` (a failed ANE compile leaks ~800 MB there) [S12]. Bounded peak memory is worth the ~2x load on cache hits.
2. **Keep the specialization cache alive, and plan for when it dies.** The 3.5-5.5 min (A13) / 125-160 s (A19 GPU) build is keyed to absolute `.mlmodelc` path + `MLModelConfiguration` + OS build [S1][S2]. Check: compile once, move out of tmp to a fixed Application Support path with `isExcludedFromBackup` [S7]; load only from that path; identical configuration per stage on every launch; no `.fastPrediction` [S10]. Expect a full rebuild after every App Store update and every iOS update; detect a version change and show the warm-up UI again rather than hiding it behind the first import. Confirm with the Core ML Instrument's "cached" label, not by timing.
3. **Deduplicate the download by content hash: 619 MB to 238 MB, 72 to 63 requests.** Download into `blobs/<sha256>` once, then copy or hard-link into the four `.mlpackage` paths. This is the biggest first-launch cut available and needs no hosting change. Also consider shipping precompiled `.mlmodelc` from the Mac (`xcrun coremlcompiler compile`) [S8] so the phone skips the MIL compile step; it will not remove specialization.
4. **Make the downloader survive a 429 and a suspension.** Read `ratelimit` / `ratelimit-policy` and the body on any 429 and sleep for `t` (+ jitter, cap ~300 s) before retrying the same file [S37]; the app currently discards the headers, so we cannot tell quota from blocklist. HEAD each file to check `X-Linked-Etag`/`X-Linked-Size` against the pin before spending bandwidth [S47]. Replace one-session-per-file with a single background `URLSession` and resume from the `huggingface.co` URL with Range, not from stale resume data [S43]. Medium term, mirror to R2 behind a custom domain (Apache-2.0 allows it) [S46] or an unmanaged Background Assets pack (iOS 18 floor fits) [S44]; either removes dependence on anonymous-IP policy [S39].
5. **Stop treating the background as a producer: render deep while frontmost.** No iPhone gets background GPU under any iOS 26 API [S19][S20], Core ML does not degrade to CPU when GPU is refused [S22], and the 36 s/60 s pacing starves a 60 s play-ahead. At RTF 0.05 the 17 Pro renders 20 min of audio per foreground minute; at RTF 0.17 the 11 Pro renders ~6 min. Render ahead by chapter (int16 PCM at 24 kHz is ~2.9 MB/min on disk), run the G2P for the whole document up front, and make the background loop a top-up. Before backgrounding: stop dispatching GPU-configured stages on `willResignActive`, drain in-flight predictions, and only then hand over [S17][S27].
6. **Never run MLX while not active; cap its cache.** The MisakiSwift/BART abort is a libdispatch-uncatchable throw [S24][S25]; gate on scene phase, run it in the foreground for the whole text, and set `MLX.GPU.set(cacheLimit:)` to ~20 MB since its default memory limit is tied to Metal's working set, not jetsam [S55][S56][S62]. Keep a non-MLX CPU G2P for the simulator and any background path. Also check that the 17 Pro's abort was not compounded by MLX holding GB-scale buffers next to the Core ML GPU plans.
7. **Audit the pacing arithmetic and stay far below the limit.** The budget is 48 CPU-seconds per 60 s summed across threads [S30]; a multi-thread BNNS stage burns 36 CPU-s in a fraction of that wall time, and a 60%/15 s window also exists [S31]. Measure with `proc_pid_rusage` during a background render, pace in short slices spread across every 15 s instead of one burst, and add MetricKit `MXCPUExceptionDiagnostic` logging to the spike builds [S36]. With render-ahead (item 5) the background render should rarely run at all.
8. **Audio-session hygiene for the starved minute.** Keep the engine running (schedule silence) rather than stopping on underrun, use a non-mixable `.playback` session and Now Playing, or a silent gap can be read as an interruption and the app suspended [S35]. Note DTS's ~100 MB background guidance: 620 MB of resident stages while locked is a jetsam candidate on the 11 Pro, another argument for foreground render-ahead and for unloading stages not needed by the background path (cached reload should be seconds; verify on the A13).
9. **Use `MLComputePlan` and the performance report on the largest stage before any more device pacing.** The A19 Pro CPU compiler "never finishes" a stage the A13 finishes in minutes; the report's per-op placement and "why unsupported" hints [S11][S77] are the fastest way to find the op or bucket at fault, and compile time scales with total graph size, so fewer decoder buckets (upstream ships five) would cut both download and warm-up. If ANE is revisited, do it upstream's way: only `decoder-pre`, only on 8 GB+ devices, never `.all` [S57][S13], and remember iOS 27 will need the background-inference entitlement [S65].
10. **Ship a remote tier table and a runtime gate.** Copy WhisperKit's identifier-prefix JSON [S5][S74]: `iPhone12,x` (A13, 4 GB) = CPU only, sequential, one or two stages resident; 6 GB A14/A15 = CPU or gated GPU; 8 GB+ = GPU foreground; gate GPU on `os_proc_available_memory()` and `thermalState` at load time [S52][S69], and add the Increased Memory Limit entitlement for the 17 Pro class only (it does nothing on the 11 Pro) [S50][S51]. An iOS 27 Core AI spike (AOT compile, explicit cache) is worth it on the 17 Pro once the app can target 27, but it requires a PyTorch re-export and excludes the 11 Pro [S63][S64].

## Open questions / what to measure next

- Why does the largest stage's CPU plan never finish on the A19 Pro when the A13 finishes all 14 in 3.5-5.5 min? Same iOS build? FluidAudio's SME-path crash on A19 Pro [S59] hints at a different CPU code path on that chip; run the Core ML Instrument and `MLComputePlan` on that stage on both phones.
- Does the cache actually hit on the second launch on both phones (Instrument label "cached", and load time in seconds)? In a debug build, list `Library/Caches/**/com.apple.e5rt.e5bundlecache/<build>/` after warm-up to get its size and a poor-man's "warm for this OS build" check (path documented on macOS only [S72], unverified on iOS).
- What does the 429 say? Capture `ratelimit`, `ratelimit-policy` and body on the next failure to tell quota (`r=0`) from blocklist; note whether the phone was on Wi-Fi or carrier CGNAT.
- Is the pacing budget counting thread-summed CPU time, and how many threads does each BNNS stage use? Log `proc_pid_rusage` per slice.
- Peak `phys_footprint` per stage on the A13 CPU path, loaded vs predicting: are weights clean (file-backed) or dirty? This decides whether stage unloading buys anything.
- Does `BGContinuedProcessingTask` relax the CPU monitor for a "render this chapter" tap on iOS 26? Only one report (153% CPU, no kill) [S23]; test on the 11 Pro with the audio session active.
- Long-listen stability on iOS 26.6.1: FluidAudio reports a libBNNS segfault on iOS 26.6 [S59]; run a 1-2 h foreground listen on the 11 Pro and check for `libBNNS` in the crash log.
- Does the fp16 render carry high-frequency hiss? If so, test fp32 only for the noise/tail stages [S67].
- Does 8-bit palettization reduce resident memory on the CPU path on the A13, or only download size, and does it lengthen the plan build [S54][S60]?
- Would upstream's five-model layout, or FluidAudio's precompiled `.mlmodelc` set, specialize faster on the 11 Pro than the current 14 stages? A direct A/B of first-load time is cheaper than more pacing work.

## Sources

- S1 https://developer.apple.com/videos/play/wwdc2023/10049/
- S2 https://developer.apple.com/forums/thread/786051
- S3 https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/Configurations.swift
- S4 https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/WhisperKit.swift#L360
- S5 https://github.com/argmaxinc/WhisperKit/blob/main/Sources/WhisperKit/Core/Models.swift
- S6 https://github.com/apple/ml-stable-diffusion/blob/main/README.md
- S7 https://developer.apple.com/documentation/coreml/downloading-and-compiling-a-model-on-the-user-s-device
- S8 https://developer.apple.com/forums/thread/718136
- S9 https://developer.apple.com/forums/thread/709211
- S10 https://developer.apple.com/documentation/coreml/mloptimizationhints-swift.struct/specializationstrategy-swift.enum/fastprediction
- S11 https://developer.apple.com/documentation/coreml/mlcomputeplan-85vdw
- S12 https://developer.apple.com/forums/thread/721756
- S13 https://github.com/apple/ml-stable-diffusion/issues/255
- S14 https://github.com/apple/ml-stable-diffusion/issues/291
- S15 https://github.com/apple/ml-stable-diffusion/issues/298
- S16 https://raw.githubusercontent.com/apple/ml-stable-diffusion/main/swift/StableDiffusion/pipeline/StableDiffusionPipeline.swift
- S17 https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background
- S18 https://developer.apple.com/documentation/coreml/mlcomputeunits
- S19 https://developer.apple.com/forums/thread/797538
- S20 https://developer.apple.com/forums/thread/801229
- S21 https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados
- S22 https://developer.apple.com/forums/thread/757715
- S23 https://developer.apple.com/forums/thread/807957
- S24 https://github.com/ml-explore/mlx/issues/3390
- S25 https://github.com/mlalma/kokoro-ios/issues/18
- S26 https://github.com/ggml-org/llama.cpp/issues/16998
- S27 https://github.com/ggml-org/whisper.cpp/issues/3531
- S28 https://github.com/Blaizzy/mlx-audio-swift/pull/8
- S29 https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/WorkLessInTheBackground.html
- S30 https://developer.apple.com/forums/thread/690666
- S31 https://developer.apple.com/forums/thread/758387
- S32 https://developer.apple.com/forums/thread/729442
- S33 https://developer.apple.com/forums/thread/675166
- S34 https://developer.apple.com/videos/play/wwdc2019/707/
- S35 https://developer.apple.com/forums/thread/764096
- S36 https://developer.apple.com/documentation/metrickit/mxcpuexceptiondiagnostic
- S37 https://huggingface.co/docs/hub/rate-limits
- S38 https://huggingface.co/docs/hub/security-tokens
- S39 https://discuss.huggingface.co/t/429-for-kokoro-82m-model/155806
- S40 https://github.com/huggingface/swift-transformers/blob/main/Sources/Hub/HubApi.swift
- S41 https://github.com/huggingface/swift-huggingface
- S42 https://github.com/FluidInference/FluidAudio/blob/main/Sources/FluidAudio/Shared/Download/RetryPolicy.swift
- S43 https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background
- S44 https://developer.apple.com/documentation/backgroundassets/configuring-an-unmanaged-background-assets-project
- S45 https://developer.apple.com/documentation/backgroundassets/downloading-apple-hosted-asset-packs
- S46 https://developers.cloudflare.com/r2/pricing/
- S47 https://huggingface.co/docs/huggingface_hub/package_reference/file_download
- S48 https://developer.apple.com/forums/thread/688973
- S49 https://liuliu.me/eyes/stretch-iphone-to-its-limit-a-2gib-model-that-can-draw-everything-in-your-pocket/
- S50 https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit
- S51 https://zenn.dev/mtfum/articles/ios_memory_entitlements?locale=en
- S52 https://developer.apple.com/documentation/os/os_proc_available_memory
- S53 https://developer.apple.com/videos/play/wwdc2018/416/
- S54 https://developer.apple.com/videos/play/wwdc2023/10047/
- S55 https://raw.githubusercontent.com/ml-explore/mlx-swift/main/Source/MLX/Memory.swift
- S56 https://github.com/ml-explore/mlx-swift/blob/main/Source/MLX/Documentation.docc/Articles/running-on-ios.md
- S57 https://huggingface.co/mattmireles/kokoro-coreml
- S58 https://github.com/FluidInference/FluidAudio/blob/main/Documentation/TTS/KokoroAne.md
- S59 https://github.com/FluidInference/FluidAudio/issues/889
- S60 https://github.com/FluidInference/FluidAudio/issues/828
- S61 https://github.com/k2-fsa/sherpa-onnx/issues/2374
- S62 https://github.com/mlalma/kokoro-ios/issues/25
- S63 https://developer.apple.com/documentation/coreai/compiling-core-ai-models-ahead-of-time
- S64 https://developer.apple.com/documentation/coreai/managing-model-specialization-and-caching
- S65 https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.inference
- S66 https://developer.apple.com/videos/play/wwdc2026/326/
- S67 https://huggingface.co/FluidInference/kokoro-82m-coreml/discussions/1
- S68 https://github.com/tensorflow/tensorflow/blob/master/tensorflow/lite/delegates/coreml/coreml_delegate.mm
- S69 https://dev.to/diyoraharshit52/mediapipe-on-ios-what-the-docs-leave-out-22bl
- S70 https://www.argmaxinc.com/blog/iphone-17-on-device-inference-benchmarks
- S71 https://developer.apple.com/forums/thread/839109
- S72 https://maderix.substack.com/p/inside-the-m4-apple-neural-engine
- S73 https://github.com/rhasspy/piper/issues/521
- S74 https://huggingface.co/argmaxinc/whisperkit-coreml/raw/main/config.json
- S75 https://huggingface.co/fredchu/breeze-asr-25-whisperkit-coreml
- S76 https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html
- S77 https://developer.apple.com/videos/play/wwdc2024/10161/
- S78 https://developer.apple.com/forums/thread/805161