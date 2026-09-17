# A chapter number read alone, and why it comes out high

_2026-09-16, on this Mac. Probe:
`Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroHeadingProbe.swift` (enabled while
`spikes/findings/heading-probe/` exists; WAVs land there, git-ignored), pitch numbers from
`scripts/analyze-wav.swift`. Block structure read out of the owner's own copy of *The Last Mughal*
by `Packages/T2SReadium/Tests/T2SReadiumTests/HeadingBlocksProbe.swift` (`T2S_PROBE_EPUB=<file>`). The owner's report: in a
chapter headed "3 An Uneasy Equilibrium", "it says three in a very high-pitched sound"._

**Answer in short.** The number is its own synthesis call of one word, and Kokoro reads a one-word
call far above the voice's own narration pitch — a semitone on `af_heart`, an octave on `am_liam`.
The fix is not to hand it a one-word call: the two halves of the heading are put back together
before segmenting (`TimelineBuilder.joined`), which lands the number within two semitones of the
narration on every voice measured. A floor under the voice-table row was tried first and ruled out.

## How the number comes to be alone

The EPUB writes the heading as one element broken by a line break:

```html
<h2 class="h2"><strong><a class="nounder" href="contents.html#ich03">3<br/>AN UNEASY EQUILIBRIUM</a></strong></h2>
```

Readium's `HTMLResourceContentIterator` calls `flushText()` when it meets a `<br/>`, ending the text
element there, so the heading arrives as two `TextContentElement`s. `ReadiumDocumentReader` makes one
`SourceBlock` of each, and `TimelineBuilder` segmented every block on its own — so `"3"` normalized
to `"three"` and became a whole call. Confirmed against the owner's file: chapters 1, 2 and 3 each
open with a block of just the number.

## The lone number against each voice's own narration

`"3"` (→ "three") and a 54-character sentence, both through the app's options at `Delivery.spread`.

| voice | lone number | narration | difference | | voice | lone number | narration | difference |
|---|---|---|---|---|---|---|---|---|
| am_liam | 240 Hz | 121 Hz | **+11.9 st** | | af_jessica | 304 Hz | 226 Hz | +5.1 st |
| am_echo | 194 Hz | 111 Hz | **+9.7 st** | | bm_george | 188 Hz | 145 Hz | +4.5 st |
| am_santa | 240 Hz | 145 Hz | **+8.7 st** | | af_alloy | 190 Hz | 148 Hz | +4.3 st |
| af_sky | 264 Hz | 161 Hz | **+8.6 st** | | bf_isabella | 255 Hz | 200 Hz | +4.2 st |
| af_aoede | 293 Hz | 182 Hz | **+8.2 st** | | bf_emma | 222 Hz | 180 Hz | +3.6 st |
| am_eric | 240 Hz | 154 Hz | +7.7 st | | am_adam | 140 Hz | 115 Hz | +3.4 st |
| bm_fable | 195 Hz | 126 Hz | +7.6 st | | am_michael | 133 Hz | 112 Hz | +3.0 st |
| af_sarah | 286 Hz | 192 Hz | +6.9 st | | am_puck | 133 Hz | 117 Hz | +2.2 st |
| af_kore | 218 Hz | 151 Hz | +6.4 st | | af_river | 207 Hz | 183 Hz | +2.1 st |
| am_onyx | 130 Hz | 91 Hz | +6.2 st | | af_bella | 220 Hz | 202 Hz | +1.5 st |
| bf_lily | 264 Hz | 185 Hz | +6.2 st | | af_heart | 224 Hz | 209 Hz | +1.2 st |
| af_nova | 242 Hz | 171 Hz | +6.0 st | | bm_daniel | 125 Hz | 122 Hz | +0.4 st |
| bf_alice | 312 Hz | 224 Hz | +5.7 st | | bm_lewis | 80 Hz | 83 Hz | −0.6 st |
| am_fenrir | 192 Hz | 138 Hz | +5.7 st | | af_nicole | 145 Hz | 158 Hz | −1.5 st |

