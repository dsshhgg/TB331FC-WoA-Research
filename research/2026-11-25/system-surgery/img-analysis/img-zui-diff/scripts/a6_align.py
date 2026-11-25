#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""判定同名镜像的差异是"真实内容改动"还是"仅仅是 4K 对齐补零 / 重新封装"。
全部流式处理，不把大文件读进内存。"""
import os

Z16 = "/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
Z17 = "/mnt/e/rom/work/zui17_images"
OUT = "/mnt/e/rom/work/img-zui-diff/a6_align.txt"

PAIRS = [
    ("xbl", "xbl.elf", "xbl.img"),
    ("xbl_config", "xbl_config.elf", "xbl_config.img"),
    ("abl", "abl.elf", "abl.img"),
    ("tz", "tz.mbn", "tz.img"),
    ("keymaster", "keymint.mbn", "keymaster.img"),
    ("hyp", "hyp.mbn", "hyp.img"),
    ("devcfg", "devcfg.mbn", "devcfg.img"),
    ("rpm", "rpm.mbn", "rpm.img"),
    ("featenabler", "featenabler.mbn", "featenabler.img"),
    ("uefisecapp", "uefi_sec.mbn", "uefisecapp.img"),
    ("imagefv", "imagefv.elf", "imagefv.img"),
    ("multiimgoem", "multi_image.mbn", "multiimgoem.img"),
    ("qupfw", "qupv3fw.elf", "qupfw.img"),
    ("bluetooth", "BTFM.bin", "bluetooth.img"),
    ("boot", "boot.img", "boot.img"),
    ("init_boot", "init_boot.img", "init_boot.img"),
    ("vendor_boot", "vendor_boot.img", "vendor_boot.img"),
    ("dtbo", "dtbo.img", "dtbo.img"),
    ("vbmeta", "vbmeta.img", "vbmeta.img"),
    ("vbmeta_system", "vbmeta_system.img", "vbmeta_system.img"),
    ("recovery", "recovery.img", "recovery.img"),
    ("modem", "NON-HLOS.bin", "modem.img"),
    ("dsp", "dspso.bin", "dsp.img"),
]

CH = 4 << 20

def compare(p16, p17, count_diffs=False):
    """returns (size16, size17, firstdiff, ndiff_common, tail_all_zero_after_16)"""
    s16, s17 = os.path.getsize(p16), os.path.getsize(p17)
    fd = -1
    nd = 0
    with open(p16, "rb") as f16, open(p17, "rb") as f17:
        pos = 0
        while True:
            a = f16.read(CH)
            b = f17.read(CH)
            if not a and not b: break
            n = min(len(a), len(b))
            if a[:n] != b[:n]:
                for i in range(0, n, 512):
                    sa, sb = a[i:i+512], b[i:i+512]
                    if sa != sb:
                        for j in range(min(len(sa), len(sb))):
                            if sa[j] != sb[j]:
                                if fd < 0: fd = pos + i + j
                                nd += 1
                                break
            pos += n
            if s16 <= pos:  # Z16 exhausted; check Z17 tail
                rest_start = pos
                break
    # tail of Z17 after Z16 end
    tail_nonzero = None
    with open(p17, "rb") as f17:
        f17.seek(s16)
        t = f17.read()
    if all(x == 0 for x in t):
        tail_nonzero = False
    else:
        tail_nonzero = True
    return s16, s17, fd, nd, tail_nonzero

def main():
    L = []
    def P(*a):
        s = " ".join(str(x) for x in a); L.append(s); print(s)

    P("%-14s %-10s %-10s %-8s %-11s %-34s %s" % ("base", "Z16size", "Z17size", "delta", "firstdiff", "判定", "Z17在Z16长度之后是否全零"))
    for base, f16, f17 in PAIRS:
        p16, p17 = os.path.join(Z16, f16), os.path.join(Z17, f17)
        if not (os.path.exists(p16) and os.path.exists(p17)):
            P("%-14s MISSING" % base); continue
        s16, s17, fd, nd, tailnz = compare(p16, p17, count_diffs=True)
        if fd < 0 and s16 == s17:
            v = "完全一致"
        elif fd < 0 and tailnz is False:
            v = "Z17 = Z16 + 尾部补零（仅对齐差）"
        elif fd < 0 and tailnz is True:
            v = "Z16 是 Z17 的前缀，且 Z17 尾部有真实数据"
        else:
            v = "内容真实不同（首个差异 @0x%x，512B 块差异 %d 处）" % (fd, nd)
        with open(p16, "rb") as f: m16 = f.read(8)
        with open(p17, "rb") as f: m17 = f.read(8)
        P("%-14s %-10d %-10d %-8d %-11d %-34s %s" % (base, s16, s17, s17 - s16, fd, v, tailnz))
        P("      magic Z16=%s  Z17=%s" % (m16.hex(), m17.hex()))

    open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")

main()
