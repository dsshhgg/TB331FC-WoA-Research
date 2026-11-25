#!/usr/bin/env python3
import hashlib, struct, os

def info(p):
    d = open(p, 'rb').read()
    nz_tail = len(d) - max((i for i, b in enumerate(d) if b), default=-1) - 1
    print('%-70s size=%-10d sha256=%s trailing_zero_bytes=%d' %
          (os.path.basename(p), len(d), hashlib.sha256(d).hexdigest(), nz_tail))
    print('    last64=%s' % d[-64:-48].hex())
    fb = d[-64:-60]
    print('    footer_magic=%r' % fb)
    return d

d1 = info('/mnt/e/rom/work/of/v3/stock/dtbo_a.bin')
print('    dtbo total_size=3500977; nonzero last offset check:',
      max(i for i, b in enumerate(d1) if b))

d2 = info('/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin')
d3 = info('/mnt/e/rom/work/a17dump/boot_a.img')
d4 = info('/mnt/e/rom/work/a17dump/vbmeta_a.img')
print('    vbmeta_a nonzero last offset:', max(i for i, b in enumerate(d4) if b))
d5 = info('/mnt/e/rom/work/a17dump/vbmeta_system_a.img')
print('    vbmeta_system nonzero last offset:', max(i for i, b in enumerate(d5) if b))
d6 = info('/mnt/e/rom/work/zui16_flash/image/init_boot.img')
print('    init_boot nonzero last offset:', max(i for i, b in enumerate(d6) if b))
