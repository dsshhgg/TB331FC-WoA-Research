#!/usr/bin/env python3
"""Extract disassembly lines from full.asm by VA range.
usage: python rng.py LO HI [file]
"""
import re, sys

P = r'E:\rom\work\woa\abl-jump-analysis\full.asm'
lo = int(sys.argv[1], 0)
hi = int(sys.argv[2], 0)
if len(sys.argv) > 3:
    P = sys.argv[3]

lines = open(P, errors='replace').read().splitlines()
pat = re.compile(r'^\s*([0-9a-fA-F]+):')
for ln in lines:
    m = pat.match(ln)
    if not m:
        continue
    a = int(m.group(1), 16)
    if lo <= a <= hi:
        print(ln.rstrip())
