import struct, sys, zlib
BASE = r'E:\rom\TB331FC\刷机包\TB331FC_ZUI_16.0.544\image'
def hdr(name):
    p = BASE + '\\' + name
    d = open(p,'rb').read(0x2000)
    magic = d[:8]
    ks, rs, osv, hsz = struct.unpack_from('<IIII', d, 8)
    hv = struct.unpack_from('<I', d, 0x28)[0]
    print('%-22s magic=%r kernel_size=%d(0x%x) ramdisk_size=%d(0x%x) osv=%x hdr_size=%d(0x%x) ver=%d'
          % (name, magic, ks, ks, rs, rs, osv, hsz, hsz, hv))
    return d, ks, rs, hsz, hv

for n in ['boot.img','init_boot.img','recovery.img','vendor_boot.img']:
    hdr(n)

# gunzip kernel from boot.img
d = open(BASE + r'\boot.img','rb').read(0x1000 + 0x4000000)
ks = struct.unpack_from('<I', d, 8)[0]
for off in (0x1000, 0x1000+4096):
    if d[off:off+3] == b'\x1f\x8b\x08':
        print('gzip at', hex(off))
        o = zlib.decompressobj(31)
        out = o.decompress(d[off:off+ks])
        print('compressed kernel_size=%d  decompressed=%d (0x%x) = %.2f MB' % (ks, len(out), len(out), len(out)/1048576))
        break
