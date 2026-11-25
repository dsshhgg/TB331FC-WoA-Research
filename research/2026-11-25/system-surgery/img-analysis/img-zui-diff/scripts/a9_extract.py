#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 ramdisk cpio 里抽出指定文件到磁盘，便于文本 diff。"""
import os, sys, hashlib

W = "/mnt/e/rom/work/img-zui-diff/work"
O = "/mnt/e/rom/work/img-zui-diff/work/x"
os.makedirs(O, exist_ok=True)

def extract(path, want):
    data = open(path, "rb").read()
    pos = 0
    n = len(data)
    out = {}
    while pos + 110 <= n:
        if data[pos:pos+6] not in (b"070701", b"070702"):
            nxt = data.find(b"070701", pos)
            if nxt < 0: break
            pos = nxt; continue
        hdr = data[pos:pos+110]
        try:
            fsize = int(hdr[54:62], 16); namesize = int(hdr[94:102], 16)
        except ValueError:
            break
        name = data[pos+110:pos+110+namesize-1].decode("utf-8", "replace")
        pad_name = (4 - ((110 + namesize) % 4)) % 4
        dstart = pos + 110 + namesize + pad_name
        if name in want:
            out[name] = data[dstart:dstart+fsize]
        pos = dstart + fsize
        pos += (4 - (fsize % 4)) % 4
    return out

jobs = [
    ("rec16.cpio", ["prop.default", "vendor_file_contexts", "vendor_service_contexts"], "r16"),
    ("rec17.cpio", ["prop.default", "vendor_file_contexts", "vendor_service_contexts"], "r17"),
    ("ib16.cpio", ["system/etc/ramdisk/build.prop"], "i16"),
    ("ib17.cpio", ["system/etc/ramdisk/build.prop"], "i17"),
    ("vb16.cpio", ["lib/modules/modules.load", "lib/modules/modules.load.recovery"], "v16"),
    ("vb17.cpio", ["lib/modules/modules.load", "lib/modules/modules.load.recovery"], "v17"),
]
for cpf, want, tag in jobs:
    got = extract(os.path.join(W, cpf), set(want))
    for name, blob in got.items():
        fn = os.path.join(O, tag + "__" + name.replace("/", "_"))
        open(fn, "wb").write(blob)
        print("wrote", fn, len(blob))
