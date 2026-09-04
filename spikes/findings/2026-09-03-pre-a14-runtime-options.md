# Desk research: a Kokoro runtime for pre-A14 iPhones (input to Plan 0 Task 8)

**Spec section:** §7.3 Step 5 (a runtime that does not need `simdgroup_matrix`); Plan 0 Task 8
**Date:** 2026-09-03
**Devices:** none — desk research only; the iPhone 11 Pro (A13, 4 GB, iOS 26) is the target
**Status:** input to the spike, not a finding. The spike on the phone produces the finding.

Nothing here was built or measured; every number is attributed to a source
and to the hardware it was measured on.

---

## Answer in three sentences

Spike **`mattmireles/kokoro-coreml`'s `KokoroPipeline` Swift package** first: it is the only Kokoro path
with a *published, dated iPhone measurement on 4 GB Apple silicon* (iPhone 12 Pro, June 2026, RTF
0.41–0.46 across four length buckets), it runs on Core ML / MPSGraph rather than MLX's
`simdgroup_matrix` GEMMs, it is Apache-2.0 end to end with the same MisakiSwift the app already
links, and its `SynthesisResult.tokenDurationFrames` gives per-token frame counts — the exact
input `KokoroTokenTimingMapper` already consumes.

Be honest about the likely outcome: extrapolating that A14 result one generation back, the A13 lands
around **RTF 0.5–0.65**, which *fails* the spec's ≤ 0.35 bar and would cap the 11 Pro at roughly
1.2–1.6x playback — so the real decision the spike settles is "cap the rate on A13" vs "no Kokoro on
A13", not "does Kokoro pass on A13".

The cheapest control to run in the same session is MLX with `Device.cpu` (mlx-swift *does* compile the
real CPU backend on iOS — only the CPU **JIT-compile** path is stubbed out — so it is a one-line
change to the existing SpikeHarness), and the credible fallback if Core ML disappoints is ONNX Runtime's
CPU EP with `onnx-community/Kokoro-82M-v1.0-ONNX-timestamped`, whose graph I verified byte-for-byte
exposes a `durations` output.

---

## Options table

RTF = synthesis wall time ÷ audio duration. "A13 expected" is my extrapolation unless marked *measured*.

