#!/usr/bin/env python3
"""Scan vendor_boot images for panel-selection strings and dump their cmdline/bootconfig."""
import struct, os, glob
def parse(p):
    d = open(p, 'rb').read()
    if d[:8] != b'VNDRBOOT':
        return None
    hv, ps, ka, ra, vrs = struct.unpack_from('<5I', d, 8)
    cm = d[28:28+2048].split(b'\x00')[0].decode('utf-8', 'replace')
    hs = struct.unpack_from('<I', d, 2096)[0]
    dtbs = struct.unpack_from('<I', d, 2100)[0]
    if hv >= 4:
        tsz, tnum, tesz, bcs = struct.unpack_from('<4I', d, 2112)
    else:
        tsz = tnum = tesz = bcs = 0
    def al(x): return (x + ps - 1)//ps*ps
    o = al(hs)
    vrd = o; o += al(vrs)
    dtb = o; o += al(dtbs)
    tab = o; o += al(tsz)
    bc = o
    bct = d[bc:bc+bcs].decode('utf-8', 'replace') if bcs else ''
    return dict(path=p, size=len(d), hdr_ver=hv, page=ps, ramdisk=vrs, dtb=dtbs,
                table=tsz, num=tnum, bootconfig_size=bcs, cmdline=cm, bootconfig=bct,
                ramdisk_region=d[vrd:vrd+vrs])

cands = []
for pat in ('/mnt/e/rom/work/zui16_flash/image/*vendor_boot*',
            '/mnt/e/rom/work/zui17_images/*vendor_boot*',
            '/mnt/e/rom/work/dtwork/vb460/*.img',
            '/mnt/e/rom/work/**/vendor_boot*.img'):
    cands += glob.glob(pat, recursive=True)
cands = sorted(set(cands))
for p in cands:
    r = parse(p)
    if not r:
        print(p, '-> not VNDRBOOT'); continue
    hit_cmd = 'dsi_display0' in r['cmdline']
    hit_bc = 'dsi_display0' in r['bootconfig']
    hit_rd = b'dsi_display0' in r['ramdisk_region']
    print('%-70s size=%-9d v%d rd=%-9d dtb=%-8d tab=%-4d bc=%-5d cmd=%d bc_hit=%d rd_hit=%d'
          % (os.path.basename(p), r['size'], r['hdr_ver'], r['ramdisk'], r['dtb'], r['table'],
             r['bootconfig_size'], hit_cmd, hit_bc, hit_rd))
    print('    cmdline=%r' % r['cmdline'][:200])
    if r['bootconfig_size']:
        print('    bootconfig(%d B)=%r' % (r['bootconfig_size'], r['bootconfig'][:300]))
