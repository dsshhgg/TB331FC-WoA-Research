#!/usr/bin/env python3
"""Inspect the region between parsed payload end and AVB original_image_size."""
import sys, struct

path = '/mnt/e/rom/work/a17dump/boot_a.img'
d = open(path, 'rb').read()
print('filesize', len(d))
orig = struct.unpack_from('>Q', d, len(d) - 64 + 12)[0]
print('avb original_image_size', orig)

payload_end = 43098112
print('payload_end', payload_end, 'gap', orig - payload_end)

# nonzero map in 64KiB chunks across the whole image
for base in range(0, orig, 65536):
    chunk = d[base:base + 65536]
    nz = sum(1 for b in chunk if b)
    print('0x%08x  nz=%6d  %s' % (base, nz, chunk[:16].hex()))

# look at gap start
print('--- gap head ---')
print(d[payload_end:payload_end + 256].hex())
print('--- first nonzero offset in gap ---')
for i in range(payload_end, orig, 4096):
    if any(d[i:i + 4096]):
        print('first nonzero page at', i, '0x%x' % i, d[i:i + 64].hex())
        break
