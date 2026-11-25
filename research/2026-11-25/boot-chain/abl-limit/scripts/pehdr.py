import struct, sys
P = r'E:\rom\work\woa\abl-hang-analysis\extract\Z17_9e21fd93_lz_f536d559_PE32_at_0xb4.bin'
d = open(P,'rb').read()
print('size', len(d), 'first16', d[:16].hex())
e_lfanew = struct.unpack_from('<I', d, 0x3c)[0]
print('e_lfanew', hex(e_lfanew), 'sig', d[e_lfanew:e_lfanew+4])
fh = e_lfanew+4
machine, nsec, _, _, _, optsz, chars = struct.unpack_from('<HHIIIHH', d, fh)
print('machine %04x nsec %d optsz %d chars %04x' % (machine, nsec, optsz, chars))
opt = fh+20
magic = struct.unpack_from('<H', d, opt)[0]
print('opt magic', hex(magic))
imgbase = struct.unpack_from('<Q', d, opt+24)[0]
print('ImageBase', hex(imgbase))
sec = opt+optsz
for i in range(nsec):
    o = sec + i*40
    name = d[o:o+8].rstrip(b'\x00').decode()
    vsz, va, rawsz, rawptr = struct.unpack_from('<IIII', d, o+8)
    print('%-8s VA=%08x vsz=%08x rawsz=%08x rawptr=%08x' % (name, va, vsz, rawsz, rawptr))
