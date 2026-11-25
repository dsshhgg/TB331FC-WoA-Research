#!/bin/bash
# build_all.sh - rebuild the DTB (with -@), the minimal initramfs, and every
# bootable image variant for TB331FC.  Nothing here touches the device.
#
#   IN  (already built kernel, do NOT rebuild):
#       /mnt/e/rom/work/linux-build/out/Image-6.14.0-rc5-tb331fc
#       /mnt/e/rom/work/linux-build/out/Image.gz
#   OUT: /mnt/e/rom/work/linux-boot/out/
set -eu

HERE=/mnt/e/rom/work/linux-boot
OUT=$HERE/out
KOUT=/mnt/e/rom/work/linux-build/out
KDIR=/root/linux-tb331fc
DTS=$KDIR/arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dts
IMAGE=$KOUT/Image-6.14.0-rc5-tb331fc
IMAGE_GZ=$KOUT/Image.gz
PY=python3
MK="env PYTHONIOENCODING=utf-8 $PY $HERE/scripts/mkboot.py"

mkdir -p "$OUT"

# The cmdline lives in the vendor_boot header.  Notes:
#  * no root= and no noinitrd  (both make the kernel ignore/!wait-for the
#    initramfs - the TB128FU-derived DTB has them in /chosen/bootargs)
#  * clk_ignore_unused pd_ignore_unused: without them the kernel powers down the
#    display clocks/power domains ABL left running -> black screen
#  * nomodeset: let simpledrm/fbcon own the panel for the console-only bring-up
#  * earlycon on the geni debug UART is free insurance if the panel stays dark
CMDLINE='console=tty0 keep_bootcon ignore_loglevel loglevel=8 fbcon=rotate:1 nomodeset clk_ignore_unused pd_ignore_unused rdinit=/init earlycon=qcom_geni,0x4a90000 androidboot.hardware=qcom panic=10'

echo "=========================================================="
echo " 1) DTS bluetooth node fix + DTB rebuild (-@ for __symbols__)"
echo "=========================================================="
$PY "$HERE/scripts/fix_dts_bt.py" "$DTS" --diff "$OUT/dts-bt-fix.diff"

# Rebuild ONLY the dtb.  kbuild's dtbs target re-enters the dts dir and is
# fussy about paths from here, so do exactly what scripts/Makefile.lib's
# cmd_dtc does: cpp -> dtc -@ (the -@ is what emits __symbols__, which ABL's
# libufdt needs to apply the vendor overlay from dtbo; without it ABL refuses
# to boot).
( cd "$KDIR" && gcc -E -nostdinc \
      -I include -I arch/arm64/boot/dts -I arch/arm64/boot/dts/include \
      -I scripts/dtc/include-prefixes -I arch/arm64/boot/dts/qcom \
      -undef -D__DTS__ -x assembler-with-cpp "$DTS" -o /tmp/tb331fc-pre.dts ) \
  || { echo "cpp of $DTS failed"; exit 1; }
rm -f /tmp/tb331fc.dtb
( cd "$KDIR" && dtc -@ -I dts -O dtb -o /tmp/tb331fc.dtb /tmp/tb331fc-pre.dts 2>/tmp/dtc.err )
DTC_RC=$?
echo "  dtc rc=$DTC_RC  warnings=$(grep -ci warning /tmp/dtc.err || true)"
grep -i 'error' /tmp/dtc.err | head -5 || true
[ -s /tmp/tb331fc.dtb ] || { echo "!! dtb not produced"; exit 1; }

DTB_SRC=/tmp/tb331fc.dtb
cp -f "$DTB_SRC" "$OUT/sm6225-lenovo-tb331fc-linux.dtb"
DTB=$OUT/sm6225-lenovo-tb331fc-linux.dtb

bash "$HERE/scripts/verify_dtb.sh" "$DTB"
grep -q 'qcom,wcn3990-bt' <(dtc -I dtb -O dts "$DTB" 2>/dev/null) || { echo "  !! bt node not wcn3990"; exit 1; }

echo
echo "=========================================================="
echo " 2) minimal initramfs"
echo "=========================================================="
OUT=$OUT bash "$HERE/scripts/mk_initramfs.sh"
IR=$OUT/initramfs-tb331fc.cpio.gz

