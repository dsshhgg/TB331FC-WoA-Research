"""Locate the SEC entry points inside the built FD (read-only).

    python3 fdsec.py <SILICIUM_UEFI.fd>

Prints the SECURITY_CORE FFS, its TE header, _ModuleEntryPoint, and the
`ldr x0, =SecEntry` literal that the entry stub loads (that is the C entry
SecMain/SecPaintEarly hangs off).
"""
import struct, sys

FD = sys.argv[1]
FD_BASE = 0x5FC00000

def u16(b, o): return struct.unpack_from("<H", b, o)[0]
def u24(b, o): return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16)
def u32(b, o): return struct.unpack_from("<I", b, o)[0]
def u64(b, o): return struct.unpack_from("<Q", b, o)[0]

d = open(FD, "rb").read()
print("FD size=%d (%#x)  FVH@%#x FvLength=%#x"
      % (len(d), len(d), d.find(b"_FVH"), u64(d, 0x20)))

o = u16(d, 0x30)
while o + 24 <= len(d) and d[o:o + 24] != b"\xff" * 24:
    ftype, size, hdr = d[o + 18], u24(d, o + 20), 24
    if size == 0xFFFFFF:
        size, hdr = u64(d, o + 24), 32
    if ftype == 0x03:
        print("SECURITY_CORE FFS @%#x size=%#x" % (o, size))
        p = o + hdr
        while p + 4 <= o + size:
            ssz, st = u24(d, p), d[p + 3]
            if st == 0x12:
                q = p + 4
                entry, ib = u32(d, q + 8), u64(d, q + 0x10)
                e = q + entry
                print("TE imagebase=%#x entry_rva=%#x  (imagebase+entry=%#x)"
                      % (ib, entry, FD_BASE + e))
                for i in range(16):
                    w = u32(d, e + 4 * i)
                    if (w & 0xFF000000) == 0x58000000:      # LDR Xt, literal
                        rt, imm19 = w & 0x1F, (w >> 5) & 0x7FFFF
                        if imm19 & 0x40000:
                            imm19 -= 0x80000
                        tgt = e + 4 * i + imm19 * 4
                        print("  +%02d: ldr x%d, =%#x   (file %#x)   value=%#x"
                              % (4 * i, rt, FD_BASE + tgt, tgt, u64(d, tgt)))
            p = (p + ssz + 3) & ~3
        break
    o = (o + size + 7) & ~7