| # | Runtime | How the model gets in | G2P / licence | Word timings | Expected A13 RTF (provenance) | Memory | Integration effort here | Main risks |
|---|---|---|---|---|---|---|---|---|
| **1** | **Core ML, staged pipeline** — `mattmireles/kokoro-coreml` `KokoroPipeline` (SPM, iOS 16+) | 10–22 `.mlpackage`s, fp16, static shapes, from HF `mattmireles/kokoro-coreml`; **~178 MB** for one bucket, 474 MB for the published "starter" profile. Download (sha256 published per file) | Starts from **token IDs**; its own SDK layer uses a MisakiSwift fork. Vocab file is byte-identical to Kokoro's canonical 178-symbol vocab. **Apache-2.0**, no espeak anywhere | **Yes, exact.** `SynthesisResult.tokenDurationFrames: [Int]` — per-input-token duration frames, plus `PipelineConstants.samplesPerDurationFrame = 600` (25 ms/frame) | **0.50–0.65** (extrapolated from *measured* iPhone 12 Pro / A14 / 4 GB: 0.461, 0.424, 0.417, 0.410 for 3/7/15/30 s buckets, June 2026, iOS 26.5, median of 5 warm calls) | fp16 weights: ~166 MB resident for one bucket's four models. The 4 GB iPhone 12 Pro completed the 30 s bucket where MLX OOM'd | **Low–medium.** Add one SPM package + a resource downloader; feed our existing MisakiSwift token IDs; fold `tokenDurationFrames` onto words. A ready-made iPhone bench app (`ios-bench/`, XcodeGen) already exists in the repo | ANE compile is already known to fail on iPhone (`ANECCompile() FAILED` on A14 *and* A17 Pro) so iPhone runs a staged CPU+GPU policy; unknown whether A13's older MPSGraph path degrades further. Duration-frame → seconds constant needs calibrating against the WAV. 62-star single-maintainer repo |
| **2** | **ONNX Runtime, CPU EP (XNNPACK)** — `onnxruntime-objc` 1.29.0 (pod) or `onnxruntime-swift-package-manager` 1.24.2 (SPM) | `onnx-community/Kokoro-82M-v1.0-ONNX-timestamped`: `model.onnx` 326 MB fp32, `model_fp16.onnx` 163 MB, `model_q8f16.onnx` 86.1 MB, `model_quantized.onnx` 92.4 MB. Voice styles as `.bin` (`[N,1,256]` fp32) | Takes `input_ids` directly — **no espeak needed**. ORT is **MIT**, model **Apache-2.0** | **Yes.** I verified the graph's outputs by range-reading the fp16 file: `waveform [1, num_samples] f32`, `num_samples`, **`durations [1, sequence_length] f32`** | **0.6–0.9 fp32** (extrapolated from *measured* iPad Pro 3rd gen / A12X / 4 GB via sherpa-onnx: **0.621**, Feb 2026). int8/fp16 effect unknown and possibly negative — the same benchmark measured Kokoro int8 builds *slower* (1.57–1.82) | 833 MB in that A12X measurement (fp32, sherpa-onnx harness) — **over the 400 MB bar**; the 86 MB q8f16 build should be far lower but is unmeasured | **Medium.** Obj-C API only (`OnnxRuntimeBindings`); SPM version lags the pod by 5 minor releases; write our own tensor plumbing and the durations→words fold | CoreML EP is not a real option here (below); dynamic `sequence_length` + LSTM + STFT keep it on CPU. Memory is the likely failure, not just speed |
| **3** | **MLX with `Device.cpu`** — already linked (mlx-swift 0.30.2, kokoro-ios 1.0.11) | Nothing new — the 327 MB fp32 safetensors already on the phone | Unchanged (MisakiSwift 1.0.6) | **Yes** — the existing `start_ts`/`end_ts` path, unchanged | **Unknown; likely 2–10.** No published number exists. MLX's iOS build compiles `no_cpu/compiled.cpp`, so there is **no kernel fusion at all** on CPU; GEMM goes through Accelerate/BNNS | fp32 weights ≈ 327 MB resident before activations — probably over the bar on its own | **Trivial** — set the default device to `.cpu` in the SpikeHarness | Almost certainly too slow, and `mx.compile` on a CPU stream throws `[Compiled::eval_cpu] CPU compilation not supported on the platform`. Worth 30 minutes as a control, not as a plan |
| **4** | **sherpa-onnx** (k2-fsa) Kokoro recipe | `model.onnx` 310–330 MB + `voices.bin` + `tokens.txt` + **`espeak-ng-data/`**; 686–718 MB archives | **Blocked today.** The shipped Kokoro English pipeline phonemizes through espeak-ng (GPL-3). Removing it is issue #3731, opened 2026-07-08, still open, slated for sherpa-onnx **2.0.0** | **No** — the TTS API returns samples, not durations | 0.6–0.9 (same A12X anchor, 0.621 *measured*) | 833 MB *measured* on A12X | Medium (C API + Obj-C/Swift bridge) | Licence blocker until 2.0.0 lands the `tokens` passthrough; no timings even then. **Rule out** |
| **5** | **ExecuTorch** — `pytorch/executorch` SPM (`swiftpm-1.0.0`), BSD-3 | `software-mansion/react-native-executorch-kokoro`: XNNPACK-optimised **fp32** `.pte`, split into duration-predictor + synthesizer, Apache-2.0 | Their C++ phonemizer ("Phonemis") — **licence not published on the model card**; we would use MisakiSwift instead and feed IDs | **Probably** — the duration predictor is a separate `.pte` that "predicts per-token durations" | **No published mobile number at all** | Unknown | **High.** No Swift API for this model; port the RN library's C++ pipeline | Zero benchmarks, fp32 only, unproven G2P licence. Not first |
| **6** | **GGML — `mmwillet/TTS.cpp`** | GGUF-style Kokoro | MIT, but "**GPL-3.0-or-later** if eSpeak NG support is enabled" | Not documented | **~1.11 on an M1 Max** with Q5_0 and **no Metal path for Kokoro** — an A13 would be several times worse | — | High (C++ bridge, no iOS support: "only currently supported on OS X") | **Rule out** |
| **7** | **Smaller model instead of Kokoro** | Kitten Nano EN v0.2 fp16 (*measured* A12X **RTF 0.368, 193 MB**) or Matcha-LJSpeech + Vocos (*measured* A12X **RTF 0.084, 211 MB**) | **Both blocked**: KittenTTS phonemizes with espeak-ng; the sherpa Matcha en_US archive ships `espeak-ng-data/`. Piper's upstream is now GPL-3.0 outright | **No** timings exposed by either | Would pass the speed bar comfortably | Passes | High — new engine, new voice, new timing story | Licence blocker is the *phonemizer*, not the model; a Misaki-phoneme-trained small model does not exist. Quality drop from Kokoro is large (LJSpeech single speaker / 15 M params) |

---

## Details per option, with sources

### 1. Core ML — `mattmireles/kokoro-coreml` (recommended)

- Repo: <https://github.com/mattmireles/kokoro-coreml> — Apache-2.0 (GitHub API `license.spdx_id = "Apache-2.0"`),
  created 2025-07-09, last push **2026-08-31**, 62 stars, 571 files.
