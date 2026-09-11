# Quantizing our Kokoro Core ML export: the recipe, what ONNX buys us, and publishing it

_2026-09-11, later the same evening as `2026-09-11-kokoro-quantization-quality.md` (which surveyed what
other people report about quantizing Kokoro). That doc's headline — "nobody has published a quantized
Core ML Kokoro yet" — is now wrong; see below. This one is hands-on: five researchers ran coremltools
directly against our 14 staged `.mlpackage` files on this Mac, cross-checked each other, and answer the
owner's three questions — how, does ONNX help, can we publish it._

## Short version

1. **How:** `coremltools.optimize.coreml.linear_quantize_weights` runs directly on the fp16 `.mlpackage`
   files we already have — no PyTorch, no re-export, seconds per file. Verified on this Mac. It roughly
   halves every stage's weight bytes; the compiled `.mlmodelc` keeps the compressed weights, so both the
   download and the phone's linked footprint shrink, and the existing hard-link dedupe survives. Nothing
   speeds up on the iPhone 11 Pro's CPU path — Apple decompresses to fp16 at load, so this is a size lever
   only, and plan-build time on the A13 is unmeasured and could go either way.
2. **ONNX:** not as a conversion path (dead end — no ONNX→Core&nbsp;ML converter exists anymore, and the
   alternatives would replace our whole Swift runtime). As evidence, yes: the community's 8-bit ONNX
   export tells us which two things to leave alone (the last conv, and the two transposed convs in the
   generator) and gives a rough upper bound on how much numeric error is safe.
3. **Publish:** yes. Apache-2.0 all the way from hexgrad's weights through to our derivative, hexgrad's
   own card invites it, Hugging Face hosting and bandwidth are free, and three other people already
   shipped an 8-bit Core ML Kokoro this year. The one thing that isn't automatic: our installer's
   `repositoryURL` is hard-coded to `mattmireles/kokoro-coreml`, so serving our own files — quantized or
   not — needs a small code change, not just new files on the Hub.

## 1. How to quantize it

### The recipe, verified on our files

`coremltools` 9.0 (current PyPI release; needs Python 3.9–3.13, not the Mac's default 3.14 — see
"Doing it on this Mac" below) loads an `.mlpackage`, rewrites its large weight tensors into a compressed
op, and re-serializes it:

```python
import coremltools as ct
import coremltools.optimize.coreml as cto

m = ct.models.MLModel(path, skip_model_load=True)
config = cto.OptimizationConfig(
    global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8", granularity="per_channel"),
    op_name_configs={"weight_101_to_fp16": None, "op_416_to_fp16": None, "op_1798_to_fp16": None},  # exemptions, see below
)
cto.linear_quantize_weights(m, config).save(out_path)
```

This ran against copies of our shipped files (`App/Resources/KokoroCoreML/coreml/*.mlpackage`) and
produced real output:

| stage | fp16 weight bytes | int8 per-channel | 6-bit palettized | time |
|---|---|---|---|---|
| `kokoro_f0ntrain_t120` | 20.5 MB | 8.5 MB | 6.3 MB | 1–2 s |
| `kokoro_decoder_har_post_3s` | 39.4 MB | 19.8 MB | 14.8 MB | 4–6 s |
| `kokoro_decoder_pre_3s` | 67.2 MB | ~33.7 MB | ~25.2 MB | ~10 s (est.) |
| `kokoro_duration_t128` | 38.9 MB | 19.6 MB | 14.7 MB | 66 s (unrolled LSTM, 5,396 weight tensors) |

