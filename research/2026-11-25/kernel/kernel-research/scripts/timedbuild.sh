#!/bin/bash
set -o pipefail
K=/root/linux-tb331fc
O=/root/kbuild-clean
rm -rf "$O"; mkdir -p "$O"
cd "$K" || exit 1
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
echo "=== $(date '+%F %T') defconfig ==="
make O="$O" tb331fc_defconfig 2>&1 | tail -3
echo "config lines: $(grep -c '^CONFIG_' $O/.config)"
echo
echo "=== $(date '+%F %T') START make -j8 Image dtbs ==="
S=$(date +%s)
make O="$O" -j8 Image dtbs 2>&1 | tail -25
RC=$?
E=$(date +%s)
echo "=== Image+dtbs exit=$RC elapsed=$((E-S))s ($(( (E-S)/60 ))m$(( (E-S)%60 ))s) ==="
ls -l "$O/arch/arm64/boot/Image" 2>/dev/null
echo
echo "=== $(date '+%F %T') START make -j8 modules ==="
S=$(date +%s)
make O="$O" -j8 modules 2>&1 | tail -15
RC=$?
E=$(date +%s)
echo "=== modules exit=$RC elapsed=$((E-S))s ($(( (E-S)/60 ))m$(( (E-S)%60 ))s) ==="
echo "ko count: $(find $O -name '*.ko' | wc -l)"
echo "build dir size: $(du -sh $O | cut -f1)"
echo "=== DONE $(date '+%F %T') ==="
