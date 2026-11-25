#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 avbtool info_image 输出里精确配对 (partition, image_size) 并列出摘要。"""
import re, os

O = "/mnt/e/rom/work/img-zui-diff/work/x"

def parse(fn):
    txt = open(os.path.join(O, fn), encoding="utf-8", errors="replace").read().splitlines()
    pairs = []
    cur_size = None
    for line in txt:
        m = re.search(r"Image Size:\s+(\d+)", line)
        if m:
            cur_size = int(m.group(1)); continue
        m = re.search(r"Partition Name:\s+(\S+)", line)
        if m:
            pairs.append((m.group(1), cur_size))
            cur_size = None
    return pairs

for tag in ("vb16", "vb17"):
    print("=== %s ===" % tag)
    for p, s in parse(tag + ".info"):
        print("  %-16s %s" % (p, s))