Summed over the four **distinct** stages (buckets share weights already): fp16 166 MB → int8 ~82 MB →
6-bit ~61 MB. Against the manifest's 227 MB of distinct download bytes (`docs/research/2026-09-11-kokoro-
quantization-quality.md`'s byte accounting is off by a little: voices are 14.6 MB not 4 MB, and the two
duration `model.mlmodel` files add another 16.5 MB outside `weight.bin`), that's roughly **227 → ~120 MB
at int8**, matching the earlier research's estimate.

What we get for free from our iOS 18 floor: every `coremltools` compression mode runs, including the
iOS 18-only ones (4-bit, per-block, grouped-channel LUTs) — but reaching them needs either a fresh
PyTorch export with `minimum_deployment_target=ct.target.iOS18`, or an undocumented-but-verified trick:
`coremltools.models.utils._apply_graph_pass(mlmodel, pass, spec_version=9)` re-serializes our existing
iOS 15-opset packages at the iOS 18 opset in about a second, no PyTorch needed. int8 and 6/8-bit
per-tensor palettization need none of this — they run on our files as shipped and Core ML just bumps the
package to iOS 16's spec version automatically.

**Quality, honestly:** the probes above ran on random synthetic inputs, which is a plausibility check, not
a verdict — one draw even produced `NaN` on the un-quantized fp16 model, and re-running the same
comparison twice gave meaningfully different magnitudes (though the same *ordering*). The one thing worth
trusting from these probes is the **relative ranking**: the duration model's LSTM path and the generator
(`decoder_har_post`) are more sensitive than `f0ntrain`/`decoder_pre`; per-tensor int8 (vs. per-channel)
is clearly worse; anything below 6 bits degrades visibly. Getting a real answer needs real inputs — and we
already have the plumbing: `KokoroSynthesisExecutor.executeKokoroSynthesis(...tensorDump:)` is public and
writes every stage's actual tensors (`en`, `s`, `f0`, `n`, `x_pre`, `har`, `pred_dur`, `waveform`, …) to a
documented raw format; a model-backed Swift test that calls it for a fixed sentence list, next to
`KokoroCoreMLLoadTests`, is the one piece of new code needed to make the coremltools comparison mean
anything.

**External evidence that 8-bit is safe**, for calibration: FluidAudio's shipped 8-bit Core ML Kokoro chain
(see §3 below) measures `waveform corr = 0.806`, `mel-spectrogram corr = 0.994` against the PyTorch
reference — a real number, not ours, but the closest thing to ground truth anyone has published. cstr's
GGUF Q8_0 port keeps 9 of 16 internal stages at cosine ≥ 0.999 against the fp32 reference and reports an
identical ASR round-trip transcript.

### The starting exclusion list

Two independent lines of evidence — the community's 8-bit ONNX export (see §2) and our own reconstruction-
error probe — agree on where to be careful:

- **`conv_post`** (the decoder's very last conv, shape `22×128×7`, ~20 KB): every 8-bit ONNX export and
  every published 8-bit Core ML port leaves this alone. It's tiny, so exempting it costs nothing.
- **The two `ConvTranspose` upsamplers in the generator** (2.62M + 0.39M elements, ~6 MB fp16, shared
  across all four decoder buckets): `onnxruntime` structurally cannot quantize this op, so there's no
  external evidence either way; keep fp16 until a real-input test says otherwise.
- **`f0ntrain`'s LSTM weights**: stored fp32 in the shipped export (7.3 MB, not the 2.6 MB an early note
  said), the only fp32 weights outside a `float16` package. Exempting them costs 5.5 MB of the 20 MB
  stage; our probe's error was dominated by this path when everything else was quantized.

Everything else — ALBERT, the duration/prosody LSTMs and convs, the AdaIN blocks, the generator's
resblocks — has direct 8-bit precedent from either the ONNX exports or the other Core ML ports below, with
no reported issues.

### What doesn't change, and what does

- The compiled `.mlmodelc` keeps the compressed weights byte-for-byte (`xcrun coremlcompiler compile`
  verified on fp16 and int8 copies); quantizing a bucket variant with the same recipe still produces
  byte-identical `weight.bin` across buckets (verified for two of the three shared-weight groups), so
  `KokoroCoreMLInstall.linkDuplicateWeights` keeps working unchanged.
- **The Swift runtime needs no changes** to load a compressed package — Core ML decompresses the
  constexpr ops itself, and `MLModel`/`MLModelConfiguration` don't care.
- **The installer does.** `KokoroCoreMLManifest.repositoryURL` is hard-coded to
  `https://huggingface.co/mattmireles/kokoro-coreml`, and `File.url` resolves against it — we can't add a
  revision to someone else's repository. Quantized files mean our own hosting (the R2 mirror already
  planned in `docs/HANDOFF.md`, and/or a Hugging Face repo of our own, §3) plus the small code change that
  plan already anticipates: a `mirrorURL`/`repositoryURL` swap and a new pinned revision. The app's
  revision-keyed install/plan-cache/render-key design (spec §5) means this "just works" once the URL and
  hashes point at the new files — every phone re-downloads and re-warms once, by design.
