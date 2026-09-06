# Why the Core ML Kokoro voice sounds cut off, abrupt and flat — measured

_2026-09-05, on this Mac. Probe: `scripts/audio-probe.sh` (WAVs and `metrics.md` in
`spikes/findings/audio-probe/`, git-ignored); analysis: `scripts/analyze-wav.swift`. The owner's first
listen on the iPhone 11 Pro reported: "feels like someone struggling, it cuts in the end, randomly
starting a new sentence, too robotic, monotone, abrupt change of sentence. Is this Kokoro, or how we set
it up?"_

**Answer: mostly how we set it up, in four places; one part is Kokoro itself.** In order of what a
listener hears:

| # | What is heard | Cause | Evidence | Fix (Plan 9) |
|---|---|---|---|---|
| 1 | Word endings cut off | Upstream's post-process silences the duration span of **every punctuation token** (quotes and commas included) with a 5 ms fade. The Core ML decoder does not put its audio exactly where the duration model predicted, so the zeroing lands on speech. | A vs B: 25 of 45 zeroed spans held ≥10 ms of audible signal (above −34 dBFS), 1.1 s of speech zeroed in 32 s; worst: 75 ms at peak 0.75 after "Bah!" | Engine default `punctuationSuppression: .none` (the PyTorch reference does no zeroing). Cost: 5 more small impulses per 32 s (B: 6 vs A: 1). |
| 2 | Abrupt sentence changes, dead air, "randomly starting a new sentence" | **One Kokoro call per sentence.** At the end of an input Kokoro predicts a long final pause: ~800 ms of dead air after every sentence, then a cold start. Identical on MLX, so this is the model's behaviour for short inputs, not the port. | A (Core ML) vs G (MLX), same 11 sentences: 32.4 s vs 31.9 s; both show 17 pauses of 770–870 ms. Whole paragraph in one call (C): 27.0 s, pauses 230–740 ms, voiced 37% → 47%. | Segmenter packs consecutive sentences of a paragraph into one utterance (~160 characters ≈ 160 ids at the measured 0.98 ids per character; the 15 s bucket holds 176). The engine's piece cutter prefers sentence and clause boundaries when a piece must still be cut. |
| 3 | Sentences cut mid-way with a seam | Any sentence over 176 phoneme ids is cut into pieces at the last **word** before the cap and the pieces are butted together. The probe's third sentence (197 ids) is cut this way in today's app. | Calibration: 436 ids for 444 characters; per-sentence ids `[6, 24, 197, 30, 21, 33, 22, 16, 29, 31, 17]` | Cut at the last sentence-final, else clause, punctuation before the cap; 5 ms equal-power crossfade at the join (`PcmJoiner`); a piece whose predicted audio would overflow its bucket is re-split instead of dropped for 200 ms of silence. |
| 4 | "Robotic", underwater, effortful | **Every second the reader hears has been through the 32 kbps AAC cache** (`AACCodec`, spec §3.4): the coordinator plays from the store, never from the render. At 24 kHz mono, 32 kbps leaves an SNR of 13 dB. | C through AAC: 32 kbps 13.2 dB SNR, 18.9 MB/h; 48 kbps 19.4 dB, 26.3 MB/h; 64 kbps 23.6 dB, 33.6 MB/h (the encoder refuses 96 kbps at 24 kHz mono). The time-pitch unit at 1.0x is transparent (141 dB). | Cache at 64 kbps (+15 MB per hour of audio; the LRU cap is unchanged). Old 32 kbps entries are not re-used. |
| 5 | Monotone delivery | **Kokoro itself.** The Core ML port is not flatter than the reference: pitch spread 4.4 semitones (5–95 %: 11.0 st) against MLX's 3.9 st (9.7 st), same medians, same pause pattern. Heart is an even, calm narrator; expressive range is what the 82 M-parameter model lacks against ElevenLabs. | A vs G in `analyze-wav.swift`; C vs H | Nothing to fix in code. Voice previews (Task 3) let the reader pick a livelier voice; British voices and Bella/Nicole read with more movement. |

## The probe

Passage: 444 characters of *A Christmas Carol* (public domain) — quotation marks, commas, semicolons,
questions and exclamations. Voice `af_heart`. Nine renders, all 24 kHz mono float, in
`spikes/findings/audio-probe/`:

| File | What it is |
|---|---|
| `A-current-per-sentence-all-suppressed.wav` | **Today's app path**: the segmenter's 11 sentences, one Kokoro call each, upstream punctuation silencing, pieces butted together |
| `B-per-sentence-no-suppression-crossfade.wav` | Same, silencing off, crossfaded pieces |
| `C-paragraph-no-suppression-crossfade.wav` | The whole paragraph in one utterance (three pieces at the 176-id cap), silencing off |
| `D-paragraph-sentence-final-crossfade.wav` | As C, silencing only `.` `!` `?` `…` spans |
| `E-long-sentence-current.wav`, `F-…-no-suppression-crossfade.wav` | A 70-word sentence (two pieces) today vs with the fixes |
| `G-mlx-per-sentence.wav`, `H-mlx-paragraph.wav`, `I-mlx-long-sentence.wav` | **Control**: kokoro-ios on MLX (the reference implementation's behaviour), same inputs |
| `C-…-through-aac32k.wav`, `C-…-through-aac64k.wav` | C after a round trip through the cache codec at each bitrate |

Measurements (`scripts/analyze-wav.swift`; pauses are quiet stretches of ≥150 ms, impulses are samples
six times their 40 ms neighbourhood's RMS and above −20 dBFS):

```
A  32.40 s, voiced 37%; F0 median 200 Hz, spread 4.4 st, 5–95% 157–296 Hz; pauses 17 [410,790,780,320,270,590,350,770,830,800,820,840,870,760,820,870,460]; impulses 1
B  32.40 s, voiced 37%; F0 median 200 Hz, spread 4.4 st; pauses 27 (340–430 ms typical); impulses 6
C  26.96 s, voiced 47%; F0 median 194 Hz, spread 3.9 st, 5–95% 154–264 Hz; pauses 15 [320,550,230,380,740,480,270,340,400,490,330,320,410,230,420]; impulses 6
D  26.96 s, as C
E  23.93 s, voiced 53%; spread 3.5 st; pauses 10; impulses 4       F  23.91 s, as E
G  31.93 s, voiced 36%; F0 median 207 Hz, spread 3.9 st, 5–95% 161–282 Hz; pauses 17 [410,790,770,320,290,600,340,220,810,820,770,800,800,780,810,840,400]; impulses 11
H  24.02 s (one 436-id call; the MLX route's cap is 510), pauses 11
```

Silencing measured sample by sample (A against B, which differ only inside the zeroed spans): 45 spans
zeroed; 25 of them contained ≥10 ms of audible signal; 1 096 ms of audible speech removed in 32.4 s;
the largest: 75 ms at 0.42 s (peak 0.75), 50 ms at 23.12 s (peak 0.54), 75 ms at 25.12 s (peak 0.29).

## What was checked and is fine

- The pipeline wiring matches Kokoro: `ref_s[128:]` styles the duration/F0 predictor, the full `ref_s`
  goes to the decoder, the voice row is `len(phonemes) − 1`, `speed` is 1.0 and playback rate is applied
  by the time-pitch unit — which measures transparent at 1.0x.
- The trim after the generator keeps exactly the predicted span; no samples are lost there.
- `AVAudioFile`'s AAC round trip returns the same sample count (no priming loss).
- The G2P (MisakiSwift) is the reference's own; punctuation reaches the model.

## Not done here

- **A 30-second bucket.** The reference lets one call carry 510 tokens (≈25 s); our Core ML staging
  ships the 7 s and 15 s buckets only, so the longest single call is 176 ids (≈13 s). Upstream exports a
  30 s bucket and a 512-token duration model; staging them would let a whole paragraph go in one call
  (H above) at the price of a larger bundle and a longer first-launch compute-plan build on the A13.
  Worth a spike once Plan 9 has been heard on the phone.
- **Listening.** Every number above is a proxy. The WAVs are for the owner's ears; the plan's defaults
  follow the numbers and are all switchable (`KokoroCoreMLEngine.Options`, the segmenter's pack length,
  `AACCodec`'s bitrate).