echo
echo "=========================================================="
echo " 3) images"
echo "=========================================================="

# (a) boot_a: v4, page 4096, kernel only.  Raw Image first: both stock boot
#     images on this device carry an uncompressed arm64 Image, and ABL's
#     decompression path is unproven.  Image.gz variant also built.
echo "-- (a) boot_a (kernel only, raw Image) --"
$MK boot --kernel "$IMAGE" --out "$OUT/boot_a-linux.img"

echo "-- (a') boot_a, gzip kernel variant --"
$MK boot --kernel "$IMAGE_GZ" --out "$OUT/boot_a-linux-gz.img"

echo "-- (a'') boot_a with ONE appended FDT (speculative single-partition form) --"
# The FDT is counted inside kernel_size on purpose: ABL's CheckAppendedDtb works on
# the loaded kernel buffer and errors with "Dtb offset goes beyond the image size"
# when the offset it derives is outside kernel_size.
$MK boot --kernel "$IMAGE" --dtb "$DTB" --dtb-in-kernel-size \
         --out "$OUT/boot_a-linux-dtb.img"

echo "-- (a) vendor_boot_a: our initramfs + our DTB + our cmdline --"
$MK vboot --vendor-ramdisk "$IR" --dtb "$DTB" --cmdline "$CMDLINE" \
          --out "$OUT/vendor_boot_a-linux.img"

echo "-- (a3) variant: ramdisk in init_boot instead (vendor_boot carries dtb+cmdline only) --"
$MK vboot --vendor-ramdisk "" --dtb "$DTB" --cmdline "$CMDLINE" \
          --out "$OUT/vendor_boot_a-linux-nord.img"
$MK recovery --ramdisk "$IR" --out "$OUT/init_boot_a-initramfs.img"

echo "-- init_boot_a: empty cpio placeholder (keep it out of the ramdisk chain) --"
EMPTY=/mnt/e/rom/work/linuximg/empty.cpio
[ -f "$EMPTY" ] || { printf '0707010000000000000000000000000000000000000000000000000000000000000000'
                     printf '0000000000000000000000000000000000000000000000000000000000000000'
                     printf '0000000B00000000TRAILER!!!'; \
                     dd if=/dev/zero bs=1 count=100 >> "$OUT/tmp.cpio" 2>/dev/null; }
[ -f "$EMPTY" ] && cp -f "$EMPTY" "$OUT/init_boot-empty.cpio"
$MK recovery --ramdisk "$OUT/init_boot-empty.cpio" --out "$OUT/init_boot_a-empty.img"

# (b) recovery_a: v4, kernel_size = 0, ramdisk = our initramfs
echo "-- (b) recovery_a (kernel_size=0 + our initramfs) --"
$MK recovery --ramdisk "$IR" --out "$OUT/recovery_a-linux.img"

echo
echo "=========================================================="
echo " 4) verify headers"
echo "=========================================================="
$MK dump "$OUT/boot_a-linux.img" "$OUT/boot_a-linux-gz.img" \
         "$OUT/boot_a-linux-dtb.img" "$OUT/vendor_boot_a-linux.img" \
         "$OUT/init_boot_a-empty.img" "$OUT/recovery_a-linux.img"

echo
echo "=========================================================="
echo " 5) size budget (ABL: ramdisk total well under 28 MB)"
echo "=========================================================="
sz() { stat -c%s "$1"; }
printf '  %-34s %10d\n' "kernel Image (raw)"   "$(sz "$IMAGE")"
printf '  %-34s %10d\n' "kernel Image.gz"      "$(sz "$IMAGE_GZ")"
printf '  %-34s %10d\n' "initramfs.cpio.gz"    "$(sz "$IR")"
printf '  %-34s %10d\n' "dtb"                  "$(sz "$DTB")"
printf '  %-34s %10d\n' "vendor_boot_a total"  "$(sz "$OUT/vendor_boot_a-linux.img")"
printf '  %-34s %10d\n' "recovery_a total"     "$(sz "$OUT/recovery_a-linux.img")"

echo
echo "=========================================================="
echo " 6) sha256"
echo "=========================================================="
( cd "$OUT" && sha256sum *.img *.dtb *.cpio.gz init_boot-empty.cpio > SHA256SUMS && cat SHA256SUMS )
echo
echo "done -> $OUT"
