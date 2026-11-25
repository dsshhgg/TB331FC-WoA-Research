/*
 * paint_stub.S -- "the payload really ran" proof for the TB331FC (khaje).
 *
 * This is NOT a UEFI payload.  It is a ~140-byte trampoline that is appended to
 * the *real* A17 (HyperOS 4 / Android 17) Linux kernel and entered from the
 * kernel image's own entry point, so that a colour on the panel can never be
 * confused with "our own shim never got control".
 *
 * How it is wired (see patch_boot_a.py):
 *
 *   file offset 0x000000  MZ @ fa | b  -> 0x42918A00      (4 bytes rewritten)
 *   file offset 0x2918A00  <this stub>  (appended, kernel_size grows by 4 KiB)
 *
 *   runtime:  ABL loads the raw Image at 0x40000000 (text_offset = 0) and jumps
 *             to 0x40000000 -> code0 ("MZ" ccmp, untouched) -> code1 (our b)
 *             -> 0x42918A00 (this stub) -> paint -> 0x42550000 (primary_entry)
 *
 * The stub is position independent: every branch below is a PC-relative b/b.cond
 * whose *offset* is what matters, so it does not care what KernelBaseAddr is.
 *
 * Register discipline at a Linux arm64 kernel entry:
 *   x0 = FDT physical address, x1..x3 = 0  (must survive)
 *   nothing else is defined, so x9..x14 are free scratch here.
 *
 * Lineage of the MMU part: work\woa\sentinel\BootShim.S (read-modify-write of
 * SCTLR, never "msr sctlr_elX, xzr": that would zero RES1 bits).
 */
    .text
    .global _start
_start:
    /* ---- 1. which EL are we on? ---------------------------------------- */
    mrs     x9, CurrentEL
    ubfx    x9, x9, #2, #2          /* 1 = EL1, 2 = EL2, 3 = EL3 */
    cmp     x9, #2
    b.eq    L_el2
    cmp     x9, #3
    b.eq    L_el3
    mrs     x10, sctlr_el1          /* x10 = original SCTLR (kept for restore) */
    b       L_off
L_el2:
    mrs     x10, sctlr_el2
    b       L_off
L_el3:
    mrs     x10, sctlr_el3

    /* ---- 2. MMU + D-cache off (VA == PA before touching 0x5C000000) ----- */
L_off:
    bic     x11, x10, #1            /* clear M (bit 0)  : MMU off */
    bic     x11, x11, #4            /* clear C (bit 2)  : D-cache off */
    cmp     x9, #2
    b.eq    L_w2
    cmp     x9, #3
    b.eq    L_w3
    msr     sctlr_el1, x11
    b       L_isb1
L_w2:
    msr     sctlr_el2, x11
    b       L_isb1
L_w3:
    msr     sctlr_el3, x11
L_isb1:
    isb

    /* ---- 3. paint the whole cont_splash_region (15 MiB) RED ------------ */
    movz    x13, #0x5C00, lsl #16   /* 0x5C000000  splash_region@5c000000  */
    movz    x12, #0xFFFF, lsl #16   /* 0x00000000FFFF0000 ...              */
    movk    x12, #0xFFFF, lsl #48   /* ... = 0xFFFF0000FFFF0000 (A=0xFF)   */
    movz    x14, #0xF, lsl #16      /* 0xF0000 x 16 B = 0xF00000 = 15 MiB  */
L_paint:
    stp     x12, x12, [x13], #16
    subs    x14, x14, #1
    b.ne    L_paint
    dsb     sy

    /* ---- 4. hand the machine back exactly as we found it ---------------- */
    cmp     x9, #2
    b.eq    L_r2
    cmp     x9, #3
    b.eq    L_r3
    msr     sctlr_el1, x10
    b       L_isb2
L_r2:
    msr     sctlr_el2, x10
    b       L_isb2
L_r3:
    msr     sctlr_el3, x10
L_isb2:
    isb

    /* ---- 5. continue the kernel at its original code1 target ----------- */
    /* b 0x42550000, expressed so GAS can resolve it while the section VMA is
     * still 0: the encoded imm26 is (target - here)/4, identical at any base. */
L_jump:
    b       . + (0x42550000 - (0x42918A00 + (L_jump - _start)))
