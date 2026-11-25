import struct, gzip, re, zlib

p = r'E:\rom\work\of\v3\stock\vendor_boot_a.bin'
d = open(p, 'rb').read()
hv, page = struct.unpack_from('<II', d, 8)
kernel_addr, ramdisk_addr, vrsize = struct.unpack_from('<III', d, 16)
cmdline = d[28:28+2048]
tags, = struct.unpack_from('<I', d, 2076)
name = d[2080:2096]
hsize, dtb_size = struct.unpack_from('<II', d, 2096)
dtb_addr, = struct.unpack_from('<Q', d, 2104)
print('hv', hv, 'page', page, 'hsize', hsize, 'vrsize', vrsize, 'dtb_size', dtb_size)
print('name', name.split(b'\0')[0], 'tags', hex(tags))
print('cmdline', cmdline.split(b'\0')[0][:120])
off = (hsize + page - 1)//page*page
vr = d[off:off+vrsize]
print('ramdisk at', hex(off), len(vr), vr[:2].hex())
raw = gzip.decompress(vr) if vr[:2] == b'\x1f\x8b' else None
if raw is None:
    for wbits in (31, 15, -15):
        try:
            raw = zlib.decompress(vr, wbits); print('zlib wbits', wbits, len(raw)); break
        except Exception as e:
            pass
print('raw', None if raw is None else len(raw))
if raw:
    names = sorted(set(re.findall(rb'[\w\./\-]{4,120}\.ko\x00', raw)))
    print('ko in ramdisk:', len(names))
    for n in names[:120]:
        print('  ', n[:-1].decode(errors='replace'))
doff = (hsize + page - 1)//page*page + ((vrsize + page - 1)//page)*page
dtb = d[doff:doff+dtb_size]
print('dtb section at', hex(doff), 'len', dtb_size, 'magic', dtb[:4].hex() if len(dtb)>=4 else '')
