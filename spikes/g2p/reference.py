# reference.py — Python misaki (pip install 'misaki[en]') phonemes, one line per stdin sentence.
import sys
from misaki import en

g2p = en.G2P(trf=False, british=False, fallback=None)
for line in sys.stdin:
    ps, _ = g2p(line.strip())
    print(ps)
