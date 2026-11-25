#!/bin/bash
cd /root/kbtest || exit 1
echo "=== where is DTC_INCLUDE defined? ==="
grep -rn 'DTC_INCLUDE' Makefile scripts/Makefile* arch/arm64/Makefile 2>/dev/null | head
echo
echo "=== how the failing command looked (from .pre.tmp dep or log) ==="
ls -la arch/arm64/boot/dts/qcom/.sm6225-lenovo-tb128* 2>/dev/null
cat arch/arm64/boot/dts/qcom/.sm6225-lenovo-tb128.dtb.d.pre.tmp 2>/dev/null | head -5
echo
echo "=== reproduce the exact make recipe dry-run ==="
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make -n qcom/sm6225-lenovo-tb128.dtb 2>&1 | grep -E 'HOSTCC|gcc -E|dtc' | head -5
echo
echo "=== check the include dir actually passed ==="
make -n dtbs 2>&1 | grep -m2 'DTC_INCLUDE\|-nostdinc' | head -3
