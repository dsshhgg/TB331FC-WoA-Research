#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""按 A/B 槽位逐一判定：每个机上分区更像 ZUI16 还是 ZUI17。"""
import os, hashlib, json

Z16 = "/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
Z17 = "/mnt/e/rom/work/zui17_images"
DEVFP = "/mnt/e/rom/work/device-profile/03_fp.tsv"
OUT = "/mnt/e/rom/work/img-zui-diff"

CAND = {  # base -> (z16 file, z17 file)
    "xbl":          ("xbl.elf",          "xbl.img"),
    "xbl_config":   ("xbl_config.elf",   "xbl_config.img"),
    "abl":          ("abl.elf",          "abl.img"),
    "tz":           ("tz.mbn",           "tz.img"),
    "keymaster":    ("keymint.mbn",      "keymaster.img"),
    "hyp":          ("hyp.mbn",          "hyp.img"),
    "devcfg":       ("devcfg.mbn",       "devcfg.img"),
    "rpm":          ("rpm.mbn",          "rpm.img"),
    "featenabler":  ("featenabler.mbn",  "featenabler.img"),
    "uefisecapp":   ("uefi_sec.mbn",     "uefisecapp.img"),
    "imagefv":      ("imagefv.elf",      "imagefv.img"),
    "multiimgoem":  ("multi_image.mbn",  "multiimgoem.img"),
    "qupfw":        ("qupv3fw.elf",      "qupfw.img"),
    "bluetooth":    ("BTFM.bin",         "bluetooth.img"),
    "boot":         ("boot.img",         "boot.img"),
    "init_boot":    ("init_boot.img",    "init_boot.img"),
    "vendor_boot":  ("vendor_boot.img",  "vendor_boot.img"),
    "dtbo":         ("dtbo.img",         "dtbo.img"),
    "vbmeta":       ("vbmeta.img",       "vbmeta.img"),
    "vbmeta_system":("vbmeta_system.img","vbmeta_system.img"),
    "recovery":     ("recovery.img",     "recovery.img"),
    "modem":        ("NON-HLOS.bin",     "modem.img"),
    "dsp":          ("dspso.bin",        "dsp.img"),
    "storsec":      ("storsec.mbn",      None),
    "apdp":         ("apdp.mbn",         None),
    "logfs":        ("logfs_ufs_8mb.bin",None),
}

ZERO = b"\0" * (1 << 20)

def sha_padded(p, target):
    h = hashlib.sha256(); got = 0
    with open(p, "rb") as f:
        while got < target:
            c = f.read(min(8 << 20, target - got))
            if not c: break
            h.update(c); got += len(c)
    while got < target:
        k = min(len(ZERO), target - got)
        h.update(ZERO[:k]); got += k
    return h.hexdigest()

def main():
    dev = {}
    for line in open(DEVFP, encoding="utf-8-sig"):
        if not line.strip(): continue
        p = line.rstrip("\n").split("\t")
        if p[0] == "MISSING": continue
        dev[p[0]] = dict(size=int(p[1]), mode=p[2], sha=p[3], h4k=p[4])

    cache = {}
    def cand_hash(which, base, size, mode):
        key = (which, base, size, mode)
        if key in cache: return cache[key]
        fn = CAND[base][0 if which == "Z16" else 1]
        if not fn:
            cache[key] = None; return None
        p = os.path.join(Z16 if which == "Z16" else Z17, fn)
        if not os.path.exists(p):
            cache[key] = None; return None
        lim = size if mode == "FULL" else 67108864
        cache[key] = sha_padded(p, lim)
        return cache[key]

    L = []
    def P(*a):
        s = " ".join(str(x) for x in a); L.append(s); print(s)

    P("机上分区\t槽位基名\t大小\t模式\tZUI16匹配\tZUI17匹配\t判定")
    verdict = {}
    rows = []
    for name in sorted(dev):
        d = dev[name]
        base = name[:-2] if (name.endswith("_a") or name.endswith("_b")) else name
        if base not in CAND:
            continue
        h16 = cand_hash("Z16", base, d["size"], d["mode"])
        h17 = cand_hash("Z17", base, d["size"], d["mode"])
        m16 = "YES" if h16 == d["sha"] else "no"
        m17 = "YES" if h17 == d["sha"] else "no"
        if m16 == "YES" and m17 == "YES": v = "两版相同"
        elif m16 == "YES": v = "= ZUI16"
        elif m17 == "YES": v = "= ZUI17"
        else: v = "都不是（被改过/第三来源）"
        verdict[name] = v
        rows.append(dict(part=name, base=base, size=d["size"], mode=d["mode"],
                         m16=m16, m17=m17, verdict=v, dev_sha=d["sha"],
                         h16=h16, h17=h17))
        P("%s\t%s\t%d\t%s\t%s\t%s\t%s" % (name, base, d["size"], d["mode"], m16, m17, v))

    P("")
    P("=== 摘要 ===")
    from collections import Counter
    c = Counter(verdict.values())
    for k, n in c.most_common():
        P("  %-24s %d" % (k, n))

    P("")
    P("=== 逐基名结论（合并 a/b）===")
    byb = {}
    for name, v in verdict.items():
        base = name[:-2] if (name.endswith("_a") or name.endswith("_b")) else name
        byb.setdefault(base, {})[name] = v
    for base in sorted(byb):
        P("  %-14s %s" % (base, "  ".join("%s=%s" % (k, v) for k, v in sorted(byb[base].items()))))

    json.dump(rows, open(os.path.join(OUT, "a3_slots.json"), "w"), indent=1)
    open(os.path.join(OUT, "a3_slots.tsv"), "w", encoding="utf-8").write("\n".join(L) + "\n")

main()
