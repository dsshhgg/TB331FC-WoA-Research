#!/usr/bin/env python3
import hashlib, os

def nz_extent(p):
    d = open(p, 'rb').read()
    last = max(i for i, b in enumerate(d) if b)
    # sample density per 8MB
    out = []
    for base in range(0, len(d), 8 * 1024 * 1024):
        chunk = d[base:base + 8 * 1024 * 1024]
        out.append('%dM:%d%%' % (base >> 20, int(100 * sum(1 for b in chunk if b) / max(1, len(chunk)))))
    return last, out

for p in ('/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin',
          '/mnt/e/rom/work/a17dump/boot_a.img'):
    last, dens = nz_extent(p)
    print('%-40s last_nonzero=%d (0x%x)  %s' % (os.path.basename(p), last, last, ' '.join(dens)))

dev = open('/mnt/e/rom/work/of/v3/stock/dtbo_a.bin', 'rb').read()
pkg = open('/mnt/e/rom/work/zui16_flash/image/dtbo.img', 'rb').read()
print('\ndev dtbo[0:3500977] sha256', hashlib.sha256(dev[:3500977]).hexdigest())
print('pkg dtbo[0:3500977] sha256', hashlib.sha256(pkg[:3500977]).hexdigest())
print('pkg dtbo size', len(pkg), 'equal first 3500977 bytes:', dev[:3500977] == pkg[:3500977])
print('dev[8388544:8388580]', dev[8388544:8388580].hex())
print('pkg[-64:]', pkg[-64:].hex())
print('pkg dtbo header total_size', int.from_bytes(pkg[4:8], 'big'), 'entries', int.from_bytes(pkg[16:20], 'big'))
