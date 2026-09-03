# Spike: runtime RTF, memory, thermals — MLX path

**Spec section:** §7.3, §7.5 (and §7.4, which depends on a runtime that runs)
**Date:** 2026-09-03
**Devices:** iPhone 11 Pro (A13, 4 GB, iOS 26.6.1) ; iPhone 17 Pro (A19 Pro) — PENDING
**Harness commit:** e98385f (kokoro-ios 1.0.11, mlx-swift 0.30.2, Release build, `ENABLE_DEBUG_DYLIB=NO`)

## Question
On the slowest supported phone, how fast does Kokoro-82M synthesize through kokoro-ios/MLX, how
much memory does it hold, and does it stay cool at 3x — the numbers spec §3.6 and §7.5 need.

## Method
Release harness installed with `devicectl`, launched with `SPIKE_AUTORUN_SECONDS=300` (flat out),
console attached on the second attempt to capture MLX's error text. Two launches, same result.

## Results
| Metric | iPhone 11 Pro (A13) | iPhone 17 Pro |
|---|---|---|
| Model + voices load | succeeds (~2–3 s from launch to first `generateAudio`) | pending |
| First `generateAudio` | **fatal MLX error** in `KokoroTTS.predictDurations → MLXArray.item → mlx_array_eval`: `[metal::Device] Unable to load kernel steel_gemm_fused_nt_float32_float32_bm64_bn32_bk32_wm2_wn2_… Compilation failed due to an interrupted connection: XPC_ERROR_CONNECTION_INTERRUPTED. This error occurred after multiple retries.` (`MLX/ErrorHandler.swift:343`, SIGTRAP) | pending |
| Median RTF, flat out | not measurable | pending |
| Peak footprint | not measurable (no `sentence` rows were logged) | pending |
| Thermal at 3x for 20 min | not measurable | pending |

Cause: MLX's fused GEMM kernels (`mlx/backend/metal/kernels/steel/gemm/mma.h`) are written on
`simdgroup_matrix`, which Metal provides from Apple GPU family 7 (A14 / M1) upward. The A13 is
family 6, so the Metal compiler cannot build the pipeline state; the XPC interruption is how the
failed compile surfaces, and MLX's error handler traps rather than throwing. Deterministic across
launches; unrelated to memory (the load itself was fine) and to the harness changes (the crash is
inside the first synthesis call).

## Decision
1. **The MLX route has a hard device floor of A14 (iPhone 12) or newer.** `KokoroEngine` must not
   be selected on older hardware: probe `MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7)`
   at configuration time and route the whole document to `system:<voice>` on failure, exactly as
   Plan 5 Task 5 already requires for a failed model load. Spec §7.3/§7.5 gain a "supported
   devices" line; §3.6 keeps its illustrative figures until the 17 Pro numbers exist.
2. The §7.3/§7.5/§7.4 measurements move to the iPhone 17 Pro (the protocol is one command; see
   `spikes/README.md`). Those numbers set the rate threshold and memory limits for A14+ phones.
3. Whether the iPhone 11 Pro — the product owner's own phone — gets Kokoro at all is now the
   CoreML/ONNX question spec §7.3 Step 5 timeboxes (a runtime that does not need
   `simdgroup_matrix`). That is a separate spike with its own timing-accuracy question; it is not
   answered here.

**Product decision (owner, 2026-09-03):** ship Kokoro through MLX on A14+ devices as soon as the
17 Pro numbers pass, keep `SystemSpeechEngine` on older phones, and run a separate timeboxed spike
(Plan 0 Task 8) on an ONNX Runtime / CoreML Kokoro that would cover the A13.

## Fallback taken (if any)
On the A13 the app keeps `SystemSpeechEngine`. No Kokoro numbers exist yet for any device.