- Model card: <https://huggingface.co/mattmireles/kokoro-coreml> (last modified 2026-07-25), licence
  `apache-2.0`, "inherited from Kokoro-82M".
- **The architecture** (README, "Why surgery?"): the monolithic model is cut into five stages —
  `kokoro_duration_t{32,64,128,256,320,384,512}` (CPU/GPU), an alignment matrix built in Swift,
  `kokoro_f0ntrain_t{120,280,400,600,1200}` (ANE), `kokoro_decoder_pre_{3,7,10,15,30}s` (ANE),
  `kokoro_decoder_har_post_{3,7,10,15,30}s` (ANE, iSTFT → waveform), plus the hn-NSF harmonic source
  in Swift/vDSP. "Everything is static and float16. No dynamic ops. No `RangeDim`. No `non_zero` kernels."
- **iPhone measurements** (README, "On iPhone"; June 2026, iOS 26.5, median of 5 warm calls,
  timing boundary = token IDs in → PCM out, so G2P is *excluded*):

  | Audio | iPhone 15 Pro Max (A17 Pro) | → RTF | iPhone 12 Pro (A14, 4 GB) | → RTF |
  |---|---|---|---|---|
  | 3 s | 702 ms (vs MLX 919) | 0.234 | 1,383 ms (vs MLX 1,624) | **0.461** |
  | 7 s | 1,492 ms (vs MLX 1,875) | 0.213 | 2,966 ms (vs MLX 2,405) | **0.424** |
  | 15 s | 3,272 ms (vs MLX 3,805) | 0.218 | 6,250 ms (vs MLX 5,022) | **0.417** |
  | 30 s | 6,374 ms (vs MLX 7,792) | 0.212 | 12,301 ms (vs MLX **OOM**) | **0.410** |

  The MLX comparator is `mlalma/kokoro-ios` **1.0.8** and its timing *includes* Misaki G2P, so the
  head-to-head slightly flatters Core ML. Note the A14 row where MLX wins the middle buckets
  (0.344 / 0.335) — that matches `kokoro-ios`'s own claim of "~3.3 times faster than real-time on
  the release build on iPhone 13 Pro" (RTF ≈ 0.30).
- **The disclosure that matters for us**, verbatim from the README: "the iPhone ANE compiler
  (A14 **and** A17 Pro) rejects the full-ANE plan that every M-series Mac runs (`ANECCompile() FAILED`),
  so iPhone rows use the staged policy — decoder-pre on the ANE, the other stages on CPU+GPU."
  The shipped policy (`swift-tts/Sources/KokoroTTS/KokoroComputePolicy.swift`, `gistDefault`) is
  duration `.cpuOnly`, f0ntrain `.cpuAndGPU`, decoderPre `.cpuAndNeuralEngine`, generator `.cpuAndGPU`,
  with a comment that "the padded duration graph can spend minutes in MPSGraph specialization on
  recent iOS builds". A `.cpuOnly` policy is also provided.
- **Requirements** (README): "iOS 18.0+ / macOS 15.0+ for the drop-in raw-text `KokoroTTS` SDK",
  "Apple Silicon (M1+) or **A15+** for Neural Engine acceleration", "Runs on older chips too, just
  slower". Crucially the *low-level* package `swift/Package.swift` declares `.iOS(.v16)` — the
  iOS-18 floor is only the high-level SDK, which we do not need.
- **Timings.** `swift/Sources/KokoroPipeline/KokoroPipeline.swift` defines
  `public struct SynthesisResult` with
  `public let tokenDurationFrames: [Int]` — "Per-input-token duration frame counts (BOS + phoneme
  ids + EOS), aligned with the caller's `inputIds` prefix" — plus per-stage `StageTimings`.
  `PipelineConstants.f0FrameRate = 80.0` and `samplesPerDurationFrame = sampleRate * 2 / f0FrameRate = 600`,
  i.e. 25 ms per duration frame at 24 kHz.
- **Vocab compatibility.** `runtime/kokoro-vocab.json` on HF is the canonical Kokoro symbol table
  (`ˈ`: 156, `ˌ`: 157, `ː`: 158, `ᵻ`: 177, …), identical to
  `hexgrad/Kokoro-82M/config.json` lines 34–148 that MisakiSwift already targets. Our existing
  token IDs go straight in.
- **Tensor contract** (README, "Tensor shapes"): `kokoro_duration_t128` takes
  `input_ids [1,128] int32`, `attention_mask [1,128] f16`, `ref_s [1,256] f16`, `speed [1] f16`
  and returns `pred_dur [1,128]` plus `t_en, d, s, ref_s_out`.
- **Download inventory** (HF API, `blobs=true`): 1,060 MB for everything. `sdk/starter/KokoroRuntimeManifest.json`
  pins revision `2e878c6a33c56b40de094ef8237bf15a83d233c5` and lists 10 packages + 1 voice = **473.9 MB**
  with a `sha256` for every file. A single-bucket subset is far smaller (see the spike protocol).
