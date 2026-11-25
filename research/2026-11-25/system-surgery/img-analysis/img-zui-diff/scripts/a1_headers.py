#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Parse Android boot/vendor_boot/recovery headers + locate embedded sections
for ZUI16 (EDL flat package) vs ZUI17 image set."""
import os, struct, sys, json

Z16 = "/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
Z17 = "/mnt/e/rom/work/zui17_images"
OUT = "/mnt/e/rom/work/img-zui-diff/a1_headers.txt"

def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]

def rd(p, n):
    with open(p, "rb") as f:
        return f.read(n)

def fsz(p):
    return os.path.getsize(p)

def parse_boot(p):
    """boot/init_boot/recovery: Android boot image v3/v4"""
    b = rd(p, 4096)
    if b[:8] != b"ANDROID!":
        return {"file": p, "kind": "not-ANDROID!", "magic": b[:8].hex()}
    kv = u32(b, 40)
    hs = u32(b, 20)
    d = {
        "file": p, "kind": "boot-v%d" % kv, "header_version": kv, "header_size": hs,
        "kernel_size": u32(b, 8), "ramdisk_size": u32(b, 12), "os_version": u32(b, 16),
        "page_size": u32(b, 108) if kv >= 4 else u32(b, 36),
    }
    if kv >= 4:
        d["kernel_addr"] = u32(b, 112)
        d["ramdisk_addr"] = u32(b, 116)
        # v4 boot: cmdline 1536B @124, then tags_addr 2080, name 2088, chksum 2112, extra 2176..
        cmd = b[124:124+1536]
    else:
        cmd = b[64:64+512]
    d["cmdline"] = cmd.split(b"\0")[0].decode("utf-8", "replace")
    # section layout
    if kv >= 3:
        off = hs
    else:
        ps = d["page_size"]
        off = ((hs + ps - 1)//ps)*ps
    d["kernel_off"] = off
    d["ramdisk_off"] = off + d["kernel_size"]
    return d

def parse_vendor_boot(p):
    b = rd(p, 4096)
    if b[:8] != b"VNDRBOOT":
        return {"file": p, "kind": "not-VNDRBOOT", "magic": b[:8].hex()}
    d = {"file": p, "kind": "vendor_boot"}
    d["header_version"] = u32(b, 8)
    # v3/v4 share the first fields
    d["page_size"] = u32(b, 12)
    d["kernel_addr"] = u32(b, 16)
    d["ramdisk_addr"] = u32(b, 20)
    d["vendor_ramdisk_size"] = u32(b, 24)
    d["cmdline"] = b[28:28+2048].split(b"\0")[0].decode("utf-8", "replace")
    d["tags_addr"] = u32(b, 2076)
    d["name"] = b[2080:2096].split(b"\0")[0].decode("utf-8", "replace")
    d["header_checksum"] = b[2096:2128].hex()
    d["header_size"] = u32(b, 3152)
    d["dtb_size"] = u32(b, 3156)
    d["dtb_addr"] = struct.unpack_from("<Q", b, 3160)[0]
    return d

def find_sub(hay_path, needle_path):
    """find byte offset of needle file inside hay file (needle small enough)"""
    n = rd(needle_path, 64)
    if not n:
        return None
    hs = fsz(hay_path); ns = fsz(needle_path)
    with open(hay_path, "rb") as h, open(needle_path, "rb") as nd:
        pat = nd.read()
        CH = 8 << 20
        buf = b""
        pos = 0
        first = h.read(CH)
        off = first.find(pat)
        return off if off >= 0 else None

def main():
    L = []
    def P(*a):
        s = " ".join(str(x) for x in a)
        L.append(s)
        print(s)

    P("=== A. boot / init_boot / recovery 头 ===")
    rows = []
    for ver, base in (("ZUI16", Z16), ("ZUI17", Z17)):
        for name in ("boot.img", "init_boot.img", "recovery.img"):
            p = os.path.join(base, name)
            if not os.path.exists(p):
                P("  %-6s %-14s MISSING" % (ver, name)); continue
            d = parse_boot(p)
            d["ver"] = ver; d["name"] = name; d["size"] = fsz(p)
            rows.append(d)
            P("  %-6s %-14s size=%-10d %-10s hdr_ver=%s hdr_size=%-5s page=%-6s kernel=%-9d ramdisk=%-9d" % (
                ver, name, d["size"], d["kind"], d.get("header_version"), d.get("header_size"),
                d.get("page_size"), d.get("kernel_size", -1), d.get("ramdisk_size", -1)))
            P("         cmdline=%r" % d.get("cmdline", ""))
            P("         ramdisk_off=0x%x kernel_off=0x%x" % (d.get("ramdisk_off", 0), d.get("kernel_off", 0)))

    P("")
    P("=== B. vendor_boot 头 ===")
    vrows = []
    for ver, base in (("ZUI16", Z16), ("ZUI17", Z17)):
        p = os.path.join(base, "vendor_boot.img")
        if not os.path.exists(p):
            P("  %-6s MISSING" % ver); continue
        d = parse_vendor_boot(p)
        d["ver"] = ver; d["size"] = fsz(p)
        vrows.append(d)
        P("  %-6s size=%-10d hdr_ver=%s page=%-6s dict=%r" % (ver, d["size"], d["header_version"], d["page_size"], d["name"]))
        P("         header_size=%-5d vendor_ramdisk_size=%-9d dtb_size=%-9d dtb_addr=0x%x tags_addr=0x%x" % (
            d["header_size"], d["vendor_ramdisk_size"], d["dtb_size"], d["dtb_addr"], d["tags_addr"]))
        P("         cmdline=%r" % d["cmdline"])

    P("")
    P("=== C. vendor_boot 内嵌段定位（用已解包的 vb_ramdisk.cpio / vb_dtb.dtb 反查 ZUI17）===")
    vb17 = os.path.join(Z17, "vendor_boot.img")
    for comp in ("vb_dtb.dtb", "vb_ramdisk.cpio"):
        c = os.path.join(Z17, comp)
        if os.path.exists(c) and os.path.exists(vb17):
            off = find_sub(vb17, c)
            P("  %-16s local_size=%-9d offset_in_ZUI17_vendor_boot=%s" % (
                comp, fsz(c), ("0x%x" % off) if off is not None else "NOT-FOUND"))

    P("")
    P("=== D. 组件级差异（ZUI16 vs ZUI17）===")
    for a, b in (("boot.img", "boot.img"), ("init_boot.img", "init_boot.img"),
                 ("recovery.img", "recovery.img"), ("vendor_boot.img", "vendor_boot.img"),
                 ("dtbo.img", "dtbo.img"), ("vbmeta.img", "vbmeta.img")):
        pa, pb = os.path.join(Z16, a), os.path.join(Z17, b)
        if os.path.exists(pa) and os.path.exists(pb):
            P("  %-14s ZUI16=%-10d ZUI17=%-10d delta=%+d" % (a, fsz(pa), fsz(pb), fsz(pb)-fsz(pa)))

    P("")
    P("=== E. recovery ramdisk 大小交叉验证 ===")
    for ver, base in (("ZUI16", Z16), ("ZUI17", Z17)):
        p = os.path.join(base, "recovery.img")
        d = parse_boot(p)
        P("  %-6s recovery ramdisk_size = %d (0x%x)  kernel_size = %d" % (
            ver, d["ramdisk_size"], d["ramdisk_size"], d["kernel_size"]))
        # also sha256 of the ramdisk region
        import hashlib
        h = hashlib.sha256()
        with open(p, "rb") as f:
            f.seek(d["ramdisk_off"])
            left = d["ramdisk_size"]
            while left > 0:
                chunk = f.read(min(left, 8 << 20))
                if not chunk: break
                h.update(chunk); left -= len(chunk)
        P("         ramdisk sha256 = %s" % h.hexdigest())

    open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")
    json.dump({"boot": rows, "vboot": vrows}, open("/mnt/e/rom/work/img-zui-diff/a1_headers.json", "w"), indent=1)

main()
