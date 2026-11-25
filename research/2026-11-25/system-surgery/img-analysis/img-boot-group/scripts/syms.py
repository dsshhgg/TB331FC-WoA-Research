#!/usr/bin/env python3
"""Count __symbols__ in the first FDT of a few vendor_boot dtb blobs."""
import struct, importlib.util, glob
spec = importlib.util.spec_from_file_location('dtbo', '/mnt/e/rom/work/img-boot-group/tools/dtbo.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

def dtb_region(path):
    d = open(path, 'rb').read()
    hv, ps = struct.unpack_from('<2I', d, 8)
    hs = struct.unpack_from('<I', d, 2096)[0]
    dtbs = struct.unpack_from('<I', d, 2100)[0]
    def al(x): return (x + ps - 1) // ps * ps
    o = al(hs) + al(struct.unpack_from('<I', d, 24)[0])
    return d[o:o + dtbs], dtbs

for p in ('/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin',
          '/mnt/e/rom/work/zui17_images/vendor_boot.img',
          '/mnt/e/rom/work/boot-backup-20261008/bk/vendor_boot_a.img',
          '/mnt/e/rom/work/boot-backup-20261024/vendor_boot_a.img'):
    try:
        blob, n = dtb_region(p)
    except Exception as e:
        print(p, 'ERR', e); continue
    pos, i, tot = 0, 0, 0
    out = []
    while pos + 4 <= len(blob) and struct.unpack_from('>I', blob, pos)[0] == 0xd00dfeed:
        t = struct.unpack_from('>I', blob, pos + 4)[0]
        fdt = m.parse_fdt(blob[pos:pos + t])
        s = 0
        for c in fdt['root']['children']:
            if c['name'] == '__symbols__':
                s = len(c['props'])
        out.append('%d:%d' % (t, s))
        tot += s
        pos += t
        i += 1
    print('%-46s dtb=%d  FDTs=%s  sum_syms=%d' % (p.split('/')[-1], n, ' '.join(out), tot))
