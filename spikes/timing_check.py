# spikes/timing_check.py — usage: python3 timing_check.py <spike.csv> <dir with sentence-N.wav>
# First-pass §7.4 check: for each logged token start, measure the audio energy just before vs
# just after it. A word onset should sit on a rise (quiet -> loud). Reports each sentence's
# tokens with the energy ratio and flags starts that land inside sustained sound or silence.
# This is a screen for gross drift only; the plan's pass criterion (±100 ms) is judged by ear.
import csv, math, os, sys, wave, array
from collections import defaultdict

csv_path, wav_dir = sys.argv[1], sys.argv[2]
WIN = 0.06  # seconds each side of the boundary

timings = defaultdict(dict)   # i -> k -> (token, start, end)
texts = {}
with open(csv_path) as f:
    for ts, event, k, v in csv.reader(f):
        pass  # header skip handled by event check below
with open(csv_path) as f:
    rows = list(csv.reader(f))
cur = defaultdict(dict)
for ts, event, k, v in rows:
    if event == "timing":
        cur[ts][k] = v
        r = cur[ts]
        if all(x in r for x in ("i", "k", "token")):
            timings[int(r["i"])][int(r["k"])] = (r["token"], r.get("start", ""), r.get("end", ""))
    elif event == "wav.written":
        cur[ts][k] = v
        r = cur[ts]
        if "i" in r and "text" in r:
            texts[int(r["i"])] = r["text"]

def rms(samples, a, b):
    a, b = max(0, a), min(len(samples), b)
    if b <= a:
        return 0.0
    return math.sqrt(sum(s * s for s in samples[a:b]) / (b - a))

for i in sorted(timings):
    path = os.path.join(wav_dir, f"sentence-{i}.wav")
    if not os.path.exists(path):
        print(f"[{i}] no {path}")
        continue
    with wave.open(path) as w:
        sr, n = w.getframerate(), w.getnframes()
        raw = array.array("h"); raw.frombytes(w.readframes(n))
        samples = [x / 32768.0 for x in raw]
    dur = n / sr
    print(f"\n[{i}] {texts.get(i, '')!r}\n    audio {dur:.2f}s @ {sr} Hz, {len(timings[i])} tokens")
    floor = rms(samples, 0, len(samples)) * 0.15
    flagged = 0
    for k in sorted(timings[i]):
        tok, s, e = timings[i][k]
        if not s or not tok.strip():
            continue
        t = float(s)
        before = rms(samples, int((t - WIN) * sr), int(t * sr))
        after = rms(samples, int(t * sr), int((t + WIN) * sr))
        ratio = (after + 1e-6) / (before + 1e-6)
        note = ""
        if t > dur + 0.05:
            note = "PAST END"
        elif after < floor:
            note = "silent after start"
        elif ratio < 0.7:
            note = "energy falling at start"
        if note:
            flagged += 1
        print(f"    {t:6.2f}s  {tok:<14} before={before:.3f} after={after:.3f} x{ratio:4.1f}  {note}")
    last_end = max((float(e) for _, _, e in timings[i].values() if e), default=0)
    print(f"    last token end {last_end:.2f}s vs audio {dur:.2f}s (delta {last_end - dur:+.2f}s); flagged {flagged}")
