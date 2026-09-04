# Spike: a Kokoro runtime for pre-A14 phones — Core ML on the iPhone 11 Pro

**Spec section:** §7.3 Step 5 / Plan 0 Task 8 (addendum), with §7.4 and §7.5 data for this runtime
**Date:** 2026-09-03 → 2026-09-04
**Devices:** iPhone 11 Pro (A13, 4 GB, iOS 26.6.1), on USB and charging throughout
**Harness commit:** 28c5202 (Core ML arm, autorelease per sentence, bucket selection, warm-skip analysis)
**Runtime:** `mattmireles/kokoro-coreml` low-level `KokoroPipeline` package (Apache-2.0), models from Hugging
Face revision `2e878c6a` with hashes from the corrected manifest at `32399b33` (see `scripts/fetch-kokoro-coreml.sh`),
buckets 7 s + 15 s, duration models t128 + t256; G2P MisakiSwift 1.0.6 with MLX pinned to the CPU.

## Question
kokoro-ios/MLX cannot run on Apple GPU family 6. Can Kokoro-82M run on the A13 through Core ML at the
spec's bar (median warm RTF ≤ 0.35, peak footprint ≤ 400 MB, no thermal state 2 for 20 minutes at the
highest offered rate), with word timings good enough for read-along?

## Method
The spike harness's Core ML arm (`CoreMLBench.swift`): MisakiSwift phonemes → Kokoro's 178-symbol vocab →
token IDs → the four Core ML stages → PCM and per-token duration frames. Each run is a `devicectl` autorun
over the 50-sentence corpus; CSV rows per sentence (RTF with and without G2P, per-stage times,
`phys_footprint`, thermal state, battery); the first two calls per configuration are discarded (Core ML
compiles compute plans on first use). Analysis: `spikes/analyze.py` (warm-skip 2, grouped by
engine/policy/buckets). Timing gate: `spikes/timing_check.py` plus an energy envelope over the three WAVs.
An earlier run (2026-09-03, harness 523d0c3) had no autorelease pool around the bench loop and only the
15 s bucket staged; its numbers (RTF 0.56, footprint growing +23 MB per sentence to 1.6 GB, jetsam) were
measurement artifacts and are superseded by the runs below.

## Results

| Run | Policy | Rate | Length | Sentences | Median RTF | p90 | Peak footprint | Footprint slope | Thermal | Load |
|---|---|---|---|---|---|---|---|---|---|---|
| B | default (CPU+GPU+ANE) | flat out | 300 s | 134 | 0.373 | 0.511 | 1,198 MB | flat (−0.3 MB/sentence) | state 2 at +3 s (phone already hot) | 4.6 s |
| C | cpuOnly | flat out | 300 s | 267 | **0.181** | 0.246 | **116 MB** | flat (0.00) | state 2 at +2 s (phone already hot) | 5.3 s |
| F | cpuOnly | 4x | 1200 s | 801 | **0.163** | 0.238 (max 0.335) | **119 MB** | flat (0.00) | state 1 at +50 s, **state 2 at +150 s**, held to the end; RTF never exceeded 0.335 | 2.9 s |
| H | MLX on CPU (control) | flat out | — | 5 | 15.0 | — | 420 MB, rising | — | state 2 at +70 s | — |

- First launch after install: 206 s to build Core ML compute plans (2026-09-03 run); every later launch 3–5 s.
- Stage split, cpuOnly warm call: generator 0.75–0.87 s of ~1.0 s; duration 0.08–0.09 s; the rest under 0.04 s each.
- Bucket use: 7 s bucket for 88–90% of sentences, 15 s for the rest; duration model t128 for all.
- Battery: 100% → 100% on charge (no drain figure yet; the unplugged run is still to do).
- Word timings (three WAVs, per-word rows folded from duration frames at 600 samples = 25 ms per frame):
  worst word-**onset** error 55 ms (bar ±100 ms); word-**end** errors up to 315 ms because the trailing pause
  is charged to the word rather than the punctuation. The energy envelope confirms speech fills the file
  (12.5 ms per frame would leave the second half silent), so the 25 ms constant is settled from the audio.

## Decision
**Core ML, CPU-only, is the Kokoro runtime for pre-A14 phones — and passes the bar on the A13.**
- RTF 0.16–0.18 ≤ 0.35: the app's rule `0.8 / RTF` gives 4.4, so every listed rate up to 4x is offered; no cap.
- Footprint 119 MB ≤ 400 MB, flat over 20 minutes and 800 sentences.
- Thermals: state 2 was reached after 150 s of continuous 4x synthesis *on a charging phone*, and the
  phone throttled without ever falling below real time (max RTF 0.335). Charging heat is a confound the
  owner raised; the spec's "no state 2 in 20 minutes" reading is therefore **not met on charge at 4x** and
  **unmeasured unplugged**. Recorded as a follow-up, not a blocker: at 1–2x the duty cycle is 16–33%,
  and the app's render-ahead means synthesis is bursty rather than continuous.
- The GPU-assisted `default` policy is slower (0.37) and needs 1.2 GB on this chip; do not use it on family 6.
- MLX on the CPU is not an option (RTF 15).
- Word timings pass the onset gate; word ends need the trailing-pause fix in the fold (assign the pause after a
  word's last phoneme to the following punctuation token, not the word).

Owner's decision (2026-09-04): this becomes the engine in the app, and newer phones are offered the best
measured architecture too — which means Core ML is the baseline everywhere until an MLX measurement on an
A14+ phone beats it by a margin that changes an offered rate or battery life.

## Fallback taken (if any)
None. Follow-ups: (1) a 20-minute unplugged run at 4x for the thermal and battery numbers; (2) measure
`cpuOnly` vs `default` on an A14+ phone before choosing the policy there; (3) the word-end pause fix in the
timing fold.

## Evidence
CSV/WAV/log files from this session, kept outside the repo: `scratchpad/spike8b/runs/{B-default-b715-300,
C-cpuonly-b715-300,F-cpuonly-rate4-1200,H-mlxcpu}/final/spike-*.csv`, `spike8-rescue/spike-1788489345.csv`
(the superseded 2026-09-03 run) and `sentence-{0,1,2}.wav`, `spike8b/pausegate-runA.txt` (timing gate).