- **Nothing gets faster on the A13.** Apple's docs are explicit: the CPU path (and often the GPU)
  decompresses weights to fp16 *at load time*, so resident memory and per-inference latency stay exactly
  what they are today. This is a download-size and disk-footprint lever only. Whether **plan-build time**
  changes (today: 60 s and 235 s for the two longest stages) or the ~600 MB–1 GB plan cache shrinks is
  genuinely unknown — Apple documents no such thing either way, and the one piece of real field evidence
  found (an ExecuTorch report on an M1 Pro) showed a quantized model taking *three times longer* to load
  than fp32, not less. This has to be measured on the phone, not assumed.

### Doing it on this Mac

Python 3.14 (the Mac's default) and Homebrew's 3.12 both fail (`pyexpat` is broken against this system's
libexpat), which breaks `pip` under either. The Xcode Command Line Tools' `/usr/bin/python3` (3.9.6) works
fine: `/usr/bin/python3 -m pip install --target ./pylib coremltools numpy` (~9 s, ~70 MB; k-means
palettization additionally needs `scikit-learn`). No PyTorch is needed for any of the above — only a full
re-export (changing the stage split, adding `EnumeratedShapes`, or replacing the duration model's unrolled
LSTM with a real `lstm` op) would need upstream's pinned `torch==2.5.0` + `coremltools==8.3.0` + `misaki`
toolchain and the 327 MB PyTorch checkpoint, on Python 3.9–3.12.

### A free win found along the way, independent of quantization

`ct.utils.save_multifunction` merges `kokoro_duration_t128` and `_t256` into one iOS 18 package with
shared weights: 77.9 MB → 39.1 MB, no PyTorch, 113 s. This is the ~39 MB duplicate the earlier research
doc flagged; it needs `KokoroPipeline` to load one package by `functionName` instead of two packages, and
it's orthogonal to quantization (could be done before, after, or instead of it).

## 2. Does the ONNX version help?

**As a conversion path: no.** `coremltools` 9.0 has no ONNX importer (removed years ago); `onnx2torch`
doesn't support the ops Kokoro's ONNX export uses (LSTM, `MatMulInteger`, `DynamicQuantizeLinear`);
`onnxruntime`'s Core ML execution provider has no LSTM or quantized-op support either, and using it would
mean replacing our whole Swift `KokoroPipeline` runtime with an ONNX Runtime session — throwing away the
bucketed static-shape design, the compute-unit placement, and the plan-cache understanding we already
have, for a hypothetical no better than what direct `coremltools` compression already gives us.

**As evidence: yes, in three ways.**

1. **The exclusion list**, already folded into §1 above: the shipped `onnx-community/Kokoro-82M-v1.0-
   ONNX` 8-bit file (I downloaded and inspected it directly, 86 MB) quantizes *every* weight-bearing node
   to int8 except `conv_post` and the six `ConvTranspose` ops. Two independent people (the onnx-community
   upload and Adrian Lyjak's own from-scratch replication) converged on the same single named exception,
   `conv_post` — worth trusting.
2. **A conservative bound.** The ONNX 8-bit export quantizes weights *and* activations dynamically
   (`DynamicQuantizeLinear` → `MatMulInteger`/`ConvInteger`, uint8 per-tensor); our plan is weight-only
   int8 with fp16 activations, which is a strictly smaller set of approximations at every layer both
   schemes touch. So "the community reports 8-bit ONNX sounds fine" is reasonable grounds to expect our
   coarser-grained Core ML int8 to sound at least as fine — but this is an inference from how the two
   schemes work, not something any source states outright, and it says nothing about the two
   `ConvTranspose` upsamplers ONNX never touches.
3. **A reference oracle**, if wanted: `onnxruntime` runs fine on this Mac, and Adrian Lyjak's calibration
   set (120 sentences) and his log-mel-distance function are reusable to sanity-check thresholds. Better
   still is upstream's own PyTorch pipeline (`kokoro/coreml_pipeline.py` in the `mattmireles/kokoro-coreml`
   GitHub repo) run against our *exact* weights, though it currently only exercises one of our four stage
   types end-to-end (the har-post/generator path) rather than all four.

There's no public recipe for how the ONNX 8-bit files were actually made (no script is published for the
exact `q8f16` variant), so nothing there is a template to copy — only the finished artifact is useful, as
described above.

## 3. Publishing it on Hugging Face

**The licence chain is clean.** `hexgrad/Kokoro-82M` is Apache-2.0 and its README says outright: *"Ship
it. Sell it. Fork it. ... We welcome the deployment of the model in real use cases."*
`mattmireles/kokoro-coreml` is Apache-2.0 too (`docs/licenses.md` already has both rows). Neither ships a
`NOTICE` file, so Apache §4(d) doesn't bind us; what's required is a `LICENSE` file, credit to hexgrad
and mattmireles in the README, and a note of what changed (Apache §4(b)/(c)). hexgrad's card also carries
a small Creative Commons attribution table for two training corpora — worth copying verbatim into our card
since it's the clearest example of an "attribution notice" the chain actually has.

**We would not be first.** Contrary to the earlier research doc, at least three groups have already
shipped an 8-bit Core ML Kokoro this year, all via k-means palettization, none with a published per-layer
sensitivity study:

- **`aufklarer/Kokoro-82M-CoreML-INT8`** (2026-04-19): one end-to-end 5-second-bucket model, 83 MB vs.
  310 MB fp16-storage-as-fp32(!) reference, reports a log-spectral distance of 0.42 ("close to inaudible")
  and zero duration-frame drift.
- **`laishere/kokoro-coreml`**, shipped as `FluidInference/kokoro-82m-coreml`'s `ANE/` folder and consumed
  by the FluidAudio Swift library since April: seven stages, `palettize_weights(nbits=8, mode="kmeans")`
  applied globally, with two stages (`Noise`, `Tail`) kept in **fp32** — not for weight-precision reasons,
  but because Kokoro's harmonic-source phase accumulation collapses audibly in fp16 compute. (Our export
  computes that phase accumulation in Swift already, so this doesn't apply to us — but it's a real
  quantization-adjacent hazard worth remembering if the fp16 `har_post` decoder is ever revisited.) This
  chain's measured parity against PyTorch — `waveform corr 0.806`, `mel corr 0.994` — is the best evidence
  anyone has published that 8-bit Core ML Kokoro sounds right.
- **`smdesai/kokoro-82m-coreml`**: a `*_mixed_int8` variant, no quality data published.

None of them is a drop-in for our staged 14-package design (they're single- or seven-bucket, ANE-oriented
pipelines), but all three are usable as card templates, and their existence is the answer to "would this
be normal to publish" — yes, this is exactly what other people do with Kokoro Core ML conversions.

**Hosting is free.** Public storage on the Hub is "best-effort" free with no per-repo size cap, egress and
CDN are included at no cost, and nothing in the terms of service singles out apps using the Hub as a
download source — WhisperKit (11.6M downloads) and FluidAudio both do exactly this, and Hugging Face's own
rate-limit docs name "AI applications" as expected resolver traffic. Owning the repo doesn't change the
app's exposure to the anonymous 3,000-requests-per-5-minutes-per-IP limit (quotas are per downloading IP,
not per repo owner) — which is exactly why the R2 mirror plan in `docs/HANDOFF.md` still matters
regardless of where the canonical files live.

