#!/bin/bash
# Clean-build timing in a throwaway copy (original tree untouched)
set -o pipefail
SRC=/root/linux-tb331fc
T=/root/kbtest
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-

if [ ! -d "$T" ]; then
  echo "=== $(date '+%F %T') copying source tree (1.9G) ==="
  cp -a "$SRC" "$T"
fi
cd "$T" || exit 1
echo "=== $(date '+%F %T') make mrproper ==="
make mrproper >/dev/null 2>&1
echo "tree size after mrproper: $(du -sh . | cut -f1)"
echo "=== $(date '+%F %T') tb331fc_defconfig ==="
make tb331fc_defconfig 2>&1 | tail -3
echo "config lines: $(grep -c '^CONFIG_' .config)"
echo
echo "=== $(date '+%F %T') START: make -j8 Image dtbs ==="
S=$(date +%s); make -j8 Image dtbs > /root/kbtest-build.log 2>&1; RC=$?; E=$(date +%s)
echo "Image+dtbs exit=$RC elapsed=$((E-S))s (=$(( (E-S)/60 ))m$(( (E-S)%60 ))s)"
ls -l arch/arm64/boot/Image 2>/dev/null | awk '{print "Image:", $5, "bytes"}'
echo "log tail:"; tail -6 /root/kbtest-build.log
echo
echo "=== $(date '+%F %T') START: make -j8 modules ==="
S=$(date +%s); make -j8 modules > /root/kbtest-mod.log 2>&1; RC=$?; E=$(date +%s)
echo "modules exit=$RC elapsed=$((E-S))s (=$(( (E-S)/60 ))m$(( (E-S)%60 ))s)"
echo "ko count: $(find . -name '*.ko' | wc -l)"
echo "log tail:"; tail -6 /root/kbtest-mod.log
echo "total build dir size: $(du -sh . | cut -f1)"
echo "=== DONE $(date '+%F %T') ==="
