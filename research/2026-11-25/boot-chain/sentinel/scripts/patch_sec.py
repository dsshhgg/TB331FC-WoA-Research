import pathlib, sys

p = pathlib.Path('/root/woa/uefi-tb128fu/Silicon/Silicium/SiliciumPkg/Sec/Sec.c')
t = p.read_text()
orig = t

subs = [
("""  // Magenta = SEC's first C statement ran; white = the 64 KiB loop below it
  // completed. Both survive an R/B channel swap, unlike the green/blue bands.
  SecPaintBand (0x00FF00FF, 0x00000000, 0x00010000);""",
 """  // BLUE = SEC's first C statement ran (the "SEC is alive" answer to the shim's
  // RED/GREEN); WHITE = both early bands are on the panel. Palette is shared with
  // BootShim.S, see sentinel/REPORT.md.
  SecPaintBand (0xFF0000FF, 0x00000000, 0x00010000);"""),

("""  // SEC reached memory setup: green band across the top of the panel (~1 row at
  // 1200 px). Painted before MemoryPeim turns the MMU on.
  SecPaintBand (0x0000FF00, 0x00000000, 0x00001000);""",
 """  // SEC reached memory setup ("DXE Heap" located): ORANGE band at +0x12000, so it
  // does not eat into the 64 KiB BLUE band above it. Painted before MemoryPeim
  // turns the MMU on.
  SecPaintBand (0xFFFF8000, 0x00012000, 0x00001000);"""),

("""  // Memory init done: blue band right after the white one, so the panel shows how
  // far SEC got. Written with the MMU on (Display Reserved is WRITE_THROUGH_XN).
  SecPaintBand (0x00FF0000, 0x00011000, 0x00001000);""",
 """  // Memory init done: YELLOW band at +0x11000, written with the MMU on (Display
  // Reserved is WRITE_THROUGH_XN).
  SecPaintBand (0xFFFFFF00, 0x00011000, 0x00001000);"""),

("""// buffer at 0x5C000000 ("Display Reserved" in MemoryMapLib). Writing there
// needs no library, no stack beyond this frame and no MMU, so SEC paints it as
// the very first thing it does: a stall anywhere after the first C statement
// then shows up as a colour on the panel instead of a black screen that cannot
// be told apart from "SEC never ran".""",
 """// buffer at 0x5C000000 ("Display Reserved" in MemoryMapLib, the device DTBO's
// splash_region@5c000000). Writing there needs no library, no stack beyond this
// frame and no MMU, so SEC paints it as the very first thing it does: a stall
// anywhere after the first C statement then shows up as a colour on the panel
// instead of a black screen that cannot be told apart from "SEC never ran".
//
// Band map (all offsets from 0x5C000000, see sentinel/REPORT.md):
//   +0x00000 64 KiB  BLUE   SEC's first C statement ran   (BootShim: RED->GREEN)
//   +0x10000  4 KiB  WHITE  both early bands are on the panel
//   +0x11000  4 KiB  YELLOW InitializeMemory completed (MMU on)
//   +0x12000  4 KiB  ORANGE "DXE Heap" located, before MemoryPeim"""),
]

for old, new in subs:
    if old not in t:
        print('MISS: ' + old.splitlines()[0])
        sys.exit(1)
    t = t.replace(old, new, 1)

p.write_text(t)
print('patched Sec.c, %d -> %d bytes' % (len(orig), len(t)))
