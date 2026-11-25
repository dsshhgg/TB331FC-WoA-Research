#!/usr/bin/env python3
"""List ramdisk contents (init_boot + vendor_boot) by magic detection."""
import gzip, lzma, io, sys, struct

def decomp(b):
    if b[:2] == b'\x1f\x8b':
        return gzip.decompress(b)
    if b[:1] == b'\x5d':
        return lzma.decompress(b)
    if b[:4] == b'\x02\x21\x4c\x18':  # lz4 legacy frame
        import lz4.block
        out = b''
        pos = 4
        while pos + 4 <= len(b):
            n = struct.unpack_from('<I', b, pos)[0]
            pos += 4
            if n == 0:
                break
            blk = b[pos:pos + n]
            pos += n
            for guess in (1 << 25, 1 << 24, 1 << 23):
                try:
                    out += lz4.block.decompress(blk, uncompressed_size=guess)
                    break
                except Exception:
                    continue
        return out
    if b[:4] == b'\x04\x22\x4d\x18':
        import lz4.frame
        return lz4.frame.decompress(b)
    if b[:6] == b'\xfd7zXZ\x00':
        return lzma.decompress(b)
    return b

def cpio_list(d):
    out = []
    pos = 0
    while True:
        if d[pos:pos + 6] not in (b'070701', b'070702'):
            if d[pos:pos + 6] == b'070707':
                break
            break
        fields = [int(d[pos + 6 + i * 8:pos + 14 + i * 8], 16) for i in range(13)]
        namesize = fields[11]
        filesize = fields[6]
        name = d[pos + 110:pos + 110 + namesize - 1].decode('utf-8', 'replace')
        pos = (pos + 110 + namesize + 3) & ~3
        data = d[pos:pos + filesize]
        pos = (pos + filesize + 3) & ~3
        if name == 'TRAILER!!!':
            break
        out.append((name, filesize, data))
    return out

def show(label, blob, limit=200):
    raw = decomp(blob)
    kind = 'gzip' if blob[:2] == b'\x1f\x8b' else ('lz4' if blob[:4] == b'\x02\x21\x4c\x18' else
                                                  ('lzma' if blob[:1] == b'\x5d' else 'raw'))
    ents = cpio_list(raw)
    print('== %s: %d bytes -> %s %d bytes, %d entries' % (label, len(blob), kind, len(raw), len(ents)))
    for n, s, _ in ents[:limit]:
        print('   %-60s %d' % (n, s))
    hits = [n for n, s, _ in ents if any(k in n.lower() for k in
            ('novatek', 'touch', 'panel', 'hx', 'build.prop', 'firmware'))]
    print('   -- notable:', hits)
    return ents

# init_boot ramdisk
d = open('/mnt/e/rom/work/zui16_flash/image/init_boot.img', 'rb').read()
show('init_boot ramdisk', d[4096:4096 + 2005893])

# vendor_boot vendor_ramdisk
v = open('/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin', 'rb').read()
show('vendor_boot vendor_ramdisk', v[4096:4096 + 11628676], limit=60)