- **Prior art on the hard problem**: <https://github.com/k2-fsa/sherpa-onnx/discussions/2182>
  (2025-05-06) — sherpa-onnx's maintainer csukuangfj: "If you know anyone can use coreml with
  onnxruntime for kokoro tts, please let us know." kokoro-coreml is the answer to that thread, a year
  later, by going PyTorch → coremltools directly instead of through ONNX.

### 2. ONNX Runtime on iOS

- **Packaging.** `onnxruntime` is MIT (GitHub API). Latest release **v1.29.0, 2026-08-12**; latest
  patch v1.28.2, 2026-09-03. CocoaPods `onnxruntime-objc` has **1.29.0 published 2026-08-18**
  (trunk.cocoapods.org API). The official SPM package
  <https://github.com/microsoft/onnxruntime-swift-package-manager> is at **1.24.2 (2026-02-25)** and its
  `Package.swift` pulls `pod-archive-onnxruntime-c-1.24.2.zip`
  (sha256 `f7100a99…600b54`), platforms iOS 15 / macOS 14, products `onnxruntime` + `onnxruntime_extensions` 0.13.0.
- **EPs in the prebuilt iOS binary.** ONNX Runtime's XNNPACK EP doc states: "Pre-built binaries
  (`onnxruntime-objc` and `onnxruntime-c`) of ONNX Runtime with XNNPACK EP for iOS are published to
  CocoaPods." The same docs say the prebuilt iOS mobile package includes the CoreML EP. XNNPACK
  threading note from the same doc: it has its own threadpool, so set ORT intra-op threads to 1 and
  disable spinning, or the two pools fight.
