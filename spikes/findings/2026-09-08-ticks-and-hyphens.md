# The tick before a sentence resumes, and the pause inside "commander-in-chief" — measured

_2026-09-08, on this Mac. Probe: `Packages/T2SKokoro/Tests/T2SKokoroTests/CoreML/KokoroQualityProbe.swift`
(runs only while `spikes/findings/quality-probe/` exists; WAVs and `report.md` land there,
git-ignored), fed by a test-only utterance trace in `KokoroCoreMLEngine` that places every sample of the
output on the token that owns it. The owner's second listen on the iPhone 11 Pro reported: "sometimes mid
sentence I can hear a tick or a clap, before the sentence resumes", and "commander-in-chief, cost-cutting:
it pauses instead of reading it like a full word"._

**Answer: both are ours, and neither is Kokoro's.** The tick is a click the Core ML pipeline leaves at the
tail of every call, which the reader hears wherever a call ends inside a sentence. The hyphen pause is
MisakiSwift turning every hyphen into Kokoro's em-dash pause symbol.

## 1. The tick: a click at the tail of every Core ML call

Every call to the Core ML pipeline ends the same way (`scripts`: the probe's `tails.swift` numbers, 16-bit
WAVs, so "zero" means below −96 dBFS):

| Render (call) | Last 160 ms of the call | Burst peak |
|---|---|---|
| `packed-0` — `"Bah!" said Scrooge, "Humbug!"` | zeros −160…−60 ms, **burst −60…−40 ms**, zeros −39…0 | 0.178 (−15 dBFS) |
| `packed-3` — `What reason … poor enough."` | zeros −89…−62, **burst −62…−40**, zeros −39…0 | 0.210 (−14 dBFS) |
| `packed-1` piece 1 — `… his eyes sparkled,` (cut at the comma) | zeros −83…−60, **burst −60…−40**, zeros −40…0 | 0.261 (−12 dBFS) |
| `packed-1` piece 2 — `and his breath smoked again.` | zeros −160…−58, burst −56…−40, zeros −40…0 | 0.024 (−32 dBFS) |
| `long-two-pieces` piece 1 — `… the reading` (cut at a word) | zeros −90…−59, burst −59…−40, zeros −40…0 | 0.058 (−25 dBFS) |
| `long-two-pieces` pieces 2, 3; `hyphen-*`; `packed-2` (long trailing pause) | zeros, a burst under −60 dBFS or none | inaudible |
| **MLX reference, all 11 calls of `G-mlx-per-sentence.wav`** | zeros to the very last sample; the next call's lead-in zeros follow contiguously | none |

So: a burst of about 20 ms, always 60 to 40 ms before the end of the trimmed audio, bounded by digital
silence on both sides, and **loud exactly when the call ends soon after speech** — after a comma, a closing
quote or a bare word, where the model predicts only 50–75 ms of trailing pause — and negligible when the
call ends in a long predicted pause. The first-listen finding measured the same thing without recognising
it ("5 more small impulses per 32 s" when upstream's punctuation zeroing was switched off; upstream's own
comment speaks of "Core ML decoder transients on punctuation-owned duration spans" and zeroed whole spans to
hide them, which cut speech instead).

Where the reader hears it: a call ends inside a sentence whenever an utterance needs two pipeline calls —
any sentence past ~176 phoneme ids (about 180 characters; the segmenter allows 300), cut at the last clause
boundary or word before the cap. `packed-1` is the app's own second utterance of the Dickens passage and
lands as: *"…his eyes sparkled,"* — **click** — 30 ms of silence — 320 ms of the next piece's lead-in —
*"and his breath smoked again."* That is "a tick, before the sentence resumes". The same click ends every
utterance at a sentence boundary too (`packed-0`, `packed-3`), 300 ms before the next sentence starts, where
it passes for a mouth noise.

Checked and ruled out on the way: the AAC cache (the click survives the 64 kbps round trip at 0.109 vs
0.111 peak, so the cache neither causes nor hides it; the join between two decoded utterances is a 0.0001
step between two runs of zeros); pre-echo before onsets (no onset in the paragraph render rises out of
silence below −60 dBFS); the generator's first samples (every call starts on exact zeros and fades in);
plosives (the isolated impulses inside speech occur at the same rate and with the same 1–2 ms shape in the
MLX reference); the crossfade (5 ms, joining zeros to zeros).

What is not known: the mechanism inside the split decoder. The burst sits at a fixed distance from the
trim point, the last 40 ms of every call are exactly zero, and the lead-in before speech measures 30–45 ms
shorter than the BOS frames predict at every seam (325→280, 350→320, 375→330 ms) — consistent with the
generator's output running ~40 ms ahead of its feature timeline, so that its response to the step from real
`x_pre` frames into the bucket's zero padding lands inside the kept audio. That would also explain why
upstream's span zeroing hit the following word. Confirming it needs a tensor dump around the trim point
against the PyTorch reference; the fix below does not depend on it.

## 2. The hyphen: MisakiSwift reads every hyphen as an em dash

`NLTagger` makes every hyphen its own word token tagged `Dash` — `commander | - | in | - | chief` — and
MisakiSwift's `retokenize` maps every `.dash` token to the phoneme `—`, Kokoro's em-dash symbol (vocab id
9), which the duration model gives a clause-length pause. The reference Python `misaki` only does that for a
dash that stands alone (spaCy tag `:`); an intra-word hyphen (spaCy `HYPH`) is junk and the pieces join
silently. The 2026-09-03 G2P coverage finding saw this on "twenty-three" and worked around it for numbers
only (`NumberWords` joins with a space).

Measured on *"The commander-in-chief announced a cost-cutting plan, and twenty-five officers re-entered the
well-known hall."*, voice `af_heart`:

| | as written | hyphens as spaces |
|---|---|---|
| Phonemes | `kəmˈændəɹ—ˈɪn—ʧˈif … kˈɔst—kˈʌTɪŋ … twˈɛnti—fˈIv … ɹˌA—ˈɛntəɹd … wˈɛl—nˈOn` | `kəmˈændəɹ ɪn ʧˈif … kˈɔst kˈʌTɪŋ …` |
| Frames on the joiner | `—`: 3–4 frames, 75–100 ms each | space: 1–3 frames, 25–75 ms |
| Silent stretches ≥ 60 ms inside the compounds | 150 ms in "cost—cutting", 160 ms in "re—entered" | none |
| Stress | "in" becomes `ˈɪn` (stressed, a word on its own) | `ɪn`, unstressed |
| Audio | 7.10 s | 6.80 s |

So the hyphen costs a real 150–160 ms hole inside the compound plus a stressed reading of the joiner —
"commander — IN — chief".

## Decision

- **Hyphens: fix once in the normalizer, for every book.** A rule after URL collapsing turns a hyphen with
  a letter or digit on each side (at least one a letter) into a space — `SplitHyphenatedCompoundsRule`,
  `Versions.normalizer` 3 (every stored timeline re-derives on its next play, rendered audio is orphaned).
  A spaced dash, `--`, `—`, `–` and a hyphen between digits stay: those are pauses or ranges. The pronunciation
  dictionary would fix one term at a time; the G2P is the right place in principle (MisakiSwift should map
  `.dash` to `—` only when the dash stands alone, as the reference does) and is worth an upstream patch, but
  the app should not wait on a dependency release. There is no TTS markup standard on this path: SSML is
  what cloud voices accept; Kokoro takes phonemes, and MisakiSwift's only markup is the inline
  `[word](/phonemes/)` form. The normalizer (spec §4.1) *is* this app's markup layer.
- **The tick: remove the artifact where it is, in the engine.** After each pipeline call, if the last
  non-silent stretch of the audio is an island shorter than 30 ms bounded by at least 10 ms of silence on
  both sides within the final 120 ms, it is zeroed — `KokoroCoreMLTailClick`. Nothing else in the audio has
  that shape; speech never ends in a 20 ms island between two runs of digital silence.
- **The seam itself is a separate task.** Removing the click leaves every two-piece sentence with a dead
  stop of 350–450 ms (the cut's trailing pause plus the next piece's BOS lead-in) and a sentence-final
  tune on the word before it. Trimming the lead-in at seams to a clause-length beat, and the 30 s bucket
  that makes whole utterances one call, are Plan 11's remaining tasks.

