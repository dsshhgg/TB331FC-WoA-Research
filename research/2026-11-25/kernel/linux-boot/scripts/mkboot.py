#!/usr/bin/env python3
"""mkboot.py - Android boot/recovery/vendor_boot image packer for TB331FC.

Header v4 only, page size 4096 (this device's ABL requirement).

  boot      ANDROID! v4    kernel (+ optional single appended DTB) + ramdisk
  recovery  ANDROID! v4    kernel_size = 0, pure ramdisk
  vboot     VNDRBOOT v4    vendor_ramdisk | dtb | vendor_ramdisk_table | bootconfig

Section order for vendor_boot is the one ABL actually accepts and that matches
the factory image byte for byte (see TB331FC-Linux-main/dtb/mkv4.py): the
ramdisk table comes AFTER the dtb.  Swapping them makes ABL read table bytes
as the DTB and hard-fail.

  ./mkboot.py boot     --kernel Image [--ramdisk x.cpio.gz] [--dtb d.dtb] --out boot_a.img
  ./mkboot.py recovery --ramdisk x.cpio.gz --out recovery_a.img
  ./mkboot.py vboot    --vendor-ramdisk x.cpio.gz --dtb d.dtb --cmdline '...' --out vendor_boot_a.img
  ./mkboot.py dump     file.img [file2.img ...]
"""
import argparse, struct, os, sys

PAGE = 4096
BOOT_HDR_V4 = 1584
VB_HDR_V4 = 2128
RAMDISK_TABLE_ENTRY = 108


def align(n, p=PAGE):
    return (n + p - 1) // p * p


def pad(b):
    return b + b'\0' * (align(len(b)) - len(b))


def write(path, data):
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data)
    print('  %-46s %12d bytes' % (os.path.basename(path), len(data)))


# --------------------------------------------------------------------------- boot
def mk_boot(kernel=b'', ramdisk=b'', cmdline='', dtb=b'', dtb_in_kernel_size=False,
            out='boot.img'):
    """kernel_size excludes the appended DTB unless dtb_in_kernel_size is set."""
    if not kernel:
        raise SystemExit('boot mode needs --kernel')
    ksz = len(kernel) + (len(dtb) if dtb and dtb_in_kernel_size else 0)

    hdr = bytearray(BOOT_HDR_V4)
    hdr[0:8] = b'ANDROID!'
    struct.pack_into('<I', hdr, 0x008, ksz)
    struct.pack_into('<I', hdr, 0x00c, len(ramdisk))
    struct.pack_into('<I', hdr, 0x010, 0)              # os_version
    struct.pack_into('<I', hdr, 0x014, BOOT_HDR_V4)    # header_size
    struct.pack_into('<I', hdr, 0x028, 4)              # header_version
    cb = cmdline.encode()[:1535]
    hdr[0x02c:0x02c + len(cb)] = cb

    buf = pad(bytes(hdr)) + pad(kernel)
    if dtb:                                            # exactly one, 8-byte aligned
        buf = buf[:align(len(hdr)) + len(kernel)]
        while len(buf) % 8:
            buf += b'\0'
        buf += dtb
        buf = pad(buf)
    if ramdisk:
        buf += pad(ramdisk)
    write(out, buf)
    print('    kernel_size=%d ramdisk_size=%d dtb=%d header_version=4 page=4096'
          % (ksz, len(ramdisk), len(dtb)))
    return buf


# ----------------------------------------------------------------------- recovery
def mk_recovery(ramdisk, out='recovery.img'):
    hdr = bytearray(BOOT_HDR_V4)
    hdr[0:8] = b'ANDROID!'
    struct.pack_into('<I', hdr, 0x008, 0)              # kernel_size = 0  <-- key
    struct.pack_into('<I', hdr, 0x00c, len(ramdisk))
    struct.pack_into('<I', hdr, 0x014, BOOT_HDR_V4)
    struct.pack_into('<I', hdr, 0x028, 4)
    buf = pad(bytes(hdr)) + pad(ramdisk)
    write(out, buf)
    print('    kernel_size=0 ramdisk_size=%d header_version=4 (recovery-carries-ramdisk form)'
          % len(ramdisk))
    return buf