- **The CoreML EP is not usable for this graph.** Its op list
  (<https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html>) covers neither
  **LSTM** nor **STFT/DFT**; MLProgram adds ConvTranspose/GroupNorm/LayerNorm but nothing that helps.
  Kokoro is StyleTTS2 — bidirectional LSTMs in the duration encoder and prosody predictor, and an
  iSTFT vocoder head. Reported partitioning on the Kokoro ONNX graph
  (<https://huggingface.co/hexgrad/Kokoro-82M/discussions/14>): "number of partitions supported by
  CoreML: 123, number of nodes in the graph: 2361, number of nodes supported by CoreML: 949" — 123
  partitions means 123 CPU↔CoreML round trips per call, which is reliably *slower* than plain CPU.
  Same thread reports CoreML rejecting the STFT `window_sum` shape (`{5000015}` > the 16384 dim
  limit) and dim-0 shapes. Treat "ONNX on iOS" as "ONNX on the CPU EP".
- **Graph contract — verified directly, not from a README.** I range-read the tail of
  `onnx/model_fp16.onnx` from
  `onnx-community/Kokoro-82M-v1.0-ONNX-timestamped` and decoded the GraphProto input/output block:
  - inputs: `input_ids` INT64 `[1, sequence_length]`, `style` FLOAT `[1, 256]`, `speed` FLOAT `[1]`
  - outputs: **`waveform` FLOAT `[1, num_samples]`**, **`num_samples`**, **`durations` FLOAT `[1, sequence_length]`**

  So the timestamped build takes phoneme token IDs directly (no espeak) and hands back per-token
  durations. `sequence_length` is symbolic — good for the CPU EP, another reason the CoreML EP is out.
- **File variants and sizes** (HF `onnx/` listing): `model.onnx` 326 MB, `model_fp16.onnx` 163 MB,
  `model_q4.onnx` 305 MB, `model_q4f16.onnx` 155 MB, `model_q8f16.onnx` 86.1 MB,
  `model_quantized.onnx` 92.4 MB, `model_uint8.onnx` 177 MB, `model_uint8f16.onnx` 114 MB.
  The README's Python example is exactly our shape: Misaki phonemes → ids from Kokoro's `config.json`,
  pad with 0 at both ends, ≤510 real tokens, `ref_s = voices[len(tokens)]` from a `[N,1,256]` f32 `.bin`.
- **Speed anchors.**
  - *iPad Pro 3rd gen (A12X, 4 GB, iPadOS 17+), sherpa-onnx, warm, English, published 2026-02-15*
    (<https://voiceping.net/en/blog/research-offline-tts-eval/>): Kokoro EN v0.19 **RTF 0.621, 4.01 tok/s,
    833 MB**; Kokoro Multi-lang v1.0 int8 **1.822, 515 MB**; v1.1 int8 **1.569, 588 MB**. Same run:
    Matcha+Vocos 0.084 / 211 MB, Kitten Nano EN v0.2 fp16 0.368 / 193 MB, Kitten Nano en v0.1 fp16
    0.407 / 108 MB, Kitten Mini EN v0.1 1.135 / 427 MB, VITS LJS int8 2.023, VITS VCTK int8 2.062.
    The A12X is the closest published silicon to an A13 (four Vortex performance cores at 2.5 GHz vs
    the A13's two Lightning cores at 2.65 GHz) — treat it as a same-class, not identical, proxy.
  - *Raspberry Pi 4B (Cortex-A72)*, sherpa-onnx docs
    (<https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html>): kokoro-multi-lang-v1_0
    fp32, 310 MB — RTF 7.635 / 4.470 / 3.430 / 3.191 at 1/2/3/4 threads; kokoro-en-v0_19 fp32, 330 MB —
    6.629 / 3.870 / 2.999 / 2.774. **Not transferable** to an A13 without a large factor; included only
    to show the shape of the thread scaling.
  - Server CPU numbers (e.g. the widely cited c6a.8xlarge "5x realtime" gist, 32 threads, AMD EPYC 7R32)
    are irrelevant here.

### 3. MLX on the CPU

This is the cheapest experiment and I can state its feasibility from primary source rather than guess:

- `mlx-swift/Package.swift` (Apple-platform branch) excludes `mlx/mlx/backend/no_cpu` — **the real CPU
  backend is compiled into the iOS build** — and defines `MLX_USE_ACCELERATE`, linking Accelerate.
  `mlx/backend/cpu/{matmul,conv,fft,gemms/bnns}.cpp` are all in the build.
- `Source/Cmlx/mlx-conditional/compiled_conditional.cpp`:
  `#if TARGET_OS_IOS || TARGET_OS_VISION` → `#include "../mlx/mlx/backend/no_cpu/compiled.cpp"`.
  `jit_compiler_conditional.cpp` explains why: "`JitCompiler` shells out via `std::system()`, which is
  unavailable on iOS and visionOS." So on iOS there is **zero CPU kernel fusion**; every elementwise op
  is a separate pass over memory. `mlx/backend/no_cpu/compiled.cpp` makes
  `compile_available_for_device(cpu)` return false (so `compile()` degrades to a passthrough rather
  than throwing) and `Compiled::eval_cpu` throws
  `"[Compiled::eval_cpu] CPU compilation not supported on the platform."` if it is ever reached.
- `Source/MLX/Device.swift` exposes `DeviceType.cpu`, `Device.cpu` and `withDefaultDevice(_:)`.
- MLX's `fast::` ops (layer norm, RoPE, SDPA) each carry a `fallback` selected by `use_fallback(stream)`
  in `mlx/fast.cpp`, so `MLXFast.layerNorm` — which `kokoro-ios`'s `LayerNormInference.swift` imports —
  will not hard-fail off the GPU.

Conclusion: `Device.cpu` **will run** on the A13, and will be slow. No one has published an MLX-CPU
TTS number on any iPhone. Run it as a 30-minute control, not as a candidate.

### 4. sherpa-onnx

- Kokoro model archives ship `espeak-ng-data/` (docs page above), and the English pipeline phonemizes
  through it. <https://github.com/k2-fsa/sherpa-onnx/issues/3731> (opened **2026-07-08**, still open):
  "espeak-ng is licensed under GPL, it introduces license constraints that are incompatible with the
  Apache-2.0 license of sherpa-onnx" — the fix is a breaking change landing in **sherpa-onnx 2.0.0**,
  replacing it with either a `lexicon.txt` or a new `tokens` field on `GenerationConfig` that accepts
  externally produced phonemes. Until that ships, sherpa-onnx's Kokoro path is a §1.1 violation.
- Even after 2.0.0, its TTS API returns audio, not durations, so read-along would need a second
  duration pass. Rule out.

### 5. ExecuTorch

- ExecuTorch is **BSD-3-Clause**; iOS runtime ships as prebuilt `.xcframework`s consumed via SPM
  (`.package(url: "https://github.com/pytorch/executorch.git", branch: "swiftpm-1.0.0")`), with Core ML
  and MPS backends available.
- `software-mansion/react-native-executorch-kokoro` (Apache-2.0, exported with ExecuTorch v1.0.0,
  "no forward compatibility guaranteed") ships **XNNPACK-optimised fp32** `.pte` files split into a
  duration predictor ("predicts per-token durations and prosody features") and a synthesizer.
  `react-native-executorch` itself is MIT; Kokoro support arrived in **v0.7.0**.
- Software Mansion's own post (<https://swmansion.com/blog/on-device-ai-beats-cloud-for-tts-heres-why/>,
  **2026-04-15**) says "getting Kokoro running on-device required writing a phonemizer from scratch in
  C++" but publishes **no device, latency, RTF or memory numbers at all**, and does not state the
  phonemizer's licence. We would not use their phonemizer anyway (MisakiSwift stays), but the absence
  of any benchmark plus fp32-only weights makes this a second- or third-choice spike.

### 6. GGML / llama.cpp

- No Kokoro support in `ggml-org/llama.cpp` (its `tools/tts` is OuteTTS + WavTokenizer); there is an
  open feature request, issue #11050.
- `mmwillet/TTS.cpp` (MIT, "**GPL-3.0-or-later** if eSpeak NG support is enabled") does support Kokoro,
  but: "This library is only currently supported on OS X", Metal acceleration is listed for Parler and
  Dia and **not** for Kokoro, and its best published figure is **RTF ≈ 1.11 on an M1 Max** with Q5_0.
  An A13 would be multiples worse. Rule out.

### 7. Smaller models

Every fast, permissively licensed alternative fails on the **phonemizer**, not the model:

- **KittenTTS** (`kitten-tts-nano`, 15 M params, ~56 MB) is Apache-2.0 but phonemizes with espeak-ng.
  Measured A12X: **RTF 0.368 / 193 MB** for Nano EN v0.2 fp16 — it would pass the bar. There is no
  Misaki-phoneme variant, so we would need an espeak-compatible G2P we are allowed to ship.
- **Matcha-icefall-en_US-ljspeech + Vocos**: fastest thing in the whole A12X benchmark
  (**RTF 0.084 / 211 MB**), 71 MB `model-steps-3.onnx`, but the sherpa archive contains
  `espeak-ng-data/` and no lexicon (the lexicon variant is the Chinese one). Single-speaker LJSpeech
  quality is a large step down from Kokoro.
- **Piper** is now GPL-3.0 upstream (`OHF-Voice/piper1-gpl`); the older MIT `rhasspy/piper` still
  reached espeak-ng through `piper-phonemize`, which is the same GPL linkage. Rule out.
- Neither exposes word timings through its shipping API.

The honest reading: MisakiSwift is what makes Kokoro legally usable for us, and no other permissively
licensed English TTS of comparable quality has a Misaki-compatible front end. A fallback model is a
*new* G2P project, not a drop-in.

---

## Licence audit — the recommended path (Core ML)

Everything that would be added to, or already sits on, the A13 Kokoro path.

| Component | Version / pin | Licence | Source |
|---|---|---|---|
| `KokoroPipeline` (from `mattmireles/kokoro-coreml`, `swift/`) | pin a commit; repo at `2026-08-31` | Apache-2.0 | <https://github.com/mattmireles/kokoro-coreml> (`LICENSE`; GitHub API `spdx_id: Apache-2.0`) |
| Kokoro Core ML `.mlpackage`s + `voices/*.bin` + `runtime/*.json` | HF revision `2e878c6a33c56b40de094ef8237bf15a83d233c5` | Apache-2.0 ("inherited from Kokoro-82M") | <https://huggingface.co/mattmireles/kokoro-coreml> |
| Kokoro-82M weights (upstream of the conversion) | v1.0 | Apache-2.0 | <https://huggingface.co/hexgrad/Kokoro-82M> |
| MisakiSwift | 1.0.6 (already shipped) | Apache-2.0 | <https://github.com/mlalma/MisakiSwift> — 32 files, `Resources/{us,gb}_{gold,silver}.json` + BART safetensors for OOV; **no espeak** |
| Apple Core ML / Accelerate / vDSP | system | Apple SDK terms | — |
| *(unchanged)* kokoro-ios `KokoroSwift` 1.0.11, mlx-swift 0.30.2, MLXUtilsLibrary 0.0.6, swift-numerics 1.1.1 | as in `docs/licenses.md` | MIT / MIT / Apache-2.0 / Apache-2.0 | already audited |

Not on this path and deliberately excluded: espeak-ng (GPL-3), piper-phonemize, sherpa-onnx's
`espeak-ng-data`, `bootphon/phonemizer` (GPL-3), TTS.cpp with eSpeak enabled.

Two things to check by hand during the spike, because `scripts/check-licenses.sh` only walks SPM checkouts:
1. `kokoro-coreml`'s `LICENSE` at the pinned commit (its README's Credits section names the sources but
   makes no licence declaration for third-party code — the repo-level Apache-2.0 is what we rely on).
2. `swift-tts` pulls `mattmireles/MisakiSwift` (a fork of `mlalma/MisakiSwift`, also Apache-2.0) — the
   **low-level `KokoroPipeline` package has zero dependencies**, so taking only `swift/` avoids a second
   MisakiSwift copy in the graph. Take `swift/`, not `swift-tts/`.

---

## One-day spike protocol — iPhone 11 Pro (A13, 4 GB, iOS 26.6.1)

Goal: one number — the median RTF of the Core ML pipeline on the A13 — plus peak footprint and one
timing sample, using the existing `spikes/SpikeHarness` conventions (`devicectl` install, Release
build with `ENABLE_DEBUG_DYLIB=NO`, `SPIKE_AUTORUN_SECONDS`, CSV out of the app container).

**Hour 0–1 — get the model files.** Minimal single-bucket set for a ~15 s bucket at ≤256 tokens
(sizes and `sha256` from `sdk/starter/KokoroRuntimeManifest.json`, revision
`2e878c6a33c56b40de094ef8237bf15a83d233c5`):

| File | Bytes | tree sha256 (prefix) |
|---|---|---|
| `coreml/kokoro_duration_t256.mlpackage` | 50.0 MB | `dd0953c711a9bc6f…` |
| `coreml/kokoro_f0ntrain_t600.mlpackage` | 20.6 MB | `c01fc9efa172c636…` |
| `coreml/kokoro_decoder_pre_15s.mlpackage` | 67.3 MB | `0c2a481aad2af83a…` |
| `coreml/kokoro_decoder_har_post_15s.mlpackage` | 39.7 MB | `156fbd526c9eac2f…` |
| `voices/af_heart.bin` | 522,240 | `d583ccff3cdca2f7fae535cb998ac07e9fcb90f09737b9a41fa2734ec44a8f0b` |
| `runtime/kokoro-vocab.json`, `runtime/hnsf_weights.json` | 1,159 / 336 | in `sdk/SDKReleaseManifest.json` |

≈ **178 MB**. Add `kokoro_duration_t128` (44.5 MB) + `f0ntrain_t280` + `decoder_pre_7s` +
`decoder_har_post_7s` only if you also want the 7 s bucket. Download with
`https://huggingface.co/mattmireles/kokoro-coreml/resolve/<revision>/<path>`; verify each `sha256`
before staging, the same way `scripts/fetch-kokoro-model.sh` does today.

**Hour 1–3 — build.** Add `.package(url: "https://github.com/mattmireles/kokoro-coreml", revision: <pin>)`
and depend on the `KokoroPipeline` product from a new `spikes/SpikeHarness` target arm (it declares
`.iOS(.v16)`, so no deployment-target change). Do **not** take `swift-tts` — it declares iOS 18 and drags
in a second MisakiSwift. Stage the `.mlpackage`s as a resource group so Xcode compiles them to
`.mlmodelc` in the bundle. Sanity-build for the simulator first; then Release for `generic/platform=iOS`.

**Hour 3–5 — the smallest experiment that yields all three numbers.** Reuse the harness's existing
sentence corpus so the A13 Core ML arm is directly comparable to the A19 MLX arm:

1. Feed each sentence through the app's existing MisakiSwift path to get token IDs (this is already
   `KokoroEngine`'s front half) — that also proves the vocab really matches.
2. Call `KokoroPipeline` with `KokoroComputePolicy.gistDefault`; log per sentence:
   `wallTimeSeconds`, `audioDurationSeconds`, the `StageTimings` breakdown
   (`durationCoreML / f0ntrainCoreML / decoderPre / hnsfSwift / generatorCoreML`), the chosen bucket,
   and `os_proc_available_memory()` / `task_vm_info.phys_footprint` after each call.
3. Repeat once with `KokoroComputePolicy.cpuOnly`. On an A13 the GPU is the weakest part relative to
   the CPU, and the shipped policy puts two stages on `.cpuAndGPU`; this second run costs ten minutes
   and may be the whole finding.
4. Write `sentence-N.wav` for the first three sentences plus a `timing` row per token from
   `tokenDurationFrames`, so §7.4's Audacity check can run unchanged.

Discard the first two calls per configuration (Core ML compiles on first load — the README warns
"cold start takes a few seconds"). Report the **median of the warm calls**, matching the comparator's
methodology.

**Hour 5–6 — the free control.** In the existing MLX arm, wrap synthesis in
`MLX.Device.withDefaultDevice(.cpu) { … }` and run one sentence with a generous timeout. Either it
produces audio (record the RTF) or it fails; both outcomes are one line in the findings file. Do not
spend more than an hour here.

**Hour 6–8 — write it up** in `spikes/findings/` using `TEMPLATE.md`, alongside the existing
`2026-09-03-runtime-benchmark.md`.

### Pass / fail

| Outcome | Decision |
|---|---|
| Median warm RTF **≤ 0.35** and peak footprint ≤ 400 MB and timings line up with the WAV | Ship Kokoro on A13 through Core ML. Then decide whether A14+ *also* moves to Core ML (it is 1.2x faster than MLX on the A17 Pro and never OOMs) or the app carries two Kokoro backends |
| RTF **0.35–0.75**, footprint ≤ 400 MB, timings good | The interesting case, and the one I expect. Kokoro is viable on A13 **with the maximum rate capped** at `0.8 / RTF` — the app already disables rates above that rather than lowering them silently. This is a product call: "Kokoro at up to ~1.5x on an iPhone 11 Pro" vs "system voice at 4x". Take it to the owner with the measured cap, and check thermals at the capped rate before shipping |
| RTF **> 0.75**, or peak footprint > 400 MB, or the ANE/MPSGraph path fails on family-6 hardware | Stop. Do **not** proceed to the ONNX spike on the strength of hope — its only same-class anchor is *worse* (0.621 on A12X at 833 MB). Keep `SystemSpeechEngine` on pre-A14 and close Plan 0 Task 8 |
| Any run traps, OOMs, or `ANECCompile()` fails and `.cpuOnly` is also too slow | Same as above; record the exact failure the way the MLX finding did |

Timing correctness is a **gate, not a metric**: `PipelineConstants` implies 25 ms per duration frame
(600 samples at 24 kHz) while the ONNX community's timestamp recipe divides by 80 (12.5 ms). One of
those is wrong for our units. Verify against the WAV before believing any read-along output.

---

## What I could not confirm

Extrapolations and gaps, explicitly:

1. **Every A13 RTF in this note is extrapolated.** No published Kokoro measurement exists on any A13
   device, in any runtime. The A14 (0.41–0.46) and A12X (0.621) figures are real; the A13 range
   (0.50–0.65) is my interpolation and could be wrong in either direction by a wide margin.
2. **The A13-vs-A14 scaling factor.** I could not fetch Geekbench's device pages (browser.geekbench.com
   returns 403 to this tool). Search snippets suggested GB6 single-core ≈ 1,306 (A13) vs 1,574 (A14),
   but I did not verify them against the primary source. My 1.2–1.4x factor is an assumption. The GPU
   gap is probably larger than the CPU gap, which matters because the shipped iPhone compute policy
   puts two of four stages on `.cpuAndGPU`.
