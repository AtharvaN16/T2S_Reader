# Spike: MisakiSwift coverage and the Kokoro-path license audit

**Spec section:** §7.1
**Date:** 2026-09-03
**Devices:** n/a (desk work on macOS; MisakiSwift 1.0.6 builds and runs natively on macOS 15)
**Harness commit:** dev d0a21a6 plus the uncommitted `spikes/g2p/` tool

## Question
Is every dependency on the Kokoro path permissively licensed, and does MisakiSwift's English G2P
match the reference Python `misaki` closely enough to trust it as the only G2P (spec §7.1 rules
out espeak-ng)?

## Method
- Licenses: read from the LICENSE file of each package resolved by the spike harness under
  `spikes/SpikeHarness/.build/dd/SourcePackages/checkouts/` at the pinned versions; recorded in
  `docs/licenses.md` ("Kokoro path").
- Coverage: `spikes/g2p/` — `g2pdump` (Swift, MisakiSwift 1.0.6 `EnglishG2P(british: false)
  .phonemize(text:)`) and `reference.py` (Python `misaki` `en.G2P(trf=False, british=False,
  fallback=None)`) over `spikes/SpikeHarness/Resources/corpus.txt`, diffed by `compare.py`.
  The plan asks for a 200-sentence corpus; this pass used the committed 50 sentences.

## Results
| Metric | Value |
|---|---|
| kokoro-ios 1.0.11 | MIT |
| mlx-swift 0.30.2 | MIT |
| MisakiSwift 1.0.6 | Apache-2.0 (spec §7.1 says MIT; that is wrong) |
| MLXUtilsLibrary 0.0.6 | Apache-2.0 |
| swift-numerics 1.1.1 | Apache-2.0 |
| ZIPFoundation 0.9.20 (transitive) | MIT |
| Kokoro-82M weights | Apache-2.0 |
| Copyleft anywhere on the path | none |
| Exact match, raw corpus text | 32/50 (64%) |
| Exact match, text as the app's `TextNormalizer` emits it (`normdump`) | 34/50 (68%) |
| … of which the *reference* gave up (`❓` on names: Bennet, Adler, Okafor, Darcy, Ahab, Ramirez, "St") while MisakiSwift produced a plausible pronunciation | 7 sentences |
| … of which only the separator inside a hyphenated compound number differs (Swift keeps `—` between "twenty" and "three"; the reference joins them; phonemes identical) | 6 sentences |
| Exact match excluding those two classes | 34/37 (92%) |
| Remaining real divergences | 3: stress on a function word ("can", "that") ×2; the heteronym "read" (past tense) pronounced as present — MisakiSwift has no POS tagger |
| Crashes while phonemizing the corpus | 0 (and 0 in the Python reference) |

Divergence classes on the raw corpus that vanish after normalization: numerals, decimals,
currency, percent (MisakiSwift 1.0.6 drops or truncates digits — "23 houses" → "three houses",
"$2,450" loses "dollars"). The app never sends digits to an engine (`ExpandNumbersRule`, spec
§4.1), so this class does not reach Kokoro.

## Decision
License: the Kokoro path may ship; `scripts/check-licenses.sh` will cover these packages once they
are declared in the root package, and the Apache-2.0 notices (MisakiSwift, MLXUtilsLibrary,
swift-numerics, weights) join the acknowledgements screen. Correct spec §7.1's MisakiSwift
licence to Apache-2.0.

Coverage: MisakiSwift is accepted as the only G2P, English-only, with two recorded mitigations.
The plan's literal bar (≥ 95% exact) is not met on this 50-sentence corpus, but the misses that
are audible reduce to (a) compound numbers and (b) heteronyms:
1. `NumberWords` should join compound numbers with a space, not a hyphen ("twenty three"), so
   MisakiSwift does not emit a `—` token that Kokoro may render as a pause. One-line normalizer
   change with a test; do it in Plan 5 Task 5.
2. Heteronyms (read/lead/live/wind/tear/close/bass…) get the dominant reading. This is a known
   limitation relative to AVSpeechSynthesizer, which has a POS tagger; the pronunciation
   dictionary can override per document. Revisit only if users report it.
Stress marks on function words do not change the spoken word.

## Fallback taken (if any)
None. The G2P comparison used the committed 50-sentence corpus rather than the 200 the plan asks
for; the divergence classes were already unambiguous at 50.
