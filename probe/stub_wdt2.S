#define WDT     0xF017000
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
  /* disable MMU at the current EL first */
  mrs   x0, CurrentEL
  lsr   x0, x0, #2
  cmp   x0, #2
  b.eq  _el2
  cmp   x0, #1
  b.eq  _el1
  b     _wdt

_el2:
  msr   sctlr_el2, xzr
  isb
  b     _wdt

_el1:
  msr   sctlr_el1, xzr
  isb
  b     _wdt

_wdt:
  movz  x4, #(WDT >> 16), lsl #16      /* 0xF017000 */
  movk  x4, #(WDT & 0xFFFF)
  mov   w5, #0
  str   w5, [x4, #0x08]                /* EN = 0 */
  mov   w5, #1
  str   w5, [x4, #0x04]                /* RST = 1 */
  mov   w5, #1
  str   w5, [x4, #0x10]                /* BARK = 1 tick */
  mov   w5, #2
  str   w5, [x4, #0x14]                /* BITE = 2 ticks */
  mov   w5, #1
  str   w5, [x4, #0x08]                /* EN = 1 -> bite soon */
  dsb   sy
1:
  wfe
  b     1b

.text
.ltorg
.align 4
_Payload:
