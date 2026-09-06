# Plan 9 — Voice quality, Kokoro-only voices with previews, and the Reader after ElevenReader

_2026-09-05. Branch `plan-9-voice-quality-readalong` off `dev` @ 3b77b0f. Written from the owner's
first-listen feedback on the iPhone 11 Pro, executed with the subagent-driven workflow; the ledger with
every ruling is `.superpowers/sdd/2026-09-05-plan-9-voice-quality-readalong/progress.md` (local, git-ignored)._

## Why

The owner listened to the first Kokoro build and reported three things:

1. The voice list should be Kokoro only, with a way to hear each voice before choosing it.
2. The read-along page looked wrong — a black page, one word filling the screen, a comb of ticks — and
   ElevenReader was given as the reference.
3. The voice sounded cut off at word ends, abrupt between sentences, and flat. "Is this Kokoro, or how we
   set it up?"

The third question was answered first, by measurement:
[spikes/findings/2026-09-05-coreml-audio-quality.md](../../../spikes/findings/2026-09-05-coreml-audio-quality.md).
Four of the five causes are ours (upstream's punctuation silencing removes ~1 s of speech per 30 s; one
Kokoro call per sentence leaves ~800 ms of dead air after every sentence; long sentences are cut at a word
and butted together; and every second heard passes through a 32 kbps AAC cache at 13 dB SNR). The fifth —
an even, calm delivery — is Kokoro's own; the Core ML port measures no flatter than the MLX reference.

## Tasks

| # | Task | Owns | Verification |
|---|---|---|---|
| 1 | **Engine and cache quality.** `KokoroCoreMLEngine.Options.default` becomes `punctuationSuppression: .none, crossfadePieces: true`; the piece cutter prefers sentence-final, then clause, punctuation before the 176-id cap; a piece whose predicted audio would not fit its bucket is split in two and rendered rather than dropped for silence; `AACCodec` encodes at 64 kbps under a new identifier and `FileAudioStore` removes stale codec directories; the model-backed tests share one compiled staging and `scripts/test-kokoro.sh` sweeps the Core ML runtime cache. | `Packages/T2SKokoro`, `Packages/KokoroPipeline` (the vendored addition), `Sources/T2SAudio/AACCodec.swift`, `Sources/T2SCore/Render/FileAudioStore.swift`, `scripts/test-kokoro.sh`, `scripts/audio-probe.sh` | `swift test`; `scripts/test-kokoro.sh` (model-backed suite included, disk permitting); the probe re-run |
| 2 | **Sentence packing and word-precise seeks.** `Segmenter` packs consecutive sentences of a block into one utterance while the packed source stays within 160 UTF-16 units (0.98 ids per character measured; the 15 s bucket holds 176); `Versions.segmenter` → 2; `ReaderModel.seek(to:)` lands on the tapped word's timing inside the utterance instead of the utterance start. | `Sources/T2SCore/Segment`, `Sources/T2SCore/Versions.swift`, `Sources/T2SApp/Reader/ReaderModel.swift`, their tests | `swift test` |
| 3 | **Kokoro-only voice list with previews.** System rows disappear wherever a Kokoro route is listed (the Simulator build keeps them); rows show name, accent and gender with an avatar; every row previews a sample sentence through the routed engine on a dedicated player (`VoicePreviewModel`); the old AVSpeech preview goes. | `Sources/T2SApp/Preferences`, `App/T2SReader/Preferences`, `App/T2SReader/System/{SystemVoiceCatalog,AudioSessionController}.swift`, `AppEnvironment.swift`, tests | `swift test`; `scripts/build-app.sh` |
| 4 | **The Reader after ElevenReader.** Fix the 1800 % font (Readium's `fontSize` is a ratio), drop publisher styles; sentence tint + word tint; floating circular top buttons; thin progress bar with times; transport row with sleep timer and speed; tool row with appearance, voice chip and contents. | `App/T2SReader/Reader`, `App/T2SReader/Design/Tokens.swift`, `Sources/T2SCore/Timeline/Highlighter.swift`, `Sources/T2SApp/Reader/ReaderModel.swift` (one property) | `swift test`; `scripts/build-app.sh`; a simulator screenshot |
| 5 | **Docs.** HANDOFF (state, the deferred phone listen, the new probe), README (scripts, voice list), the spec's Reader paragraph (§2.4.5) and codec line (§3.4) updated with a changelog entry. | `docs/`, `README.md` | review |

Tasks 1, 3 and 4 are independent; 2 runs after 3 (shared build directories on a small disk). Every task
ends with a review; the whole branch gets a final review before `dev` fast-forwards.

## Decisions taken without the owner (each also in the ledger, with its cost if wrong)

- **Silencing off rather than sentence-final only.** The worst measured cut (75 ms, peak 0.75) was on an
  exclamation mark, so restricting the zeroing to sentence-final marks keeps the worst case. Cost: a
  handful of small impulses per minute; the switch is one enum case.
- **Pack to 160 characters, not to the 300-character cap.** Anything past ~176 ids is cut by the engine,
  and the seam is what the owner heard; 160 leaves a margin for phoneme-dense text. Cost: a constant.
- **64 kbps, not 48.** 48 kbps measures 19 dB and 64 kbps 24 dB against the render; the encoder tops out
  below 96 at 24 kHz mono. +15 MB per hour of audio under an unchanged LRU cap. Cost: a constant and a
  cache namespace.
- **The Simulator build keeps the system voices.** It links no Kokoro engine; an empty voice list would
  be worse than the old one. Cost: two lines.
- **The Reader page is the redesign target, not the Player sheet.** The owner's screenshot is the Reader
  (the Readium page); the Player sheet keeps its tick scrubber and layout. Cost: none if wrong — the
  Player sheet can follow in a later plan.
- **Voice previews pause the book.** A preview over a playing book would be two voices at once.

## Deferred

- A 30-second Core ML bucket (whole paragraphs in one call, as the MLX reference does) — a spike after
  the phone listen.
- The Player sheet's styling.
- Everything under "pending hardware" in HANDOFF; the phone is unplugged until the owner reconnects it.
