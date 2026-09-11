#!/usr/bin/env python3
"""Compares two Core ML Kokoro model sets on the one output where a small error is not small:
the duration model's integer frame counts.

Usage:
    PYTHONPATH=.build/ctlib /usr/bin/python3 scripts/compare-kokoro-durations.py

Every other stage emits floats, where a quantization error shows up as a slightly different number.
The duration model emits INT32 frames per phoneme, and those frames build the one-hot alignment every
later stage is indexed by, so a single flipped count shifts everything after it in time. A cosine
distance cannot see that; only an exact comparison can. This script does the exact comparison, on
realistic input, without the Swift pipeline or an on-device render.

It reproduces the app's input contract exactly, which is the part worth keeping — see
KokoroCoreMLEngine.render and KokoroTokenizer:

  input_ids       [boundary] + phoneme ids + [boundary], padded to the bucket with the boundary id (0)
  attention_mask  1 for the framed tokens, 0 for the padding
  ref_s           voice row clamp(len(phonemes) - 1, 0, 509), counted over the *unframed* phoneme
                  string's characters, not the token ids the vocabulary lookup survives
  speed           1.0

The phoneme strings below are written in the Misaki American-English notation this vocabulary encodes
(A=eI, I=aI, O=oU, W=aU, Y=OI as single characters; U+02C8 primary and U+02CC secondary stress). They
are hand-written rather than produced by G2P so that this script needs no MisakiSwift and no Swift
build; they only have to be representative, not the exact phonemization the app would produce for the
same text.

Measured 2026-09-11 for the int8 candidate of scripts/quantize-kokoro-coreml.py: 4 of 363 phonemes
came out one frame different, 6 of the 10 sentences were identical, and the total drifted 0.025 s
across 13.1 s of speech. For scale, the repo already treats a 0.33 s difference between a streamed
and a whole render of the same passage as two performances of the same words (docs/HANDOFF.md).
"""

import json, numpy as np, coremltools as ct

VOCAB = json.load(open("App/Resources/KokoroCoreML/runtime/kokoro-vocab.json"))["vocab"]
VOICE = np.fromfile("App/Resources/KokoroCoreML/voices/af_heart.bin", dtype=np.float32).reshape(510, 256)
BOUNDARY, BUCKET = 0, 128

# Misaki-style American English IPA, the notation this vocab encodes
# (A=eɪ, I=aɪ, O=oʊ, W=aʊ, Y=ɔɪ; ˈ primary stress, ˌ secondary).
SENTENCES = [
    ("hello world",            "həlˈO wˈɜɹld"),
    ("the quick brown fox",    "ðə kwˈɪk bɹˈWn fˈɑks"),
    ("it was the best of times, it was the worst of times",
                               "ɪt wʌz ðə bˈɛst ʌv tˈImz, ɪt wʌz ðə wˈɜɹst ʌv tˈImz"),
    ("call me Ishmael",        "kˈɔl mi ˈɪʃmeɪəl"),
    ("twenty-five officers re-entered the well-known hall",
                               "twˈɛnti fˈIv ˈɔfɪsɚz ɹiˈɛntɚd ðə wˈɛlnOn hˈɔl"),
    ("a thousand ships and the topless towers of Ilium",
                               "ɐ θˈWzənd ʃˈɪps ænd ðə tˈɑpləs tˈWɚz ʌv ˈɪliəm"),
    ("Bah! said Scrooge. Humbug!",  "bˈɑ! sˈɛd skɹˈuʤ. hˈʌmbʌɡ!"),
    ("she sells sea shells by the sea shore",
                               "ʃi sˈɛlz sˈi ʃˈɛlz bI ðə sˈi ʃˈɔɹ"),
    ("the commander-in-chief announced a cost-cutting plan",
                               "ðə kəmˈændɚɪnʧˈif ɐnˈWnst ɐ kˈɔstkʌtɪŋ plˈæn"),
    ("in the beginning God created the heaven and the earth",
                               "ɪn ðə bɪɡˈɪnɪŋ ɡˈɑd kɹiˈAtɪd ðə hˈɛvən ænd ðə ˈɜɹθ"),
]

def build(phonemes):
    ids = [VOCAB[c] for c in phonemes if c in VOCAB]
    dropped = sum(1 for c in phonemes if c not in VOCAB)
    framed = [BOUNDARY] + ids + [BOUNDARY]
    pad = BUCKET - len(framed)
    assert pad >= 0, f"{len(framed)} tokens exceeds {BUCKET}"
    row = max(0, min(509, len(phonemes) - 1))          # tokenizer.refS: unframed phoneme count
    return {
        "input_ids": np.array([framed + [BOUNDARY] * pad], np.int32),
        "attention_mask": np.array([[1] * len(framed) + [0] * pad], np.int32),
        "ref_s": VOICE[row:row + 1].copy(),
        "speed": np.array([1.0], np.float32),
    }, len(ids), dropped

models = {}
for tag, root in (("fp16", "KokoroCoreML"), ("int8", "KokoroCoreML-int8")):
    models[tag] = ct.models.MLModel(
        f"App/Resources/{root}/coreml/kokoro_duration_t128.mlpackage",
        compute_units=ct.ComputeUnit.CPU_ONLY)
    print(f"loaded {tag}", flush=True)

total_tok = total_flip = total_frames_a = total_frames_b = 0
print(f"\n{'sentence':<34} {'tok':>4} {'flips':>6} {'frames fp16→int8':>20} {'drift':>7}")
for text, phon in SENTENCES:
    feed, ntok, dropped = build(phon)
    a = models["fp16"].predict(feed); b = models["int8"].predict(feed)
    da = np.asarray(a["pred_dur"]).ravel()[:ntok + 2]
    db = np.asarray(b["pred_dur"]).ravel()[:ntok + 2]
    flips = int((da != db).sum())
    fa, fb = int(da.sum()), int(db.sum())
    ms = (fb - fa) * 300 / 24000 * 1000
    total_tok += len(da); total_flip += flips; total_frames_a += fa; total_frames_b += fb
    warn = "  <-- dropped %d" % dropped if dropped else ""
    print(f"{text[:33]:<34} {ntok:>4} {flips:>6} {fa:>9} → {fb:<8} {ms:>6.0f}ms{warn}")

print(f"\ntokens {total_tok}, differing {total_flip} ({total_flip/total_tok:.1%})")
print(f"frames {total_frames_a} → {total_frames_b}  "
      f"({(total_frames_b-total_frames_a)*300/24000:.3f} s over "
      f"{total_frames_a*300/24000:.1f} s of speech)")
