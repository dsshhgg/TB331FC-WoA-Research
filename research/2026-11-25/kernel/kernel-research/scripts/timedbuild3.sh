#!/bin/bash
# Fix the zip-damaged dtc include-prefixes symlinks, then measure a真实 clean build
set -o pipefail
T=/root/kbtest
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
cd "$T" || exit 1

echo "=== fixing scripts/dtc/include-prefixes symlinks ==="
cd scripts/dtc/include-prefixes || exit 1
for d in arc arm arm64 dt-bindings microblaze mips nios2 openrisc powerpc riscv sh xtensa; do
  rm -f "$d"
  case "$d" in
    dt-bindings) ln -s ../../../include/dt-bindings "$d" ;;
    arm64)       ln -s ../../../arch/arm64/include "$d" ;;
    *)           ln -s ../../../arch/$d/include "$d" ;;
  esac
done
ls -la | head -15
cd "$T" || exit 1

echo
echo "=== sanity: is sm6225.dtsi compilable now? (dtbs) ==="
S=$(date +%s); make -j8 dtbs > /root/kbtest-dtbs2.log 2>&1; RC=$?; E=$(date +%s)
echo "dtbs exit=$RC elapsed=$((E-S))s"
grep -cE 'fatal error' /root/kbtest-dtbs2.log
ls -l arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dtb arch/arm64/boot/dts/qcom/sm6225-lenovo-tb128.dtb 2>/dev/null | awk '{print $5, $9}'

echo
echo "=== $(date '+%F %T') FULL CLEAN: make -j8 Image dtbs ==="
make mrproper >/dev/null 2>&1
# mrproper removes symlinks? no, but re-apply to be safe
cd scripts/dtc/include-prefixes
for d in arc arm arm64 dt-bindings microblaze mips nios2 openrisc powerpc riscv sh xtensa; do
  rm -f "$d"
  case "$d" in
    dt-bindings) ln -s ../../../include/dt-bindings "$d" ;;
    arm64)       ln -s ../../../arch/arm64/include "$d" ;;
    *)           ln -s ../../../arch/$d/include "$d" ;;
  esac
done
cd "$T" || exit 1
make tb331fc_defconfig >/dev/null 2>&1
S=$(date +%s); make -j8 Image dtbs > /root/kbtest-full.log 2>&1; RC=$?; E=$(date +%s)
echo "Image+dtbs exit=$RC elapsed=${E}s-${S}s = $((E-S))s (= $(( (E-S)/60 ))m$(( (E-S)%60 ))s)"
ls -l arch/arm64/boot/Image 2>/dev/null | awk '{print "Image bytes:", $5}'
tail -4 /root/kbtest-full.log

echo
echo "=== $(date '+%F %T') modules ==="
S=$(date +%s); make -j8 modules > /root/kbtest-mod2.log 2>&1; RC=$?; E=$(date +%s)
echo "modules exit=$RC elapsed=$((E-S))s (= $(( (E-S)/60 ))m$(( (E-S)%60 ))s)"
echo "ko count: $(find . -name '*.ko' | wc -l)"
tail -4 /root/kbtest-mod2.log
echo "build tree size: $(du -sh $T | cut -f1)"
echo "=== DONE $(date '+%F %T') ==="