## Verification (`scripts/quality-probe.sh`, after the fix)

The probe renders the four packed utterances twice, with `Options.removeTailClick` on (the app's
default) and off, and prints the last 160 ms of every call:

| Call | With the removal | Without it |
|---|---|---|
| `packed-0` | silence −160…0 ms | silence −160…−59, island, silence −40…0; peak 0.178 (−15 dBFS) at −46 ms; 470 samples differ |
| `packed-1` piece 1 (the mid-sentence seam) | silence −83…0 ms; loudest remaining sample 0.018 (−35 dBFS) at −93 ms, the decay of "sparkled," | island at −59…−40, peak 0.304 (−10 dBFS) at −45 ms |
| `packed-1` piece 2 | silence −160…0 ms | island at −47…−40, 0.024 (−32 dBFS) |
| `packed-2` (ends in a 480 ms pause) | silence −160…0 ms | the same — 0 samples differ, so the rule has no false positive |
| `packed-3` | silence −160…0 ms | island at −60…−39, peak 0.210 (−14 dBFS) at −45 ms |

What the removal exposes: the seam holes are bigger than the click made them look. In
`long-two-pieces`, with the click gone, the quiet run before seam 1 (a bare-word cut) is 460 ms and the
lead-in after it 280 ms — a 740 ms hole between "reading" and "tables"; seam 2 (a comma cut) is 490 +
330 = 820 ms. Each call ends with the model's end-of-input pause (the first listen's "800 ms of dead
air"), whatever the cut. `packed-1`'s comma seam is 80 + 320 = 400 ms, about a natural comma.

**Plan 11 Task 3** (`KokoroCoreMLSeam`) trims both sides of a seam to a budget by the kind of cut —
60 ms after a bare word, 320 ms after a clause mark, 500 ms after a sentence mark, the model's own
pauses inside one call — measuring silence at −50 dBFS like every pause above: the next piece's lead-in
first (never past its BOS frames; the fold offset moves back with it, so no word start moves), then the
previous piece's tail (silence the model rendered inside its last word's frames; the fold clamps that
word's end to the audio left). The probe after it, seams measured at the actual join:

| Seam | Before | After |
|---|---|---|
| `long-two-pieces` seam 1, bare-word cut ("reading ‖ tables") | 740 ms | 60 ms |
| `long-two-pieces` seam 2, comma cut | 820 ms | 320 ms |
| `packed-1` seam, comma cut ("sparkled, ‖ and his breath") | 400 ms | 310 ms |
| `long-two-pieces` total | 24.52 s | 23.34 s |

The longest quiet stretch left in the long sentence is 460 ms, a pause the model put at a comma inside
a call; the word timings' assertion in `synthesizesALongPassageInPieces` bounds it at 600 ms.

## Not done here

- The mechanism of the burst (tensor dump at the trim point; compare `waveform_full` to the reference).
- Listening. Every number above is a proxy; `spikes/findings/quality-probe/*.wav` are for the
  owner's ears — `packed-1.wav` at 10.9 s is the click before the seam.

## 2026-09-10 — the click on every voice: the island rule was Heart's

_The owner, after the voice picker shipped: "does changing voice reintroduce the click sounds in the
playback? I am getting them when I change voice." Probe: `scripts/voice-tail-probe.sh`
(`KokoroVoiceTailProbe`, enabled while `spikes/findings/voice-tail-probe/` exists), which renders
`packed-0`, `packed-1` and `packed-3` above through every one of the 28 voices at the app's delivery
with the pieces plain-appended — no crossfade, no seam trim, no removal — slices each pipeline call
out by the trace, describes its tail at the island rule's −80 dBFS bound and at the seam's −50 dBFS
bound, runs the shipped `KokoroCoreMLTailClick.removed(from:)` over the slice, and reports what is
left; then streams `packed-1` per voice down the app's own path with the app's options._

