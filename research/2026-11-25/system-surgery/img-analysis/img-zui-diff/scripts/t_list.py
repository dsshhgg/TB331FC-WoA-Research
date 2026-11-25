#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
from collections import defaultdict

D = "/mnt/e/rom/work/img-zui-diff"
rs = json.load(open(D + "/a3_slots.json"))
g = defaultdict(list)
for r in rs:
    g[r["verdict"]].append(r["part"])
for k, v in sorted(g.items(), key=lambda x: -len(x[1])):
    print("%s : %d" % (k, len(v)))
    print("    " + ", ".join(sorted(v)))
print()
print("total slots:", len(rs))
print()
print("=== ZUI16 关键镜像整文件 sha256 ===")
want = ("init_boot.img", "vendor_boot.img", "recovery.img", "boot.img", "dtbo.img",
        "vbmeta.img", "vbmeta_system.img")
for line in open(D + "/zui16.sha256", encoding="utf-8"):
    p = line.rstrip("\n").split("  ", 1)
    if len(p) == 2 and p[1].lstrip("./") in want:
        print("  %-22s %s" % (p[1].lstrip("./"), p[0]))
