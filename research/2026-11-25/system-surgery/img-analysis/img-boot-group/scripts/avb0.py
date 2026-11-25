#!/usr/bin/env python3
import struct
for p in ('/mnt/e/rom/work/zui16_flash/image/boot.img',
          '/mnt/e/rom/work/zui16_flash/image/init_boot.img',
          '/mnt/e/rom/work/of/v3/stock/vendor_boot_a.bin'):
    d = open(p, 'rb').read()
    offs = []
    i = d.find(b'AVB0')
    while i >= 0 and len(offs) < 12:
        auth = struct.unpack_from('>Q', d, i + 12)[0]
        aux = struct.unpack_from('>Q', d, i + 20)[0]
        alg = struct.unpack_from('>I', d, i + 28)[0]
        offs.append((i, auth, aux, alg, 256 + auth + aux))
        i = d.find(b'AVB0', i + 1)
    print('%-40s AVB0 headers: %s' % (p.split('/')[-1], offs))
