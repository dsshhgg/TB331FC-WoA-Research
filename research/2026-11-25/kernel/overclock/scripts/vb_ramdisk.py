import struct, gzip, io, re

p = r'E:\rom\work\of\v3\stock\vendor_boot_a.bin'
d = open(p, 'rb').read()
print('magic', d[:8])
kernel_size, ramdisk_size, os_ver, header_size = struct.unpack_from('<IIII', d, 8)
header_version = struct.unpack_from('<I', d, 40)[0]
page = struct.unpack_from('<I', d, 36)[0] or 4096
print('header_version', header_version, 'page', page,
      'kernel_size', kernel_size, 'ramdisk_size', ramdisk_size, 'header_size', header_size)

# vendor_boot v4 header layout: after common header there is
# header_size, dtb_size, dtb_addr (v4)
if header_version >= 3:
    vrb = struct.unpack_from('<I', d, 1580)[0]  # vendor_ramdisk_size at end of v3/v4 header
    dtb_size = struct.unpack_from('<I', d, 1584)[0]
    dtb_addr = struct.unpack_from('<Q', d, 1588)[0]
    print('vendor_ramdisk_size(v4 hdr)', vrb, 'dtb_size', dtb_size, 'dtb_addr', hex(dtb_addr))

off = 4096
kernel = d[off:off + kernel_size]
off = 4096 + ((kernel_size + page - 1)//page)*page
vr = d[off:off + ramdisk_size]
print('ramdisk bytes at', hex(off), 'len', len(vr), 'starts', vr[:4].hex())
try:
    raw = gzip.decompress(vr)
    print('decompressed', len(raw))
    names = re.findall(rb'[\w\./\-]{4,120}\.ko\x00', raw)
    print('modules found:', len(names))
    for n in sorted(set(names))[:80]:
        print('  ', n[:-1].decode())
except Exception as e:
    print('gzip failed', e)
    # maybe cpio plain
    names = re.findall(rb'[\w\./\-]{4,120}\.ko\x00', vr)
    print('plain ko names', len(names), sorted(set(names))[:40])
