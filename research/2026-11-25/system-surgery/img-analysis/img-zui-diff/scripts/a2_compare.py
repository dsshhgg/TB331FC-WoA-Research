#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ZUI16 (EDL flat pkg) vs ZUI17 (image set) 逐分区对比 + 与机上实测指纹对照.

机上指纹来自 E:\\rom\\work\\device-profile\\03_fp.tsv，语义由 fingerprint.sh 定义：
  sz   = 分区大小
  mode = FULL (sz<=64MiB, 对整分区含零填充求 sha256) / HEAD64M (sz>64MiB, 只取前 64MiB)
  sha  = 上述 sha256
  h4k  = 前 4096 字节 sha256
因此本脚本可以“精确复现”机上值：把包内镜像按分区大小零填充后算同样的摘要。
"""
import os, struct, hashlib, json

Z16 = "/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
Z17 = "/mnt/e/rom/work/zui17_images"
DEVFP = "/mnt/e/rom/work/device-profile/03_fp.tsv"
OUT = "/mnt/e/rom/work/img-zui-diff"

MAP = [
    ("xbl_a",          "xbl.elf",         "xbl.img"),
    ("xbl_config_a",   "xbl_config.elf",  "xbl_config.img"),
    ("abl_a",          "abl.elf",         "abl.img"),
    ("tz_a",           "tz.mbn",          "tz.img"),
    ("keymaster_a",    "keymint.mbn",     "keymaster.img"),
    ("hyp_a",          "hyp.mbn",         "hyp.img"),
    ("devcfg_a",       "devcfg.mbn",      "devcfg.img"),
    ("rpm_a",          "rpm.mbn",         "rpm.img"),
    ("featenabler_a",  "featenabler.mbn", "featenabler.img"),
    ("uefisecapp_a",   "uefi_sec.mbn",    "uefisecapp.img"),
    ("imagefv_a",      "imagefv.elf",     "imagefv.img"),
    ("multiimgoem_a",  "multi_image.mbn", "multiimgoem.img"),
    ("qupfw_a",        "qupv3fw.elf",     "qupfw.img"),
    ("bluetooth_a",    "BTFM.bin",        "bluetooth.img"),
    ("boot_a",         "boot.img",        "boot.img"),
    ("init_boot_a",    "init_boot.img",   "init_boot.img"),
    ("vendor_boot_a",  "vendor_boot.img", "vendor_boot.img"),
    ("dtbo_a",         "dtbo.img",        "dtbo.img"),
    ("vbmeta_a",       "vbmeta.img",      "vbmeta.img"),
    ("vbmeta_system_a","vbmeta_system.img","vbmeta_system.img"),
    ("recovery_a",     "recovery.img",    "recovery.img"),
    ("modem_a",        "NON-HLOS.bin",    "modem.img"),
    ("dsp_a",          "dspso.bin",       "dsp.img"),
    # 只在 ZUI16 出现的固件（ZUI17 集里没有）
    ("storsec",        "storsec.mbn",     None),
    ("apdp",           "apdp.mbn",        None),
    ("logfs",          "logfs_ufs_8mb.bin", None),
    # 逻辑分区（super 内）
    ("super_5/system_dlkm", "super_5.img", "system_dlkm.img"),
    ("super_8/vendor_dlkm", "super_8.img", "vendor_dlkm.img"),
    ("?/odm",          None,              "odm.img"),
]

def fsz(p):
    if not p or not os.path.exists(p):
        return None
    return os.path.getsize(p)

def sha_stream(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        while True:
            c = f.read(8 << 20)
            if not c: break
            h.update(c)
    return h.hexdigest()

def sha_head(p, n):
    h = hashlib.sha256()
    left = n
    with open(p, "rb") as f:
        while left > 0:
            c = f.read(min(left, 8 << 20))
            if not c: break
            h.update(c); left -= len(c)
    if left > 0:
        h.update(b"\0" * left)
    return h.hexdigest()

ZERO = b"\0" * (1 << 20)

def sha_padded(p, part_size, limit=None):
    """sha256 of (file bytes + zero padding) truncated to limit (default part_size)."""
    target = part_size if limit is None else min(limit, part_size)
    h = hashlib.sha256()
    got = 0
    with open(p, "rb") as f:
        while got < target:
            c = f.read(min(8 << 20, target - got))
            if not c: break
            h.update(c); got += len(c)
    while got < target:
        k = min(len(ZERO), target - got)
        h.update(ZERO[:k]); got += k
    return h.hexdigest()

def load_devfp():
    d = {}
    for line in open(DEVFP, encoding="utf-8-sig"):
        line = line.rstrip("\n")
        if not line.strip(): continue
        p = line.split("\t")
        if p[0] == "MISSING": continue
        d[p[0]] = dict(size=int(p[1]), mode=p[2], sha=p[3], h4k=p[4])
    return d

def main():
    dev = load_devfp()
    rows = []
    L = []
    def P(*a):
        s = " ".join(str(x) for x in a)
        L.append(s); print(s)

    P("分区\tZ16文件\tZ16大小\tZ17文件\tZ17大小\tsize_delta\tfile_sha_equal\tdev_mode\tdev_size\tZ16==dev\tZ17==dev\th4k相等")
    for part, f16, f17 in MAP:
        p16 = os.path.join(Z16, f16) if f16 else None
        p17 = os.path.join(Z17, f17) if f17 else None
        s16, s17 = fsz(p16), fsz(p17)
        if s16 is None and s17 is None: continue
        sh16 = sha_stream(p16) if s16 else ""
        sh17 = sha_stream(p17) if s17 else ""
        h4k16 = sha_head(p16, 4096) if s16 else ""
        h4k17 = sha_head(p17, 4096) if s17 else ""
        dd = dev.get(part)
        m16 = m17 = ""
        if dd:
            ps = dd["size"]
            if dd["mode"] == "FULL":
                c16 = sha_padded(p16, ps) if s16 else ""
                c17 = sha_padded(p17, ps) if s17 else ""
            else:
                c16 = sha_padded(p16, ps, 67108864) if s16 else ""
                c17 = sha_padded(p17, ps, 67108864) if s17 else ""
            m16 = "YES" if c16 == dd["sha"] else ("file>part" if (s16 and s16 > ps) else "no")
            m17 = "YES" if c17 == dd["sha"] else ("file>part" if (s17 and s17 > ps) else "no")
        rows.append(dict(part=part, f16=f16, f17=f17, s16=s16, s17=s17, sh16=sh16, sh17=sh17,
                         h4k16=h4k16, h4k17=h4k17, dev=dd, m16=m16, m17=m17))
        P("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s" % (
            part, f16 or "-", s16 if s16 else "-", f17 or "-", s17 if s17 else "-",
            ("" if (s16 is None or s17 is None) else "%+d" % (s17 - s16)),
            ("SAME" if (sh16 and sh16 == sh17) else ("-" if not (sh16 and sh17) else "DIFF")),
            dd["mode"] if dd else "-", dd["size"] if dd else "-", m16, m17,
            ("SAME" if (h4k16 and h4k16 == h4k17) else ("-" if not (h4k16 and h4k17) else "DIFF"))))

    P("")
    P("=== 机上未出现在映射里的分区（信息）===")
    mapped = {r["part"] for r in rows}
    for k, v in dev.items():
        base = k[:-2] if k.endswith(("_a", "_b")) else k
        if k in mapped or any(m == k for m in mapped): continue

    json.dump(rows, open(os.path.join(OUT, "a2_compare.json"), "w"), indent=1, default=str)
    open(os.path.join(OUT, "a2_compare.tsv"), "w", encoding="utf-8").write("\n".join(L) + "\n")

main()