3. **Whether kokoro-coreml runs at all on Apple GPU family 6.** The README's "Runs on older chips too,
   just slower" is the author's claim; the oldest device he actually measured is an A14. Core ML's
   MPSGraph and ANE paths on an A13 under iOS 26 are untested for this graph. This is the spike's
   primary binary risk.
4. **Peak memory for the Core ML path.** I computed ~166 MB of fp16 weights for one bucket from the
   published file sizes; activations, Core ML's compiled-model overhead and the `har [1,22,28801]`
   excitation buffer are not in that figure. The only evidence it fits in 4 GB is that the iPhone
   12 Pro completed the 30 s bucket.
5. **Whether the ONNX q8f16 / fp16 builds are faster or slower than fp32 on Apple ARM.** The one
   same-class data point (A12X) shows Kokoro *int8* builds at 1.57–1.82 vs *fp32* at 0.621 — but those
   are different models (multi-lang v1.0/v1.1 vs en v0.19), so it is not a clean comparison. ORT's
   dynamic-quantisation path on ARM64 is a known variable I did not resolve.
6. **The exact ONNX `durations` unit.** I verified the tensor exists, its name, dtype and shape by
   reading the model file. I did **not** verify what a unit of `durations` means in seconds; the
   community recipe's divisor of 80.0 conflicts with kokoro-coreml's 40 fps duration frames.
