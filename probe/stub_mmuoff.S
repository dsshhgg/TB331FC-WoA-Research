#define FB      0x5C000000
_Head:
  adr   x1, _Payload
  b     _Start
  .quad 0x5FC00000
  .quad 0x3000C0
  .quad 0
  .quad 0
  .quad 0
  .quad 0
  .ascii "ARM\x64"
  .long 0

_Start:
  /* ---- disable MMU/caches at the current EL ---- */
  mrs   x0, CurrentEL
  lsr   x0, x0, #2
  cmp   x0, #2
  b.eq  _el2
  cmp   x0, #1
  b.eq  _el1
  b     _paint                 /* EL3/EL0: just try */

_el2:
  msr   sctlr_el2, xzr
  isb
  b     _paint

_el1:
  msr   sctlr_el1, xzr
  isb
  b     _paint

_paint:
  /* 64 KiB of 0x00FF00FF at 0x5C000000 */
  movz  x1, #(FB >> 16), lsl #16
  movz  x2, #0x00FF
  movk  x2, #0x00FF, lsl #16
  movz  x3, #0x0001, lsl #16      /* 65536 bytes */
1:
  stp   x2, x2, [x1], #16
  subs  x3, x3, #16
  b.ne  1b
  dsb   sy

  /* wait ~3 s using the generic timer */
  mrs   x4, cntfrq_el0
  cbz   x4, _reset
  mov   x5, #3
  mul   x4, x4, x5
  mrs   x5, cntpct_el0
  add   x5, x5, x4
2:
  isb
  mrs   x6, cntpct_el0
  cmp   x6, x5
  b.lo  2b

_reset:
  movz  w0, #0x8400, lsl #16
  movk  w0, #0x0009
  mov   x1, xzr
  mov   x2, xzr
  mov   x3, xzr
  smc   #0
3:
  wfe
  b     3b

.text
.ltorg
.align 4
_Payload:
