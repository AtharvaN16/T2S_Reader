# Quantizing Kokoro: what people report about quality loss

_2026-09-11 evening. Web research for the owner's question "can the download go lower than 240 MB, and what
does quantization cost in quality?" Our model is `mattmireles/kokoro-coreml`, exported "static and
float16" ([source](https://huggingface.co/mattmireles/kokoro-coreml)); its 227 MB of distinct bytes are
94 duration, 67 decoder-pre, 41 decoder-post, 21 pitch, 4 voices (measured from the manifest)._

## The short version

- **8-bit weights lose nothing anyone can hear or measure.** The only quantitative report is the GGUF
  port: F16 156 MB → Q8_0 135 MB, "no observable quality loss", identical ASR round-trip transcriptions,
  and per-stage cosine similarity to the PyTorch reference ≥ 0.999 on 9 of 16 stages and ≥ 0.85 on the
  rest ([cstr/kokoro-82m-GGUF](https://huggingface.co/cstr/kokoro-82m-GGUF)). The ONNX community ships
  8-bit at 92 MB and 8-bit-weights/fp16-activations at 86 MB against 326 MB fp32 and says "the model is
  resilient to quantization" ([onnx-community/Kokoro-82M-v1.0-ONNX](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX));
  NimbleEdge ships that q8f16 variant on phones at ~80 MB ([blog](https://www.nimbleedge.com/blog/how-to-run-kokoro-tts-model-on-device/)).
- **But not by quantizing everything blindly.** The one careful write-up found that casting or
  quantizing *all* layers gives "terrible" output — "weird static sounds, and other distortions" — and
  that a few layers are too sensitive; the author found them one by one with a mel-spectrogram
  difference against the fp32 model (an MSE loss misses static) and left those in higher precision
  ([Adrian Lyjak, "Exporting and quantizing Kokoro to ONNX"](https://www.adrianlyjak.com/p/onnx/)). The
  8-bit ONNX files above are the products of that kind of selective work.
- **4-bit is where quality goes.** The community's 4-bit variants exist (`q4` 305 MB with only the
  matmuls at 4 bits; `q4f16` 154 MB) but nobody vouches for them; Apple's own Core ML guidance recommends
  6-bit palettization as the point where "the precision loss is small", and says 4-bit or lower needs
  training-time compression to hold quality ([Hugging Face on Core ML diffusers](https://huggingface.co/blog/fast-diffusers-coreml),
  [coremltools palettization](https://apple.github.io/coremltools/docs-guides/source/opt-palettization-overview.html)).
- **Nobody has published a quantized Core ML Kokoro.** All the reports are ONNX or GGUF; the Core ML
  export we use is fp16 with no quantization attempted. So the work is ours: coremltools post-training
  8-bit linear quantization (or 6-bit palettization) of the fp16 mlpackages, the sensitive layers kept
  in fp16, judged the way Lyjak did — a mel-spectrogram distance against the fp16 output, then listening.

## What it would buy us, roughly

| | today | 8-bit weights (est.) | 6-bit palettized (est.) |
|---|---|---|---|
| distinct download | 227 MB | ~120 MB | ~95 MB |
| on the phone (linked) | ~240 MB | ~125 MB | ~100 MB |
| quality (per the reports) | reference | indistinguishable when the sensitive layers stay fp16 | "small" loss per Apple; untested on Kokoro |

Estimates halve the 94/67/41/21 MB weights (the duration models' two near-duplicate exports would also
collapse to one if re-exported with shared weights: another ~39 MB, independent of quantization).

## What it would cost, and the risks nobody's numbers cover

- A conversion pipeline of our own (Python, coremltools) on top of the upstream export — a day, plus the
  layer-by-layer sensitivity pass (the part that keeps static out).
- Speed is not free: on the A13 the CPU path runs BNNS fp16 plans; 8-bit weights are dequantized at load
  or at run time depending on the op, and the compute-plan build times we measured (60 s and 235 s per
  long plan) would have to be re-measured — quantized weights can compile *slower*. Lyjak saw int8 slower
  than fp32 on one backend and faster on another.
- The Core ML plan cache (600 MB per install today) is sized by the compiled graphs, not the weights; it
  would not shrink much.
- Every phone re-downloads and re-warms once (the model revision changes the content keys, the plan cache
  identity and the render keys — rendered audio is invalidated by design, spec §5).

## Recommendation

Do it once, when the mirror exists, as one piece of work: our own export (duration weights shared,
8-bit weights with the sensitive layers in fp16, judged by mel distance + listening on both phones), hosted
on R2. Expect ~110–125 MB down from 227 with no audible change if the sensitive-layer pass is done; skip
6-bit unless the extra 25 MB matters, because no one has measured it on Kokoro. Until then 227 MB once per
phone is fine.

## Sources
- https://huggingface.co/mattmireles/kokoro-coreml — our export: "everything is static and float16"
- https://huggingface.co/cstr/kokoro-82m-GGUF — Q8_0 vs F16: sizes, ASR round-trip, per-stage cosine similarity
- https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX — the size table for fp32/fp16/q8/q8f16/uint8/q4/q4f16
- https://www.adrianlyjak.com/p/onnx/ — blind quantization → static; finding the sensitive layers with a mel-spectrogram loss
- https://www.nimbleedge.com/blog/how-to-run-kokoro-tts-model-on-device/ — q8f16 shipped on phones at ~80 MB
- https://huggingface.co/blog/fast-diffusers-coreml — Apple/HF: 6-bit palettization recommended, 4-bit needs training-time compression
- https://apple.github.io/coremltools/docs-guides/source/opt-palettization-overview.html — bit widths, per-grouped-channel, OS floors
- https://huggingface.co/NeuML/kokoro-int8-onnx, https://huggingface.co/magicunicorn/kokoro-npu-quantized — int8 exports (122 MB NPU int8 vs 170 MB fp16) with no quality data
