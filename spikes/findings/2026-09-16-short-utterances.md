# A shriek in the middle of a chapter: short calls, and what `af_aoede` does at every one

_2026-09-16, on this Mac. Probe:
`Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroShriekProbe.swift` (enabled while
`spikes/findings/shriek-probe/` exists), over the owner's own copy of *Bad Blood*, chapter 1. Pitch
from `scripts/analyze-wav.swift` and two throwaway contour tools. The owner's report: listening on
`af_aoede`, "while the narration was going on normally suddenly the voice would almost scream in a
shrill voice… as if it ran out of breath", with six screenshots of where it happened._

**Answer in short.** Two separate things, one fixed here.

1. **Fixed.** A line break inside a paragraph — a drop cap — made `NLTokenizer` end a sentence at it,
   and packing could not take the fragment back, so `"elizabeth's"` became a synthesis call of eleven
   characters. `af_aoede` said it at **279 Hz for its whole 1.32 s against the paragraph's 176 Hz**.
   `Segmenter.minUtteranceLength` now joins any packed utterance under 24 characters to its
   neighbour. Same family as the chapter number in
   [`2026-09-16-lone-chapter-numbers.md`](2026-09-16-lone-chapter-numbers.md), one layer down.
2. **Not fixed, and the bigger half.** `af_aoede` opens *every* call with a pitch excursion to
   ~390 Hz — over an octave above its own 170–180 Hz narration — held for 250–450 ms. The app cuts
   an utterance every ~160 characters, so that lands every 8 seconds or so. This is the model's own
   contour on this voice, not anything the app adds.

## Where the owner's six moments are

Each screenshot's read/unread boundary is the word being spoken (`ReaderTextView`). All six sit
exactly at an utterance boundary — the last word of one call, the first of the next:

| elapsed | last painted | that utterance | the one starting |
|---|---|---|---|
| 16:45 | "…turn of the twentieth century." | p02-u1, 131 chars | p03-u0 |
| 18:48 | "…younger brother, Christian." | p07-u2, 132 chars | p08-u0 |
| 20:43 | "…becoming an entrepreneur." | p12-u1, 130 chars | p12-u2 |
| 21:09 | "…little startup called Google." | p12-u4, 134 chars | p13-u0 |
| 23:43 | "…than his fifty-nine years." | p17-u2, 201 chars | p18-u0 |
| 23:52 | "…controlled drug-delivery devices." | p18-u0, 130 chars | p18-u1 |

## The onset, by voice

The same utterance (p12-u2, "The little agricultural college founded by railroad tycoon Leland
Stanford…") on four voices at the app's delivery. A "high stretch" is ≥100 ms held at least 7
semitones over that render's own median:

| voice | median | high stretches | peak | held for |
|---|---|---|---|---|
| af_aoede | 179 Hz | **2** | **387 Hz (+13.3 st)** | 270 ms, then another 330 ms at +9.6 |
| af_heart | 203 Hz | 1 | 393 Hz (+11.4 st) | 110 ms |
| af_bella | 202 Hz | **0** | — | — |
| bf_emma | 180 Hz | **0** | — | — |

The tracker is not octave-doubling: the contour climbs smoothly
`211 → 226 → 250 → 276 → 304 → 329 → 375 → 393` over 300 ms and comes back down the same way.

`af_bella` and `bf_emma` do not do this at all, and `af_heart` only blips. This tracks the model
author's grades (`2026-09-08-quality-levers.md`): Heart A, Bella A-, Emma B-, and `af_aoede` is a C.

## What it is not

- **Not the GPU.** `KokoroComputeUnits.defaultPolicy` gives an iPhone 18,x `.cpuAndGPU` and everything
  else `.cpu`; the owner's phone is on the CPU path, the same one these renders use. The phone's
  audio is this audio.
- **Not `Delivery.spread`.** The app widens the predicted contour by a quarter, chosen by ear on
  `af_heart` and applied to every voice. At the model's own contour the same onset measures
  **393 Hz — higher** than the app's 364 Hz. The spread is not what makes the peak.
- **Not the seam.** The tails of the utterances the owner's screenshots ended on decline cleanly to
  140–160 Hz and stop. "Ran out of breath" is that decline; the shriek is the *next* call opening.

## The fix, and its limit

`Segmenter.minUtteranceLength` = 24 characters. Chosen from the length sweep in
[`2026-09-16-lone-chapter-numbers.md`](2026-09-16-lone-chapter-numbers.md): a call of 1–11 characters
lands +6 to +12 semitones high, and by 21 characters it is back on the baseline. A run still under it
keeps taking the next piece however far past `packLength` that goes; a run left short at the end of a
block joins the utterance before it. It never splits, only joins, and never across a block — a
one-line paragraph is the author's. It applies only where packing does, so a segmenter built with
`packLength` 0 still gives one sentence per utterance.

On the real chapter this turns `"elizabeth's"` (11 chars) into a 200-character utterance with the
sentence that follows it. The 37–62 character utterances in the same chapter are left alone; they
measured on the baseline.

**What is left.** Item 2 above. Nothing in this change touches `af_aoede`'s opening excursion, which
is the model's own and happens at every call boundary. Three options, none taken yet, none free:
pack longer so there are fewer boundaries (the engine's own 176-id cap re-splits anything much over
180 characters, and each piece is its own call, so this buys little); tame the predicted contour's
peaks per voice rather than widening them all by a fixed quarter; or say plainly in the voice list
which voices narrate well — the measurement says Bella and Emma, and the author's grades agree.
