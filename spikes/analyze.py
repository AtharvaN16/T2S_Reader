# spikes/analyze.py — usage: python3 analyze.py [--warm-skip N] [--per-minute] spike-*.csv
#
# Summarises SpikeLog CSVs (ts,event,k,v) from the Spike Harness. Plan 0 Task 4 Step 1; extended
# for Task 8b.
#
# Two things it does that a hand median does not:
#
#   * It splits by run. One CSV can hold several `bench.start`s and a device can be relaunched with
#     a different engine, policy or bucket staging into the same file, and mixing an `mlx` run with
#     a `coreml` one — or a `default` policy with `cpuOnly` — produces a median of nothing.
#   * It discards the first `--warm-skip` calls of each run (default 2). Core ML builds its compute
#     plan on the first prediction and MLX has its own cold start, so call 0 is routinely 2-3x the
#     warm cost. The protocol says warm medians; this is where that happens.
#
# It also reports what the memory question needs: the footprint at the first warm call, the peak,
# a least-squares slope in MB per sentence over the warm calls, and the same slope over each half
# of the run, because a leak keeps the same slope while a cache that fills has a second half
# flatter than its first. Elapsed times are measured from `bench.start`, not from the first
# sentence, so a thermal threshold is quoted against the same clock the protocol uses.
import csv, statistics, sys
from collections import defaultdict

WARM_SKIP_DEFAULT = 2


def parse_args(argv):
    warm_skip, per_minute, paths = WARM_SKIP_DEFAULT, False, []
    it = iter(argv)
    for arg in it:
        if arg == "--warm-skip":
            warm_skip = int(next(it))
        elif arg.startswith("--warm-skip="):
            warm_skip = int(arg.split("=", 1)[1])
        elif arg == "--per-minute":
            per_minute = True
        else:
            paths.append(arg)
    return warm_skip, per_minute, paths


def read_events(path):
    """Yield `(ts, event, fields)` per logged event.

    `SpikeLog.record` writes one CSV line per field, all sharing the event's timestamp and emitted
    in sorted key order. Timestamps have millisecond resolution, and the per-word `timing` rows of
    one sentence are written in a tight loop — dozens of them land on the same millisecond. So a
    record cannot be keyed by timestamp: the boundary is a key that repeats.
    """
    ts_prev, ev_prev, fields = None, None, {}
    with open(path) as f:
        for ts, event, k, v in csv.reader(f):
            if event == "event":        # header
                continue
            if event != ev_prev or ts != ts_prev or k in fields:
                if ev_prev is not None:
                    yield ts_prev, ev_prev, fields
                ts_prev, ev_prev, fields = ts, event, {}
            if k:
                fields[k] = v
    if ev_prev is not None:
        yield ts_prev, ev_prev, fields


def read_runs(paths):
    """Every `sentence` row, tagged with the run context in force when it was written."""
    runs = []           # list of dicts: context + rows
    for path in paths:
        ctx = {"path": path, "engine": "?", "policy": "", "staged": "", "rate": "?", "load": None}
        current = None
        for ts, event, fields in read_events(path):
            if event == "model.loaded":
                ctx = dict(ctx)
                ctx["engine"] = fields.get("engine", ctx["engine"])
                ctx["policy"] = fields.get("policy", "")
                ctx["staged"] = fields.get("buckets", fields.get("bucket", ""))
                if "seconds" in fields:
                    ctx["load"] = float(fields["seconds"])
            elif event == "bench.start" and "sentences" in fields:
                ctx = dict(ctx)
                ctx["engine"] = fields.get("engine", ctx["engine"])
                ctx["policy"] = fields.get("policy", ctx["policy"])
                ctx["rate"] = fields.get("rate", "?")
                current = {"ctx": ctx, "rows": [], "t0": ts}
                runs.append(current)
            elif event == "sentence" and "rtf" in fields and "i" in fields:
                if current is None:     # a CSV that starts mid-run
                    current = {"ctx": ctx, "rows": [], "t0": ts}
                    runs.append(current)
                current["rows"].append({"ts": ts, **fields})
    return [r for r in runs if r["rows"]]


def floats(rows, key):
    out = []
    for r in rows:
        try:
            x = float(r[key])
        except (KeyError, ValueError):
            continue
        if x == x:      # not NaN
            out.append(x)
    return out


def p90(xs):
    if not xs:
        return float("nan")
    s = sorted(xs)
    return s[min(len(s) - 1, int(round(0.9 * (len(s) - 1))))]


def slope(ys):
    """Least-squares MB per sentence over an evenly spaced series."""
    n = len(ys)
    if n < 3:
        return float("nan")
    xs = list(range(n))
    mx, my = sum(xs) / n, sum(ys) / n
    den = sum((x - mx) ** 2 for x in xs)
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den if den else float("nan")


