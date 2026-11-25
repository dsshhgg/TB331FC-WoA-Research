#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import struct, lz4.block
Z16 = "/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
with open(Z16 + "/recovery.img", "rb") as f:
    f.seek(4096)
    raw = f.read(14572954)
size = struct.unpack_from("<I", raw, 4)[0]
print("block0 size", size)
try:
    d = lz4.block.decompress(raw[8:8+size], uncompressed_size=8 << 20)
    print("decompressed", len(d), "head:", d[:16].hex(), "cpio?", d[:6] == b"070701")
    print("first 64:", d[:64])
except Exception as e:
    print("err", e)
# try without size hint, narrower
for s in (size, size - 4, size + 4):
    try:
        d = lz4.block.decompress(raw[8:8+s], uncompressed_size=8 << 20)
        print("ok at size", s, len(d), d[:6])
    except Exception as e:
        print("fail size", s, type(e).__name__)
