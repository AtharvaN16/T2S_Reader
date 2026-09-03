# spikes/analyze.py — usage: python3 analyze.py spike-*.csv
# Summarises SpikeLog CSVs (ts,event,k,v) from the Spike Harness: per-minute median RTF,
# peak memory footprint, worst thermal state, and battery delta. Plan 0 Task 4 Step 1.
import csv, statistics, sys
from collections import defaultdict

rows = defaultdict(dict)
for path in sys.argv[1:]:
    with open(path) as f:
        for ts, event, k, v in csv.reader(f):
            if event == "sentence":
                rows[(path, ts)][k] = v

by_min = defaultdict(list)
battery = []
footprint = []
thermal = []
for (path, ts), r in sorted(rows.items()):
    minute = ts[:16]
    try:
        by_min[minute].append(float(r["rtf"]))
        footprint.append(int(r["footprintMB"]))
        thermal.append(int(r["thermal"]))
        battery.append((ts, float(r["battery"])))
    except (KeyError, ValueError):
        pass

for m, xs in sorted(by_min.items()):
    print(f"{m}  n={len(xs):3d}  median rtf={statistics.median(xs):.3f}")
if footprint:
    print(f"peak footprint MB: {max(footprint)}")
if thermal:
    print(f"max thermal state: {max(thermal)}  (0 nominal, 1 fair, 2 serious, 3 critical)")
if len(battery) >= 2:
    (t0, b0), (t1, b1) = battery[0], battery[-1]
    print(f"battery {b0:.2f} -> {b1:.2f} between {t0} and {t1}")
