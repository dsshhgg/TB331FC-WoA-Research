#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从两侧镜像里抽版本字符串，用于归因（内核版本、固件版本、安全补丁）。"""
import os, re, struct

Z16 = "/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
Z17 = "/mnt/e/rom/work/zui17_images"
OUT = "/mnt/e/rom/work/img-zui-diff/a5_strings.txt"

PATS = [
    re.compile(rb"Linux version [0-9][^\x00\n]{0,200}"),
    re.compile(rb"MPSS\.[A-Za-z0-9._\-]{3,40}"),
    re.compile(rb"QC_IMAGE_VERSION_STRING=[^\x00\n]{0,60}"),
    re.compile(rb"IMAGE_VARIANT_STRING=[^\x00\n]{0,60}"),
    re.compile(rb"OEM_IMAGE_VERSION_STRING=[^\x00\n]{0,80}"),
    re.compile(rb"QCOM-[A-Za-z0-9._\-]{3,60}"),
    re.compile(rb"ZUI[_ ]?[0-9][A-Za-z0-9._\-]{0,30}"),
    re.compile(rb"TB331FC[_A-Za-z0-9._\-]{0,60}"),
]

def strings_scan(p, maxlen=400):
    """stream-scan for printable ASCII runs that look interesting."""
    out = set()
    with open(p, "rb") as f:
        buf = b""
        while True:
            c = f.read(8 << 20)
            if not c: break
            buf += c
            for pat in PATS:
                for m in pat.finditer(buf):
                    s = m.group(0)
                    out.add(s[:maxlen])
            buf = buf[-512:] if len(buf) > 512 else buf
    return out

def main():
    L = []
    def P(*a):
        s = " ".join(str(x) for x in a); L.append(s); print(s)

    targets = [
        ("boot.img", "boot.img"),
        ("init_boot.img", "init_boot.img"),
        ("recovery.img", "recovery.img"),
        ("vendor_boot.img", "vendor_boot.img"),
        ("xbl.elf", "xbl.img"),
        ("abl.elf", "abl.img"),
        ("tz.mbn", "tz.img"),
        ("keymint.mbn", "keymaster.img"),
        ("hyp.mbn", "hyp.img"),
        ("NON-HLOS.bin", "modem.img"),
        ("dspso.bin", "dsp.img"),
        ("xbl_config.elf", "xbl_config.img"),
    ]
    for f16, f17 in targets:
        p16 = os.path.join(Z16, f16)
        p17 = os.path.join(Z17, f17) if f17 else None
        s16 = strings_scan(p16) if os.path.exists(p16) else set()
        s17 = strings_scan(p17) if p17 and os.path.exists(p17) else set()
        P("")
        P("### %s  (Z16) vs %s (Z17)" % (f16, f17))
        only16 = {x for x in s16 if x not in s17}
        only17 = {x for x in s17 if x not in s16}
        common = s16 & s17
        for tag, S in (("BOTH", common), ("ONLY-Z16", only16), ("ONLY-Z17", only17)):
            for x in sorted(S)[:14]:
                P("  [%s] %s" % (tag, x.decode("utf-8", "replace")))

    open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")

main()