**Answer: the click was never voice-specific, but the rule that removed it was.** Every voice
leaves the burst in the same place — it ends where the call's final 36–45 ms of exact zeros begin
and begins at most 66 ms before the end (44 clean cases, 28 voices) — because the place is the
pipeline's: the zeros are the generator's output for the bucket's zero padding, pulled inside the
kept audio by its ~40 ms look-ahead, and the burst is its pre-echo of the step into that padding.
What differs by voice is the *surroundings* the island rule keyed on: at least 10 ms under −80 dBFS
on both sides of a stretch under 30 ms.

| Tail shape (raw, last 120 ms) | Voices | Island rule |
|---|---|---|
| Speech, digital zeros, burst, zeros — e.g. Heart `packed-1` call 1: zeros −85…−60 ms, burst −59…−41 (0.303, −10 dBFS), zeros −41…0 | Heart, Bella, Sarah, Michael, Lewis, Santa | removes it |
| A floor of −60 to −50 dBFS laps at the burst — e.g. Alloy `packed-0`: 0.001–0.003 through −65…−48 ms, burst −48…−41 (0.109) | Alloy, Nova, Onyx, Echo, River, Fable, Isabella … | finds no 10 ms of silence before it: leaves it |
| The last word decays straight into the burst — e.g. Jessica `packed-0`: "Humbug!" at −30 dBFS to −52 ms, burst −48…−44 (0.178, −15 dBFS), zeros −40…0 | Jessica, Kore, Liam, Puck, George, Daniel … | no island at any bound: leaves it |

Over the 113 calls: 82 had an island bounded at −80 dBFS, but only 44 of those were under the
rule's 30 ms (the rest were a word's decay fused with the burst); the rule zeroed something in 62
calls and **left a burst standing right before the final zeros in 45 calls on 22 of the 28 voices**,
at peaks up to 0.584 (−5 dBFS, George, Daniel, Alloy). The streamed pass — the app's own path, which
a voice change forces because it evicts every clip and the reader presses Play before Prepare can
render ahead — left the burst on the first piece for eight voices (Alloy 0.567, River 0.501, Fable,
Jessica, Echo, Onyx, Santa, Isabella). The joins between streamed pieces are clean everywhere: the
largest step across a join was 0.0048.

So the rule now goes by place, not shape (`KokoroCoreMLTailClick`): the last 70 ms of every call are
set to zero — the measured 66 ms plus a margin for the zeros' own scatter — and the 10 ms before
them ramp down to meet the zeros, so a decay that reaches the window (Jessica's) steps down instead
of off a cliff. What the window holds besides the burst is the end-of-input pause: the EOS token's
single 25 ms frame (three of three seams measured above), shifted by the same look-ahead. The
finishing revision rides on the voice route as `#2` (`KokoroVoiceID.finish`, `Delivery.finish`), so
every Kokoro clip re-renders once (spec §5) and none finished the old way is served beside one
finished the new.

### Verification (the same probe, after)

| | Island rule (before) | By place (after) |
|---|---|---|
| Calls with a burst standing before the final zeros | 45 of 113, on 22 voices, up to −5 dBFS | **0 of 113** |
| Trailing silence of every call | 35–45 ms | 70 ms or more (70–91 ms on 44 calls; the rest end in a longer pause) |
| Streamed first pieces (app path, app options) with a burst | 8 voices, up to −5 dBFS | 0; three pieces (Alloy, Jessica, River) end in a word's decay at −35 to −39 dBFS before the 60 ms word-cut pause — speech, not the burst |
| Largest step across a streamed join | 0.0048 | 0.0048 |

What the probe still flags after the rule — 37 calls — is the last word's decay before the pause,
at −25 to −40 dBFS and 70 ms or more from the end, the same stretch it flagged before: speech, left
where it was. The ramp shows in the bins: Jessica `packed-0` reads 0.028 at −80 ms, 0.013 at −75,
zero from −70; Alloy 0.009, 0.001, zero. WAVs of every flagged call, raw and after, are in
`spikes/findings/voice-tail-probe/` for the owner's ears; `report-before.md` beside `report.md` is
the island rule's run.

Not listened to. Every number is a proxy, and the phone renders in fp16 where this Mac renders in
fp32 — the zeros' scatter may differ there; the 70 ms window has 4 ms over the widest start seen.
