_Head:
  adr   x1, _Payload    /* Set _Entry address */
  b     _Start          /* Jump to the real code */

#if REQUIRES_KERNEL_HEADER == 1
_StackBase:
  .quad FD_BASE         /* Text Offset */

_StackSize:
  .quad FD_SIZE + (_Payload - _Head) /* Complete shim and payload */
  .quad 0               /* Flags */
  .quad 0               /* Reserved */
  .quad 0               /* Reserved */
  .quad 0               /* Reserved */
  .ascii "ARM\x64"      /* ARM64 Magic */
  .long 0               /* Reserved */
#endif

/*
 * v9 THREE-COLOUR SENTINEL  (see sentinel/REPORT.md)
 *
 * The panel is still scanning out ABL cont_splash_region (0x5C000000,
 * "splash_region@5c000000" / cont_splash_region in the device DTBO, 15 MiB;
 * panel qcom,mdss_dsi_panel_p255_hx83102j_fhd_video is DSI video mode, so the
 * mixer keeps re-reading DDR).  Painting that buffer makes "who died" visible
 * on the panel itself:
 *
 *   0x5C000000 + 0x00000, 64 KiB   RED    -> this _Start ran (shim is alive)
 *   0x5C000000 + 0x00000, 64 KiB   GREEN  -> FD copied to FD_BASE, jump next
 *   0x5C000000 + 0x00000, 64 KiB   BLUE   -> painted by SEC (SecPaintEarly)
 *   0x5C000000 + 0x10000,  4 KiB   WHITE  -> painted by SEC (both bands done)
 *   0x5C000000 + 0x11000,  4 KiB   YELLOW -> painted by SEC (InitializeMemory)
 *   0x5C000000 + 0x20000,  4 KiB   CYAN   -> ABL handed over with MMU *on*
 *
 * Every band is written with the MMU off, so the store goes straight to DRAM
 * (no translation, no cache: Device-nGnRnE, strongly ordered) and is followed
 * by "dsb sy".  No stack is used; x0 (the DT pointer that SEC forwards in a
 * HOB) is parked in x17 and restored before the jump.
 */
#define SENTINEL_FB        0x5C000000
#define SENTINEL_FB_CYAN   0x5C020000
#define SENTINEL_PIXELS    0x4000        /* 64 KiB / 4 */
#define SENTINEL_RED       0xFFFF0000    /* a8r8g8b8.  Alpha is FF on purpose: a   */
#define SENTINEL_GREEN     0xFF00FF00    /* zero alpha pixel would vanish if the   */
#define SENTINEL_CYAN      0xFF00FFFF    /* mixer kept per-pixel alpha blending.   */

_Start:
  mov   x17, x0         /* keep the DT pointer ABL gave us (SEC forwards it) */

  /* ---- SENTINEL 1/3: force the MMU off, then paint RED -------------------
   * VA == PA must be guaranteed before touching 0x5C000000 from a stage
   * whose TTBR0/MAIR we did not author.  SCTLR is read-modify-write so the
   * RES1 bits survive (a bare "msr sctlr_elN, xzr" is architecturally
   * unpredictable).
   */
  mrs   x9, CurrentEL
  ubfx  x9, x9, #2, #2            /* x9 = current EL (1 or 2) */
  cmp   x9, #2
  b.eq  _SntEl2
  mrs   x10, sctlr_el1
  and   x11, x10, #1              /* x11 = "MMU was already on" flag */
  bic   x10, x10, #1              /* M = 0: MMU off */
  bic   x10, x10, #4              /* C = 0: data cache off */
  msr   sctlr_el1, x10
  b     _SntMmuOff
_SntEl2:
  mrs   x10, sctlr_el2
  and   x11, x10, #1
  bic   x10, x10, #1
  bic   x10, x10, #4
  msr   sctlr_el2, x10
_SntMmuOff:
  isb

  ldr   x13, =SENTINEL_FB
  mov   x14, #SENTINEL_PIXELS
  ldr   w0,  =SENTINEL_RED
  bl    _SntPaint

  cbz   x11, _SntRedDone          /* MMU was already off: nothing to report */
  ldr   x13, =SENTINEL_FB_CYAN
  mov   x14, #0x400
  ldr   w0,  =SENTINEL_CYAN
  bl    _SntPaint
_SntRedDone:

#if SENTINEL_HALT
  /* Control image (-DSENTINEL_HALT=1): stop right here, on purpose, without
   * touching the FD.  Its only job is to prove the framebuffer channel: if this
   * image shows RED then a blank screen from any other build really means "that
   * code never ran"; if this one is blank too, a blank screen proves nothing. */
  b     _Dead
#endif

  mov   x4, x1
  ldr   x5, =FD_BASE
  cmp   x4, x5
  beq   _Entry
  ldr   x6,  =FD_SIZE

_CopyLoop:
  ldp   x2, x3, [x4], #16
  stp   x2, x3, [x5], #16
  subs  x6, x6, #16
  b.ne  _CopyLoop
  ldr   x5, =FD_BASE

_Entry:
  /* ---- SENTINEL 2/3: FD is at FD_BASE and the jump is next => GREEN ------ */
  ldr   x13, =SENTINEL_FB
  mov   x14, #SENTINEL_PIXELS
  ldr   w0,  =SENTINEL_GREEN
  bl    _SntPaint

  /* Publish the copied instructions before executing them. */
  dsb   sy
  mrs   x9, ctr_el0
  ubfx  x9, x9, #16, #4
  mov   x10, #4
  lsl   x9, x10, x9
  sub   x10, x9, #1
  bic   x8, x5, x10
  ldr   x7, =FD_SIZE
  add   x7, x5, x7

_CleanLoop:
  dc    cvac, x8
  add   x8, x8, x9
  cmp   x8, x7
  b.lo  _CleanLoop
  dsb   sy
  ic    iallu
  dsb   sy
  isb
  mov   x0, x17         /* hand the DT pointer back to the payload */
  br    x5

_Dead:
  b     _Dead

/* x13 = base, x14 = pixel count, w0 = colour.  Clobbers x15, x16, x30. */
_SntPaint:
  mov   x15, x13
  mov   x16, x14
_SntPaintLoop:
  str   w0, [x15], #4
  subs  x16, x16, #1
  b.ne  _SntPaintLoop
  dsb   sy
  ret

.text
.ltorg
.align 4

_Payload:
