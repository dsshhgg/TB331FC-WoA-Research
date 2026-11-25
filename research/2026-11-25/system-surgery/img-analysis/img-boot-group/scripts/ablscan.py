#!/usr/bin/env python3
"""Scan ABL / XBL images for strings that reveal how the boot chain reads images."""
import glob, os, re

FILES = sorted(set(glob.glob('/mnt/e/rom/work/zui16_flash/image/abl*.img') +
                   glob.glob('/mnt/e/rom/work/zui16_flash/image/xbl*.img') +
                   glob.glob('/mnt/e/rom/work/ZUI15-extract/**/abl*.img', recursive=True) +
                   glob.glob('/mnt/e/rom/TB331FC/**/abl*.img', recursive=True) +
                   glob.glob('/mnt/e/rom/work/zui17_images/abl*.img')))

PATTERNS = [b'msm_drm.dsi_display0', b'dsi_display0', b'bootconfig', b'dtbo', b'DTBO',
            b'Selecting panel', b'panel selection', b'vbmeta', b'init_boot', b'vendor_boot',
            b'LoadKernel', b'LoadRamdisk', b'dtb_idx', b'khaje']
for p in FILES:
    d = open(p, 'rb').read()
    print('### %s  (%d bytes)' % (p, len(d)))
    for pat in PATTERNS:
        n = d.count(pat)
        if n:
            print('    %-24s x%d' % (pat.decode('latin1'), n))
    # print context around first dsi_display0 hit
    i = d.find(b'dsi_display0')
    if i >= 0:
        print('    ctx: %r' % d[max(0, i - 60):i + 80])
