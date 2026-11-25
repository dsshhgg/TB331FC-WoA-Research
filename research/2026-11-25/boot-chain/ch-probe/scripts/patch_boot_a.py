#!/usr/bin/env python3
"""patch_boot_a.py -- build the "does a write to 0x5C000000 reach the panel?" proof.

Idea
----
Instead of trusting our own UEFI shim, patch the *real* A17 (HyperOS 4 / A17,
kernel_size 0x2918A00, uncompressed arm64 `Image`) that provably boots to
Android on this tablet, and let it carry the payload:

    boot_a.img  kernel payload
    offset 0x000000 : 4d 5a 40 fa   "MZ" + ccmp  (untouched, MZ magic survives)
    offset 0x000004 : b 0x42918A00  (was: b 0x2550000)   <-- 4 bytes rewritten
    offset 0x2918A00: paint_stub.bin (appended, kernel_size += 0x1000)

Runtime picture (KernelBaseAddr = 0x40000000, text_offset = 0, so the raw
Image is loaded at 0x40000000 and ABL `blr`s to that same address):

    0x40000000  ccmp  x18,#0,#0xd,pl     (harmless, only here for "MZ")
    0x40000004  b     0x42918A00         our patch
    0x42918A00  stub: MMU+D-cache off -> paint 15 MiB of 0xFFFF0000 into
                0x5C000000 (cont_splash_region) -> restore SCTLR -> b 0x42550000
    0x42550000  original primary_entry   (the kernel's own code1 target)

Why this is a *conclusive* experiment
-------------------------------------
0x40000004 used to be the only way into the kernel, and the only way into the
stub is through that instruction.  So:

    screen goes red  -> the write to 0x5C000000 reached the panel.
    Android boots but the screen never went red
                     -> the stub DID execute (the kernel cannot be reached any
                        other way), yet 0x5C000000 is not what the mixer scans
                        => the whole "stuck on the Lenovo logo" evidence base
                        means nothing, and the v9 sentinel verdict ("ABL never
                        jumped") is unsupported.

Nothing here is size-critical: `image_size` (+0x10) is *not* touched, so ABL's
`image_size <= DtbLoadAddr - KernelLoadAddr` gate (0xa3e8) is bit-for-bit the
same as on the stock image that already boots.  Only `kernel_size` (+0x08 of
the boot header, not of the arm64 header) grows by one page.

Usage
-----
    python patch_boot_a.py            # writes out\\boot_a-paint-proof.img
    python patch_boot_a.py --ctl      # 1-instruction control: same trampoline,
                                      # no paint. proves the mechanism is inert.
"""

import argparse
import hashlib
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

SRC_DEFAULT = r"E:\rom\work\a17dump\boot_a.img"
SRC_SHA256 = "2510b098380a573a40ee6600aa9124ced06a047c14c21e6bf7cd596fbbc3c14b"
PAGE = 4096

KERNEL_OFF = 0x0
CODE1_OFF = 0x4
TEXT_OFFSET_OFF = 0x8
IMAGE_SIZE_OFF = 0x10
MAGIC_OFF = 0x38

STUB_OFF = 0x2918A00          # == stock kernel_size, first byte of .bss
STUB_VA = 0x40000000 + STUB_OFF
KERNEL_ENTRY_VA = 0x40000000 + 0x2550000   # stock code1 target (primary_entry)

MZ_CCMP = 0xFA405A4D          # "MZ" + ccmp x18,#0,#0xd,pl
OLD_CODE1 = 0x14953FFF        # b 0x2550000

# control stub: a bare `b 0x42550000` at STUB_OFF
CTL_STUB = struct.pack("<I", 0x14000000 | (((KERNEL_ENTRY_VA - STUB_VA) >> 2) & 0x03FFFFFF))


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def u64(b, o):
    return struct.unpack_from("<Q", b, o)[0]


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def enc_b(from_va, to_va):
    """encode `b to_va` placed at from_va (pc-relative, imm26 in words)."""
    delta = to_va - from_va
    if delta % 4:
        raise ValueError("branch target not 4-byte aligned")
    imm = delta >> 2
    if not (-(1 << 25) <= imm < (1 << 25)):
        raise ValueError("branch target out of +-128 MiB range")
    return 0x14000000 | (imm & 0x03FFFFFF)


def decode_b(pc_va, word):
    imm = word & 0x03FFFFFF
    if imm & 0x02000000:
        imm -= 0x04000000
    return pc_va + (imm << 2)