The default voice is the second-mildest of the 28, which is why the first measurement of this bug —
taken on `af_heart` alone — looked like nothing and sent the investigation down a blind alley.

## How short is too short

Semitones above the same voice's narration, by the source block's length in characters:

| voice | 1 | 4 | 11 | 21 | 29 | 39 | 60 | 92 |
|---|---|---|---|---|---|---|---|---|
| am_liam | +11.9 | +1.6 | +5.7 | +0.1 | +1.9 | +1.2 | +0.1 | +0.6 |
| af_aoede | +8.2 | +9.8 | +8.4 | +0.3 | +0.9 | −0.8 | −1.3 | −1.1 |
| af_sky | +8.6 | +6.1 | +7.8 | +3.3 | +3.8 | +2.1 | −0.1 | −0.9 |
| af_heart | +1.2 | +1.7 | +1.4 | +1.6 | +1.2 | −1.2 | −0.3 | −0.9 |

Under about twenty characters the call is read high; past it, it settles on the narration. This is
the model's own documented "weaknesses on short utterances"
(`spikes/findings/2026-09-08-quality-levers.md`), measured.

## The voice row: tried, ruled out

A Kokoro voice is a 510×256 table and the engine reads row `phonemes − 1`
(`KokoroTokenizer.refS`). "three" phonemizes to `θɹˈi`, four characters, so a lone number reads
row 3 — whose predictor half is 3.5× the magnitude and ~0.29 cosine against the rows an ordinary
sentence uses. That made the row look like the cause. It is not: with a floor forced under the row,

| voice | narration | ships (row 3) | row 10 | row 20 | row 30 | row 50 | row 80 | row 120 |
|---|---|---|---|---|---|---|---|---|
| am_liam | 121 Hz | 240 | 240 | 202 | 180 | 182 | 179 | 182 |
| am_echo | 111 Hz | 194 | 194 | 192 | 185 | 189 | 180 | 176 |
| af_aoede | 182 Hz | 293 | 273 | 267 | 270 | 255 | 250 | 242 |
| af_heart | 209 Hz | 224 | 240 | 276 | 286 | 267 | 255 | 240 |

— the pitch moves *up* on the default voice, and on the worst voices never reaches the narration
baseline. The row is a passenger; the length of the call is what the model is responding to. The
lever was removed again.

## The fix, measured

`TimelineBuilder.joined` puts consecutive blocks of one source element back together before
segmenting — same resource, same CSS selector, adjacent in the extracted text — so the heading is
one utterance, "three AN uneasy equilibrium".

| voice | narration | number alone | joined to the title |
|---|---|---|---|
| am_liam | 121 Hz | 240 Hz (+11.9 st) | 136 Hz (+2.0 st) |
| am_echo | 111 Hz | 194 Hz (+9.7 st) | 109 Hz (−0.3 st) |
| af_sky | 161 Hz | 264 Hz (+8.6 st) | 195 Hz (+3.3 st) |
| af_aoede | 182 Hz | 293 Hz (+8.2 st) | 182 Hz (+0.0 st) |
| af_heart | 209 Hz | 224 Hz (+1.2 st) | 200 Hz (−0.8 st) |

The rule is deliberately narrow — one element's own pieces, nothing else. A short paragraph of
dialogue is a whole element and keeps its own pause and its own highlight, even though the table
above says Kokoro will read it high too; merging paragraphs would change how the book reads, which
is a larger decision than this bug. A PDF block carries no selector and never joins at all.

Because a stored timeline is only re-derived when a version changes, `Versions.segmenter` goes to 3:
every library re-segments and the affected chapters re-render once.

## Loose end

The same table says any one-word paragraph is read high on most voices — "Yes." on `af_aoede` is
+9.8 st. Only the heading case is fixed here. Whether a one-word paragraph should be packed with its
neighbour is a reading decision for the owner, not a bug fix.
