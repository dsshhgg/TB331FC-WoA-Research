import struct, zlib, sys, os
def probe(p):
    d = open(p,'rb').read(0x3000)
    ks, rs = struct.unpack_from('<II', d, 8)
    hv = struct.unpack_from('<I', d, 0x28)[0]
    hs = struct.unpack_from('<I', d, 0x14)[0]
    print('%-48s size=%d ver=%d kernel_size=%d(0x%x) ramdisk_size=%d header_size=%d'
          % (os.path.basename(p), os.path.getsize(p), hv, ks, ks, rs, hs))
    for off in (0x1000, 0x2000):
        if d[off:off+2] == b'\x1f\x8b':
            f = open(p,'rb'); f.seek(off)
            o = zlib.decompressobj(31)
            out = o.decompress(f.read(ks if ks else os.path.getsize(p)))
            isz = struct.unpack_from('<Q', out, 0x10)[0] if len(out) > 0x20 else -1
            print('    gzip: decompressed=%d (0x%x)  Image.image_size=0x%x  magic@0x38=%r'
                  % (len(out), len(out), isz, out[0x38:0x40]))
            return
        if d[off:off+2] == b'MZ':
            isz = struct.unpack_from('<Q', d, off+0x10)[0]
            print('    raw MZ Image: kernel_size=%d image_size=0x%x magic@0x38=%r'
                  % (ks, isz, d[off+0x38:off+0x40]))
            return
    print('    unknown payload magic', d[0x1000:0x1010].hex())

for p in sys.argv[1:]:
    probe(p)
