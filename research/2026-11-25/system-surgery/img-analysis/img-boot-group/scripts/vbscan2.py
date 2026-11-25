#!/usr/bin/env python3
"""Scan a fixed short list of vendor_boot images for panel-selection strings."""
import struct, os
FILES = [
    '/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin',
    '/mnt/e/rom/work/zui16_flash/image/vendor_boot.img',
    '/mnt/e/rom/work/zui17_images/vendor_boot.img',
    '/mnt/e/rom/work/boot-backup-20261008/bk/vendor_boot_a.img',
    '/mnt/e/rom/work/boot-backup-20261024/vendor_boot_a.img',
]
for p in FILES:
    if not os.path.exists(p):
        print(p, 'MISSING'); continue
    d = open(p, 'rb').read()
    if d[:8] != b'VNDRBOOT':
        print('%-64s not VNDRBOOT (%r)' % (os.path.basename(p), d[:8])); continue
    hv, ps, ka, ra, vrs = struct.unpack_from('<5I', d, 8)
    cm = d[28:28 + 2048].split(b'\x00')[0]
    hs = struct.unpack_from('<I', d, 2096)[0]
    dtbs = struct.unpack_from('<I', d, 2100)[0]
    tsz, tnum, tesz, bcs = struct.unpack_from('<4I', d, 2112) if hv >= 4 else (0, 0, 0, 0)
    def al(x): return (x + ps - 1) // ps * ps
    o = al(hs); vrd = o; o += al(vrs); dtb = o; o += al(dtbs); tab = o; o += al(tsz); bc = o
    bct = d[bc:bc + bcs] if bcs else b''
    print('%-40s size=%-9d v%d rd=%-9d dtb=%-8d tab=%-4d bc=%-5d cmdline=%r'
          % (os.path.basename(p), len(d), hv, vrs, dtbs, tsz, bcs, cm[:90]))
    if b'dsi_display0' in cm or b'dsi_display0' in bct:
        print('    *** dsi_display0 found:', (cm + bct).decode('utf-8', 'replace')[:400])
    if bcs:
        print('    bootconfig[0:%d]=%r' % (bcs, bct[:200]))
