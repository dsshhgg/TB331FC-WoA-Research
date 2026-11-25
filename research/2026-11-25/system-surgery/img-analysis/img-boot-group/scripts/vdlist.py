#!/usr/bin/env python3
import sys, importlib.util
spec = importlib.util.spec_from_file_location('rd', '/mnt/e/rom/work/img-boot-group/tools/ramdisk.py')
# avoid running module main: re-implement quickly
import gzip, struct
import lz4.block

def decomp(b):
    if b[:4] == b'\x02\x21\x4c\x18':
        out = b''; pos = 4
        while pos + 4 <= len(b):
            n = struct.unpack_from('<I', b, pos)[0]; pos += 4
            if n == 0: break
            blk = b[pos:pos + n]; pos += n
            out += lz4.block.decompress(blk, uncompressed_size=1 << 25)
        return out
    return b

def cpio_list(d):
    out = []; pos = 0
    while d[pos:pos + 6] == b'070701':
        f = [int(d[pos + 6 + i * 8:pos + 14 + i * 8], 16) for i in range(13)]
        ns, fs = f[11], f[6]
        name = d[pos + 110:pos + 110 + ns - 1].decode('utf-8', 'replace')
        pos = (pos + 110 + ns + 3) & ~3
        data = d[pos:pos + fs]; pos = (pos + fs + 3) & ~3
        if name == 'TRAILER!!!': break
        out.append((name, fs, data))
    return out

v = open('/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin', 'rb').read()
ents = cpio_list(decomp(v[4096:4096 + 11628676]))
print('entries', len(ents))
kw = ('novatek', 'touch', 'panel', 'hx', 'firmware', 'nt36', 'focaltech', 'synaptics', 'drm', 'dtb', 'fstab', 'init.rc')
for n, s, _ in ents:
    if any(k in n.lower() for k in kw):
        print('  %-62s %d' % (n, s))
print('--- non-module entries ---')
for n, s, _ in ents:
    if 'lib/modules' not in n:
        print('  %-62s %d' % (n, s))