def seconds_between(a, b):
    """ISO8601 with fractional seconds, same day — enough for a bench run."""
    def sec(t):
        hms = t[11:-1]
        h, m, s = hms.split(":")
        return int(h) * 3600 + int(m) * 60 + float(s)
    d = sec(b) - sec(a)
    return d + 86400 if d < 0 else d


def describe(run, warm_skip, per_minute):
    ctx, rows = run["ctx"], run["rows"]
    label = f"{ctx['engine']}"
    if ctx["policy"]:
        label += f"/{ctx['policy']}"
    if ctx["staged"]:
        label += f" buckets={ctx['staged']}"
    label += f" rate={ctx['rate']}"
    warm = rows[warm_skip:]
    origin = run["t0"]      # `bench.start` where the CSV has one, else the first sentence
    print(f"\n=== {label}  ({ctx['path'].split('/')[-1]})")
    span = seconds_between(rows[0]["ts"], rows[-1]["ts"])
    print(f"    {len(rows)} sentences over {span:.0f} s; warm = {len(warm)} after skipping {warm_skip}")
    if ctx["load"] is not None:
        print(f"    model load: {ctx['load']:.1f} s")
    if not warm:
        return

    rtf = floats(warm, "rtf")
    if rtf:
        print(f"    rtf        median {statistics.median(rtf):.3f}  p90 {p90(rtf):.3f}  "
              f"min {min(rtf):.3f}  max {max(rtf):.3f}")
    pipe = floats(warm, "rtfPipeline")
    if pipe:
        print(f"    rtfPipeline median {statistics.median(pipe):.3f}  p90 {p90(pipe):.3f}   "
              f"(excludes G2P)")

    foot = [int(r["footprintMB"]) for r in warm if r.get("footprintMB", "").lstrip("-").isdigit()]
    if foot:
        half = len(foot) // 2
        print(f"    footprint  first warm {foot[0]} MB  peak {max(foot)} MB  last {foot[-1]} MB")
        print(f"    slope      {slope(foot):+.2f} MB/sentence over all warm calls; "
              f"first half {slope(foot[:half]):+.2f}, second half {slope(foot[half:]):+.2f}")

    therm = [(r["ts"], int(r["thermal"])) for r in rows if r.get("thermal", "").isdigit()]
    if therm:
        worst = max(t for _, t in therm)
        line = f"    thermal    max {worst}"
        for state in (1, 2, 3):
            hit = next((ts for ts, t in therm if t >= state), None)
            if hit:
                line += f"; reached {state} at +{seconds_between(origin, hit):.0f} s"
        print(line + "  (0 nominal, 1 fair, 2 serious, 3 critical)")

    batt = [(r["ts"], float(r["battery"])) for r in rows if r.get("battery")]
    if len(batt) >= 2:
        (t0, b0), (t1, b1) = batt[0], batt[-1]
        charging = {r.get("charging", "?") for r in rows}
        print(f"    battery    {b0:.2f} -> {b1:.2f} ({(b1 - b0) * 100:+.0f} pp) over {span:.0f} s; "
              f"charging={'/'.join(sorted(charging))}")

    stages = [k for k in warm[0] if k.startswith("st_")]
    if stages:
        parts = []
        for k in sorted(stages):
            xs = floats(warm, k)
            if xs and statistics.median(xs) >= 0.0005:
                parts.append(f"{k[3:]} {statistics.median(xs):.3f}")
        print("    stages     median s: " + ", ".join(parts))
    g2p = floats(warm, "g2p")
    if g2p:
        print(f"    g2p        median {statistics.median(g2p):.3f} s")

    for key in ("bucket", "durationModel"):
        seen = defaultdict(int)
        for r in warm:
            if key in r:
                seen[r[key]] += 1
        if seen:
            print(f"    {key:<10} " + ", ".join(f"{k}x{v}" for k, v in sorted(seen.items())))

    errs = [r["error"] for r in rows if r.get("error")]
    if errs:
        print(f"    errors     {len(errs)}: {errs[0][:120]}")

    if per_minute:
        by_min = defaultdict(list)
        for r in warm:
            try:
                by_min[r["ts"][:16]].append(float(r["rtf"]))
            except (KeyError, ValueError):
                pass
        for m, xs in sorted(by_min.items()):
            print(f"      {m}  n={len(xs):3d}  median rtf={statistics.median(xs):.3f}")


if __name__ == "__main__":
    warm_skip, per_minute, paths = parse_args(sys.argv[1:])
    runs = read_runs(paths)
    if not runs:
        sys.exit("no sentence rows found")
    for run in runs:
        describe(run, warm_skip, per_minute)
