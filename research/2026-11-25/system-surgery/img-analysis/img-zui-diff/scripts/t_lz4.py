#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""LZ4 legacy frame 结构探查。"""
import struct
Z16 = "/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
p = Z16 + "/recovery.img"
with open(p, "rb") as f:
    f.seek(4096)
    raw = f.read(14572954)
print("total", len(raw))
pos = 0
for i in range(6):
    if pos + 8 > len(raw): break
    magic, size = struct.unpack_from("<II", raw, pos)
    print("blk %d @%d magic=0x%08x size=%d(0x%x)" % (i, pos, magic, size, size))
    # look for next magic right after
    nxt = pos + 8 + size
    if nxt + 4 <= len(raw):
        print("    next4 @%d = 0x%08x ; bytes %s" % (nxt, struct.unpack_from("<I", raw, nxt)[0], raw[nxt:nxt+8].hex()))
    pos = nxt
# scan all occurrences of magic
m = struct.pack("<I", 0x184C2102)
idx = []
i = raw.find(m)
while i != -1 and len(idx) < 20:
    idx.append(i)
    i = raw.find(m, i+1)
print("magic occurrences:", idx)