**What to publish.** Apple's own pattern (`apple/coreml-stable-diffusion-*`) is `packages/<stage>.mlpackage`
(source form — what our installer downloads and compiles today, and what anyone using `coremltools` needs)
alongside `compiled/<stage>.mlmodelc` (what WhisperKit- and FluidAudio-style Swift consumers expect). Card
front matter: `license: apache-2.0`, `base_model: hexgrad/Kokoro-82M`, `base_model_relation: quantized`
(set this explicitly — the Hub's inferred relation turns out to be unreliable, tagging even some *fp16*
Kokoro Core ML repos as "quantized"), `library_name: coreml`, `pipeline_tag: text-to-speech`. There's no
Core ML entry in the Hub's open-source library registry, so expect no code-snippet widget — put Swift
usage in the README body instead, the way every other Core ML repo does.

**The one thing that isn't just "upload files":** as noted in §1, `KokoroCoreMLManifest.repositoryURL` is
hard-coded, so making our repo (or the R2 mirror) the app's actual source is a small, deliberate code
change — not something that happens by publishing alone. `docs/HANDOFF.md`'s existing mirror plan already
describes almost exactly this change (a `mirrorURL` beside `repositoryURL`, tried first, Hugging Face as
fallback); a quantized export is just new files dropped into that same plan, not a new plan.

**Do this regardless of quantization, soon:** `hf repos duplicate mattmireles/kokoro-coreml` (or a manual
download+upload if duplication turns out to be disabled) freezes today's exact fp16 bytes under our own
namespace in seconds, with identical SHA-256s — cheap insurance against the upstream repo disappearing,
independent of any quantization work.

## Recommendation

1. **Now, independent of quantization:** duplicate `mattmireles/kokoro-coreml` into our own namespace.
   Free, instant, removes the single point of failure the app currently depends on.
2. **Build the real-input test harness first**, before spending more time guessing at exclusion lists: a
   model-backed Swift test that calls `executeKokoroSynthesis(...tensorDump:)` for a fixed sentence list
   and dumps real tensors, so the coremltools comparison in step 3 means something.
3. **Produce one int8 candidate set**: `linear_quantize_weights`, int8, per-channel, with `conv_post`, the
   two generator `ConvTranspose` weights, and `f0ntrain`'s LSTM weights exempted to start. Deterministic,
   fast (minutes for all 14 files), and — unlike k-means palettization — unambiguous about preserving the
   hard-link dedupe.
4. **Judge it properly**: per-stage cosine/max-abs on real inputs (integer-identity required for
   `pred_dur` — a single duration flip shifts the whole alignment), then an end-to-end distance metric,
   then an ASR round-trip, then — only at the end, and only on a phone, never on this Mac — listening.
5. **Measure the A13 specifically** before shipping anything: plan-build time (today 60 s / 235 s for the
   two longest stages) and the plan-cache size, since nothing in Apple's documentation promises either
   stays the same.
6. **Publish**: our own duplicate-then-quantized repo on Hugging Face (Apache-2.0, explicit
   `base_model_relation: quantized`, `packages/` + `compiled/` layout, a card stating exactly what was
   exempted and the measured distances), and the same files into the R2 bucket the mirror plan already
   describes. Point the app at it via the `mirrorURL`/`repositoryURL` change `docs/HANDOFF.md` already
   sketches.

Expected result if 8-bit holds up: the 227 MB distinct download (and the ~240 MB linked on-phone
footprint) drops to roughly **120 MB**, with no change in the A13's inference speed or memory, and a
plan-build time that has to be measured rather than assumed.

## What this corrects in the earlier research doc

`docs/research/2026-09-11-kokoro-quantization-quality.md` says "nobody has published a quantized Core ML
Kokoro yet" — wrong as of today; see §3. Its byte accounting undercounts voices (14.6 MB, not 4 MB) and
omits the two duration models' non-weight bytes (~16.5 MB). Its size estimates for 8-bit and 6-bit are
otherwise close to what was actually measured here.
