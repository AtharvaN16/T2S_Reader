# compare.py — usage: python3 compare.py swift.txt ref.txt
import sys

a = open(sys.argv[1]).read().splitlines()
b = open(sys.argv[2]).read().splitlines()
assert len(a) == len(b), (len(a), len(b))
exact = sum(1 for x, y in zip(a, b) if x == y)
print(f"exact match: {exact}/{len(a)} = {exact/len(a):.1%}")
for i, (x, y) in enumerate(zip(a, b)):
    if x != y:
        print(f"--- {i}\nswift: {x}\nref:   {y}")
