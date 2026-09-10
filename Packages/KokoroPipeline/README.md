# KokoroPipeline (vendored)

`github.com/mattmireles/kokoro-coreml` at `66d8cf5108cce0991b8868b01b4d8a8b2e98881d` (main,
2026-08-28), Apache-2.0 — see `LICENSE`. `Sources/KokoroPipeline/` is upstream's
`swift/Sources/KokoroPipeline/` with these local changes, each marked "Vendored addition
(t2s_reader)" or "Vendored change (t2s_reader)" in the code:

- `KokoroSynthesisRequest.punctuationSuppression` (`PunctuationSuppression` in
  `KokoroSynthesisExecutor.swift`, `KokoroVocabulary.sentenceFinalPunctuationTokenIds`, and a
  `suppressedTokenIds` parameter on `suppressPunctuationTokenAudio`). Upstream silences the
  duration span of every punctuation token after synthesis; the app needs to choose how much of
  that to do (see `spikes/findings/2026-09-05-coreml-audio-quality.md`).
- `KokoroVocabulary.clauseBoundaryPunctuationTokenIds` (`;` `:` `,` `—`): the app's Core ML engine
  reads this to prefer a clause boundary over a bare word when it has to cut a long utterance, or
  split one that overflowed its bucket, and no sentence-final boundary is available.

- `KokoroSynthesisRequest.f0Spread` (`spreadF0` in `KokoroSynthesisExecutor.swift`): the
  predicted F0 curve's voiced frames scaled about their log-mean before the decoder; 1 is upstream.
- `HarmonicSource.swift` (Plan 16): `sineGenFromF0Frames` computes its nine sine passes over the
  voiced prefix of the padded F0 curve plus one frame (`sineFrameCount`); the mask zeroes the rest
  anyway, and the output is bit-identical to the untrimmed computation (`HarmonicSourceTests`).
- `KokoroSynthesisExecutor.swift` (Plan 16): the hn-nsf build (Stage 7) runs on another core
  while the DecoderPre prediction (Stage 6) holds the thread; `StageTimings.decoderPreHnsfOverlap`,
  which upstream declares and never sets, records the overlap.
- `KokoroSynthesisExecutor.swift` (2026-09-10): `warmKokoroStages(modelProvider:tokenLengths:buckets:)`
  runs listed duration models and buckets once on zero inputs, so the first real prediction pays no
  specialization; `warmModels` shares its bucket half (`warmBucketStages`).

Every default matches upstream's own behaviour and every output is unchanged, so the changes are
a strict superset; the remaining files are byte-identical.

It exists for one reason: the upstream repository root has no `Package.swift` — the package lives
in the `swift/` subdirectory, and SwiftPM cannot consume a subdirectory of a repository by URL.

`Package.swift` is ours and differs from upstream's only by subtraction: the two `kokoro-bench`
executable products and their targets go, and upstream's test target (whose fixtures we do not
vendor) is replaced by `Tests/KokoroPipelineTests`. Tools version and platform floors are upstream's.
The exit plan is to depend on the repo by URL if upstream ever moves its manifest to the root.