# -------------------------------------------------------------------- vendor_boot
def mk_vboot(vendor_ramdisk=b'', dtb=b'', cmdline='', bootconfig=b'',
             kernel_addr=0x00008000, ramdisk_addr=0x01000000,
             tags_addr=0x00000100, dtb_addr=0x01F00000, out='vendor_boot.img'):
    hdr = bytearray(VB_HDR_V4)
    hdr[0:8] = b'VNDRBOOT'
    struct.pack_into('<I', hdr, 0x008, 4)              # header_version
    struct.pack_into('<I', hdr, 0x00c, PAGE)           # page_size
    struct.pack_into('<I', hdr, 0x010, kernel_addr)
    struct.pack_into('<I', hdr, 0x014, ramdisk_addr)
    struct.pack_into('<I', hdr, 0x018, len(vendor_ramdisk))
    cb = cmdline.encode()[:2047]
    hdr[0x01c:0x01c + len(cb)] = cb
    struct.pack_into('<I', hdr, 0x81c, tags_addr)
    struct.pack_into('<I', hdr, 0x830, VB_HDR_V4)      # header_size
    struct.pack_into('<I', hdr, 0x834, len(dtb))       # dtb_size
    struct.pack_into('<Q', hdr, 0x838, dtb_addr)
    struct.pack_into('<I', hdr, 0x848, RAMDISK_TABLE_ENTRY)

    off_vr = align(VB_HDR_V4)
    off_dtb = off_vr + align(len(vendor_ramdisk))
    off_tbl = off_dtb + align(len(dtb))
    off_bc = off_tbl + align(RAMDISK_TABLE_ENTRY)
    total = off_bc + align(len(bootconfig))

    entry = bytearray(RAMDISK_TABLE_ENTRY)
    struct.pack_into('<I', entry, 0x00, len(vendor_ramdisk))
    struct.pack_into('<I', entry, 0x04, 0)             # offset
    struct.pack_into('<I', entry, 0x08, 1)             # type 1 = RECOVERY (as factory)

    struct.pack_into('<I', hdr, 0x840, RAMDISK_TABLE_ENTRY)
    struct.pack_into('<I', hdr, 0x844, 1)              # n entries
    struct.pack_into('<I', hdr, 0x84c, len(bootconfig))

    buf = bytearray(total)
    buf[0:VB_HDR_V4] = hdr
    buf[off_vr:off_vr + len(vendor_ramdisk)] = vendor_ramdisk
    buf[off_dtb:off_dtb + len(dtb)] = dtb
    buf[off_tbl:off_tbl + RAMDISK_TABLE_ENTRY] = bytes(entry)
    if bootconfig:
        buf[off_bc:off_bc + len(bootconfig)] = bootconfig
    write(out, bytes(buf))
    print('    vendor_ramdisk=%d dtb=%d cmdline=%d chars'
          % (len(vendor_ramdisk), len(dtb), len(cb)))
    return bytes(buf)


# --------------------------------------------------------------------------- dump
def dump_one(p):
    d = open(p, 'rb').read()
    head = d[:8]
    print('== %s  (%d bytes)' % (p, len(d)))
    if head == b'VNDRBOOT':
        hv, pg, ka, ra, vrs = struct.unpack_from('<IIIII', d, 8)
        dsz = struct.unpack_from('<I', d, 0x834)[0]
        daddr = struct.unpack_from('<Q', d, 0x838)[0]
        tsz, tn, te = struct.unpack_from('<III', d, 0x840)
        bcs = struct.unpack_from('<I', d, 0x84c)[0]
        cmd = d[0x1c:0x1c + 2048].split(b'\0')[0].decode('latin1')
        print('   VNDRBOOT v%d page=%d kernel_addr=0x%x ramdisk_addr=0x%x' % (hv, pg, ka, ra))
        print('   vendor_ramdisk=%d dtb=%d @0x%x table=%d/%d/%d bootconfig=%d'
              % (vrs, dsz, daddr, tsz, tn, te, bcs))
        print('   cmdline=%r' % cmd)
        exp = align(2128) + align(vrs) + align(dsz) + align(tsz) + align(bcs)
        print('   layout ok: %s (expected %d)' % (len(d) == exp, exp))
    elif head == b'ANDROID!':
        ks, rs, osv, hs = struct.unpack_from('<IIII', d, 8)
        hv = struct.unpack_from('<I', d, 0x28)[0]
        cmd = d[0x2c:0x2c + 1536].split(b'\0')[0].decode('latin1')
        koff = align(hs)
        roff = koff + align(ks)
        print('   ANDROID! v%d header_size=%d page=%d kernel=%d ramdisk=%d'
              % (hv, hs, PAGE, ks, rs))
        print('   cmdline=%r' % cmd)
        if ks:
            print('   kernel magic at 0x%x: %s  (4d5a.. = arm64 Image, 1f8b = gzip)'
                  % (koff, d[koff:koff + 4].hex()))
            # count FDT magics after the kernel (appended-DTB check)
            tail = d[koff + ks: koff + ks + 32]
            print('   after kernel: %s' % tail[:16].hex())
        if rs:
            print('   ramdisk starts 0x%x, magic %s (1f8b=gzip 04224d18=lz4 5d000000=xz)'
                  % (roff, d[roff:roff + 4].hex()))
        print('   total %d, page-aligned: %s' % (len(d), len(d) % PAGE == 0))
    else:
        print('   !! unknown magic %r' % head)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='mode', required=True)

    b = sub.add_parser('boot')
    b.add_argument('--kernel', required=True)
    b.add_argument('--ramdisk', default='')
    b.add_argument('--dtb', default='')
    b.add_argument('--dtb-in-kernel-size', action='store_true')
    b.add_argument('--cmdline', default='')
    b.add_argument('--out', required=True)

    r = sub.add_parser('recovery')
    r.add_argument('--ramdisk', required=True)
    r.add_argument('--out', required=True)

    v = sub.add_parser('vboot')
    v.add_argument('--vendor-ramdisk', required=True)
    v.add_argument('--dtb', required=True)
    v.add_argument('--cmdline', default='')
    v.add_argument('--bootconfig', default='')
    v.add_argument('--out', required=True)

    d = sub.add_parser('dump')
    d.add_argument('files', nargs='+')

    a = ap.parse_args()

    def rd(p):
        return open(p, 'rb').read() if p else b''

    if a.mode == 'boot':
        mk_boot(rd(a.kernel), rd(a.ramdisk), a.cmdline, rd(a.dtb),
                a.dtb_in_kernel_size, a.out)
    elif a.mode == 'recovery':
        mk_recovery(rd(a.ramdisk), a.out)
    elif a.mode == 'vboot':
        mk_vboot(rd(a.vendor_ramdisk), rd(a.dtb), a.cmdline,
                 a.bootconfig.encode() if a.bootconfig else b'', out=a.out)
    else:
        for f in a.files:
            dump_one(f)


if __name__ == '__main__':
    main()
