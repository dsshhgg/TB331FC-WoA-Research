#!/usr/bin/env python3
"""Parse Android boot-family images (boot v3/v4, vendor_boot v3/v4),
detect AVB footer, and verify vbmeta hash descriptors byte-exactly.
Read-only."""
import sys, os, struct, hashlib, json

def u32(b, o): return struct.unpack_from('<I', b, o)[0]
def u64(b, o): return struct.unpack_from('<Q', b, o)[0]

def cstr(bs):
    z = bs.find(b'\x00')
    return bs[:z].decode('utf-8', 'replace') if z >= 0 else bs.decode('utf-8', 'replace')

def parse_boot(path, data):
    out = {'file': path, 'size': len(data)}
    magic = data[:8]
    out['magic'] = magic.decode('latin1')
    out['magic_hex'] = magic.hex()
    out['kernel_size'] = u32(data, 8)
    out['ramdisk_size'] = u32(data, 12)
    out['os_version_raw'] = u32(data, 16)
    ov = out['os_version_raw']
    out['os_version'] = '%d.%d.%d' % ((ov >> 25) & 0x7f, (ov >> 18) & 0x7f, ov & 0x7ffff)
    out['header_size'] = u32(data, 20)
    out['reserved'] = [u32(data, 24 + 4 * i) for i in range(4)]
    out['header_version'] = u32(data, 40)
    out['cmdline'] = cstr(data[44:44 + 1536])
    if out['header_version'] >= 3:
        out['signature_size'] = u32(data, 1580)  # v4 only meaningful
    hp = out['header_size']
    # page size: v3/v4 = 4096, v2 = u32@36
    out['page_size'] = 4096 if out['header_version'] >= 3 else u32(data, 36)
    ps = out['page_size']
    def align(x): return (x + ps - 1) // ps * ps
    off = align(hp)
    out['kernel_offset'] = off
    off += align(out['kernel_size'])
    out['ramdisk_offset'] = off
    off += align(out['ramdisk_size'])
    out['second_offset'] = off if out['header_version'] < 3 else None
    if out['header_version'] < 3:
        off += align(u32(data, 24 + 4 * 1))  # second_size
    out['signature_offset'] = off if out['header_version'] >= 4 and out['signature_size'] else None
    out['payload_end'] = off + out['signature_size'] if out['signature_offset'] else off
    return out

def parse_vendor_boot(path, data):
    out = {'file': path, 'size': len(data)}
    out['magic'] = data[:8].decode('latin1')
    out['header_version'] = u32(data, 8)
    out['page_size'] = u32(data, 12)
    out['kernel_addr'] = u32(data, 16)
    out['ramdisk_addr'] = u32(data, 20)
    out['vendor_ramdisk_size'] = u32(data, 24)
    out['cmdline'] = cstr(data[28:28 + 2048])
    out['tags_addr'] = u32(data, 2076)
    out['name'] = cstr(data[2080:2096])
    out['header_size'] = u32(data, 2096)
    out['dtb_size'] = u32(data, 2100)
    out['dtb_addr'] = u64(data, 2104)
    ps = out['page_size']
    def align(x): return (x + ps - 1) // ps * ps
    if out['header_version'] >= 4:
        out['vendor_ramdisk_table_size'] = u32(data, 2112)
        out['vendor_ramdisk_table_entry_num'] = u32(data, 2116)
        out['vendor_ramdisk_table_entry_size'] = u32(data, 2120)
        out['bootconfig_size'] = u32(data, 2124)
    hs = out['header_size']
    o = align(hs)
    out['vendor_ramdisk_offset'] = o
    o += align(out['vendor_ramdisk_size'])
    out['dtb_offset'] = o
    o += align(out['dtb_size'])
    out['table_offset'] = o
    o += align(out.get('vendor_ramdisk_table_size', 0))
    out['bootconfig_offset'] = o
    o += align(out.get('bootconfig_size', 0))
    out['payload_end'] = o
    # ramdisk table entries
    entries = []
    tsz = out.get('vendor_ramdisk_table_entry_size', 108) or 108
    tob = out['table_offset']
    for i in range(out.get('vendor_ramdisk_table_entry_num', 0)):
        e = tob + i * tsz
        if e + tsz > len(data): break
        ramdisk_size = u32(data, e)
        ramdisk_offset = u32(data, e + 4)
        ramdisk_type = u32(data, e + 8)
        name = cstr(data[e + 12:e + 44])
        board_id = [u32(data, e + 44 + 4 * k) for k in range((tsz - 44) // 4)]
        entries.append({'i': i, 'ramdisk_size': ramdisk_size, 'ramdisk_offset': ramdisk_offset,
                        'ramdisk_type': ramdisk_type, 'ramdisk_name': name,
                        'board_id': board_id,
                        'abs_offset': out['vendor_ramdisk_offset'] + ramdisk_offset})
    out['ramdisk_table'] = entries
    if out.get('bootconfig_size'):
        bc = data[out['bootconfig_offset']:out['bootconfig_offset'] + out['bootconfig_size']]
        out['bootconfig'] = bc.decode('utf-8', 'replace')
    return out

FOOTER_MAGIC = b'AVBf'
def avb_footer(data):
    if len(data) < 64: return None
    tail = data[-64:]
    if tail[:4] != FOOTER_MAGIC: return None
    version_major, version_minor = struct.unpack_from('>II', tail, 4)
    orig_size, vbmeta_off, vbmeta_size = struct.unpack_from('>QQQ', tail, 12)
    return {'footer_version': '%d.%d' % (version_major, version_minor),
            'original_image_size': orig_size,
            'vbmeta_offset': vbmeta_off, 'vbmeta_size': vbmeta_size,
            'partition_size': len(data)}

def main():
    res = {}
    for path in sys.argv[1:]:
        with open(path, 'rb') as f: data = f.read()
        magic = data[:8]
        if magic in (b'ANDROID!',):
            r = parse_boot(path, data)
        elif magic == b'VNDRBOOT':
            r = parse_vendor_boot(path, data)
        else:
            r = {'file': path, 'size': len(data), 'magic': magic.decode('latin1'), 'raw': True}
        r['footer'] = avb_footer(data)
        res[path] = r
        print(json.dumps(r, indent=2, ensure_ascii=False))
        print('=' * 70)

if __name__ == '__main__':
    main()