7. **Whether the voiceping iOS benchmark ran on-device or under Rosetta/simulator**, its thread count,
   its sherpa-onnx version, and whether RTF is median or mean. The post states devices, warm mode and
   "English synthesis only", and nothing else about methodology. Treat 0.621 as an order-of-magnitude
   anchor, not a precise figure.
8. **The licence of Software Mansion's "Phonemis" C++ phonemizer.** Not published on the model card and
   I could not find its repository. Irrelevant if we keep MisakiSwift, but it blocks any "just use
   react-native-executorch's pipeline" shortcut.
9. **Whether ONNX Runtime's SPM package at 1.24.2 has the same EP set as the 1.29.0 pod.** The docs
   describe the *pods*; the SPM package wraps `pod-archive-onnxruntime-c-1.24.2.zip`, which is the same
   artifact family, but I did not open the archive to confirm CoreML/XNNPACK are compiled in.
10. **Whether `mx.compile` is reached anywhere in kokoro-ios's forward pass.** If it is, the
    `Device.cpu` control will throw rather than run slowly. The code path selection
    (`compile_available_for_device` returning false → passthrough) says it should be fine, but I did
    not read `KokoroSwift`'s call sites.
11. **kokoro-coreml's `ios-bench` currently needs locally exported `.mlpackage`s** (`prepare_resources.sh`
    copies from `../coreml/`, and it references `kokoro_duration_exact_t{44,105,219,476}` packages that
    are **not** in the HF repo). Using the published HF artifacts means using the padded
    `kokoro_duration_t*` models, not the "exact" ones — likely a small speed penalty I have not quantified.
