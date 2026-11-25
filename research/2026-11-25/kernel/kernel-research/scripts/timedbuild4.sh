#!/bin/bash
T=/root/kbtest
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
cd "$T" || exit 1
echo "=== pm6125.dtsi head (why the syntax error) ==="
sed -n '1,12p' arch/arm64/boot/dts/qcom/pm6125.dtsi
echo "--- IRQ_TYPE usage vs include ---"
grep -n 'IRQ_TYPE_EDGE_BOTH' arch/arm64/boot/dts/qcom/pm6125.dtsi | head -3
grep -n 'interrupt-controller/irq.h' arch/arm64/boot/dts/qcom/pm6125.dtsi || echo "!! missing #include <dt-bindings/interrupt-controller/irq.h>"

echo
echo "=== $(date '+%F %T') timed: make -j8 Image (clean) ==="
make mrproper >/dev/null 2>&1
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
S=$(date +%s)
make -j8 Image > /root/kbtest-image.log 2>&1
RC=$?
E=$(date +%s)
echo "make Image exit=$RC elapsed=$((E-S))s (= $(( (E-S)/60 ))m$(( (E-S)%60 ))s)"
ls -l arch/arm64/boot/Image 2>/dev/null | awk '{print "Image bytes:", $5}'
tail -5 /root/kbtest-image.log
echo
echo "=== $(date '+%F %T') timed: make -j8 modules ==="
S=$(date +%s); make -j8 modules > /root/kbtest-mod3.log 2>&1; RC=$?; E=$(date +%s)
echo "make modules exit=$RC elapsed=$((E-S))s (= $(( (E-S)/60 ))m$(( (E-S)%60 ))s)"
echo "ko count: $(find . -name '*.ko' | wc -l)"
tail -5 /root/kbtest-mod3.log
echo
echo "=== single dtb target check ==="
make -j8 qcom/sm6225-lenovo-tb331fc.dtb > /root/kbtest-1dtb.log 2>&1; echo "single dtb exit=$?"
ls -l arch/arm64/boot/dts/qcom/sm6225-lenovo-tb331fc.dtb 2>/dev/null | awk '{print $5, $9}'
echo "=== tree size now: $(du -sh $T | cut -f1) ==="
echo "=== DONE $(date '+%F %T') ==="
