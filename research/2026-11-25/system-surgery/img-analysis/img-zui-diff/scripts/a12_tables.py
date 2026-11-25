#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 REPORT.md 里要用的 markdown 表格片段。"""
import json, os

D = "/mnt/e/rom/work/img-zui-diff"

def load(name):
    p = os.path.join(D, name)
    if not os.path.exists(p): return None
    return json.load(open(p, encoding="utf-8"))

Z16 = "/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
Z17 = "/mnt/e/rom/work/zui17_images"

# ZUI17 文件名 -> 分区名
P17 = {
    "xbl.img": "xbl", "abl.img": "abl", "abl_inner.bin": "(abl 内部 ELF 副本)",
    "tz.img": "tz", "keymaster.img": "keymaster", "hyp.img": "hyp",
    "devcfg.img": "devcfg", "rpm.img": "rpm", "featenabler.img": "featenabler",
    "uefisecapp.img": "uefisecapp", "imagefv.img": "imagefv",
    "multiimgoem.img": "multiimgoem", "qupfw.img": "qupfw", "bluetooth.img": "bluetooth",
    "xbl_config.img": "xbl_config", "boot.img": "boot", "init_boot.img": "init_boot",
    "vendor_boot.img": "vendor_boot", "recovery.img": "recovery", "dtbo.img": "dtbo",
    "vbmeta.img": "vbmeta", "vbmeta_system.img": "vbmeta_system",
    "modem.img": "modem", "dsp.img": "dsp", "odm.img": "odm(逻辑)",
    "system_dlkm.img": "system_dlkm(逻辑)", "vendor_dlkm.img": "vendor_dlkm(逻辑)",
    "vb_dtb.dtb": "vendor_boot 内嵌 dtb", "vb_ramdisk.cpio": "vendor_boot ramdisk(解压前)",
}
P16 = {
    "xbl.elf": "xbl", "abl.elf": "abl", "tz.mbn": "tz", "keymint.mbn": "keymaster",
    "hyp.mbn": "hyp", "devcfg.mbn": "devcfg", "rpm.mbn": "rpm",
    "featenabler.mbn": "featenabler", "uefi_sec.mbn": "uefisecapp",
    "imagefv.elf": "imagefv", "multi_image.mbn": "multiimgoem",
    "qupv3fw.elf": "qupfw", "BTFM.bin": "bluetooth", "xbl_config.elf": "xbl_config",
    "boot.img": "boot", "init_boot.img": "init_boot", "vendor_boot.img": "vendor_boot",
    "recovery.img": "recovery", "dtbo.img": "dtbo", "vbmeta.img": "vbmeta",
    "vbmeta_system.img": "vbmeta_system", "NON-HLOS.bin": "modem", "dspso.bin": "dsp",
    "storsec.mbn": "storsec", "apdp.mbn": "apdp", "logfs_ufs_8mb.bin": "logfs",
    "vendor_boot-debug.img": "(debug 变体)",
}

def load_sha(fn, prefix=""):
    p = os.path.join(D, fn)
    d = {}
    if not os.path.exists(p): return d
    for line in open(p, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip(): continue
        parts = line.split("  ", 1)
        if len(parts) != 2: continue
        h, n = parts
        n = n.strip()
        if n.startswith("./"): n = n[2:]
        n = n.lstrip("*")
        d[n] = h
    return d

def main():
    s17 = load_sha("zui17.sha256")
    s16 = load_sha("zui16.sha256")
    out = []

    out.append("## 表 A · ZUI17 镜像集清单（%d 个文件）\n" % len(s17))
    out.append("| 文件 | 大小 (B) | sha256 | 对应分区 |")
    out.append("|---|---:|---|---|")
    for n in sorted(s17):
        sz = os.path.getsize(os.path.join(Z17, n))
        out.append("| `%s` | %s | `%s` | %s |" % (n, f"{sz:,}", s17[n], P17.get(n, "")))
    out.append("")

    if s16:
        out.append("## 表 B · ZUI16 包内关键镜像清单（%d 个文件里有 sha256 的）\n" % len(s16))
        out.append("| 文件 | 大小 (B) | sha256 | 对应分区 |")
        out.append("|---|---:|---|---|")
        for n in sorted(s16):
            if n not in P16:
                continue
            sz = os.path.getsize(os.path.join(Z16, n))
            out.append("| `%s` | %s | `%s` | %s |" % (n, f"{sz:,}", s16[n], P16.get(n, n)))
        out.append("")

    if s16:
        rest = [n for n in sorted(s16) if n not in P16]
        if rest:
            out.append("## 表 C · ZUI16 包内其余文件（烧写框架 / super 分片 / 单槽分区，共 %d 个）\n" % len(rest))
            out.append("| 文件 | 大小 (B) | sha256 |")
            out.append("|---|---:|---|")
            for n in rest:
                sz = os.path.getsize(os.path.join(Z16, n))
                out.append("| `%s` | %s | `%s` |" % (n, f"{sz:,}", s16[n]))
            out.append("")

    a3 = load("a3_slots.json")
    if a3:
        out.append("## 表 D · 机上 49 个分区槽位 vs 两版的精确判定\n")
        out.append("| 分区 | 大小 (B) | 模式 | = ZUI16? | = ZUI17? | 判定 |")
        out.append("|---|---:|---|---|---|---|")
        for r in sorted(a3, key=lambda x: x["part"]):
            out.append("| `%s` | %s | %s | %s | %s | **%s** |" % (
                r["part"], f"{r['size']:,}", r["mode"], r["m16"], r["m17"], r["verdict"]))
        out.append("")

    open(os.path.join(D, "tables.md"), "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("wrote tables.md,", len(out), "lines")

main()
