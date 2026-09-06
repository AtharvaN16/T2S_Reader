# KokoroPipeline (vendored)

`github.com/mattmireles/kokoro-coreml` at `66d8cf5108cce0991b8868b01b4d8a8b2e98881d` (main,
2026-08-28), Apache-2.0 — see `LICENSE`. `Sources/KokoroPipeline/` is upstream's
`swift/Sources/KokoroPipeline/` with two local additions, each marked "Vendored addition
(t2s_reader)" in the code:

- `KokoroSynthesisRequest.punctuationSuppression` (`PunctuationSuppression` in
  `KokoroSynthesisExecutor.swift`, `KokoroVocabulary.sentenceFinalPunctuationTokenIds`, and a
  `suppressedTokenIds` parameter on `suppressPunctuationTokenAudio`). Upstream silences the
  duration span of every punctuation token after synthesis; the app needs to choose how much of
  that to do (see `spikes/findings/2026-09-05-coreml-audio-quality.md`).
- `KokoroVocabulary.clauseBoundaryPunctuationTokenIds` (`;` `:` `,` `—`): the app's Core ML engine
  reads this to prefer a clause boundary over a bare word when it has to cut a long utterance, or
  split one that overflowed its bucket, and no sentence-final boundary is available.

Both defaults match upstream's own behaviour, so every other file is byte-identical and the
additions are a strict superset.

It exists for one reason: the upstream repository root has no `Package.swift` — the package lives
in the `swift/` subdirectory, and SwiftPM cannot consume a subdirectory of a repository by URL.

`Package.swift` is ours and differs from upstream's only by subtraction: the two `kokoro-bench`
executable products and their targets go, and upstream's test target (whose fixtures we do not
vendor) is replaced by `Tests/KokoroPipelineTests`. Tools version and platform floors are upstream's.
The exit plan is to depend on the repo by URL if upstream ever moves its manifest to the root.
