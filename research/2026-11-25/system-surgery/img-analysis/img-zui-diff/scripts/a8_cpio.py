#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""解析 newc cpio（可拼接），逐文件比对 ramdisk 内容。"""
import os, sys, hashlib, json

W = "/mnt/e/rom/work/img-zui-diff/work"
OUT = "/mnt/e/rom/work/img-zui-diff"

def parse_cpio(path):
    entries = {}   # name -> (size, mode, sha256)
    order = []
    with open(path, "rb") as f:
        data = f.read()
    pos = 0
    n = len(data)
    while pos + 110 <= n:
        if data[pos:pos+6] not in (b"070701", b"070702"):
            # try to resync
            nxt = data.find(b"070701", pos)
            if nxt < 0:
                break
            pos = nxt
            continue
        hdr = data[pos:pos+110]
        try:
            fsize = int(hdr[54:62], 16)
            mode = int(hdr[14:22], 16)
            namesize = int(hdr[94:102], 16)
        except ValueError:
            break
        name = data[pos+110:pos+110+namesize-1].decode("utf-8", "replace")
        pad_name = (4 - ((110 + namesize) % 4)) % 4
        dstart = pos + 110 + namesize + pad_name
        blob = data[dstart:dstart+fsize]
        entries[name] = (fsize, mode, hashlib.sha256(blob).hexdigest())
        order.append(name)
        pos = dstart + fsize
        pos += (4 - (fsize % 4)) % 4
    return entries, order

def main():
    pairs = [("recovery", "rec16.cpio", "rec17.cpio"),
             ("vendor_boot", "vb16.cpio", "vb17.cpio"),
             ("init_boot", "ib16.cpio", "ib17.cpio")]
    L = []
    def P(*a):
        s = " ".join(str(x) for x in a); L.append(s); print(s)

    summary = {}
    for tag, f16, f17 in pairs:
        e16, o16 = parse_cpio(os.path.join(W, f16))
        e17, o17 = parse_cpio(os.path.join(W, f17))
        P("")
        P("========== %s ==========" % tag)
        P("  条目数 Z16=%d  Z17=%d" % (len(e16), len(e17)))
        only16 = sorted(set(e16) - set(e17))
        only17 = sorted(set(e17) - set(e16))
        common = sorted(set(e16) & set(e17))
        changed = [k for k in common if e16[k][2] != e17[k][2]]
        same = len(common) - len(changed)
        P("  只在 Z16: %d   只在 Z17: %d   同名相同: %d   同名不同: %d" % (
            len(only16), len(only17), same, len(changed)))
        P("  --- 只在 Z16 ---")
        for k in only16[:80]:
            P("    - %-60s %d" % (k, e16[k][0]))
        P("  --- 只在 Z17 ---")
        for k in only17[:80]:
            P("    + %-60s %d" % (k, e17[k][0]))
        P("  --- 同名不同（按大小差排序）---")
        changed.sort(key=lambda k: abs(e17[k][0] - e16[k][0]), reverse=True)
        for k in changed[:120]:
            P("    * %-58s Z16=%-10d Z17=%-10d %+d" % (k, e16[k][0], e17[k][0], e17[k][0]-e16[k][0]))
        summary[tag] = dict(n16=len(e16), n17=len(e17), only16=only16, only17=only17,
                            changed=changed, same=same)

    json.dump({k: {kk: (vv if not isinstance(vv, list) else vv) for kk, vv in v.items()}
               for k, v in summary.items()}, open(os.path.join(OUT, "a8_cpio.json"), "w"), indent=1)
    open(os.path.join(OUT, "a8_cpio.txt"), "w", encoding="utf-8").write("\n".join(L) + "\n")

main()