def check_stub(stub):
    """sanity: first word mrs x9, CurrentEL; last word b primary_entry."""
    if len(stub) % 4:
        raise SystemExit("stub is not a whole number of instructions")
    if u32(stub, 0) != 0xD5384249:
        raise SystemExit("stub does not start with `mrs x9, CurrentEL`")
    last = len(stub) - 4
    w = u32(stub, last)
    if (w & 0xFC000000) != 0x14000000:
        raise SystemExit("stub does not end with an unconditional `b`")
    tgt = decode_b(STUB_VA + last, w)
    if tgt != KERNEL_ENTRY_VA:
        raise SystemExit("stub ends with `b 0x%08x`, expected 0x%08x" % (tgt, KERNEL_ENTRY_VA))


def parse_boot_header(hdr):
    if hdr[:8] != b"ANDROID!":
        raise SystemExit("not an Android boot image (magic %r)" % hdr[:8])
    h = {
        "kernel_size": u32(hdr, 0x08),
        "ramdisk_size": u32(hdr, 0x0C),
        "os_version": u32(hdr, 0x10),
        "header_size": u32(hdr, 0x14),
        "header_version": u32(hdr, 0x28),
        "signature_size": u32(hdr, 1580),
    }
    return h


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC_DEFAULT)
    ap.add_argument("--stub", default=os.path.join(HERE, "out", "paint_stub.bin"))
    ap.add_argument("--out", default=None)
    ap.add_argument("--ctl", action="store_true", help="build the no-paint mechanism control")
    args = ap.parse_args()

    out_path = args.out or os.path.join(
        HERE, "out", "boot_a-patch-ctl.img" if args.ctl else "boot_a-paint-proof.img")

    print("== source ==")
    src_sha = sha256_file(args.src)
    src_size = os.path.getsize(args.src)
    print("  %s" % args.src)
    print("  size   %d" % src_size)
    print("  sha256 %s" % src_sha)
    if src_sha != SRC_SHA256:
        print("  WARNING: source sha256 is not the archived stock dump (2510b098...)")

    with open(args.src, "rb") as f:
        blob = f.read(PAGE + 0x2918A00 + 0x1000)

    hdr = blob[:PAGE]
    h = parse_boot_header(hdr)
    print("== boot header ==")
    for k, v in h.items():
        print("  %-15s %d (0x%x)" % (k, v, v))
    if h["header_version"] != 4:
        raise SystemExit("expected header_version 4 (v4, page size is fixed 4096)")
    if h["header_size"] != 1584:
        raise SystemExit("unexpected header_size %d" % h["header_size"])
    if h["ramdisk_size"] or h["signature_size"]:
        raise SystemExit("expected a kernel-only v4 image (ramdisk_size=0, signature_size=0)")

    ks = h["kernel_size"]
    kernel = blob[PAGE:PAGE + ks]
    if len(kernel) != ks:
        raise SystemExit("truncated source image")

    print("== stock kernel header (arm64 Image) ==")
    assert u32(kernel, 0) == MZ_CCMP, hex(u32(kernel, 0))
    assert u32(kernel, 4) == OLD_CODE1, hex(u32(kernel, 4))
    text_offset = u64(kernel, TEXT_OFFSET_OFF)
    image_size = u64(kernel, IMAGE_SIZE_OFF)
    print("  code0     0x%08x  (MZ + ccmp, kept)" % u32(kernel, 0))
    print("  code1     0x%08x  (b 0x%08x, being replaced)" % (OLD_CODE1, 0x40000000 + 0x2550000))
    print("  text_offset     0x%x   -> ABL loads the Image at KernelBaseAddr+0x%x" % (text_offset, 0))
    print("  image_size      0x%x   (NOT touched: ABL gate 0xa3e8 unchanged)" % image_size)
    print("  magic @0x38     %r" % kernel[MAGIC_OFF:MAGIC_OFF + 4])
    if text_offset != 0:
        raise SystemExit("text_offset != 0: entry/load address assumptions change; stop")
    if image_size != 0x29C0000:
        raise SystemExit("unexpected image_size 0x%x" % image_size)
    if kernel[MAGIC_OFF:MAGIC_OFF + 4] != b"ARM\x64":
        raise SystemExit("missing ARM\\x64 magic at +0x38")

    # ABL: image_size <= DtbLoadAddr - KernelLoadAddr, with KernelSize 0x5700000
    # and a 13,635,716 B vendor ramdisk (measured on this unit).
    top = 0x40000000 + 0x5700000
    rd = (13635716 + PAGE - 1) & ~(PAGE - 1)
    dtb = top - rd - (PAGE + 0x200000)
    avail = dtb - 0x40000000
    print("== ABL gate 0xa3e8 (image_size <= Dtb-KL) ==")
    print("  DtbLoadAddr ~ 0x%x   available 0x%x (%d MiB)   image_size 0x%x (%d MiB)"
          % (dtb, avail, avail >> 20, image_size, image_size >> 20))
    if image_size > avail:
        raise SystemExit("image_size exceeds the available window: ABL would refuse")

    if args.ctl:
        stub = CTL_STUB
        print("== control stub: single `b 0x%08x` (no paint, no MMU touch) ==" % KERNEL_ENTRY_VA)
    else:
        with open(args.stub, "rb") as f:
            stub = f.read()
        check_stub(stub)
        print("== paint stub ==")
        print("  %s  %d bytes  sha256 %s" % (args.stub, len(stub), hashlib.sha256(stub).hexdigest()))
    if len(stub) > 0x1000:
        raise SystemExit("stub does not fit in the appended page")

    branch = enc_b(0x40000000 + CODE1_OFF, STUB_VA)
    print("== patch ==")
    print("  @kernel+0x%x : 0x%08x -> 0x%08x  (b 0x%08x)"
          % (CODE1_OFF, OLD_CODE1, branch, decode_b(0x40000000 + CODE1_OFF, branch)))
    if decode_b(0x40000000 + CODE1_OFF, branch) != STUB_VA:
        raise SystemExit("branch encoder self-check failed")

    tail = stub + b"\x00" * (0x1000 - len(stub))
    kernel_patched = kernel[:CODE1_OFF] + struct.pack("<I", branch) + kernel[CODE1_OFF + 4:] + tail
    new_ks = ks + 0x1000

    new_hdr = bytearray(hdr)
    struct.pack_into("<I", new_hdr, 0x08, new_ks)

    out = bytes(new_hdr) + kernel_patched
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(out)

    # ------------------------------------------------------------- verify --
    print("== verification ==")
    with open(out_path, "rb") as f:
        got = f.read()
    ok = True

    def chk(name, cond):
        nonlocal ok
        print("  [%s] %s" % ("ok" if cond else "FAIL", name))
        ok = ok and cond

    chk("output size == page + new kernel_size",
        len(got) == PAGE + new_ks)
    h2 = parse_boot_header(got[:PAGE])
    chk("kernel_size %d -> %d (+0x1000)" % (ks, new_ks),
        h2["kernel_size"] == new_ks)
    chk("every other header field is byte-identical",
        got[:0x08] == hdr[:0x08] and got[0x0C:PAGE] == hdr[0x0C:PAGE])
    k2 = got[PAGE:PAGE + new_ks]
    chk("code0/MZ untouched", k2[:4] == kernel[:4])
    chk("code1 == b 0x%08x" % STUB_VA, u32(k2, 4) == branch)
    chk("kernel[8:0x2918A00] byte-identical to stock",
        k2[8:STUB_OFF] == kernel[8:])
    chk("text_offset / image_size / ARM\\x64 untouched",
        k2[0x08:0x18] == kernel[0x08:0x18] and k2[0x38:0x3C] == kernel[0x38:0x3C])
    chk("stub placed at kernel+0x%x" % STUB_OFF, k2[STUB_OFF:STUB_OFF + len(stub)] == stub)
    chk("appended page is zero padded", k2[STUB_OFF + len(stub):] == b"\x00" * (0x1000 - len(stub)))

    h_out = sha256_file(out_path)
    print("  sha256 %s" % h_out)
    print("  wrote %s (%d bytes)" % (out_path, len(got)))
    if not ok:
        raise SystemExit("VERIFICATION FAILED")

    side = os.path.splitext(out_path)[0] + ".sha256"
    with open(side, "w", encoding="ascii") as f:
        f.write("%s  %s\n" % (h_out, os.path.basename(out_path)))
    print("  wrote %s" % side)

    print("== flash command (never run by this script) ==")
    print("  fastboot -s 5e367954 flash boot_a %s" % out_path)
    print("== rollback ==")
    print("  fastboot -s 5e367954 flash boot_a %s" % SRC_DEFAULT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
