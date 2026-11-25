#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""解出 recovery / vendor_boot 的 LZ4 ramdisk 到 .cpio，供 cpio 比对。"""
import os, struct, sys
import lz4.block

Z16 = "/mnt/e/rom/TB331FC/刷机包/TB331FC_ZUI_16.0.544/image"
Z17 = "/mnt/e/rom/work/zui17_images"
W = "/mnt/e/rom/work/img-zui-diff/work"
os.makedirs(W, exist_ok=True)

LZ4_MAGIC = 0x184C2102
BLK = 8 << 20

def read_hdr(p):
    b = open(p, "rb").read(4096)
    magic = b[:8]
    kv = struct.unpack_from("<I", b, 40)[0] if magic == b"ANDROID!" else struct.unpack_from("<I", b, 8)[0]
    if magic == b"VNDRBOOT":
        ps = struct.unpack_from("<I", b, 12)[0]
        ram = struct.unpack_from("<I", b, 24)[0]
        hs = struct.unpack_from("<I", b, 2096)[0]
    else:
        ps = struct.unpack_from("<I", b, 108)[0] or 4096
        ram = struct.unpack_from("<I", b, 12)[0]
        hs = struct.unpack_from("<I", b, 20)[0]
    off = ((hs + ps - 1)//ps)*ps
    return dict(magic=magic, page=ps, ramdisk_size=ram, hdr_size=hs, ramdisk_off=off)

def unlz4_legacy(data):
    """lz4 legacy 帧：magic 只出现一次，之后是 [size:4][data] 重复，末尾 size=0。"""
    out = bytearray()
    n = len(data)
    if n < 8:
        return b""
    pos = 4
    while pos + 4 <= n:
        size = struct.unpack_from("<I", data, pos)[0]
        pos += 4
        if size == 0:
            break
        chunk = data[pos:pos+size]
        try:
            out += lz4.block.decompress(chunk, uncompressed_size=BLK)
        except Exception as e:
            print("   [err] block at %d size %d: %s" % (pos, size, e))
            break
        pos += size
    return bytes(out)

def do(tag, base, name, outname):
    p = os.path.join(base, name)
    h = read_hdr(p)
    with open(p, "rb") as f:
        f.seek(h["ramdisk_off"])
        raw = f.read(h["ramdisk_size"])
    print("%s %-16s page=%d hdr=%d ramdisk_off=%d ramdisk_size=%d magic=%s" % (
        tag, name, h["page"], h["hdr_size"], h["ramdisk_off"], h["ramdisk_size"], raw[:4].hex()))
    if raw[:4] == struct.pack("<I", LZ4_MAGIC):
        dec = unlz4_legacy(raw)
        print("   decompressed %d bytes" % len(dec))
        open(os.path.join(W, outname), "wb").write(dec)
    elif raw[:2] == b"\x1f\x8b":
        import gzip
        dec = gzip.decompress(raw)
        print("   gzip decompressed %d bytes" % len(dec))
        open(os.path.join(W, outname), "wb").write(dec)
    else:
        print("   unknown compression, raw saved")
        open(os.path.join(W, outname), "wb").write(raw)

do("Z16", Z16, "recovery.img", "rec16.cpio")
do("Z17", Z17, "recovery.img", "rec17.cpio")
do("Z16", Z16, "vendor_boot.img", "vb16.cpio")
do("Z17", Z17, "vendor_boot.img", "vb17.cpio")
do("Z16", Z16, "init_boot.img", "ib16.cpio")
do("Z17", Z17, "init_boot.img", "ib17.cpio")
