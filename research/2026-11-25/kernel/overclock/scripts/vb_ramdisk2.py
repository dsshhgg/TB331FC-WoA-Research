import struct, gzip, re

p = r'E:\rom\work\of\v3\stock\vendor_boot_a.bin'
d = open(p, 'rb').read()
magic = d[:8]
hv, page = struct.unpack_from('<II', d, 8)
kernel_addr, = struct.unpack_from('<Q', d, 16)
ramdisk_addr, = struct.unpack_from('<Q', d, 24)
vrsize, = struct.unpack_from('<I', d, 32)
cmdline = d[36:36+1536]
name = d[1096:1096+64]
hsize, = struct.unpack_from('<I', d, 1132)
dtb_size, = struct.unpack_from('<I', d, 1136)
dtb_addr, = struct.unpack_from('<Q', d, 1140)
print('magic', magic, 'hv', hv, 'page', page)
print('vrsize', vrsize, 'hsize', hsize, 'dtb_size', dtb_size, 'dtb_addr', hex(dtb_addr))
print('name', name.split(b'\0')[0])
print('cmdline', cmdline.split(b'\0')[0][:200])
off = (hsize + page - 1)//page*page
vr = d[off:off+vrsize]
print('ramdisk at', hex(off), 'len', len(vr), 'magic', vr[:4].hex())
raw = None
if vr[:2] == b'\x1f\x8b':
    raw = gzip.decompress(vr)
    print('gzip ok', len(raw))
else:
    for wbits in (31, -15):
        try:
            raw = __import__('zlib').decompress(vr, wbits)
            print('zlib ok wbits', wbits, len(raw))
            break
        except Exception as e:
            print('zlib fail', wbits, e)
if raw:
    names = sorted(set(re.findall(rb'[\w\./\-]{4,120}\.ko\x00', raw)))
    print('ko count', len(names))
    for n in names[:100]:
        print('  ', n[:-1].decode(errors='replace'))
# dtb section
doff = (hsize + page - 1)//page*page + ((vrsize + page - 1)//page)*page
dtb = d[doff:doff+dtb_size]
print('dtb section', hex(doff), len(dtb), dtb[:4].hex() if len(dtb) >= 4 else '')
