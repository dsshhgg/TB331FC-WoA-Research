#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""dtbo 表项对比 + vbmeta/vbmeta_system 摘要。"""
import os, struct

Z16 = "/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
Z17 = "/mnt/e/rom/work/zui17_images"
OUT = "/mnt/e/rom/work/img-zui-diff/a10_dtbo.txt"

def parse_dtbo(p):
    b = open(p, "rb").read(4096)
    magic, total, hsize, esize, count, eoff, psize, ver = struct.unpack_from(">8I", b, 0)
    hdr = dict(magic=hex(magic), total_size=total, header_size=hsize, entry_size=esize,
               count=count, entries_off=eoff, page_size=psize, version=ver)
    ents = []
    with open(p, "rb") as f:
        f.seek(eoff)
        raw = f.read(count * 32)
    for i in range(count):
        s, o, iid, rev, c0, c1, c2, c3 = struct.unpack_from(">8I", raw, i * 32)
        ents.append(dict(idx=i, size=s, off=o, id=iid, rev=rev, custom=(c0, c1, c2, c3)))
    return hdr, ents

def main():
    L = []
    def P(*a):
        s = " ".join(str(x) for x in a); L.append(s); print(s)

    h16, e16 = parse_dtbo(Z16 + "/dtbo.img")
    h17, e17 = parse_dtbo(Z17 + "/dtbo.img")
    P("=== dtbo 头 ===")
    P("  Z16 %s" % h16)
    P("  Z17 %s" % h17)
    P("")
    P("=== dtbo 表项对比（count=%d vs %d）===" % (len(e16), len(e17)))
    P("  idx  Z16(id,rev,size)                 Z17(id,rev,size)                 变化")
    n = max(len(e16), len(e17))
    for i in range(n):
        a = e16[i] if i < len(e16) else None
        b = e17[i] if i < len(e17) else None
        sa = "id=0x%x rev=0x%x size=%d" % (a["id"], a["rev"], a["size"]) if a else "-"
        sb = "id=0x%x rev=0x%x size=%d" % (b["id"], b["rev"], b["size"]) if b else "-"
        ch = ""
        if a and b:
            if a["size"] != b["size"]:
                ch = "size %+d" % (b["size"] - a["size"])
            elif a["id"] != b["id"] or a["rev"] != b["rev"]:
                ch = "id/rev 变"
            else:
                ch = "尺寸同"
        P("  %3d  %-32s %-32s %s" % (i, sa, sb, ch))

    # 逐 entry 内容比对
    P("")
    P("=== 逐 entry 内容 sha256 ===")
    import hashlib
    with open(Z16 + "/dtbo.img", "rb") as f16, open(Z17 + "/dtbo.img", "rb") as f17:
        for i in range(min(len(e16), len(e17))):
            f16.seek(e16[i]["off"]); d16 = f16.read(e16[i]["size"])
            f17.seek(e17[i]["off"]); d17 = f17.read(e17[i]["size"])
            same = hashlib.sha256(d16).hexdigest() == hashlib.sha256(d17).hexdigest()
            P("  entry %2d  %s" % (i, "SAME" if same else "DIFF"))

    open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")

main()
