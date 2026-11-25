#!/usr/bin/env python3
"""Split a Qualcomm-style concatenated DTB blob (vendor_boot dtb region) into FDTs."""
import struct, sys, json, importlib.util
spec = importlib.util.spec_from_file_location('dtbo', '/mnt/e/rom/work/img-boot-group/tools/dtbo.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

path = '/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin'
off, size = 11636736, 1290690
blob = open(path, 'rb').read()[off:off + size]
print('region size', len(blob))
pos = 0
i = 0
while pos + 4 <= len(blob):
    magic = struct.unpack_from('>I', blob, pos)[0]
    if magic != 0xd00dfeed:
        # search forward for next magic
        nxt = blob.find(b'\xd0\x0d\xfe\xed', pos + 1)
        print('  non-FDT at %d (0x%x), next magic at %s' % (pos, pos, nxt))
        if nxt < 0:
            break
        pos = nxt
        continue
    tot = struct.unpack_from('>I', blob, pos + 4)[0]
    fdt = m.parse_fdt(blob[pos:pos + tot])
    root = fdt['root']
    syms = 0
    for c in root['children']:
        if c['name'] == '__symbols__':
            syms = len(c['props'])
    info = m.summarize(blob[pos:pos + tot], 'fdt%d' % i)
    print('FDT %d  off=%-8d size=%-8d nodes=%-4d props=%-4d syms=%-3d model=%r compat=%s'
          % (i, pos, tot, fdt['nodes'], fdt['props'], syms, info['model'], info['compatible']))
    print('      msm-id=%s board-id=%s pmic-id=%s' % (info['msm_id'], info['board_id'], info['pmic_id']))
    pos += tot
    i += 1
print('total FDTs:', i)
